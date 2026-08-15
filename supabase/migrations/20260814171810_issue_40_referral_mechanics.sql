-- Issue #40: caller-bound Investor referral creation, atomic conversion and
-- reward entitlement processing, and an exclusive referral RLS contract.

BEGIN;

-- Fail closed instead of guessing how any pre-existing historical rows should
-- be consolidated or linked to conversions.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.investor_referrals
    GROUP BY referrer_profile_id
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'issue_40_duplicate_referrer_rows_require_remediation'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.investor_referrals
    GROUP BY referral_code
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'issue_40_duplicate_referral_codes_require_remediation'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (SELECT 1 FROM public.referral_rewards) THEN
    RAISE EXCEPTION 'issue_40_existing_rewards_require_conversion_mapping'
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;

-- The delivered table model required an invitee email per row. The canonical
-- one-code-per-Investor link does not collect invitee PII during code creation.
ALTER TABLE public.investor_referrals
  ALTER COLUMN referee_email DROP NOT NULL;

CREATE UNIQUE INDEX investor_referrals_referrer_uidx
  ON public.investor_referrals (referrer_profile_id);

CREATE UNIQUE INDEX investor_referrals_code_uidx
  ON public.investor_referrals (referral_code);

ALTER TABLE public.referral_rewards
  ADD COLUMN conversion_id pg_catalog.uuid;

ALTER TABLE public.referral_rewards
  ALTER COLUMN conversion_id SET NOT NULL,
  ADD CONSTRAINT referral_rewards_conversion_id_fkey
    FOREIGN KEY (conversion_id)
    REFERENCES public.referral_conversions(id)
    ON DELETE RESTRICT,
  ADD CONSTRAINT referral_rewards_conversion_profile_key
    UNIQUE (conversion_id, profile_id);

CREATE TABLE public.referral_reward_audit_logs (
  id pg_catalog.uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reward_id pg_catalog.uuid NOT NULL
    REFERENCES public.referral_rewards(id) ON DELETE RESTRICT,
  conversion_id pg_catalog.uuid NOT NULL
    REFERENCES public.referral_conversions(id) ON DELETE RESTRICT,
  profile_id pg_catalog.uuid NOT NULL
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  action pg_catalog.text NOT NULL
    CHECK (action IN ('reward.entitled', 'reward.expired')),
  reward_type pg_catalog.text NOT NULL,
  duration_days pg_catalog.int4 NOT NULL,
  status pg_catalog.text NOT NULL,
  actor_user_id pg_catalog.uuid,
  occurred_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now()
);

COMMENT ON TABLE public.referral_reward_audit_logs IS
  'Immutable evidence for referral reward entitlement creation and expiration.';

ALTER TABLE public.referral_reward_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.audit_referral_reward_change()
RETURNS pg_catalog.trigger AS $$
DECLARE
  v_action pg_catalog.text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_action := 'reward.entitled';
  ELSIF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'expired' THEN
    v_action := 'reward.expired';
  ELSE
    RETURN NEW;
  END IF;

  INSERT INTO public.referral_reward_audit_logs (
    reward_id,
    conversion_id,
    profile_id,
    action,
    reward_type,
    duration_days,
    status,
    actor_user_id
  ) VALUES (
    NEW.id,
    NEW.conversion_id,
    NEW.profile_id,
    v_action,
    NEW.reward_type,
    NEW.duration_days,
    NEW.status,
    auth.uid()
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.reject_referral_reward_audit_mutation()
RETURNS pg_catalog.trigger AS $$
BEGIN
  RAISE EXCEPTION 'referral_reward_audit_immutable'
    USING ERRCODE = 'P0001';
END;
$$ LANGUAGE plpgsql SECURITY INVOKER SET search_path = '';

CREATE TRIGGER referral_reward_audit
  AFTER INSERT OR UPDATE OF status ON public.referral_rewards
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_referral_reward_change();

CREATE TRIGGER referral_reward_audit_immutable
  BEFORE UPDATE OR DELETE ON public.referral_reward_audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_referral_reward_audit_mutation();

CREATE OR REPLACE FUNCTION public.get_or_create_investor_referral()
RETURNS TABLE (
  referral_code pg_catalog.text,
  created_at pg_catalog.timestamptz
) AS $$
DECLARE
  v_profile_id pg_catalog.uuid;
  v_profile public.profiles;
  v_referral public.investor_referrals;
  v_code pg_catalog.text;
BEGIN
  v_profile_id := public.current_user_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'referral_profile_not_resolved' USING ERRCODE = 'P0001';
  END IF;

  SELECT profile.*
  INTO v_profile
  FROM public.profiles AS profile
  WHERE profile.id = v_profile_id
  FOR SHARE;

  IF NOT FOUND
     OR v_profile.role <> 'investor'
     OR v_profile.account_status <> 'active' THEN
    RAISE EXCEPTION 'referral_investor_not_eligible' USING ERRCODE = 'P0001';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('referral-profile:' || v_profile_id::pg_catalog.text, 0)
  );

  SELECT referral.*
  INTO v_referral
  FROM public.investor_referrals AS referral
  WHERE referral.referrer_profile_id = v_profile_id
  FOR UPDATE;

  IF FOUND THEN
    RETURN QUERY SELECT v_referral.referral_code, v_referral.created_at;
    RETURN;
  END IF;

  FOR v_attempt IN 1..5 LOOP
    v_code := pg_catalog.encode(extensions.gen_random_bytes(24), 'hex');
    BEGIN
      INSERT INTO public.investor_referrals (
        referrer_profile_id,
        referee_email,
        referral_code,
        token_hash
      ) VALUES (
        v_profile_id,
        NULL,
        v_code,
        pg_catalog.encode(extensions.digest(v_code, 'sha256'), 'hex')
      )
      RETURNING * INTO v_referral;

      RETURN QUERY SELECT v_referral.referral_code, v_referral.created_at;
      RETURN;
    EXCEPTION WHEN unique_violation THEN
      SELECT referral.*
      INTO v_referral
      FROM public.investor_referrals AS referral
      WHERE referral.referrer_profile_id = v_profile_id;

      IF FOUND THEN
        RETURN QUERY SELECT v_referral.referral_code, v_referral.created_at;
        RETURN;
      END IF;
    END;
  END LOOP;

  RAISE EXCEPTION 'referral_code_generation_failed' USING ERRCODE = 'P0001';
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.process_investor_referral_conversion(
  p_referral_code pg_catalog.text
)
RETURNS TABLE (
  conversion_id pg_catalog.uuid,
  replayed pg_catalog.bool,
  reward_entitlement_count pg_catalog.int4
) AS $$
DECLARE
  v_referee_profile_id pg_catalog.uuid;
  v_referee public.profiles;
  v_referrer public.profiles;
  v_referral public.investor_referrals;
  v_conversion public.referral_conversions;
  v_existing_hash pg_catalog.text;
  v_submitted_hash pg_catalog.text;
  v_code pg_catalog.text;
  v_reward_count pg_catalog.int4;
