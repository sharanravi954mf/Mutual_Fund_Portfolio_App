-- Test Suite: Issue #30 workspace-isolated RLS for order_requests.

BEGIN;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('97000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue30-platform-admin@moneybowl.test', '{"user_role":"platform_admin"}', '{}', now(), now()),
  ('97000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue30-owner-a@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('97000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'issue30-investor-a@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('97000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'issue30-investor-b@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('97000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'issue30-advisor-a@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('97000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'issue30-multi-advisor@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('97000000-0000-0000-0000-000000000007', 'authenticated', 'authenticated', 'issue30-owner-b@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('97000000-0000-0000-0000-000000000008', 'authenticated', 'authenticated', 'issue30-inactive-advisor@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('97000000-0000-0000-0000-000000000009', 'authenticated', 'authenticated', 'issue30-family-guest@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('97000000-0000-0000-0000-000000000010', 'authenticated', 'authenticated', 'issue30-inactive-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now());

UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id IN (
  '97000000-0000-0000-0000-000000000001',
  '97000000-0000-0000-0000-000000000002',
  '97000000-0000-0000-0000-000000000005',
  '97000000-0000-0000-0000-000000000006',
  '97000000-0000-0000-0000-000000000007',
  '97000000-0000-0000-0000-000000000008'
);

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id IN (
  '97000000-0000-0000-0000-000000000003',
  '97000000-0000-0000-0000-000000000004',
  '97000000-0000-0000-0000-000000000009',
  '97000000-0000-0000-0000-000000000010'
);

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000001', role = 'platform_admin', full_name = 'Issue 30 Platform Admin'
WHERE user_id = '97000000-0000-0000-0000-000000000001';

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000002', role = 'advisor', full_name = 'Issue 30 Owner A'
WHERE user_id = '97000000-0000-0000-0000-000000000002';

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000003', role = 'investor', full_name = 'Issue 30 Investor A'
WHERE user_id = '97000000-0000-0000-0000-000000000003';

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000004', role = 'investor', full_name = 'Issue 30 Investor B'
WHERE user_id = '97000000-0000-0000-0000-000000000004';

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000005', role = 'advisor', full_name = 'Issue 30 Advisor A'
WHERE user_id = '97000000-0000-0000-0000-000000000005';

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000006', role = 'advisor', full_name = 'Issue 30 Multi Advisor'
WHERE user_id = '97000000-0000-0000-0000-000000000006';

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000007', role = 'advisor', full_name = 'Issue 30 Owner B'
WHERE user_id = '97000000-0000-0000-0000-000000000007';

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000008', role = 'advisor', full_name = 'Issue 30 Inactive Advisor'
WHERE user_id = '97000000-0000-0000-0000-000000000008';

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000009', role = 'investor', full_name = 'Issue 30 Family Guest'
WHERE user_id = '97000000-0000-0000-0000-000000000009';

UPDATE public.profiles SET id = '97100000-0000-0000-0000-000000000010', role = 'investor', full_name = 'Issue 30 Inactive Investor'
WHERE user_id = '97000000-0000-0000-0000-000000000010';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('97200000-0000-0000-0000-000000000001', 'Issue 30 Workspace A', 'issue-30-workspace-a', '97100000-0000-0000-0000-000000000002', 'active'),
  ('97200000-0000-0000-0000-000000000002', 'Issue 30 Workspace B', 'issue-30-workspace-b', '97100000-0000-0000-0000-000000000007', 'active');

DELETE FROM public.workspace_memberships
WHERE profile_id IN (
  '97100000-0000-0000-0000-000000000001',
  '97100000-0000-0000-0000-000000000002',
  '97100000-0000-0000-0000-000000000003',
  '97100000-0000-0000-0000-000000000004',
  '97100000-0000-0000-0000-000000000005',
  '97100000-0000-0000-0000-000000000006',
  '97100000-0000-0000-0000-000000000007',
  '97100000-0000-0000-0000-000000000008',
  '97100000-0000-0000-0000-000000000009',
  '97100000-0000-0000-0000-000000000010'
);

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000003', 'investor', 'active'),
  ('97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000004', 'investor', 'active'),
  ('97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000005', 'advisor', 'active'),
  ('97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000006', 'advisor', 'active'),
  ('97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000008', 'advisor', 'inactive'),
  ('97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000009', 'investor', 'active'),
  ('97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000010', 'investor', 'inactive'),
  ('97200000-0000-0000-0000-000000000002', '97100000-0000-0000-0000-000000000007', 'admin', 'active'),
  ('97200000-0000-0000-0000-000000000002', '97100000-0000-0000-0000-000000000004', 'investor', 'active'),
  ('97200000-0000-0000-0000-000000000002', '97100000-0000-0000-0000-000000000006', 'advisor', 'active');

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('97000000-0000-0000-0000-000000000003', '97100000-0000-0000-0000-000000000003', 'verified_email', now(), 'active'),
  ('97000000-0000-0000-0000-000000000004', '97100000-0000-0000-0000-000000000004', 'verified_email', now(), 'active'),
  ('97000000-0000-0000-0000-000000000009', '97100000-0000-0000-0000-000000000009', 'verified_email', now(), 'active'),
  ('97000000-0000-0000-0000-000000000010', '97100000-0000-0000-0000-000000000010', 'verified_email', now(), 'active');

INSERT INTO public.family_delegations (id, workspace_id, owner_profile_id, delegate_profile_id, consent_status, is_active)
VALUES ('97400000-0000-0000-0000-000000000001', '97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000003', '97100000-0000-0000-0000-000000000009', 'accepted', true);

INSERT INTO public.auto_approval_rules (id, workspace_id, transaction_type, min_amount, max_amount, is_active, rule_version)
VALUES ('97500000-0000-0000-0000-000000000001', '97200000-0000-0000-0000-000000000001', 'buy', 0.00, 10000.00, true, 1);

DO $$
DECLARE
  v_policy_count pg_catalog.int4;
  v_select_policy_count pg_catalog.int4;
  v_insert_policy_count pg_catalog.int4;
  v_can_select_oid pg_catalog.oid;
  v_can_insert_oid pg_catalog.oid;
  v_policy pg_catalog.record;
BEGIN
  v_can_select_oid := 'public.can_select_order_request(pg_catalog.uuid, pg_catalog.uuid)'::pg_catalog.regprocedure::pg_catalog.oid;
  v_can_insert_oid := 'public.can_insert_order_request(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, public.order_status, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.timestamptz)'::pg_catalog.regprocedure::pg_catalog.oid;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = class.relnamespace
    WHERE namespace.nspname = 'public'
      AND class.relname = 'order_requests'
      AND class.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'order_requests RLS is not enabled';
  END IF;

  IF NOT pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'SELECT')
     OR NOT pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'INSERT') THEN
    RAISE EXCEPTION 'authenticated lacks expected order_requests read/insert grants';
  END IF;

  IF pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'DELETE')
     OR pg_catalog.has_table_privilege('service_role', 'public.order_requests', 'UPDATE')
     OR pg_catalog.has_table_privilege('service_role', 'public.order_requests', 'DELETE') THEN
    RAISE EXCEPTION 'order_requests has unexpected direct lifecycle mutation grants';
  END IF;

  IF pg_catalog.has_table_privilege('anon', 'public.order_requests', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'public.order_requests', 'INSERT') THEN
    RAISE EXCEPTION 'anon has unexpected order_requests API table grants';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_policy_count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'order_requests';

  IF v_policy_count <> 2 THEN
    RAISE EXCEPTION 'order_requests policy set is not exclusive: found % policies', v_policy_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'order_requests'
      AND policyname = 'order_requests_select_workspace_isolation'
      AND cmd = 'SELECT'
      AND roles = ARRAY['authenticated']::pg_catalog.name[]
  ) THEN
    RAISE EXCEPTION 'canonical SELECT policy is missing or has incorrect command/role';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'order_requests'
      AND policyname = 'order_requests_insert_workspace_isolation'
      AND cmd = 'INSERT'
      AND roles = ARRAY['authenticated']::pg_catalog.name[]
  ) THEN
    RAISE EXCEPTION 'canonical INSERT policy is missing or has incorrect command/role';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_select_policy_count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'order_requests'
    AND cmd = 'SELECT';

  IF v_select_policy_count <> 1 THEN
    RAISE EXCEPTION 'order_requests has unexpected additional SELECT policies: %', v_select_policy_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_insert_policy_count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'order_requests'
    AND cmd = 'INSERT';

  IF v_insert_policy_count <> 1 THEN
    RAISE EXCEPTION 'order_requests has unexpected additional INSERT policies: %', v_insert_policy_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'order_requests'
      AND cmd IN ('UPDATE', 'DELETE', 'ALL')
  ) THEN
    RAISE EXCEPTION 'order_requests exposes an UPDATE, DELETE, or ALL RLS policy';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'order_requests'
      AND roles && ARRAY['public', 'anon', 'service_role']::pg_catalog.name[]
  ) THEN
    RAISE EXCEPTION 'order_requests has a policy exposed to PUBLIC, anon, or service_role';
  END IF;

  IF EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS proc
       CROSS JOIN pg_catalog.aclexplode(coalesce(proc.proacl, pg_catalog.acldefault('f', proc.proowner))) AS acl
       WHERE proc.oid = v_can_select_oid
         AND acl.grantee = 0
         AND acl.privilege_type = 'EXECUTE'
     )
     OR pg_catalog.has_function_privilege('anon', 'public.can_select_order_request(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('service_role', 'public.can_select_order_request(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.can_select_order_request(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'can_select_order_request helper privileges are incorrect';
  END IF;

  IF EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS proc
       CROSS JOIN pg_catalog.aclexplode(coalesce(proc.proacl, pg_catalog.acldefault('f', proc.proowner))) AS acl
       WHERE proc.oid = v_can_insert_oid
         AND acl.grantee = 0
         AND acl.privilege_type = 'EXECUTE'
     )
     OR pg_catalog.has_function_privilege('anon', 'public.can_insert_order_request(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, public.order_status, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.timestamptz)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('service_role', 'public.can_insert_order_request(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, public.order_status, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.timestamptz)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.can_insert_order_request(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, public.order_status, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'can_insert_order_request helper privileges are incorrect';
  END IF;

  CREATE POLICY issue_30_unexpected_permissive_select ON public.order_requests
    FOR SELECT
    TO authenticated
    USING (true);

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_policy_count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'order_requests';

  IF v_policy_count <> 3 THEN
    RAISE EXCEPTION 'Issue #30 unexpected-policy regression setup failed: found % policies', v_policy_count;
  END IF;

  FOR v_policy IN
    SELECT policies.policyname
    FROM pg_catalog.pg_policies AS policies
    WHERE policies.schemaname = 'public'
      AND policies.tablename = 'order_requests'
  LOOP
    EXECUTE pg_catalog.format(
      'DROP POLICY IF EXISTS %I ON %I.%I',
      v_policy.policyname,
      'public',
      'order_requests'
    );
  END LOOP;

  CREATE POLICY order_requests_select_workspace_isolation ON public.order_requests
    FOR SELECT
    TO authenticated
    USING (
      public.can_select_order_request(workspace_id, investor_profile_id)
    );

  CREATE POLICY order_requests_insert_workspace_isolation ON public.order_requests
    FOR INSERT
    TO authenticated
    WITH CHECK (
      public.can_insert_order_request(
        workspace_id,
        investor_profile_id,
        initiated_by_profile_id,
        initiated_by_role,
        initiation_channel,
        status,
        reviewed_by,
        reviewed_by_profile_id,
        reviewed_at
      )
    );

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_policy_count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'order_requests';

  IF v_policy_count <> 2 OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'order_requests'
      AND policyname = 'issue_30_unexpected_permissive_select'
  ) THEN
    RAISE EXCEPTION 'unexpected permissive order_requests policy survived catalog cleanup';
  END IF;
END;
$$;

INSERT INTO public.order_requests (
  id,
  workspace_id,
  investor_profile_id,
  initiated_by_profile_id,
  initiated_by_role,
  initiation_channel,
  scheme_code,
  type,
  amount,
  status
) VALUES
  ('97300000-0000-0000-0000-000000000001', '97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000003', '97100000-0000-0000-0000-000000000003', 'investor', 'investor_portal', 'SCH30-A-OWN', 'buy', 1000.00, 'pending_qualification'),
  ('97300000-0000-0000-0000-000000000002', '97200000-0000-0000-0000-000000000001', '97100000-0000-0000-0000-000000000004', '97100000-0000-0000-0000-000000000004', 'investor', 'investor_portal', 'SCH30-A-OTHER', 'buy', 1000.00, 'pending_qualification'),
  ('97300000-0000-0000-0000-000000000003', '97200000-0000-0000-0000-000000000002', '97100000-0000-0000-0000-000000000004', '97100000-0000-0000-0000-000000000004', 'investor', 'investor_portal', 'SCH30-B-OWN', 'buy', 1000.00, 'pending_qualification');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000003', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000003","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"investor"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.order_requests
  WHERE id = '97300000-0000-0000-0000-000000000001';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'investor could not read own order in active workspace';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.order_requests
  WHERE id = '97300000-0000-0000-0000-000000000002';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'investor read another investor order';
  END IF;
END;
$$;

RESET ROLE;

UPDATE public.workspace_memberships
SET status = 'inactive'
WHERE workspace_id = '97200000-0000-0000-0000-000000000001'
  AND profile_id = '97100000-0000-0000-0000-000000000003';

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000003', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000003","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"investor"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.order_requests
  WHERE id = '97300000-0000-0000-0000-000000000001';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'investor read own order after membership became inactive';
  END IF;
END;
$$;

RESET ROLE;

UPDATE public.workspace_memberships
SET status = 'active'
WHERE workspace_id = '97200000-0000-0000-0000-000000000001'
  AND profile_id = '97100000-0000-0000-0000-000000000003';

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000005', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000005","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"mfd"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.order_requests
  WHERE id = '97300000-0000-0000-0000-000000000001';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'MFD could not read same-workspace mapped investor order';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.order_requests
  WHERE id = '97300000-0000-0000-0000-000000000003';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'same MFD read an order through another workspace';
  END IF;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000007', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000007","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"mfd"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.order_requests
  WHERE id = '97300000-0000-0000-0000-000000000001';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'unrelated MFD or forged workspace claim granted order read';
  END IF;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000001","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"platform_admin"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.order_requests;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Platform Admin has broad order read';
  END IF;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000006', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000006","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"mfd"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.order_requests
  WHERE id IN (
    '97300000-0000-0000-0000-000000000001',
    '97300000-0000-0000-0000-000000000003'
  );

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'multi-workspace MFD access did not use row workspace relationships';
  END IF;
END;
$$;

RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000003', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000003","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"investor"}}', true);

INSERT INTO public.order_requests (
  id,
  workspace_id,
  investor_profile_id,
  initiated_by_profile_id,
  initiated_by_role,
  initiation_channel,
  scheme_code,
  type,
  amount,
  status
) VALUES (
  '97300000-0000-0000-0000-000000000010',
  '97200000-0000-0000-0000-000000000001',
  '97100000-0000-0000-0000-000000000003',
  '97100000-0000-0000-0000-000000000003',
  'investor',
  'investor_portal',
  'SCH30-INV-INSERT',
  'buy',
  1500.00,
  'pending_qualification'
);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000011',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000004',
      '97100000-0000-0000-0000-000000000003',
      'investor',
      'investor_portal',
      'SCH30-INV-OTHER',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'investor initiated for another investor';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN ('order_initiator_not_authorized', 'new row violates row-level security policy for table "order_requests"') THEN
      RAISE EXCEPTION 'Unexpected investor-other insert error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000012',
      '97200000-0000-0000-0000-000000000002',
      '97100000-0000-0000-0000-000000000003',
      '97100000-0000-0000-0000-000000000003',
      'investor',
      'investor_portal',
      'SCH30-INV-OUTSIDE',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'investor initiated outside active workspace';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN ('investor_workspace_relationship_required', 'new row violates row-level security policy for table "order_requests"') THEN
      RAISE EXCEPTION 'Unexpected investor outside-workspace insert error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000013',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000003',
      '97100000-0000-0000-0000-000000000004',
      'investor',
      'investor_portal',
      'SCH30-INV-SPOOF',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'investor spoofed initiated_by_profile_id';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'initiator_profile_mismatch' THEN
      RAISE EXCEPTION 'Unexpected investor spoofing error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000014',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000003',
      '97100000-0000-0000-0000-000000000003',
      'investor',
      'investor_portal',
      'SCH30-BAD-STATUS',
      'buy',
      100.00,
      'approved'
    );
    RAISE EXCEPTION 'Issue #29 invalid initial status was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_initial_order_status' THEN
      RAISE EXCEPTION 'Unexpected Issue #29 initial-status error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      reviewed_by,
      reviewed_by_profile_id,
      reviewed_at,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000015',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000003',
      '97100000-0000-0000-0000-000000000003',
      'investor',
      'investor_portal',
      '97100000-0000-0000-0000-000000000005',
      '97100000-0000-0000-0000-000000000005',
      now(),
      'SCH30-BAD-REVIEW',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'Issue #29 reviewer-null insert rule was bypassed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'review_metadata_requires_qualification' THEN
      RAISE EXCEPTION 'Unexpected Issue #29 reviewer-null error: %', SQLERRM;
    END IF;
  END;
END;
$$;

RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000005', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000005","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"mfd"}}', true);

