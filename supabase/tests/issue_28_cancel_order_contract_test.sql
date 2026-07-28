-- Test Suite: Issue #28 cancel_order contract and order lifecycle states.

BEGIN;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('91000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue28-admin@moneybowl.test', '{"user_role":"platform_admin"}', '{}', now(), now()),
  ('91000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue28-advisor-a@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('91000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'issue28-investor-owner@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('91000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'issue28-family-guest@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('91000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'issue28-advisor-b@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now());

UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id IN (
  '91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000002',
  '91000000-0000-0000-0000-000000000005'
);

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id IN (
  '91000000-0000-0000-0000-000000000003',
  '91000000-0000-0000-0000-000000000004'
);

UPDATE public.profiles
SET id = '92000000-0000-0000-0000-000000000001', role = 'platform_admin', full_name = 'Issue 28 Platform Admin'
WHERE user_id = '91000000-0000-0000-0000-000000000001';

UPDATE public.profiles
SET id = '92000000-0000-0000-0000-000000000002', role = 'advisor', full_name = 'Issue 28 Advisor A'
WHERE user_id = '91000000-0000-0000-0000-000000000002';

UPDATE public.profiles
SET id = '92000000-0000-0000-0000-000000000003', role = 'investor', full_name = 'Issue 28 Investor Owner'
WHERE user_id = '91000000-0000-0000-0000-000000000003';

UPDATE public.profiles
SET id = '92000000-0000-0000-0000-000000000004', role = 'investor', full_name = 'Issue 28 Family Guest'
WHERE user_id = '91000000-0000-0000-0000-000000000004';

UPDATE public.profiles
SET id = '92000000-0000-0000-0000-000000000005', role = 'advisor', full_name = 'Issue 28 Advisor B'
WHERE user_id = '91000000-0000-0000-0000-000000000005';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('93000000-0000-0000-0000-000000000001', 'Issue 28 Workspace A', 'issue-28-workspace-a', '92000000-0000-0000-0000-000000000002', 'active'),
  ('93000000-0000-0000-0000-000000000002', 'Issue 28 Workspace B', 'issue-28-workspace-b', '92000000-0000-0000-0000-000000000005', 'active');

DELETE FROM public.workspace_memberships
WHERE profile_id IN (
  '92000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000002',
  '92000000-0000-0000-0000-000000000003',
  '92000000-0000-0000-0000-000000000004',
  '92000000-0000-0000-0000-000000000005'
);

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', 'investor', 'active'),
  ('93000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000005', 'advisor', 'active');

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('91000000-0000-0000-0000-000000000003', '92000000-0000-0000-0000-000000000003', 'verified_email', now(), 'active'),
  ('91000000-0000-0000-0000-000000000004', '92000000-0000-0000-0000-000000000004', 'verified_email', now(), 'active');

INSERT INTO public.family_delegations (id, workspace_id, owner_profile_id, delegate_profile_id, consent_status, is_active)
VALUES ('97000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', '92000000-0000-0000-0000-000000000004', 'accepted', true);

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;

DO $$
DECLARE
  v_order public.order_requests;
  v_audit public.workspace_audit_logs;
  v_count integer;
  v_prosecdef boolean;
  v_proconfig text[];
BEGIN
  SELECT count(*)::integer INTO v_count
  FROM pg_catalog.pg_enum e
  JOIN pg_catalog.pg_type t ON t.oid = e.enumtypid
  JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
  WHERE n.nspname = 'public'
    AND t.typname = 'order_type'
    AND e.enumlabel IN ('buy', 'sell', 'switch');

  IF v_count <> 3 THEN
    RAISE EXCEPTION 'order_type enum is missing expected values';
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM pg_catalog.pg_enum e
  JOIN pg_catalog.pg_type t ON t.oid = e.enumtypid
  JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
  WHERE n.nspname = 'public'
    AND t.typname = 'order_status'
    AND e.enumlabel IN (
      'draft',
      'pending_qualification',
      'pending_review',
      'auto_approved',
      'approved',
      'rejected',
      'cancelled'
    );

  IF v_count <> 7 THEN
    RAISE EXCEPTION 'order_status enum is missing expected values';
  END IF;

  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
    VALUES ('96000000-0000-0000-0000-000000000000', '93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', 'SCH-DRAFT', 'buy', 100.00, 'draft');
    RAISE EXCEPTION 'draft order persisted despite order_requests_status_not_draft';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE '%order_requests_status_not_draft%' THEN
      RAISE EXCEPTION 'Unexpected check violation while blocking draft orders: %', SQLERRM;
    END IF;
  END;

  SELECT p.prosecdef, p.proconfig
  INTO v_prosecdef, v_proconfig
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'cancel_order'
    AND p.oid = 'public.cancel_order(pg_catalog.uuid, pg_catalog.text)'::pg_catalog.regprocedure;

  IF v_prosecdef IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'cancel_order is not SECURITY DEFINER';
  END IF;

  IF v_proconfig IS NULL OR NOT ('search_path=""' = ANY(v_proconfig)) THEN
    RAISE EXCEPTION 'cancel_order does not enforce empty search_path';
  END IF;

  IF pg_catalog.has_function_privilege('anon', 'public.cancel_order(pg_catalog.uuid, pg_catalog.text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute cancel_order';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated', 'public.cancel_order(pg_catalog.uuid, pg_catalog.text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute cancel_order';
  END IF;

  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES ('96000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', 'SCH101', 'buy', 1000.00, 'pending_qualification');

  BEGIN
    PERFORM public.cancel_order('96000000-0000-0000-0000-000000000001', 'No profile');
    RAISE EXCEPTION 'cancel_order allowed unresolved caller profile';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'profile_resolution_failed' THEN
      RAISE EXCEPTION 'Unexpected unresolved-profile error: %', SQLERRM;
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
  v_order := public.cancel_order('96000000-0000-0000-0000-000000000001', 'Owner requested cancellation');

  IF v_order.status <> 'cancelled'
     OR v_order.cancellation_reason <> 'Owner requested cancellation'
     OR v_order.rejection_reason <> 'Owner requested cancellation'
     OR v_order.cancelled_at IS NULL THEN
    RAISE EXCEPTION 'owner cancellation did not persist status, reason, and timestamp';
  END IF;

  SELECT * INTO v_audit
  FROM public.workspace_audit_logs
  WHERE entity_id = '96000000-0000-0000-0000-000000000001'
    AND action = 'order.cancelled'
  ORDER BY occurred_at DESC
  LIMIT 1;

  IF v_audit.id IS NULL
     OR v_audit.workspace_id <> '93000000-0000-0000-0000-000000000001'
     OR v_audit.actor_profile_id <> '92000000-0000-0000-0000-000000000003'
     OR v_audit.previous_state <> 'pending_qualification'
     OR v_audit.new_state <> 'cancelled'
     OR v_audit.reason <> 'Owner requested cancellation' THEN
    RAISE EXCEPTION 'owner cancellation audit did not use database-loaded values';
  END IF;

  BEGIN
    PERFORM public.cancel_order('96000000-0000-0000-0000-000000000001', 'Repeated cancel');
    RAISE EXCEPTION 'repeated cancellation did not fail';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'already_cancelled' THEN
      RAISE EXCEPTION 'Unexpected repeated-cancel error: %', SQLERRM;
    END IF;
  END;

  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES ('96000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', 'SCH102', 'sell', 1000.00, 'pending_review');

  PERFORM set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
  v_order := public.cancel_order('96000000-0000-0000-0000-000000000002', 'Advisor cancelled pending review');

  IF v_order.status <> 'cancelled'
     OR v_order.cancellation_reason <> 'Advisor cancelled pending review'
     OR v_order.cancelled_at IS NULL THEN
    RAISE EXCEPTION 'advisor cancellation did not persist status, reason, and timestamp';
  END IF;

  SELECT * INTO v_audit
  FROM public.workspace_audit_logs
  WHERE entity_id = '96000000-0000-0000-0000-000000000002'
    AND action = 'order.cancelled'
  ORDER BY occurred_at DESC
  LIMIT 1;

  IF v_audit.actor_profile_id <> '92000000-0000-0000-0000-000000000002'
     OR v_audit.actor_type <> 'advisor'
     OR v_audit.previous_state <> 'pending_review' THEN
    RAISE EXCEPTION 'advisor cancellation audit is incorrect';
  END IF;

  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES ('96000000-0000-0000-0000-000000000003', '93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', 'SCH103', 'buy', 1000.00, 'pending_review');

  PERFORM set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000005","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
  BEGIN
    PERFORM public.cancel_order('96000000-0000-0000-0000-000000000003', 'Unrelated advisor');
    RAISE EXCEPTION 'unrelated advisor cancelled cross-workspace order';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'not_authorized' THEN
      RAISE EXCEPTION 'Unexpected unrelated advisor error: %', SQLERRM;
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
  BEGIN
    PERFORM public.cancel_order('96000000-0000-0000-0000-000000000003', 'Family guest');
    RAISE EXCEPTION 'family guest cancelled delegated owner order';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'not_authorized' THEN
      RAISE EXCEPTION 'Unexpected family guest error: %', SQLERRM;
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"platform_admin"}}', true);
  BEGIN
    PERFORM public.cancel_order('96000000-0000-0000-0000-000000000003', 'Platform admin');
    RAISE EXCEPTION 'platform admin cancelled order without MFD/investor authority';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'not_authorized' THEN
      RAISE EXCEPTION 'Unexpected platform admin error: %', SQLERRM;
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);

  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES
    ('96000000-0000-0000-0000-000000000004', '93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', 'SCH104', 'buy', 1000.00, 'auto_approved'),
    ('96000000-0000-0000-0000-000000000005', '93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', 'SCH105', 'buy', 1000.00, 'approved'),
    ('96000000-0000-0000-0000-000000000006', '93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', 'SCH106', 'buy', 1000.00, 'rejected');

  BEGIN
    PERFORM public.cancel_order('96000000-0000-0000-0000-000000000004', 'Auto approved');
    RAISE EXCEPTION 'auto_approved cancellation did not fail';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_cancellation_state' THEN
      RAISE EXCEPTION 'Unexpected auto_approved cancellation error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    PERFORM public.cancel_order('96000000-0000-0000-0000-000000000005', 'Approved');
    RAISE EXCEPTION 'approved cancellation did not fail';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_cancellation_state' THEN
      RAISE EXCEPTION 'Unexpected approved cancellation error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    PERFORM public.cancel_order('96000000-0000-0000-0000-000000000006', 'Rejected');
    RAISE EXCEPTION 'rejected cancellation did not fail';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_cancellation_state' THEN
      RAISE EXCEPTION 'Unexpected rejected cancellation error: %', SQLERRM;
    END IF;
  END;
END;
$$;

RESET ROLE;
ROLLBACK;
