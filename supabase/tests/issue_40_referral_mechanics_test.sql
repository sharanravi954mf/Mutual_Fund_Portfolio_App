-- Issue #40 regression: caller-bound referral creation, atomic conversion,
-- reward entitlement, immutable audit, exact RLS, and least privilege.

BEGIN;

INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('40000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue40-referrer@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('40000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue40-referee@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('40000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'issue40-second-referrer@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('40000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'issue40-unrelated@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('40000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'issue40-platform-admin@moneybowl.test', '{}', '{"role":"platform_admin"}', now(), now()),
  ('40000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'issue40-advisor@moneybowl.test', '{}', '{"role":"user"}', now(), now());

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id IN (
  '40000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000002',
  '40000000-0000-0000-0000-000000000003',
  '40000000-0000-0000-0000-000000000004'
);
UPDATE public.user_accounts SET account_state = 'advisor'
WHERE user_id IN (
  '40000000-0000-0000-0000-000000000005',
  '40000000-0000-0000-0000-000000000006'
);

UPDATE public.profiles SET id = '40100000-0000-0000-0000-000000000001', role = 'investor', account_status = 'active'
WHERE user_id = '40000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '40100000-0000-0000-0000-000000000002', role = 'investor', account_status = 'active'
WHERE user_id = '40000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET id = '40100000-0000-0000-0000-000000000003', role = 'investor', account_status = 'active'
WHERE user_id = '40000000-0000-0000-0000-000000000003';
UPDATE public.profiles SET id = '40100000-0000-0000-0000-000000000004', role = 'investor', account_status = 'active'
WHERE user_id = '40000000-0000-0000-0000-000000000004';
UPDATE public.profiles SET id = '40100000-0000-0000-0000-000000000005', role = 'platform_admin', account_status = 'active'
WHERE user_id = '40000000-0000-0000-0000-000000000005';
UPDATE public.profiles SET id = '40100000-0000-0000-0000-000000000006', role = 'advisor', account_status = 'active'
WHERE user_id = '40000000-0000-0000-0000-000000000006';

INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES
  ('40000000-0000-0000-0000-000000000001', '40100000-0000-0000-0000-000000000001', 'verified_email', now(), 'active'),
  ('40000000-0000-0000-0000-000000000002', '40100000-0000-0000-0000-000000000002', 'verified_email', now(), 'active'),
  ('40000000-0000-0000-0000-000000000003', '40100000-0000-0000-0000-000000000003', 'verified_email', now(), 'active'),
  ('40000000-0000-0000-0000-000000000004', '40100000-0000-0000-0000-000000000004', 'verified_email', now(), 'active');

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES (
  '40200000-0000-0000-0000-000000000001',
  'Issue 40 MFD Workspace',
  'issue-40-mfd-workspace',
  '40100000-0000-0000-0000-000000000006',
  'active'
);
INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES (
  '40200000-0000-0000-0000-000000000001',
  '40100000-0000-0000-0000-000000000006',
  'admin',
  'active'
);

CREATE TEMP TABLE issue_40_values (
  name text PRIMARY KEY,
  value text NOT NULL
);
GRANT SELECT, INSERT ON TABLE issue_40_values TO authenticated;
GRANT SELECT ON TABLE issue_40_values TO service_role;

DO $$
BEGIN
  IF (SELECT count(*) FROM pg_catalog.pg_policies
      WHERE schemaname = 'public' AND tablename = 'investor_referrals') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname = 'public' AND tablename = 'investor_referrals'
         AND policyname = 'investor_referrals_owner_select'
         AND cmd = 'SELECT' AND roles = ARRAY['authenticated']::name[]
     )
     OR (SELECT count(*) FROM pg_catalog.pg_policies
         WHERE schemaname = 'public' AND tablename = 'referral_conversions') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname = 'public' AND tablename = 'referral_conversions'
         AND policyname = 'referral_conversions_participant_select'
         AND cmd = 'SELECT' AND roles = ARRAY['authenticated']::name[]
     )
     OR (SELECT count(*) FROM pg_catalog.pg_policies
         WHERE schemaname = 'public' AND tablename = 'referral_rewards') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname = 'public' AND tablename = 'referral_rewards'
         AND policyname = 'referral_rewards_owner_select'
         AND cmd = 'SELECT' AND roles = ARRAY['authenticated']::name[]
     )
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname = 'public' AND tablename = 'referral_reward_audit_logs'
     ) THEN
    RAISE EXCEPTION 'Issue #40 effective policy sets are not exact';
  END IF;

  IF EXISTS (
       SELECT 1 FROM (VALUES
         ('investor_referrals'), ('referral_conversions'), ('referral_rewards'),
         ('referral_reward_audit_logs')
       ) AS target(table_name)
       WHERE NOT EXISTS (
         SELECT 1 FROM pg_catalog.pg_class AS c
         JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relname = target.table_name
           AND c.relrowsecurity
       )
     ) THEN
    RAISE EXCEPTION 'Issue #40 RLS is not enabled on every protected table';
  END IF;

  IF has_table_privilege('anon', 'public.investor_referrals', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.investor_referrals', 'INSERT,UPDATE,DELETE')
     OR NOT has_table_privilege('authenticated', 'public.investor_referrals', 'SELECT')
     OR has_table_privilege('anon', 'public.referral_conversions', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.referral_conversions', 'INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon', 'public.referral_rewards', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.referral_rewards', 'INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.referral_reward_audit_logs', 'SELECT,INSERT,UPDATE,DELETE')
     OR NOT has_table_privilege('service_role', 'public.referral_reward_audit_logs', 'SELECT')
     OR has_table_privilege('service_role', 'public.referral_reward_audit_logs', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'Issue #40 table privilege contract is not exact';
  END IF;

  IF has_function_privilege('anon', 'public.get_or_create_investor_referral()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_or_create_investor_referral()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.get_or_create_investor_referral()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.process_investor_referral_conversion(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.process_investor_referral_conversion(text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.process_investor_referral_conversion(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Issue #40 RPC privilege contract is not exact';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN ('get_or_create_investor_referral', 'process_investor_referral_conversion')) <> 2
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS p
       JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND p.proname IN ('get_or_create_investor_referral', 'process_investor_referral_conversion')
         AND (NOT p.prosecdef OR p.proconfig <> ARRAY['search_path=""']::text[])
     ) THEN
    RAISE EXCEPTION 'Issue #40 exposes a spoofable overload or unsafe function';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS p
       JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND p.proname = 'process_investor_referral_conversion'
         AND p.prosrc LIKE '%pg_advisory_xact_lock%'
         AND p.prosrc LIKE '%FOR UPDATE%'
         AND p.prosrc LIKE '%ON CONFLICT%'
     ) THEN
    RAISE EXCEPTION 'Issue #40 conversion processor lacks concurrency fencing';
  END IF;
END;
$$;

SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.get_or_create_investor_referral();
    RAISE EXCEPTION 'anonymous referral creation was permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM * FROM public.process_investor_referral_conversion('not-a-code');
    RAISE EXCEPTION 'anonymous referral conversion was permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;

-- The owner can create one high-entropy code and exact retries return it.
SELECT set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
INSERT INTO issue_40_values(name, value)
SELECT 'first_code', referral_code FROM public.get_or_create_investor_referral();
DO $$
DECLARE
  v_retry text;
BEGIN
  SELECT referral_code INTO v_retry FROM public.get_or_create_investor_referral();
  IF v_retry <> (SELECT value FROM issue_40_values WHERE name = 'first_code') THEN
    RAISE EXCEPTION 'referral creation retry changed the code';
  END IF;
  IF v_retry !~ '^[0-9a-f]{48}$' THEN
    RAISE EXCEPTION 'referral code is not 192-bit lowercase hex';
  END IF;
  IF (SELECT count(*) FROM public.investor_referrals) <> 1 THEN
    RAISE EXCEPTION 'referral creation is not idempotent';
  END IF;
  BEGIN
    INSERT INTO public.investor_referrals(referrer_profile_id, referee_email, referral_code, token_hash)
    VALUES ('40100000-0000-0000-0000-000000000001', NULL, 'direct', 'direct');
    RAISE EXCEPTION 'authenticated direct referral insert was permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;

DO $$
BEGIN
  IF (SELECT token_hash FROM public.investor_referrals
      WHERE referrer_profile_id = '40100000-0000-0000-0000-000000000001') <>
     pg_catalog.encode(extensions.digest(
       (SELECT value FROM issue_40_values WHERE name = 'first_code'), 'sha256'
     ), 'hex') THEN
    RAISE EXCEPTION 'stored referral hash does not match the shared code';
  END IF;
END;
$$;

-- A second Investor receives a distinct code.
SELECT set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
INSERT INTO issue_40_values(name, value)
SELECT 'second_code', referral_code FROM public.get_or_create_investor_referral();
DO $$
BEGIN
  IF (SELECT value FROM issue_40_values WHERE name = 'first_code') =
     (SELECT value FROM issue_40_values WHERE name = 'second_code') THEN
    RAISE EXCEPTION 'different Investors received the same code';
  END IF;
END;
$$;
RESET ROLE;

-- Self attribution is rejected without state change.
SELECT set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.process_investor_referral_conversion(
      (SELECT value FROM issue_40_values WHERE name = 'first_code')
    );
    RAISE EXCEPTION 'self referral was permitted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_self_not_allowed' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- The referee processes the code once; an exact replay is harmless and a
-- conflicting second code is rejected.
SELECT set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
INSERT INTO issue_40_values(name, value)
SELECT 'conversion_id', conversion_id::text
FROM public.process_investor_referral_conversion(
  (SELECT value FROM issue_40_values WHERE name = 'first_code')
)
WHERE replayed = false AND reward_entitlement_count = 2;
DO $$
DECLARE
  v_replayed boolean;
  v_count integer;
BEGIN
  SELECT replayed, reward_entitlement_count INTO v_replayed, v_count
  FROM public.process_investor_referral_conversion(
    (SELECT value FROM issue_40_values WHERE name = 'first_code')
  );
  IF NOT v_replayed OR v_count <> 2 THEN
    RAISE EXCEPTION 'exact conversion replay did not return stable state';
  END IF;

  BEGIN
    PERFORM * FROM public.process_investor_referral_conversion(
      (SELECT value FROM issue_40_values WHERE name = 'second_code')
    );
    RAISE EXCEPTION 'conflicting referral attribution was permitted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_conversion_conflict' THEN RAISE; END IF;
  END;

  IF (SELECT count(*) FROM public.referral_conversions) <> 1
     OR (SELECT count(*) FROM public.referral_rewards) <> 1 THEN
    -- RLS intentionally exposes only the referee's own entitlement here.
    RAISE EXCEPTION 'referee visibility or duplicate conversion state is wrong';
  END IF;
  BEGIN
    SELECT count(*) FROM public.referral_reward_audit_logs;
    RAISE EXCEPTION 'authenticated audit read was permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO public.referral_rewards(conversion_id, profile_id)
    VALUES (
      (SELECT value::uuid FROM issue_40_values WHERE name = 'conversion_id'),
      '40100000-0000-0000-0000-000000000002'
    );
    RAISE EXCEPTION 'authenticated direct reward insert was permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.referral_conversions
      WHERE id = (SELECT value::uuid FROM issue_40_values WHERE name = 'conversion_id')) <> 1
     OR (SELECT count(*) FROM public.referral_rewards
         WHERE conversion_id = (SELECT value::uuid FROM issue_40_values WHERE name = 'conversion_id')) <> 2
     OR (SELECT count(*) FROM public.referral_reward_audit_logs
         WHERE conversion_id = (SELECT value::uuid FROM issue_40_values WHERE name = 'conversion_id')
           AND action = 'reward.entitled') <> 2 THEN
    RAISE EXCEPTION 'conversion, reward, or audit cardinality is incorrect';
  END IF;
  BEGIN
    DELETE FROM public.referral_rewards;
    RAISE EXCEPTION 'service role reward mutation was permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;