INSERT INTO public.order_requests (
  id,
  workspace_id,
  investor_profile_id,
  initiated_by_profile_id,
  initiated_by_role,
  initiation_channel,
  scheme_code,
  type,
  amount,
  status
) VALUES (
  '97300000-0000-0000-0000-000000000020',
  '97200000-0000-0000-0000-000000000001',
  '97100000-0000-0000-0000-000000000003',
  '97100000-0000-0000-0000-000000000005',
  'advisor',
  'advisor_portal',
  'SCH30-ADV-INSERT',
  'buy',
  1600.00,
  'pending_qualification'
);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000021',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000010',
      '97100000-0000-0000-0000-000000000005',
      'advisor',
      'advisor_portal',
      'SCH30-ADV-INACTIVE-INV',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'MFD initiated for an inactive investor relationship';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN ('investor_workspace_relationship_required', 'new row violates row-level security policy for table "order_requests"') THEN
      RAISE EXCEPTION 'Unexpected inactive investor relationship error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000022',
      '97200000-0000-0000-0000-000000000002',
      '97100000-0000-0000-0000-000000000004',
      '97100000-0000-0000-0000-000000000005',
      'advisor',
      'advisor_portal',
      'SCH30-CROSS-MFD',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'cross-workspace MFD initiated an order';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN ('order_initiator_not_authorized', 'new row violates row-level security policy for table "order_requests"') THEN
      RAISE EXCEPTION 'Unexpected cross-workspace MFD error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000023',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000003',
      '97100000-0000-0000-0000-000000000006',
      'advisor',
      'advisor_portal',
      'SCH30-ADV-SPOOF',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'MFD spoofed another initiator profile';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'initiator_profile_mismatch' THEN
      RAISE EXCEPTION 'Unexpected MFD initiator spoofing error: %', SQLERRM;
    END IF;
  END;
