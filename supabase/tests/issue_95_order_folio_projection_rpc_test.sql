-- Test Suite: Issue #95 safe order folio projection RPCs.

BEGIN;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('95000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue95-investor-a@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('95000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue95-investor-b@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('95000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'issue95-advisor-a@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('95000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'issue95-advisor-b@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('95000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'issue95-platform-admin@moneybowl.test', '{"user_role":"platform_admin"}', '{}', now(), now()),
  ('95000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'issue95-inactive-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now());

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id IN (
  '95000000-0000-0000-0000-000000000001',
  '95000000-0000-0000-0000-000000000002',
  '95000000-0000-0000-0000-000000000006'
);

UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id IN (
  '95000000-0000-0000-0000-000000000003',
  '95000000-0000-0000-0000-000000000004',
  '95000000-0000-0000-0000-000000000005'
);

UPDATE public.profiles SET id = '95100000-0000-0000-0000-000000000001', role = 'investor', full_name = 'Issue 95 Investor A', account_status = 'active'
WHERE user_id = '95000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '95100000-0000-0000-0000-000000000002', role = 'investor', full_name = 'Issue 95 Investor B', account_status = 'active'
WHERE user_id = '95000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET id = '95100000-0000-0000-0000-000000000003', role = 'advisor', full_name = 'Issue 95 Advisor A', account_status = 'active'
WHERE user_id = '95000000-0000-0000-0000-000000000003';
UPDATE public.profiles SET id = '95100000-0000-0000-0000-000000000004', role = 'advisor', full_name = 'Issue 95 Advisor B', account_status = 'active'
WHERE user_id = '95000000-0000-0000-0000-000000000004';
UPDATE public.profiles SET id = '95100000-0000-0000-0000-000000000005', role = 'platform_admin', full_name = 'Issue 95 Platform Admin', account_status = 'active'
WHERE user_id = '95000000-0000-0000-0000-000000000005';
UPDATE public.profiles SET id = '95100000-0000-0000-0000-000000000006', role = 'investor', full_name = 'Issue 95 Inactive Investor', account_status = 'active'
WHERE user_id = '95000000-0000-0000-0000-000000000006';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('95200000-0000-0000-0000-000000000001', 'Issue 95 Workspace A', 'issue-95-workspace-a', '95100000-0000-0000-0000-000000000003', 'active'),
  ('95200000-0000-0000-0000-000000000002', 'Issue 95 Workspace B', 'issue-95-workspace-b', '95100000-0000-0000-0000-000000000004', 'active');

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status, ended_at)
VALUES
  ('95200000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000001', 'investor', 'active', NULL),
  ('95200000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000002', 'investor', 'active', NULL),
  ('95200000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000003', 'advisor', 'active', NULL),
  ('95200000-0000-0000-0000-000000000002', '95100000-0000-0000-0000-000000000004', 'advisor', 'active', NULL),
  ('95200000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000006', 'investor', 'inactive', NULL);

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('95000000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000001', 'verified_email', now(), 'active'),
  ('95000000-0000-0000-0000-000000000002', '95100000-0000-0000-0000-000000000002', 'verified_email', now(), 'active'),
  ('95000000-0000-0000-0000-000000000006', '95100000-0000-0000-0000-000000000006', 'verified_email', now(), 'revoked');

INSERT INTO public.portfolios (id, client_id, workspace_id, total_invested_value, current_market_value)
VALUES
  ('95300000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001', 1000, 1100),
  ('95300000-0000-0000-0000-000000000002', '95100000-0000-0000-0000-000000000002', '95200000-0000-0000-0000-000000000001', 2000, 2100),
  ('95300000-0000-0000-0000-000000000003', '95100000-0000-0000-0000-000000000006', '95200000-0000-0000-0000-000000000001', 3000, 3100);

INSERT INTO public.folio_references (id, registrar, normalized_folio_number, amc_identity, source_folio_masked)
VALUES
  ('95400000-0000-0000-0000-000000000001', 'CAMS', 'ISSUE95FOLIOA', 'AMC-A', 'CAM***A95'),
  ('95400000-0000-0000-0000-000000000002', 'KFINTECH', 'ISSUE95FOLIOB', 'AMC-B', 'KFI***B95'),
  ('95400000-0000-0000-0000-000000000003', 'CAMS', 'ISSUE95INACTIVE', 'AMC-C', 'CAM***I95');

INSERT INTO public.portfolio_folio_references (portfolio_id, folio_reference_id)
VALUES
  ('95300000-0000-0000-0000-000000000001', '95400000-0000-0000-0000-000000000001'),
  ('95300000-0000-0000-0000-000000000002', '95400000-0000-0000-0000-000000000002'),
  ('95300000-0000-0000-0000-000000000003', '95400000-0000-0000-0000-000000000003');

INSERT INTO public.verification_requests (id, user_id, method_code, status, submitted_at, resolved_at)
VALUES
  ('95500000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', 'folio', 'approved', now(), now()),
  ('95500000-0000-0000-0000-000000000002', '95000000-0000-0000-0000-000000000002', 'folio', 'approved', now(), now()),
  ('95500000-0000-0000-0000-000000000003', '95000000-0000-0000-0000-000000000006', 'folio', 'approved', now(), now()),
  ('95500000-0000-0000-0000-000000000004', '95000000-0000-0000-0000-000000000001', 'folio', 'approved', now(), now());

INSERT INTO public.folio_grants (request_id, user_id, profile_id, folio_reference_id, holder_relationship, status, approved_by, revoked_at)
VALUES
  ('95500000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000001', '95400000-0000-0000-0000-000000000001', 'SOLE_HOLDER', 'active', '95000000-0000-0000-0000-000000000003', NULL),
  ('95500000-0000-0000-0000-000000000002', '95000000-0000-0000-0000-000000000002', '95100000-0000-0000-0000-000000000002', '95400000-0000-0000-0000-000000000002', 'SOLE_HOLDER', 'active', '95000000-0000-0000-0000-000000000003', NULL),
  ('95500000-0000-0000-0000-000000000003', '95000000-0000-0000-0000-000000000006', '95100000-0000-0000-0000-000000000006', '95400000-0000-0000-0000-000000000003', 'SOLE_HOLDER', 'revoked', '95000000-0000-0000-0000-000000000003', now()),
  ('95500000-0000-0000-0000-000000000004', '95000000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000001', '95400000-0000-0000-0000-000000000001', 'JOINT_HOLDER', 'active', '95000000-0000-0000-0000-000000000003', NULL);

DO $$
DECLARE
  v_list_oid pg_catalog.oid := 'public.list_order_folios(pg_catalog.uuid, pg_catalog.uuid)'::pg_catalog.regprocedure::pg_catalog.oid;
  v_resolve_oid pg_catalog.oid := 'public.resolve_order_folio_portfolio(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)'::pg_catalog.regprocedure::pg_catalog.oid;
  v_column_names pg_catalog.text[];
  v_resolve_column_names pg_catalog.text[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE oid = v_list_oid AND prosecdef AND proconfig @> ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'issue95:list_order_folios_security_definer_contract_missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE oid = v_resolve_oid AND prosecdef AND proconfig @> ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'issue95:resolve_order_folio_portfolio_security_definer_contract_missing';
  END IF;
  IF EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS proc
       CROSS JOIN pg_catalog.aclexplode(coalesce(proc.proacl, pg_catalog.acldefault('f', proc.proowner))) AS acl
       WHERE proc.oid IN (v_list_oid, v_resolve_oid)
         AND acl.grantee = 0
         AND acl.privilege_type = 'EXECUTE'
     )
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS proc
       CROSS JOIN pg_catalog.aclexplode(coalesce(proc.proacl, pg_catalog.acldefault('f', proc.proowner))) AS acl
       WHERE proc.oid IN (v_list_oid, v_resolve_oid)
         AND acl.grantee = 'anon'::pg_catalog.regrole
         AND acl.privilege_type = 'EXECUTE'
     )
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS proc
       CROSS JOIN pg_catalog.aclexplode(coalesce(proc.proacl, pg_catalog.acldefault('f', proc.proowner))) AS acl
       WHERE proc.oid = v_list_oid
         AND acl.grantee = 'authenticated'::pg_catalog.regrole
         AND acl.privilege_type = 'EXECUTE'
     )
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS proc
       CROSS JOIN pg_catalog.aclexplode(coalesce(proc.proacl, pg_catalog.acldefault('f', proc.proowner))) AS acl
       WHERE proc.oid = v_resolve_oid
         AND acl.grantee = 'authenticated'::pg_catalog.regrole
         AND acl.privilege_type = 'EXECUTE'
     )
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS proc
       CROSS JOIN pg_catalog.aclexplode(coalesce(proc.proacl, pg_catalog.acldefault('f', proc.proowner))) AS acl
       WHERE proc.oid IN (v_list_oid, v_resolve_oid)
         AND acl.grantee = 'service_role'::pg_catalog.regrole
         AND acl.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'issue95:function_execute_acl_contract_failed';
  END IF;
  IF pg_catalog.has_table_privilege('authenticated', 'public.folio_references', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.portfolio_folio_references', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'public.folio_references', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'public.portfolio_folio_references', 'SELECT') THEN
    RAISE EXCEPTION 'issue95:protected_table_direct_select_broadened';
  END IF;

  SELECT pg_catalog.array_agg(parameter_name::pg_catalog.text ORDER BY ordinal_position)
  INTO v_column_names
  FROM information_schema.parameters
  WHERE specific_schema = 'public'
    AND specific_name = (
      SELECT specific_name
      FROM information_schema.routines
      WHERE routine_schema = 'public'
        AND routine_name = 'list_order_folios'
      LIMIT 1
    )
    AND parameter_mode = 'OUT';

  IF v_column_names <> ARRAY['folio_reference_id', 'portfolio_id', 'registrar', 'masked_folio'] THEN
    RAISE EXCEPTION 'issue95:list_order_folios_unsafe_return_columns:%', v_column_names;
  END IF;

  SELECT pg_catalog.array_agg(parameter_name::pg_catalog.text ORDER BY ordinal_position)
  INTO v_resolve_column_names
  FROM information_schema.parameters
  WHERE specific_schema = 'public'
    AND specific_name = (
      SELECT specific_name
      FROM information_schema.routines
      WHERE routine_schema = 'public'
        AND routine_name = 'resolve_order_folio_portfolio'
      LIMIT 1
    )
    AND parameter_mode = 'OUT';

  IF v_resolve_column_names <> ARRAY['portfolio_id'] THEN
    RAISE EXCEPTION 'issue95:resolve_order_folio_portfolio_unsafe_return_columns:%', v_resolve_column_names;
  END IF;
END;
$$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
  v_row pg_catalog.record;
BEGIN
  BEGIN
    PERFORM * FROM public.folio_references LIMIT 1;
    RAISE EXCEPTION 'issue95:authenticated_selected_folio_references';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM * FROM public.portfolio_folio_references LIMIT 1;
    RAISE EXCEPTION 'issue95:authenticated_selected_portfolio_folio_references';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 1 THEN RAISE EXCEPTION 'issue95:investor_expected_one_own_folio:%', v_count; END IF;

  SELECT * INTO v_row
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_row.folio_reference_id <> '95400000-0000-0000-0000-000000000001'
     OR v_row.portfolio_id <> '95300000-0000-0000-0000-000000000001'
     OR v_row.registrar <> 'CAMS'
     OR v_row.masked_folio <> 'CAM***A95' THEN
    RAISE EXCEPTION 'issue95:investor_projection_mismatch';
  END IF;

  SELECT * INTO v_row
  FROM public.resolve_order_folio_portfolio(
    '95100000-0000-0000-0000-000000000001',
    '95200000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000001'
  );
  IF v_row.portfolio_id <> '95300000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'issue95:legitimate_folio_did_not_resolve_exact_portfolio';
  END IF;

  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000002', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:unrelated_investor_saw_other_folio'; END IF;

  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000002');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:forged_workspace_did_not_fail_closed'; END IF;

  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio(
    '95100000-0000-0000-0000-000000000001',
    '95200000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000002'
  );
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:forged_folio_resolved'; END IF;

  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio(
    '95100000-0000-0000-0000-000000000002',
    '95200000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000001'
  );
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:forged_investor_profile_resolved'; END IF;

  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio(
    '95100000-0000-0000-0000-000000000001',
    '95200000-0000-0000-0000-000000000002',
    '95400000-0000-0000-0000-000000000001'
  );
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:forged_workspace_resolved'; END IF;

END;
$$;

RESET ROLE;
UPDATE public.workspace_memberships
SET status = 'inactive'
WHERE workspace_id = '95200000-0000-0000-0000-000000000001'
  AND profile_id = '95100000-0000-0000-0000-000000000001'
  AND role = 'investor';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:inactive_membership_authorized_list'; END IF;
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001', '95400000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:inactive_membership_authorized_resolve'; END IF;
END;
$$;
RESET ROLE;
UPDATE public.workspace_memberships
SET status = 'active'
WHERE workspace_id = '95200000-0000-0000-0000-000000000001'
  AND profile_id = '95100000-0000-0000-0000-000000000001'
  AND role = 'investor';

UPDATE public.investor_account_links
SET link_status = 'revoked'
WHERE user_id = '95000000-0000-0000-0000-000000000001'
  AND profile_id = '95100000-0000-0000-0000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:revoked_investor_link_authorized_list'; END IF;
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001', '95400000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:revoked_investor_link_authorized_resolve'; END IF;
END;
$$;
RESET ROLE;
UPDATE public.investor_account_links
SET link_status = 'active'
WHERE user_id = '95000000-0000-0000-0000-000000000001'
  AND profile_id = '95100000-0000-0000-0000-000000000001';

UPDATE public.user_accounts
SET account_state = 'explorer'
WHERE user_id = '95000000-0000-0000-0000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:non_linked_investor_account_authorized_list'; END IF;
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001', '95400000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:non_linked_investor_account_authorized_resolve'; END IF;
END;
$$;
RESET ROLE;
UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id = '95000000-0000-0000-0000-000000000001';

UPDATE public.folio_grants
SET status = 'revoked',
    revoked_at = now()
WHERE user_id = '95000000-0000-0000-0000-000000000001'
  AND profile_id = '95100000-0000-0000-0000-000000000001'
  AND folio_reference_id = '95400000-0000-0000-0000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:revoked_folio_grant_authorized_list'; END IF;
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001', '95400000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:revoked_folio_grant_authorized_resolve'; END IF;
END;
$$;
RESET ROLE;
UPDATE public.folio_grants
SET status = 'active',
    revoked_at = NULL
WHERE user_id = '95000000-0000-0000-0000-000000000001'
  AND profile_id = '95100000-0000-0000-0000-000000000001'
  AND folio_reference_id = '95400000-0000-0000-0000-000000000001';

UPDATE public.profiles
SET account_status = 'inactive'
WHERE id = '95100000-0000-0000-0000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:inactive_investor_profile_authorized_list'; END IF;
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001', '95400000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:inactive_investor_profile_authorized_resolve'; END IF;
END;
$$;
RESET ROLE;
UPDATE public.profiles
SET account_status = 'active'
WHERE id = '95100000-0000-0000-0000-000000000001';

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);

SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000002', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000002","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio(
    '95100000-0000-0000-0000-000000000001',
    '95200000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000001'
  );
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:unrelated_investor_resolved_other_folio'; END IF;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000003', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 1 THEN RAISE EXCEPTION 'issue95:authorized_advisor_expected_one_folio:%', v_count; END IF;

  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio(
    '95100000-0000-0000-0000-000000000001',
    '95200000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000001'
  );
  IF v_count <> 1 THEN RAISE EXCEPTION 'issue95:authorized_advisor_resolve_failed'; END IF;

  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio(
    '95100000-0000-0000-0000-000000000001',
    '95200000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000002'
  );
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:forged_portfolio_relationship_obtained'; END IF;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000004', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:unrelated_advisor_saw_folio'; END IF;

  SELECT pg_catalog.count(*) INTO v_count
  FROM public.resolve_order_folio_portfolio(
    '95100000-0000-0000-0000-000000000001',
    '95200000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000001'
  );
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:unrelated_advisor_resolved_folio'; END IF;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000005', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000005","role":"authenticated","app_metadata":{"user_role":"platform_admin"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:platform_admin_bypass_was_introduced'; END IF;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000006', true);
SELECT set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000006","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM public.list_order_folios('95100000-0000-0000-0000-000000000006', '95200000-0000-0000-0000-000000000001');
  IF v_count <> 0 THEN RAISE EXCEPTION 'issue95:inactive_link_membership_or_revoked_grant_authorized_projection'; END IF;
END;
$$;

RESET ROLE;

SET ROLE anon;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.list_order_folios('95100000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'issue95:anon_executed_list_order_folios';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM * FROM public.resolve_order_folio_portfolio(
      '95100000-0000-0000-0000-000000000001',
      '95200000-0000-0000-0000-000000000001',
      '95400000-0000-0000-0000-000000000001'
    );
    RAISE EXCEPTION 'issue95:anon_executed_resolve_order_folio_portfolio';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM * FROM public.folio_references LIMIT 1;
    RAISE EXCEPTION 'issue95:anon_selected_folio_references';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM * FROM public.portfolio_folio_references LIMIT 1;
    RAISE EXCEPTION 'issue95:anon_selected_portfolio_folio_references';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END;
$$;

RESET ROLE;

ROLLBACK;
