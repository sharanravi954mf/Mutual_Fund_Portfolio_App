-- Issue #40 corrective migration: bounded referral onboarding claim lifecycle.
-- Enforces a server-controlled expiry TTL on pre-authentication claims,
-- rejects expired claims deterministically during bind and conversion, and
-- provides a narrow service-role batch cleanup RPC while strictly preserving
-- consumed conversion/reward audit provenance.

BEGIN;

ALTER TABLE public.referral_onboarding_claims
  ADD COLUMN IF NOT EXISTS expires_at pg_catalog.timestamptz
    DEFAULT (pg_catalog.clock_timestamp() + '24 hours'::pg_catalog.interval);

UPDATE public.referral_onboarding_claims
SET expires_at = captured_at + '24 hours'::pg_catalog.interval
WHERE expires_at IS NULL;

ALTER TABLE public.referral_onboarding_claims
  ALTER COLUMN expires_at SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.referral_onboarding_claims'::pg_catalog.regclass
      AND conname = 'referral_onboarding_claim_expiry_order'
  ) THEN
    ALTER TABLE public.referral_onboarding_claims
      ADD CONSTRAINT referral_onboarding_claim_expiry_order
      CHECK (captured_at <= expires_at);
  END IF;
END;
$$;

COMMENT ON COLUMN public.referral_onboarding_claims.expires_at IS
  'Server-enforced onboarding-session expiry after which unconsumed claims cannot bind or convert.';

CREATE INDEX IF NOT EXISTS referral_onboarding_claims_cleanup_idx
  ON public.referral_onboarding_claims (expires_at)
  WHERE consumed_at IS NULL;

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
        referral_id,
        expires_at
      ) VALUES (
        pg_catalog.encode(extensions.digest(v_claim_token, 'sha256'), 'hex'),
        v_referral.id,
        pg_catalog.clock_timestamp() + '24 hours'::pg_catalog.interval
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

  IF v_claim.expires_at <= pg_catalog.clock_timestamp() THEN
    RAISE EXCEPTION 'referral_claim_expired' USING ERRCODE = 'P0001';
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

CREATE OR REPLACE FUNCTION public.process_investor_referral_conversion(
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

  IF v_claim.expires_at <= pg_catalog.clock_timestamp() THEN
    RAISE EXCEPTION 'referral_claim_expired' USING ERRCODE = 'P0001';
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

CREATE OR REPLACE FUNCTION public.cleanup_expired_referral_onboarding_claims(
  p_batch_size pg_catalog.int4 DEFAULT 1000
)
RETURNS pg_catalog.int4 AS $$
DECLARE
  v_deleted_count pg_catalog.int4;
  v_limit pg_catalog.int4;
BEGIN
  v_limit := CASE
    WHEN p_batch_size IS NULL OR p_batch_size <= 0 THEN 1000
    WHEN p_batch_size > 50000 THEN 50000
    ELSE p_batch_size
  END;

  WITH expired_unconsumed_claims AS (
    SELECT claim.id
    FROM public.referral_onboarding_claims AS claim
    WHERE claim.consumed_at IS NULL
      AND claim.expires_at <= pg_catalog.clock_timestamp()
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  ),
  deleted AS (
    DELETE FROM public.referral_onboarding_claims AS claim
    USING expired_unconsumed_claims AS target
    WHERE claim.id = target.id
    RETURNING claim.id
  )
  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_deleted_count
  FROM deleted;

  RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.cleanup_expired_referral_onboarding_claims(pg_catalog.int4) IS
  'Purges expired unconsumed referral onboarding claims in bounded batches; consumed conversion provenance is strictly preserved.';

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

REVOKE ALL ON FUNCTION public.cleanup_expired_referral_onboarding_claims(pg_catalog.int4)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_referral_onboarding_claims(pg_catalog.int4)
  TO service_role;

COMMIT;
