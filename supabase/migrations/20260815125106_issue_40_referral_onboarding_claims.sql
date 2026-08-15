-- Issue #40 corrective migration: server-owned referral onboarding provenance.
-- A public referral code can create an opaque pre-authentication claim, but
-- rewards are issued only after that claim is bound to an Auth account whose
-- trusted creation time is later than the claim capture time.

BEGIN;

CREATE TABLE public.referral_onboarding_claims (
  id pg_catalog.uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  claim_token_hash pg_catalog.text NOT NULL UNIQUE
    CHECK (pg_catalog.length(claim_token_hash) = 64),
  referral_id pg_catalog.uuid NOT NULL
    REFERENCES public.investor_referrals(id) ON DELETE RESTRICT,
  captured_at pg_catalog.timestamptz NOT NULL
    DEFAULT pg_catalog.clock_timestamp(),
  bound_user_id pg_catalog.uuid
    REFERENCES auth.users(id) ON DELETE RESTRICT,
  bound_at pg_catalog.timestamptz,
  consumed_at pg_catalog.timestamptz,
  conversion_id pg_catalog.uuid UNIQUE
    REFERENCES public.referral_conversions(id) ON DELETE RESTRICT,
  CONSTRAINT referral_onboarding_claim_binding_coherent
    CHECK ((bound_user_id IS NULL) = (bound_at IS NULL)),
  CONSTRAINT referral_onboarding_claim_consumption_coherent
    CHECK ((consumed_at IS NULL) = (conversion_id IS NULL)),
  CONSTRAINT referral_onboarding_claim_consumption_requires_binding
    CHECK (consumed_at IS NULL OR bound_user_id IS NOT NULL),
  CONSTRAINT referral_onboarding_claim_time_order
    CHECK (
      (bound_at IS NULL OR captured_at <= bound_at)
      AND (consumed_at IS NULL OR bound_at <= consumed_at)
    )
);

COMMENT ON TABLE public.referral_onboarding_claims IS
  'Server-owned pre-authentication claims proving referral signup provenance; raw claim tokens are never stored.';
COMMENT ON COLUMN public.referral_onboarding_claims.captured_at IS
  'Trusted database capture time compared with auth.users.created_at.';

CREATE INDEX referral_onboarding_claims_referral_idx
  ON public.referral_onboarding_claims (referral_id);
CREATE INDEX referral_onboarding_claims_bound_user_idx
  ON public.referral_onboarding_claims (bound_user_id)
  WHERE bound_user_id IS NOT NULL;

ALTER TABLE public.referral_onboarding_claims ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.create_referral_onboarding_claim(
  p_referral_code pg_catalog.text
)
RETURNS TABLE (
  claim_token pg_catalog.text,
  captured_at pg_catalog.timestamptz
) AS $$
DECLARE
  v_code pg_catalog.text;
  v_code_hash pg_catalog.text;
  v_claim_token pg_catalog.text;
  v_referral public.investor_referrals;
  v_referrer public.profiles;
  v_claim public.referral_onboarding_claims;
