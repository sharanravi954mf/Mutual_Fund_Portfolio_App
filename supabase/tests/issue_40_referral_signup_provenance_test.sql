-- Issue #40 corrective regression: rewarded conversions require a server
-- claim captured before Auth account creation and bound to the same account.

BEGIN;

INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('40f00000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'issue40-provenance-referrer@moneybowl.test', '{}', '{"role":"user"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('40f00000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'issue40-provenance-existing@moneybowl.test', '{}', '{"role":"user"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('40f00000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'issue40-provenance-logged-in@moneybowl.test', '{}', '{"role":"user"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('40f00000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'issue40-provenance-admin@moneybowl.test', '{}', '{"role":"platform_admin"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp());

UPDATE public.user_accounts SET account_state = 'linked_investor'
WHERE user_id IN (
  '40f00000-0000-4000-8000-000000000001',
  '40f00000-0000-4000-8000-000000000002',
  '40f00000-0000-4000-8000-000000000003'
);
UPDATE public.user_accounts SET account_state = 'advisor'
WHERE user_id = '40f00000-0000-4000-8000-000000000006';

UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000001', role = 'investor', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000001';
UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000002', role = 'investor', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000002';
UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000003', role = 'investor', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000003';
UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000006', role = 'platform_admin', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000006';

INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES
  ('40f00000-0000-4000-8000-000000000001', '40f10000-0000-4000-8000-000000000001', 'verified_email', pg_catalog.clock_timestamp(), 'active'),
  ('40f00000-0000-4000-8000-000000000002', '40f10000-0000-4000-8000-000000000002', 'verified_email', pg_catalog.clock_timestamp(), 'active'),
  ('40f00000-0000-4000-8000-000000000003', '40f10000-0000-4000-8000-000000000003', 'verified_email', pg_catalog.clock_timestamp(), 'active');

CREATE TEMP TABLE issue_40_provenance_values (
  name pg_catalog.text PRIMARY KEY,
  value pg_catalog.text NOT NULL
);
GRANT SELECT, INSERT ON issue_40_provenance_values TO anon, authenticated;

SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
INSERT INTO issue_40_provenance_values(name, value)
SELECT 'referral_code', referral_code
FROM public.get_or_create_investor_referral();
RESET ROLE;

-- Existing account and legitimate signup claims are captured by the server at
-- the same public endpoint. Eligibility differs only by trusted Auth creation
-- order, never by caller-supplied dates or identity.
SET LOCAL ROLE anon;
INSERT INTO issue_40_provenance_values(name, value)
SELECT 'existing_claim', claim_token
FROM public.create_referral_onboarding_claim(
  (SELECT value FROM issue_40_provenance_values WHERE name = 'referral_code')
);
INSERT INTO issue_40_provenance_values(name, value)
SELECT 'legitimate_claim', claim_token
FROM public.create_referral_onboarding_claim(
  (SELECT value FROM issue_40_provenance_values WHERE name = 'referral_code')
);
INSERT INTO issue_40_provenance_values(name, value)
SELECT 'advisor_claim', claim_token
FROM public.create_referral_onboarding_claim(
  (SELECT value FROM issue_40_provenance_values WHERE name = 'referral_code')
);
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.create_referral_onboarding_claim('invalid-public-code');
    RAISE EXCEPTION 'invalid public referral code created a claim';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_code_invalid' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- Opening /join while already authenticated still produces only a server
-- claim. The subsequent server binding must reject the pre-existing account.
SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000003","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
INSERT INTO issue_40_provenance_values(name, value)
SELECT 'logged_in_claim', claim_token
FROM public.create_referral_onboarding_claim(
  (SELECT value FROM issue_40_provenance_values WHERE name = 'referral_code')
);
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.bind_referral_onboarding_claim(
      (SELECT value FROM issue_40_provenance_values WHERE name = 'logged_in_claim')
    );
    RAISE EXCEPTION 'logged-in existing account bypassed referral provenance';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_claim_account_predates_capture' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- Both the lifecycle bind and a direct conversion invocation fail closed for
-- an account that predates the claim.
SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000002","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.bind_referral_onboarding_claim(
      (SELECT value FROM issue_40_provenance_values WHERE name = 'existing_claim')
    );
    RAISE EXCEPTION 'pre-existing Investor bound a referral claim';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_claim_account_predates_capture' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM * FROM public.process_investor_referral_conversion(
      (SELECT value FROM issue_40_provenance_values WHERE name = 'existing_claim')
    );
    RAISE EXCEPTION 'pre-existing Investor directly converted a referral claim';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_claim_account_predates_capture' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- These Auth users are inserted after claim capture using database time. User
-- A is the legitimate referred signup; user B proves account-bound transfer
-- prevention; the advisor proves role eligibility remains independent.
SELECT pg_catalog.pg_sleep(0.01);
INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('40f00000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'issue40-provenance-new-a@moneybowl.test', '{}', '{"role":"user"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('40f00000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'issue40-provenance-new-b@moneybowl.test', '{}', '{"role":"user"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('40f00000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'issue40-provenance-advisor@moneybowl.test', '{}', '{"role":"user"}', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp());

UPDATE public.user_accounts SET account_state = 'linked_investor'
WHERE user_id IN (
  '40f00000-0000-4000-8000-000000000004',
  '40f00000-0000-4000-8000-000000000005'
);
UPDATE public.user_accounts SET account_state = 'advisor'
WHERE user_id = '40f00000-0000-4000-8000-000000000007';
UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000004', role = 'investor', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000004';
UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000005', role = 'investor', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000005';
UPDATE public.profiles SET id = '40f10000-0000-4000-8000-000000000007', role = 'advisor', account_status = 'active'
WHERE user_id = '40f00000-0000-4000-8000-000000000007';
INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES
  ('40f00000-0000-4000-8000-000000000004', '40f10000-0000-4000-8000-000000000004', 'verified_email', pg_catalog.clock_timestamp(), 'active'),
  ('40f00000-0000-4000-8000-000000000005', '40f10000-0000-4000-8000-000000000005', 'verified_email', pg_catalog.clock_timestamp(), 'active');

SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000004","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
SELECT * FROM public.bind_referral_onboarding_claim(
  (SELECT value FROM issue_40_provenance_values WHERE name = 'legitimate_claim')
);
RESET ROLE;

-- Once bound to user A, user B cannot bind or invoke conversion with the same
-- opaque claim even though user B was also created after capture.
SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000005","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.bind_referral_onboarding_claim(
      (SELECT value FROM issue_40_provenance_values WHERE name = 'legitimate_claim')
    );
    RAISE EXCEPTION 'referral claim transferred to a second account';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_claim_account_conflict' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.process_investor_referral_conversion(
      (SELECT value FROM issue_40_provenance_values WHERE name = 'legitimate_claim')
    );
    RAISE EXCEPTION 'second account replayed another account claim';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_claim_account_conflict' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- The canonical active Investor signup converts once and exact claim replay is
-- stable. Claim consumption and conversion are committed by one RPC statement.
SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000004","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
INSERT INTO issue_40_provenance_values(name, value)
SELECT 'conversion_id', conversion_id::pg_catalog.text
FROM public.process_investor_referral_conversion(
  (SELECT value FROM issue_40_provenance_values WHERE name = 'legitimate_claim')
)
WHERE NOT replayed AND reward_entitlement_count = 2;
DO $$
DECLARE
  v_replayed pg_catalog.bool;
  v_reward_count pg_catalog.int4;
BEGIN
  SELECT replayed, reward_entitlement_count
  INTO v_replayed, v_reward_count
  FROM public.process_investor_referral_conversion(
    (SELECT value FROM issue_40_provenance_values WHERE name = 'legitimate_claim')
  );
  IF NOT v_replayed OR v_reward_count <> 2 THEN
    RAISE EXCEPTION 'exact claim replay was not idempotent';
  END IF;

  IF NOT public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'legitimate referee did not receive Premium entitlement';
  END IF;
END;
$$;
RESET ROLE;

SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF NOT public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'legitimate referrer did not receive Premium entitlement';
  END IF;
END;
$$;
RESET ROLE;

-- A newly created MFD-side account may bind possession of a claim, but role
-- eligibility still denies conversion and no Premium Investor access appears.
SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000007","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
SELECT * FROM public.bind_referral_onboarding_claim(
  (SELECT value FROM issue_40_provenance_values WHERE name = 'advisor_claim')
);
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.process_investor_referral_conversion(
      (SELECT value FROM issue_40_provenance_values WHERE name = 'advisor_claim')
    );
    RAISE EXCEPTION 'MFD-side account converted a referral claim';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_investor_not_eligible' THEN RAISE; END IF;
  END;
  IF public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'MFD-side account gained Premium Investor entitlement';
  END IF;
END;
$$;
RESET ROLE;

SELECT set_config('request.jwt.claims', '{"sub":"40f00000-0000-4000-8000-000000000006","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'Platform Admin gained Premium Investor entitlement';
  END IF;
END;
$$;
RESET ROLE;

-- Verify raw tokens are absent at rest, consumption is linked atomically, and
-- the processor uses only trusted server identities/times with no age window.
DO $$
DECLARE
  v_claim_token pg_catalog.text := (
    SELECT value FROM issue_40_provenance_values WHERE name = 'legitimate_claim'
  );
BEGIN
  IF EXISTS (
       SELECT 1 FROM public.referral_onboarding_claims
       WHERE claim_token_hash = v_claim_token
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.referral_onboarding_claims AS claim
       WHERE claim.claim_token_hash = pg_catalog.encode(
         extensions.digest(v_claim_token, 'sha256'), 'hex'
       )
         AND claim.bound_user_id = '40f00000-0000-4000-8000-000000000004'
         AND claim.consumed_at IS NOT NULL
         AND claim.conversion_id = (
           SELECT value::pg_catalog.uuid
           FROM issue_40_provenance_values WHERE name = 'conversion_id'
         )
     ) THEN
    RAISE EXCEPTION 'claim hashing, binding, or atomic consumption is incorrect';
  END IF;

  IF (SELECT pg_catalog.count(*) FROM public.referral_conversions) <> 1
     OR (SELECT pg_catalog.count(*) FROM public.referral_rewards) <> 2
     OR (SELECT pg_catalog.count(*) FROM public.referral_reward_audit_logs) <> 2 THEN
    RAISE EXCEPTION 'provenance flow changed conversion/reward/audit cardinality';
  END IF;

  IF NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS function
       JOIN pg_catalog.pg_namespace AS namespace
         ON namespace.oid = function.pronamespace
       WHERE namespace.nspname = 'public'
         AND function.proname = 'process_investor_referral_conversion'
         AND function.prosrc LIKE '%auth.users%'
         AND function.prosrc LIKE '%created_at <= v_claim.captured_at%'
         AND function.prosrc NOT LIKE '%raw_user_meta_data%'
         AND function.prosrc NOT LIKE '%make_interval%'
     ) THEN
    RAISE EXCEPTION 'conversion lacks trusted Auth-time provenance or invented an age threshold';
  END IF;
END;
$$;

ROLLBACK;