END;
$$;

RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000007', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000007","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"mfd"}}', true);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000030',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000003',
      '97100000-0000-0000-0000-000000000007',
      'advisor',
      'advisor_portal',
      'SCH30-UNRELATED-MFD',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'unrelated MFD initiated an order';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN ('order_initiator_not_authorized', 'new row violates row-level security policy for table "order_requests"') THEN
      RAISE EXCEPTION 'Unexpected unrelated MFD insert error: %', SQLERRM;
    END IF;
  END;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000008', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000008","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"mfd"}}', true);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000031',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000003',
      '97100000-0000-0000-0000-000000000008',
      'advisor',
      'advisor_portal',
      'SCH30-INACTIVE-ADV',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'inactive advisor initiated an order';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN ('order_initiator_not_authorized', 'new row violates row-level security policy for table "order_requests"') THEN
      RAISE EXCEPTION 'Unexpected inactive advisor insert error: %', SQLERRM;
    END IF;
  END;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000001","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"platform_admin"}}', true);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000032',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000003',
      '97100000-0000-0000-0000-000000000001',
      'advisor',
      'advisor_portal',
      'SCH30-ADMIN-DENIED',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'Platform Admin initiated an order';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN ('not_authorized', 'new row violates row-level security policy for table "order_requests"') THEN
      RAISE EXCEPTION 'Unexpected Platform Admin insert error: %', SQLERRM;
    END IF;
  END;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000009', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000009","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"investor"}}', true);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000033',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000003',
      '97100000-0000-0000-0000-000000000009',
      'investor',
      'investor_portal',
      'SCH30-FAMILY-DENIED',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'Family Guest initiated for another family member';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN ('order_initiator_not_authorized', 'new row violates row-level security policy for table "order_requests"') THEN
      RAISE EXCEPTION 'Unexpected Family Guest insert error: %', SQLERRM;
    END IF;
  END;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000010', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000010","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"investor"}}', true);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '97300000-0000-0000-0000-000000000034',
      '97200000-0000-0000-0000-000000000001',
      '97100000-0000-0000-0000-000000000010',
      '97100000-0000-0000-0000-000000000010',
      'investor',
      'investor_portal',
      'SCH30-INACTIVE-INV-SELF',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'inactive investor relationship initiated an order';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN ('investor_workspace_relationship_required', 'new row violates row-level security policy for table "order_requests"') THEN
      RAISE EXCEPTION 'Unexpected inactive investor self-initiation error: %', SQLERRM;
    END IF;
  END;