-- Referrer sees their referral, the shared conversion, and only their reward.
SELECT set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.investor_referrals) <> 1
     OR (SELECT count(*) FROM public.referral_conversions) <> 1
     OR (SELECT count(*) FROM public.referral_rewards) <> 1 THEN
    RAISE EXCEPTION 'referrer RLS visibility is incorrect';
  END IF;
END;
$$;
RESET ROLE;

-- Unrelated Investors and MFD-side members cannot browse referral state.
SELECT set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.investor_referrals)
     OR EXISTS (SELECT 1 FROM public.referral_conversions)
     OR EXISTS (SELECT 1 FROM public.referral_rewards) THEN
    RAISE EXCEPTION 'unrelated Investor can read referral state';
  END IF;
  BEGIN
    PERFORM * FROM public.process_investor_referral_conversion('not-a-code');
    RAISE EXCEPTION 'invalid code was accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_code_invalid' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

SELECT set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000006","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.investor_referrals)
     OR EXISTS (SELECT 1 FROM public.referral_conversions)
     OR EXISTS (SELECT 1 FROM public.referral_rewards) THEN
    RAISE EXCEPTION 'MFD-side member can read Investor referral state';
  END IF;
  BEGIN
    PERFORM * FROM public.get_or_create_investor_referral();
    RAISE EXCEPTION 'advisor referral creation was permitted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_investor_not_eligible' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

SELECT set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000005","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.investor_referrals)
     OR EXISTS (SELECT 1 FROM public.referral_conversions)
     OR EXISTS (SELECT 1 FROM public.referral_rewards) THEN
    RAISE EXCEPTION 'Platform Admin can read Investor referral state';
  END IF;
  BEGIN
    PERFORM * FROM public.get_or_create_investor_referral();
    RAISE EXCEPTION 'Platform Admin referral creation was permitted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_investor_not_eligible' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- Referential integrity prevents rewards without a real conversion, and the
-- audit ledger rejects even privileged updates/deletes.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.referral_rewards(conversion_id, profile_id)
    VALUES ('40900000-0000-0000-0000-000000000001', '40100000-0000-0000-0000-000000000004');
    RAISE EXCEPTION 'reward without conversion was permitted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.referral_reward_audit_logs SET status = 'expired';
    RAISE EXCEPTION 'audit update was permitted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_reward_audit_immutable' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM public.referral_reward_audit_logs;
    RAISE EXCEPTION 'audit delete was permitted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referral_reward_audit_immutable' THEN RAISE; END IF;
  END;
END;
$$;

ROLLBACK;