BEGIN
  v_code := pg_catalog.btrim(p_referral_code);
  IF v_code IS NULL OR v_code = '' THEN
    RAISE EXCEPTION 'referral_code_required' USING ERRCODE = 'P0001';
  END IF;

  v_code_hash := pg_catalog.encode(
    extensions.digest(v_code, 'sha256'),
    'hex'
  );

  SELECT referral.*
  INTO v_referral
  FROM public.investor_referrals AS referral
  WHERE referral.token_hash = v_code_hash
    AND referral.referral_code = v_code
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'referral_code_invalid' USING ERRCODE = 'P0001';
  END IF;

  SELECT profile.*
  INTO v_referrer
  FROM public.profiles AS profile
  WHERE profile.id = v_referral.referrer_profile_id
  FOR SHARE;

  IF NOT FOUND
     OR v_referrer.role <> 'investor'
     OR v_referrer.account_status <> 'active' THEN
    -- Do not disclose referrer identity or account state to the anonymous
    -- caller beyond whether the public code is currently usable.
    RAISE EXCEPTION 'referral_code_invalid' USING ERRCODE = 'P0001';
  END IF;

  FOR v_attempt IN 1..5 LOOP
    v_claim_token := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
    BEGIN
      INSERT INTO public.referral_onboarding_claims (
        claim_token_hash,
        referral_id
      ) VALUES (
        pg_catalog.encode(extensions.digest(v_claim_token, 'sha256'), 'hex'),
        v_referral.id
      )
      RETURNING * INTO v_claim;

      RETURN QUERY SELECT v_claim_token, v_claim.captured_at;
      RETURN;
    EXCEPTION WHEN unique_violation THEN
      -- A cryptographic collision is not observable by the caller. Generate a
      -- fresh token rather than returning or exposing the existing claim.
      NULL;
    END;
  END LOOP;

  RAISE EXCEPTION 'referral_claim_generation_failed' USING ERRCODE = 'P0001';
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.bind_referral_onboarding_claim(
  p_claim_token pg_catalog.text
)
RETURNS TABLE (
  bound pg_catalog.bool,
  replayed pg_catalog.bool
) AS $$
DECLARE
  v_user_id pg_catalog.uuid;
  v_user_created_at pg_catalog.timestamptz;
  v_token pg_catalog.text;
  v_token_hash pg_catalog.text;
  v_claim public.referral_onboarding_claims;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'referral_claim_authentication_required'
      USING ERRCODE = 'P0001';
  END IF;

  v_token := pg_catalog.btrim(p_claim_token);
  IF v_token IS NULL OR v_token = '' THEN
    RAISE EXCEPTION 'referral_claim_required' USING ERRCODE = 'P0001';
  END IF;

  v_token_hash := pg_catalog.encode(
    extensions.digest(v_token, 'sha256'),
    'hex'
  );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('referral-claim:' || v_token_hash, 0)
  );

  SELECT claim.*
  INTO v_claim
  FROM public.referral_onboarding_claims AS claim
  WHERE claim.claim_token_hash = v_token_hash
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'referral_claim_invalid' USING ERRCODE = 'P0001';
  END IF;

  SELECT "user".created_at
  INTO v_user_created_at
  FROM auth.users AS "user"
  WHERE "user".id = v_user_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'referral_claim_authentication_required'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_user_created_at <= v_claim.captured_at THEN
    RAISE EXCEPTION 'referral_claim_account_predates_capture'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_claim.bound_user_id IS NOT NULL
     AND v_claim.bound_user_id <> v_user_id THEN
    RAISE EXCEPTION 'referral_claim_account_conflict'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_claim.bound_user_id = v_user_id THEN
    RETURN QUERY SELECT true, true;
    RETURN;
  END IF;

  UPDATE public.referral_onboarding_claims AS claim
  SET bound_user_id = v_user_id,
      bound_at = pg_catalog.clock_timestamp()
  WHERE claim.id = v_claim.id;

  RETURN QUERY SELECT true, false;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

-- The input contract changes from a public referral code to the opaque,
-- server-issued onboarding claim. Dropping and recreating the function in this
-- additive transaction allows PostgREST to expose the new named parameter.
DROP FUNCTION public.process_investor_referral_conversion(pg_catalog.text);