END;
$$;

RESET ROLE;

DO $$
DECLARE
  v_audit_count pg_catalog.int4;
  v_total_count pg_catalog.int4;
  v_order public.order_requests;
  v_outbox public.event_outbox;
BEGIN
  SELECT
    pg_catalog.count(*)::pg_catalog.int4,
    pg_catalog.count(*) FILTER (WHERE action = 'order.initiated')::pg_catalog.int4
  INTO v_total_count, v_audit_count
  FROM public.workspace_audit_logs
  WHERE entity_id = '97300000-0000-0000-0000-000000000010';

  IF v_total_count <> 1 OR v_audit_count <> 1 THEN
    RAISE EXCEPTION 'order initiation audit was not exact under Issue #30 RLS: total %, initiated %', v_total_count, v_audit_count;
  END IF;

  SELECT * INTO v_outbox
  FROM public.event_outbox
  WHERE entity_id = '97300000-0000-0000-0000-000000000010'
    AND event_type = 'order.created'
  LIMIT 1;

  UPDATE public.event_outbox
  SET status = 'processing',
      claimed_at = now(),
      claimed_by = '97100000-0000-0000-0000-000000000005'
  WHERE id = v_outbox.id;

  v_order := public.apply_auto_approval_decision(
    '97300000-0000-0000-0000-000000000010',
    'pending_review',
    null,
    null,
    v_outbox.id
  );

  IF v_order.status <> 'pending_review' THEN
    RAISE EXCEPTION 'auto-evaluation pending_review transition regressed under Issue #30 RLS';
  END IF;

  SELECT
    pg_catalog.count(*)::pg_catalog.int4,
    pg_catalog.count(*) FILTER (WHERE action IN ('order.initiated', 'order.auto_qualified'))::pg_catalog.int4
  INTO v_total_count, v_audit_count
  FROM public.workspace_audit_logs
  WHERE entity_id = '97300000-0000-0000-0000-000000000010';

  IF v_total_count <> 2 OR v_audit_count <> 2 THEN
    RAISE EXCEPTION 'auto-evaluation audit count changed under Issue #30 RLS: total %, expected %', v_total_count, v_audit_count;
  END IF;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);