BEGIN
  v_code := pg_catalog.btrim(p_referral_code);
  IF v_code IS NULL OR v_code = '' THEN
    RAISE EXCEPTION 'referral_code_required' USING ERRCODE = 'P0001';
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

  v_submitted_hash := pg_catalog.encode(
    extensions.digest(v_code, 'sha256'),
    'hex'
  );

  -- One conversion is permitted per referred Investor. Serialising on that
  -- resolved database identity makes simultaneous duplicate delivery safe.
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

  IF FOUND THEN
    SELECT referral.token_hash
    INTO v_existing_hash
    FROM public.investor_referrals AS referral
    WHERE referral.id = v_conversion.referral_id;

    IF v_existing_hash <> v_submitted_hash THEN
      RAISE EXCEPTION 'referral_conversion_conflict' USING ERRCODE = 'P0001';
    END IF;

    SELECT referral.*
    INTO v_referral
    FROM public.investor_referrals AS referral
    WHERE referral.id = v_conversion.referral_id;

    INSERT INTO public.referral_rewards (conversion_id, profile_id)
    VALUES
      (v_conversion.id, v_referral.referrer_profile_id),
      (v_conversion.id, v_referee_profile_id)
    ON CONFLICT ON CONSTRAINT referral_rewards_conversion_profile_key
      DO NOTHING;

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
  WHERE referral.token_hash = v_submitted_hash
    AND referral.referral_code = v_code
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

  RETURN QUERY SELECT v_conversion.id, false, 2;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

-- Own the complete effective policy contract. PostgreSQL permissive policies
-- combine with OR, so no legacy duplicate or mutation policy may survive.
DO $$
DECLARE
  v_policy pg_catalog.record;
  v_table pg_catalog.text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'investor_referrals',
    'referral_conversions',
    'referral_rewards',
    'referral_reward_audit_logs'
  ]
  LOOP
    FOR v_policy IN
      SELECT policyname
      FROM pg_catalog.pg_policies
      WHERE schemaname = 'public' AND tablename = v_table
    LOOP
      EXECUTE pg_catalog.format(
        'DROP POLICY %I ON public.%I',
        v_policy.policyname,
        v_table
      );
    END LOOP;
  END LOOP;
END;
$$;

CREATE POLICY investor_referrals_owner_select
  ON public.investor_referrals
  FOR SELECT
  TO authenticated
  USING (referrer_profile_id = public.current_user_profile_id());

CREATE POLICY referral_conversions_participant_select
  ON public.referral_conversions
  FOR SELECT
  TO authenticated
  USING (
    referee_profile_id = public.current_user_profile_id()
    OR EXISTS (
      SELECT 1
      FROM public.investor_referrals AS referral
      WHERE referral.id = referral_conversions.referral_id
        AND referral.referrer_profile_id = public.current_user_profile_id()
    )
  );

CREATE POLICY referral_rewards_owner_select
  ON public.referral_rewards
  FOR SELECT
  TO authenticated
  USING (profile_id = public.current_user_profile_id());

REVOKE ALL ON TABLE public.investor_referrals FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.investor_referrals TO authenticated, service_role;

REVOKE ALL ON TABLE public.referral_conversions FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.referral_conversions TO authenticated, service_role;

REVOKE ALL ON TABLE public.referral_rewards FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.referral_rewards TO authenticated, service_role;

REVOKE ALL ON TABLE public.referral_reward_audit_logs FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.referral_reward_audit_logs TO service_role;

REVOKE ALL ON FUNCTION public.audit_referral_reward_change()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.reject_referral_reward_audit_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_or_create_investor_referral()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_or_create_investor_referral()
  TO authenticated;

REVOKE ALL ON FUNCTION public.process_investor_referral_conversion(pg_catalog.text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.process_investor_referral_conversion(pg_catalog.text)
  TO authenticated;

COMMIT;
