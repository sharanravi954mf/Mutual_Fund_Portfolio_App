-- Issue #40 corrective regression: bounded referral claim lifecycle,
-- expiry enforcement on binding and conversion, service-role batch cleanup,
-- immutable consumed conversion provenance preservation, and exact privilege checks.

BEGIN;

INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('40f00000-0000-4000-8000-000000000011', 'authenticated', 'authenticated', 'issue40-lifecycle-referrer@moneybowl.test', '{}', '{"role":"user"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('40f00000-0000-4000-8000-000000000012', 'authenticated', 'authenticated', 'issue40-lifecycle-referee@moneybowl.test', '{}', '{"role":"user"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp());

UPDATE public.user_accounts SET account_state = 'linked_investor'
WHERE user_id IN (
  '40f00000-0000-4000-8000-000000000011',
  '40f00000-0000-4000-8000-000000000012'
);

UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000011', role = 'investor', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000011';
UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000012', role = 'investor', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000012';

INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES
  ('40f00000-0000-4000-8000-000000000011', '40f10000-0000-4000-8000-000000000011', 'verified_email', pg_catalog.clock_timestamp(), 'active'),
  ('40f00000-0000-4000-8000-000000000012', '40f10000-0000-4000-8000-000000000012', 'verified_email', pg_catalog.clock_timestamp(), 'active');

CREATE TEMP TABLE issue_40_lifecycle_values (
  name pg_catalog.text PRIMARY KEY,
  value pg_catalog.text NOT NULL
);
GRANT SELECT, INSERT, UPDATE ON issue_40_lifecycle_values TO anon, authenticated, service_role;

-- 1. Referrer creates referral code
SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000011","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
INSERT INTO issue_40_lifecycle_values(name, value)
SELECT 'referral_code', referral_code
FROM public.get_or_create_investor_referral();
RESET ROLE;

-- 2. Anonymous visitor creates claims: one fresh, one to expire before bind, one to expire before convert
SET LOCAL ROLE anon;
INSERT INTO issue_40_lifecycle_values(name, value)
SELECT 'fresh_claim', claim_token
FROM public.create_referral_onboarding_claim(
  (SELECT value FROM issue_40_lifecycle_values WHERE name = 'referral_code')
);
INSERT INTO issue_40_lifecycle_values(name, value)
SELECT 'expired_bind_claim', claim_token
FROM public.create_referral_onboarding_claim(
  (SELECT value FROM issue_40_lifecycle_values WHERE name = 'referral_code')
);
INSERT INTO issue_40_lifecycle_values(name, value)
SELECT 'expired_convert_claim', claim_token
FROM public.create_referral_onboarding_claim(
  (SELECT value FROM issue_40_lifecycle_values WHERE name = 'referral_code')
);
INSERT INTO issue_40_lifecycle_values(name, value)
SELECT 'cleanup_candidate_claim', claim_token
FROM public.create_referral_onboarding_claim(
  (SELECT value FROM issue_40_lifecycle_values WHERE name = 'referral_code')
);
RESET ROLE;

-- Verify expires_at is correctly set and ordered on creation
DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)
  INTO v_count
  FROM public.referral_onboarding_claims
  WHERE expires_at IS NOT NULL
    AND expires_at > captured_at
    AND expires_at >= captured_at + '23 hours'::pg_catalog.interval;

  IF v_count < 4 THEN
    RAISE EXCEPTION 'claims were created without proper expires_at TTL';
  END IF;
END;
$$;