INSERT INTO public.order_requests (
  id,
  workspace_id,
  investor_profile_id,
  initiated_by_profile_id,
  initiated_by_role,
  initiation_channel,
  scheme_code,
  type,
  amount,
  status
) VALUES (
  '97300000-0000-0000-0000-000000000040',
  '97200000-0000-0000-0000-000000000001',
  '97100000-0000-0000-0000-000000000003',
  '97100000-0000-0000-0000-000000000005',
  'advisor',
  'advisor_portal',
  'SCH30-MANUAL',
  'buy',
  1700.00,
  'pending_review'
);

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000005', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000005","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"mfd"}}', true);
SELECT public.qualify_order('97300000-0000-0000-0000-000000000040', 'approved', null);
RESET ROLE;

DO $$
DECLARE
  v_audit_count pg_catalog.int4;
  v_total_count pg_catalog.int4;
BEGIN
  SELECT
    pg_catalog.count(*)::pg_catalog.int4,
    pg_catalog.count(*) FILTER (WHERE action IN ('order.initiated', 'order.qualified', 'order.approved'))::pg_catalog.int4
  INTO v_total_count, v_audit_count
  FROM public.workspace_audit_logs
  WHERE entity_id = '97300000-0000-0000-0000-000000000040';

  IF v_total_count <> 3 OR v_audit_count <> 3 THEN
    RAISE EXCEPTION 'manual qualification audit count changed under Issue #30 RLS: total %, expected %', v_total_count, v_audit_count;
  END IF;