CREATE FUNCTION public.process_investor_referral_conversion(
  p_claim_token pg_catalog.text
)
RETURNS TABLE (
  conversion_id pg_catalog.uuid,
  replayed pg_catalog.bool,
  reward_entitlement_count pg_catalog.int4
) AS $$
DECLARE
  v_user_id pg_catalog.uuid;
  v_user_created_at pg_catalog.timestamptz;
  v_referee_profile_id pg_catalog.uuid;
  v_referee public.profiles;
  v_referrer public.profiles;
  v_referral public.investor_referrals;
  v_claim public.referral_onboarding_claims;
  v_conversion public.referral_conversions;
  v_token pg_catalog.text;
  v_token_hash pg_catalog.text;
  v_reward_count pg_catalog.int4;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'referral_claim_authentication_required'
      USING ERRCODE = 'P0001';
  END IF;

  v_token := pg_catalog.btrim(p_claim_token);
  IF v_token IS NULL OR v_token = '' THEN
    RAISE EXCEPTION 'referral_claim_required' USING ERRCODE = 'P0001';
  END IF;

  v_token_hash := pg_catalog.encode(
    extensions.digest(v_token, 'sha256'),
    'hex'
  );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('referral-claim:' || v_token_hash, 0)
  );

  SELECT claim.*
  INTO v_claim
  FROM public.referral_onboarding_claims AS claim
  WHERE claim.claim_token_hash = v_token_hash
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'referral_claim_invalid' USING ERRCODE = 'P0001';
  END IF;

  SELECT "user".created_at
  INTO v_user_created_at
  FROM auth.users AS "user"
  WHERE "user".id = v_user_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'referral_claim_authentication_required'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_user_created_at <= v_claim.captured_at THEN
    RAISE EXCEPTION 'referral_claim_account_predates_capture'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_claim.bound_user_id IS NULL THEN
    RAISE EXCEPTION 'referral_claim_not_bound' USING ERRCODE = 'P0001';
  END IF;

  IF v_claim.bound_user_id <> v_user_id THEN
    RAISE EXCEPTION 'referral_claim_account_conflict'
      USING ERRCODE = 'P0001';
  END IF;

  v_referee_profile_id := public.current_user_profile_id();
  IF v_referee_profile_id IS NULL THEN
    RAISE EXCEPTION 'referral_profile_not_resolved' USING ERRCODE = 'P0001';
  END IF;

  SELECT profile.*
  INTO v_referee
  FROM public.profiles AS profile
  WHERE profile.id = v_referee_profile_id
  FOR SHARE;

  IF NOT FOUND
     OR v_referee.role <> 'investor'
     OR v_referee.account_status <> 'active' THEN
    RAISE EXCEPTION 'referral_investor_not_eligible' USING ERRCODE = 'P0001';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'referral-conversion:' || v_referee_profile_id::pg_catalog.text,
      0
    )
  );

  SELECT conversion.*
  INTO v_conversion
  FROM public.referral_conversions AS conversion
  WHERE conversion.referee_profile_id = v_referee_profile_id
  FOR UPDATE;

  IF v_claim.consumed_at IS NOT NULL THEN
    IF NOT FOUND OR v_claim.conversion_id <> v_conversion.id THEN
      RAISE EXCEPTION 'referral_claim_consumption_conflict'
        USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.referral_rewards (conversion_id, profile_id)
    SELECT v_conversion.id, beneficiary.profile_id
    FROM (
      SELECT referral.referrer_profile_id AS profile_id
      FROM public.investor_referrals AS referral
      WHERE referral.id = v_claim.referral_id
      UNION ALL
      SELECT v_referee_profile_id
    ) AS beneficiary
    ON CONFLICT ON CONSTRAINT referral_rewards_conversion_profile_key
      DO NOTHING;

    SELECT pg_catalog.count(*)::pg_catalog.int4
    INTO v_reward_count
    FROM public.referral_rewards AS reward
    WHERE reward.conversion_id = v_conversion.id;

    RETURN QUERY SELECT v_conversion.id, true, v_reward_count;
    RETURN;
  END IF;

  IF FOUND THEN
    IF v_conversion.referral_id <> v_claim.referral_id THEN
      RAISE EXCEPTION 'referral_conversion_conflict' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.referral_rewards (conversion_id, profile_id)
    SELECT v_conversion.id, beneficiary.profile_id
    FROM (
      SELECT referral.referrer_profile_id AS profile_id
      FROM public.investor_referrals AS referral
      WHERE referral.id = v_claim.referral_id
      UNION ALL
      SELECT v_referee_profile_id
    ) AS beneficiary
    ON CONFLICT ON CONSTRAINT referral_rewards_conversion_profile_key
      DO NOTHING;

    UPDATE public.referral_onboarding_claims AS claim
    SET consumed_at = pg_catalog.clock_timestamp(),
        conversion_id = v_conversion.id
    WHERE claim.id = v_claim.id;

    SELECT pg_catalog.count(*)::pg_catalog.int4
    INTO v_reward_count
    FROM public.referral_rewards AS reward
    WHERE reward.conversion_id = v_conversion.id;

    RETURN QUERY SELECT v_conversion.id, true, v_reward_count;
    RETURN;
  END IF;

  SELECT referral.*
  INTO v_referral
  FROM public.investor_referrals AS referral
  WHERE referral.id = v_claim.referral_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'referral_code_invalid' USING ERRCODE = 'P0001';
  END IF;

  IF v_referral.referrer_profile_id = v_referee_profile_id THEN
    RAISE EXCEPTION 'referral_self_not_allowed' USING ERRCODE = 'P0001';
  END IF;

  SELECT profile.*
  INTO v_referrer
  FROM public.profiles AS profile
  WHERE profile.id = v_referral.referrer_profile_id
  FOR SHARE;

  IF NOT FOUND
     OR v_referrer.role <> 'investor'
     OR v_referrer.account_status <> 'active' THEN
    RAISE EXCEPTION 'referral_code_inactive' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.referral_conversions (referral_id, referee_profile_id)
  VALUES (v_referral.id, v_referee_profile_id)
  RETURNING * INTO v_conversion;

  INSERT INTO public.referral_rewards (conversion_id, profile_id)
  VALUES
    (v_conversion.id, v_referral.referrer_profile_id),
    (v_conversion.id, v_referee_profile_id);

  UPDATE public.referral_onboarding_claims AS claim
  SET consumed_at = pg_catalog.clock_timestamp(),
      conversion_id = v_conversion.id
  WHERE claim.id = v_claim.id;

  RETURN QUERY SELECT v_conversion.id, false, 2;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON TABLE public.referral_onboarding_claims
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.create_referral_onboarding_claim(pg_catalog.text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_referral_onboarding_claim(pg_catalog.text)
  TO anon, authenticated;

REVOKE ALL ON FUNCTION public.bind_referral_onboarding_claim(pg_catalog.text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bind_referral_onboarding_claim(pg_catalog.text)
  TO authenticated;

REVOKE ALL ON FUNCTION public.process_investor_referral_conversion(pg_catalog.text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.process_investor_referral_conversion(pg_catalog.text)
  TO authenticated;

COMMIT;