-- Create legitimate new user whose creation time is after claim capture
SELECT pg_catalog.pg_sleep(0.01);
INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('40f00000-0000-4000-8000-000000000013', 'authenticated', 'authenticated', 'issue40-lifecycle-new@moneybowl.test', '{}', '{"role":"user"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp());

UPDATE public.user_accounts SET account_state = 'linked_investor'
WHERE user_id = '40f00000-0000-4000-8000-000000000013';
UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000013', role = 'investor', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000013';
INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES
  ('40f00000-0000-4000-8000-000000000013', '40f10000-0000-4000-8000-000000000013', 'verified_email', pg_catalog.clock_timestamp(), 'active');

-- Simulate expiry for expired_bind_claim, expired_convert_claim, and cleanup_candidate_claim
UPDATE public.referral_onboarding_claims
SET captured_at = pg_catalog.clock_timestamp() - '25 hours'::pg_catalog.interval,
    expires_at = pg_catalog.clock_timestamp() - '1 hour'::pg_catalog.interval
WHERE claim_token_hash = pg_catalog.encode(
  extensions.digest((SELECT value FROM issue_40_lifecycle_values WHERE name = 'expired_bind_claim'), 'sha256'),
  'hex'
);

UPDATE public.referral_onboarding_claims
SET captured_at = pg_catalog.clock_timestamp() - '25 hours'::pg_catalog.interval,
    expires_at = pg_catalog.clock_timestamp() - '1 hour'::pg_catalog.interval
WHERE claim_token_hash = pg_catalog.encode(
  extensions.digest((SELECT value FROM issue_40_lifecycle_values WHERE name = 'cleanup_candidate_claim'), 'sha256'),
  'hex'
);

-- 3. Expired claim cannot bind
SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000013","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.bind_referral_onboarding_claim(
      (SELECT value FROM issue_40_lifecycle_values WHERE name = 'expired_bind_claim')
    );
    RAISE EXCEPTION 'expired claim was successfully bound';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_claim_expired' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- 4. Bind expired_convert_claim while valid, then simulate expiry, then verify conversion fails
SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000013","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
SELECT * FROM public.bind_referral_onboarding_claim(
  (SELECT value FROM issue_40_lifecycle_values WHERE name = 'expired_convert_claim')
);
RESET ROLE;

UPDATE public.referral_onboarding_claims
SET captured_at = pg_catalog.clock_timestamp() - '25 hours'::pg_catalog.interval,
    bound_at = pg_catalog.clock_timestamp() - '24 hours'::pg_catalog.interval,
    expires_at = pg_catalog.clock_timestamp() - '1 hour'::pg_catalog.interval
WHERE claim_token_hash = pg_catalog.encode(
  extensions.digest((SELECT value FROM issue_40_lifecycle_values WHERE name = 'expired_convert_claim'), 'sha256'),
  'hex'
);

SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000013","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.process_investor_referral_conversion(
      (SELECT value FROM issue_40_lifecycle_values WHERE name = 'expired_convert_claim')
    );
    RAISE EXCEPTION 'expired bound claim converted into rewards';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_claim_expired' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- 5. Fresh claim binds and converts successfully
SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000013","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
SELECT * FROM public.bind_referral_onboarding_claim(
  (SELECT value FROM issue_40_lifecycle_values WHERE name = 'fresh_claim')
);
INSERT INTO issue_40_lifecycle_values(name, value)
SELECT 'fresh_conversion_id', conversion_id::pg_catalog.text
FROM public.process_investor_referral_conversion(
  (SELECT value FROM issue_40_lifecycle_values WHERE name = 'fresh_claim')
);
RESET ROLE;

-- 6. Simulate expiry on the already-consumed fresh claim, then verify exact replay still works
UPDATE public.referral_onboarding_claims
SET captured_at = pg_catalog.clock_timestamp() - '25 hours'::pg_catalog.interval,
    bound_at = pg_catalog.clock_timestamp() - '24 hours'::pg_catalog.interval,
    consumed_at = pg_catalog.clock_timestamp() - '23 hours'::pg_catalog.interval,
    expires_at = pg_catalog.clock_timestamp() - '1 hour'::pg_catalog.interval
WHERE claim_token_hash = pg_catalog.encode(
  extensions.digest((SELECT value FROM issue_40_lifecycle_values WHERE name = 'fresh_claim'), 'sha256'),
  'hex'
);

SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000013","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  v_replayed pg_catalog.bool;
  v_reward_count pg_catalog.int4;
BEGIN
  SELECT replayed, reward_entitlement_count
  INTO v_replayed, v_reward_count
  FROM public.process_investor_referral_conversion(
    (SELECT value FROM issue_40_lifecycle_values WHERE name = 'fresh_claim')
  );
  IF NOT v_replayed OR v_reward_count <> 2 THEN
    RAISE EXCEPTION 'consumed claim exact replay failed after expiry';
  END IF;
END;
$$;
RESET ROLE;

-- 7. Test cleanup mechanism:
-- Only service_role can execute cleanup_expired_referral_onboarding_claims
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM public.cleanup_expired_referral_onboarding_claims(100);
    RAISE EXCEPTION 'anon was allowed to call cleanup_expired_referral_onboarding_claims';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$$;
RESET ROLE;

SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000013","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.cleanup_expired_referral_onboarding_claims(100);
    RAISE EXCEPTION 'authenticated was allowed to call cleanup_expired_referral_onboarding_claims';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$$;
RESET ROLE;

-- Now run cleanup as service_role
SET LOCAL ROLE service_role;
INSERT INTO issue_40_lifecycle_values(name, value)
SELECT 'deleted_count', public.cleanup_expired_referral_onboarding_claims(100)::pg_catalog.text;
RESET ROLE;

DO $$
DECLARE
  v_deleted pg_catalog.int4;
  v_consumed_exists pg_catalog.bool;
  v_unconsumed_expired_exists pg_catalog.bool;
BEGIN
  SELECT value::pg_catalog.int4
  INTO v_deleted
  FROM issue_40_lifecycle_values
  WHERE name = 'deleted_count';

  IF v_deleted < 3 THEN
    RAISE EXCEPTION 'cleanup did not remove expected expired unconsumed claims (deleted: %)', v_deleted;
  END IF;

  -- Verify consumed claim survived
  SELECT EXISTS (
    SELECT 1 FROM public.referral_onboarding_claims
    WHERE claim_token_hash = pg_catalog.encode(
      extensions.digest((SELECT value FROM issue_40_lifecycle_values WHERE name = 'fresh_claim'), 'sha256'),
      'hex'
    )
    AND consumed_at IS NOT NULL
  ) INTO v_consumed_exists;

  IF NOT v_consumed_exists THEN
    RAISE EXCEPTION 'cleanup deleted consumed conversion provenance row!';
  END IF;

  -- Verify conversions and rewards survived
  IF (SELECT pg_catalog.count(*) FROM public.referral_conversions) < 1
     OR (SELECT pg_catalog.count(*) FROM public.referral_rewards) < 2
     OR (SELECT pg_catalog.count(*) FROM public.referral_reward_audit_logs) < 2 THEN
    RAISE EXCEPTION 'cleanup impacted conversion/reward/audit records!';
  END IF;

  -- Verify expired unconsumed claims were purged
  SELECT EXISTS (
    SELECT 1 FROM public.referral_onboarding_claims
    WHERE consumed_at IS NULL
      AND expires_at <= pg_catalog.clock_timestamp()
  ) INTO v_unconsumed_expired_exists;

  IF v_unconsumed_expired_exists THEN
    RAISE EXCEPTION 'expired unconsumed claims still exist after cleanup!';
  END IF;
END;
$$;

-- 8. Table-level security and metadata verification
DO $$
BEGIN
  -- Direct mutation/read checks
  IF pg_catalog.has_table_privilege('anon', 'public.referral_onboarding_claims', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'public.referral_onboarding_claims', 'INSERT')
     OR pg_catalog.has_table_privilege('anon', 'public.referral_onboarding_claims', 'UPDATE')
     OR pg_catalog.has_table_privilege('anon', 'public.referral_onboarding_claims', 'DELETE') THEN
    RAISE EXCEPTION 'anon has direct table privileges on referral_onboarding_claims';
  END IF;

  IF pg_catalog.has_table_privilege('authenticated', 'public.referral_onboarding_claims', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.referral_onboarding_claims', 'INSERT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.referral_onboarding_claims', 'UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', 'public.referral_onboarding_claims', 'DELETE') THEN
    RAISE EXCEPTION 'authenticated has direct table privileges on referral_onboarding_claims';
  END IF;

  -- Cleanup function privileges
  IF pg_catalog.has_function_privilege('anon', 'public.cleanup_expired_referral_onboarding_claims(int4)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'public.cleanup_expired_referral_onboarding_claims(int4)', 'EXECUTE') THEN
    RAISE EXCEPTION 'unprivileged roles can execute cleanup_expired_referral_onboarding_claims';
  END IF;

  IF NOT pg_catalog.has_function_privilege('service_role', 'public.cleanup_expired_referral_onboarding_claims(int4)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role cannot execute cleanup_expired_referral_onboarding_claims';
  END IF;

  -- Function security check: SECURITY DEFINER + search_path = ''
  IF EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS function
       JOIN pg_catalog.pg_namespace AS namespace
         ON namespace.oid = function.pronamespace
       WHERE namespace.nspname = 'public'
         AND function.proname IN (
           'create_referral_onboarding_claim',
           'bind_referral_onboarding_claim',
           'process_investor_referral_conversion',
           'cleanup_expired_referral_onboarding_claims'
         )
         AND (
           NOT function.prosecdef
           OR NOT (
             ARRAY['search_path=']::text[] <@ COALESCE(function.proconfig, ARRAY[]::text[])
             OR ARRAY['search_path=""']::text[] <@ COALESCE(function.proconfig, ARRAY[]::text[])
             OR ARRAY['search_path=pg_temp']::text[] <@ COALESCE(function.proconfig, ARRAY[]::text[])
           )
         )
     ) THEN
    RAISE EXCEPTION 'referral claim RPCs lack SECURITY DEFINER or empty search_path';
  END IF;

  -- Cleanup partial index verification
  IF NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND tablename = 'referral_onboarding_claims'
         AND indexname = 'referral_onboarding_claims_cleanup_idx'
     ) THEN
    RAISE EXCEPTION 'referral_onboarding_claims_cleanup_idx is missing';
  END IF;
END;
$$;

ROLLBACK;