END;
$$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000003', true);
SELECT set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000003","role":"authenticated","workspace_id":"97200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"investor"}}', true);
INSERT INTO public.order_requests (
  id,
  workspace_id,
  investor_profile_id,
  initiated_by_profile_id,
  initiated_by_role,
  initiation_channel,
  scheme_code,
  type,
  amount,
  status
) VALUES (
  '97300000-0000-0000-0000-000000000041',
  '97200000-0000-0000-0000-000000000001',
  '97100000-0000-0000-0000-000000000003',
  '97100000-0000-0000-0000-000000000003',
  'investor',
  'investor_portal',
  'SCH30-CANCEL',
  'buy',
  1800.00,
  'pending_qualification'
);
SELECT public.cancel_order('97300000-0000-0000-0000-000000000041', 'Issue 30 RLS cancellation compatibility');
RESET ROLE;

DO $$
DECLARE
  v_audit_count pg_catalog.int4;
  v_total_count pg_catalog.int4;
BEGIN
  SELECT
    pg_catalog.count(*)::pg_catalog.int4,
    pg_catalog.count(*) FILTER (WHERE action IN ('order.initiated', 'order.cancelled'))::pg_catalog.int4
  INTO v_total_count, v_audit_count
  FROM public.workspace_audit_logs
  WHERE entity_id = '97300000-0000-0000-0000-000000000041';

  IF v_total_count <> 2 OR v_audit_count <> 2 THEN
    RAISE EXCEPTION 'cancellation audit count changed under Issue #30 RLS: total %, expected %', v_total_count, v_audit_count;
  END IF;
END;
$$;

ROLLBACK;
