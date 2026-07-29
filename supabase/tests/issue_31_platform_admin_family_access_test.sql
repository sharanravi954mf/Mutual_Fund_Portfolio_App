-- Test Suite: Issue #31 Platform Admin override and Family Access boundary.

BEGIN;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('98000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue31-platform-admin@moneybowl.test', '{"user_role":"platform_admin"}', '{}', now(), now()),
  ('98000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue31-non-admin@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('98000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'issue31-owner@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('98000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'issue31-delegate@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('98000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'issue31-other-owner@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('98000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'issue31-workspace-owner@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now());

UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id IN (
  '98000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000002',
  '98000000-0000-0000-0000-000000000006'
);

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id IN (
  '98000000-0000-0000-0000-000000000003',
  '98000000-0000-0000-0000-000000000004',
  '98000000-0000-0000-0000-000000000005'
);

UPDATE public.profiles SET id = '98100000-0000-0000-0000-000000000001', role = 'platform_admin', full_name = 'Issue 31 Platform Admin'
WHERE user_id = '98000000-0000-0000-0000-000000000001';

UPDATE public.profiles SET id = '98100000-0000-0000-0000-000000000002', role = 'advisor', full_name = 'Issue 31 Non Admin'
WHERE user_id = '98000000-0000-0000-0000-000000000002';

UPDATE public.profiles SET id = '98100000-0000-0000-0000-000000000003', role = 'investor', full_name = 'Issue 31 Owner'
WHERE user_id = '98000000-0000-0000-0000-000000000003';

UPDATE public.profiles SET id = '98100000-0000-0000-0000-000000000004', role = 'investor', full_name = 'Issue 31 Delegate'
WHERE user_id = '98000000-0000-0000-0000-000000000004';

UPDATE public.profiles SET id = '98100000-0000-0000-0000-000000000005', role = 'investor', full_name = 'Issue 31 Other Owner'
WHERE user_id = '98000000-0000-0000-0000-000000000005';

UPDATE public.profiles SET id = '98100000-0000-0000-0000-000000000006', role = 'advisor', full_name = 'Issue 31 Workspace Owner'
WHERE user_id = '98000000-0000-0000-0000-000000000006';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('98200000-0000-0000-0000-000000000001', 'Issue 31 Workspace A', 'issue-31-workspace-a', '98100000-0000-0000-0000-000000000006', 'active'),
  ('98200000-0000-0000-0000-000000000002', 'Issue 31 Workspace B', 'issue-31-workspace-b', '98100000-0000-0000-0000-000000000006', 'active');

DELETE FROM public.workspace_memberships
WHERE profile_id IN (
  '98100000-0000-0000-0000-000000000001',
  '98100000-0000-0000-0000-000000000002',
  '98100000-0000-0000-0000-000000000003',
  '98100000-0000-0000-0000-000000000004',
  '98100000-0000-0000-0000-000000000005',
  '98100000-0000-0000-0000-000000000006'
);

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('98200000-0000-0000-0000-000000000001', '98100000-0000-0000-0000-000000000006', 'admin', 'active'),
  ('98200000-0000-0000-0000-000000000001', '98100000-0000-0000-0000-000000000002', 'advisor', 'active'),
  ('98200000-0000-0000-0000-000000000001', '98100000-0000-0000-0000-000000000003', 'investor', 'active'),
  ('98200000-0000-0000-0000-000000000001', '98100000-0000-0000-0000-000000000004', 'investor', 'active'),
  ('98200000-0000-0000-0000-000000000001', '98100000-0000-0000-0000-000000000005', 'investor', 'active'),
  ('98200000-0000-0000-0000-000000000002', '98100000-0000-0000-0000-000000000005', 'investor', 'active');

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('98000000-0000-0000-0000-000000000003', '98100000-0000-0000-0000-000000000003', 'verified_email', now(), 'active'),
  ('98000000-0000-0000-0000-000000000004', '98100000-0000-0000-0000-000000000004', 'verified_email', now(), 'active'),
  ('98000000-0000-0000-0000-000000000005', '98100000-0000-0000-0000-000000000005', 'verified_email', now(), 'active');

INSERT INTO public.family_delegations (id, workspace_id, owner_profile_id, delegate_profile_id, consent_status, is_active, expires_at)
VALUES
  ('98400000-0000-0000-0000-000000000001', '98200000-0000-0000-0000-000000000001', '98100000-0000-0000-0000-000000000003', '98100000-0000-0000-0000-000000000004', 'accepted', false, now() + interval '7 days'),
  ('98400000-0000-0000-0000-000000000002', '98200000-0000-0000-0000-000000000001', '98100000-0000-0000-0000-000000000005', '98100000-0000-0000-0000-000000000004', 'pending', true, now() + interval '7 days'),
  ('98400000-0000-0000-0000-000000000003', '98200000-0000-0000-0000-000000000001', '98100000-0000-0000-0000-000000000003', '98100000-0000-0000-0000-000000000005', 'rejected', false, now() + interval '7 days'),
  ('98400000-0000-0000-0000-000000000004', '98200000-0000-0000-0000-000000000001', '98100000-0000-0000-0000-000000000005', '98100000-0000-0000-0000-000000000003', 'accepted', false, now() - interval '1 day');

INSERT INTO public.portfolios (
  id,
  client_id,
  workspace_id,
  total_invested_value,
  current_market_value
)
VALUES (
  '98500000-0000-0000-0000-000000000001',
  '98100000-0000-0000-0000-000000000003',
  '98200000-0000-0000-0000-000000000001',
  10000.00,
  12345.67
);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'order_requests'
      AND policyname NOT IN (
        'order_requests_select_workspace_isolation',
        'order_requests_insert_workspace_isolation'
      )
  ) THEN
    RAISE EXCEPTION 'Issue #31 changed Issue #30 order_requests policy set';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'order_requests';

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Issue #30 order_requests policy count changed: %', v_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'family_delegations',
        'workspace_audit_logs',
        'profiles',
        'workspaces',
        'workspace_memberships',
        'portfolios',
        'transactions',
        'order_requests',
        'payment_events',
        'workspace_billing',
        'advisor_investor_assignments',
        'workspace_invitations'
      )
      AND cmd IN ('ALL', 'UPDATE', 'DELETE')
      AND (
        qual ILIKE '%platform_admin%'
        OR with_check ILIKE '%platform_admin%'
        OR qual ILIKE '%is_platform_admin%'
        OR with_check ILIKE '%is_platform_admin%'
      )
  ) THEN
    RAISE EXCEPTION 'broad Platform Admin mutation policy survived';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'family_delegations'
      AND (
        qual ILIKE '%platform_admin%'
        OR with_check ILIKE '%platform_admin%'
        OR cmd IN ('UPDATE', 'DELETE', 'ALL')
      )
  ) THEN
    RAISE EXCEPTION 'family_delegations exposes broad Platform Admin policy';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS proc
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = proc.pronamespace
    WHERE namespace.nspname = 'public'
      AND proc.proname IN ('override_account_unlock', 'override_access_reset')
  ) THEN
    RAISE EXCEPTION 'pre-Issue #31 direct override functions survived';
  END IF;

  IF pg_catalog.has_function_privilege('authenticated', 'public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', 'public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role', 'public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'restore family delegation RPC privileges are incorrect';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated', 'public.begin_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.uuid)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', 'public.begin_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.uuid)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('service_role', 'public.begin_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'begin override RPC privileges are incorrect';
  END IF;
END;
$$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"98000000-0000-0000-0000-000000000001","role":"authenticated","workspace_id":"98200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"platform_admin"},"amr":["pwd","mfa"],"aal":"aal2"}', true);

SELECT public.begin_platform_admin_override_attempt(
  '98200000-0000-0000-0000-000000000001',
  'family_delegations',
  '98400000-0000-0000-0000-000000000001',
  'family_delegation.restore_access',
  'Restore consent-backed family access after identity-link correction',
  '98900000-0000-0000-0000-000000000001'
);

DO $$
BEGIN
  BEGIN
    PERFORM public.platform_admin_restore_family_delegation_access(
      '98900000-0000-0000-0000-000000000001',
      '98200000-0000-0000-0000-000000000001',
      '98400000-0000-0000-0000-000000000001',
      '98100000-0000-0000-0000-000000000003',
      '98100000-0000-0000-0000-000000000004'
    );
    RAISE EXCEPTION 'authenticated executed service-only family restore RPC';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END;
$$;

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.family_delegations;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Platform Admin has broad family_delegations SELECT';
  END IF;

  BEGIN
    UPDATE public.family_delegations
    SET is_active = true
    WHERE id = '98400000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'Platform Admin direct family_delegations UPDATE succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
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
      '98310000-0000-0000-0000-000000000001',
      '98200000-0000-0000-0000-000000000001',
      '98100000-0000-0000-0000-000000000003',
      '98100000-0000-0000-0000-000000000001',
      'investor',
      'investor_portal',
      'SCH31-ADMIN-DENIED',
      'buy',
      1000.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'Platform Admin initiated an order';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'Platform Admin initiated an order' THEN
      RAISE;
    END IF;
  END;
END;
$$;

RESET ROLE;

SET ROLE service_role;

SELECT public.platform_admin_restore_family_delegation_access(
  '98900000-0000-0000-0000-000000000001',
  '98200000-0000-0000-0000-000000000001',
  '98400000-0000-0000-0000-000000000001',
  '98100000-0000-0000-0000-000000000003',
  '98100000-0000-0000-0000-000000000004'
);

SELECT public.finish_platform_admin_override_attempt(
  '98900000-0000-0000-0000-000000000001',
  'override.succeeded',
  NULL
);

SELECT public.finish_platform_admin_override_attempt(
  '98900000-0000-0000-0000-000000000001',
  'override.succeeded',
  NULL
);

DO $$
BEGIN
  BEGIN
    PERFORM public.finish_platform_admin_override_attempt(
      '98900000-0000-0000-0000-000000000001',
      'override.denied',
      'conflicting_replay'
    );
    RAISE EXCEPTION 'conflicting terminal replay was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'terminal_outcome_conflict' THEN
      RAISE EXCEPTION 'Unexpected conflicting terminal replay error: %', SQLERRM;
    END IF;
  END;
END;
$$;

RESET ROLE;

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.workspace_audit_logs
  WHERE correlation_id = '98900000-0000-0000-0000-000000000001';

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'successful override audit sequence is not exactly attempted plus succeeded: %', v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.family_delegations
    WHERE id = '98400000-0000-0000-0000-000000000001'
      AND consent_status = 'accepted'
      AND is_active
      AND owner_profile_id = '98100000-0000-0000-0000-000000000003'
      AND delegate_profile_id = '98100000-0000-0000-0000-000000000004'
  ) THEN
    RAISE EXCEPTION 'consent-backed family delegation was not restored without identity substitution';
  END IF;
END;
$$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000002', true);
SELECT set_config('request.jwt.claims', '{"sub":"98000000-0000-0000-0000-000000000002","role":"authenticated","workspace_id":"98200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"mfd"},"amr":["pwd","mfa"],"aal":"aal2"}', true);

DO $$
BEGIN
  BEGIN
    PERFORM public.begin_platform_admin_override_attempt(
      '98200000-0000-0000-0000-000000000001',
      'family_delegations',
      '98400000-0000-0000-0000-000000000002',
      'family_delegation.restore_access',
      'Non-admin attempt',
      '98900000-0000-0000-0000-000000000002'
    );
    RAISE EXCEPTION 'non-admin began Platform Admin override attempt';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'not_authorized' THEN
      RAISE EXCEPTION 'Unexpected non-admin begin error: %', SQLERRM;
    END IF;
  END;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"98000000-0000-0000-0000-000000000001","role":"authenticated","workspace_id":"98200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"platform_admin"},"amr":["pwd"],"aal":"aal1"}', true);

DO $$
BEGIN
  BEGIN
    PERFORM public.begin_platform_admin_override_attempt(
      '98200000-0000-0000-0000-000000000001',
      'family_delegations',
      '98400000-0000-0000-0000-000000000002',
      'family_delegation.restore_access',
      'Missing step-up attempt',
      '98900000-0000-0000-0000-000000000003'
    );
    RAISE EXCEPTION 'Platform Admin without step-up began override attempt';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'platform_admin_step_up_required' THEN
      RAISE EXCEPTION 'Unexpected no-step-up begin error: %', SQLERRM;
    END IF;
  END;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"98000000-0000-0000-0000-000000000001","role":"authenticated","workspace_id":"98200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"platform_admin"},"amr":["pwd","mfa"],"aal":"aal2"}', true);

DO $$
BEGIN
  BEGIN
    PERFORM public.begin_platform_admin_override_attempt(
      '98200000-0000-0000-0000-000000000001',
      'family_delegations',
      '98400000-0000-0000-0000-000000000002',
      'family_delegation.restore_access',
      '',
      '98900000-0000-0000-0000-000000000004'
    );
    RAISE EXCEPTION 'missing reason was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'reason_required' THEN
      RAISE EXCEPTION 'Unexpected missing reason error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    PERFORM public.begin_platform_admin_override_attempt(
      '98200000-0000-0000-0000-000000000001',
      'family_delegations',
      '98400000-0000-0000-0000-000000000002',
      'family_delegation.restore_access',
      'Missing correlation',
      NULL
    );
    RAISE EXCEPTION 'missing correlation_id was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'correlation_id_required' THEN
      RAISE EXCEPTION 'Unexpected missing correlation error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    PERFORM public.begin_platform_admin_override_attempt(
      '98200000-0000-0000-0000-000000000002',
      'family_delegations',
      '98400000-0000-0000-0000-000000000002',
      'family_delegation.restore_access',
      'Wrong workspace',
      '98900000-0000-0000-0000-000000000005'
    );
    RAISE EXCEPTION 'mismatched workspace was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'target_workspace_mismatch' THEN
      RAISE EXCEPTION 'Unexpected workspace mismatch error: %', SQLERRM;
    END IF;
  END;
END;
$$;

SELECT public.begin_platform_admin_override_attempt(
  '98200000-0000-0000-0000-000000000001',
  'family_delegations',
  '98400000-0000-0000-0000-000000000002',
  'family_delegation.restore_access',
  'Attempt against pending consent',
  '98900000-0000-0000-0000-000000000006'
);

RESET ROLE;
SET ROLE service_role;

DO $$
BEGIN
  BEGIN
    PERFORM public.platform_admin_restore_family_delegation_access(
      '98900000-0000-0000-0000-000000000006',
      '98200000-0000-0000-0000-000000000001',
      '98400000-0000-0000-0000-000000000002',
      '98100000-0000-0000-0000-000000000005',
      '98100000-0000-0000-0000-000000000004'
    );
    RAISE EXCEPTION 'pending consent was silently activated';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'owner_consent_not_recorded' THEN
      RAISE EXCEPTION 'Unexpected pending consent restore error: %', SQLERRM;
    END IF;
  END;

  PERFORM public.finish_platform_admin_override_attempt(
    '98900000-0000-0000-0000-000000000006',
    'override.denied',
    'owner_consent_not_recorded'
  );
END;
$$;

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"98000000-0000-0000-0000-000000000001","role":"authenticated","workspace_id":"98200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"platform_admin"},"amr":["pwd","mfa"],"aal":"aal2"}', true);

SELECT public.begin_platform_admin_override_attempt(
  '98200000-0000-0000-0000-000000000001',
  'family_delegations',
  '98400000-0000-0000-0000-000000000004',
  'family_delegation.restore_access',
  'Attempt against expired consent',
  '98900000-0000-0000-0000-000000000007'
);

DO $$
BEGIN
  BEGIN
    PERFORM public.begin_platform_admin_override_attempt(
      '98200000-0000-0000-0000-000000000001',
      'family_delegations',
      '98400000-0000-0000-0000-000000000004',
      'family_delegation.read',
      'Reuse correlation with different action',
      '98900000-0000-0000-0000-000000000007'
    );
    RAISE EXCEPTION 'correlation was reused for a different action';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'correlation_id_conflict' THEN
      RAISE EXCEPTION 'Unexpected correlation conflict error: %', SQLERRM;
    END IF;
  END;
END;
$$;

RESET ROLE;
SET ROLE service_role;

DO $$
BEGIN
  BEGIN
    PERFORM public.platform_admin_restore_family_delegation_access(
      '98900000-0000-0000-0000-000000000007',
      '98200000-0000-0000-0000-000000000001',
      '98400000-0000-0000-0000-000000000004',
      '98100000-0000-0000-0000-000000000005',
      '98100000-0000-0000-0000-000000000003'
    );
    RAISE EXCEPTION 'expired consent was silently extended/restored';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'delegation_expired' THEN
      RAISE EXCEPTION 'Unexpected expired restore error: %', SQLERRM;
    END IF;
  END;

  PERFORM public.finish_platform_admin_override_attempt(
    '98900000-0000-0000-0000-000000000007',
    'override.denied',
    'delegation_expired'
  );
END;
$$;

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"98000000-0000-0000-0000-000000000001","role":"authenticated","workspace_id":"98200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"platform_admin"},"amr":["pwd","mfa"],"aal":"aal2"}', true);

SELECT public.begin_platform_admin_override_attempt(
  '98200000-0000-0000-0000-000000000001',
  'family_delegations',
  '98400000-0000-0000-0000-000000000001',
  'family_delegation.read',
  'Read support projection for restored family access',
  '98900000-0000-0000-0000-000000000008'
);

RESET ROLE;
SET ROLE service_role;

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.platform_admin_read_family_delegation_support_projection(
    '98900000-0000-0000-0000-000000000008',
    '98200000-0000-0000-0000-000000000001',
    '98400000-0000-0000-0000-000000000001',
    '98100000-0000-0000-0000-000000000003',
    '98100000-0000-0000-0000-000000000004'
  );

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'narrow family support read projection did not return exact target row';
  END IF;

  PERFORM public.finish_platform_admin_override_attempt(
    '98900000-0000-0000-0000-000000000008',
    'override.succeeded',
    NULL
  );
END;
$$;

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000004', true);
SELECT set_config('request.jwt.claims', '{"sub":"98000000-0000-0000-0000-000000000004","role":"authenticated","workspace_id":"98200000-0000-0000-0000-000000000999","app_metadata":{"user_role":"investor"}}', true);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.portfolios
  WHERE id = '98500000-0000-0000-0000-000000000001';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Family Guest read access did not use restored accepted active delegation';
  END IF;

  UPDATE public.family_delegations
  SET is_active = false
  WHERE id = '98400000-0000-0000-0000-000000000001';

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.portfolios
  WHERE id = '98500000-0000-0000-0000-000000000001';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Family Guest portfolio read ignored active consent-backed delegation state';
  END IF;
EXCEPTION WHEN insufficient_privilege THEN
  -- The direct UPDATE must be blocked for the Family Guest; owner/delegate access is read-only.
  NULL;
END;
$$;

RESET ROLE;

DO $$
DECLARE
  v_attempts pg_catalog.int4;
  v_terminals pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_attempts
  FROM public.workspace_audit_logs
  WHERE event_type = 'override.attempted'
    AND correlation_id IN (
      '98900000-0000-0000-0000-000000000001',
      '98900000-0000-0000-0000-000000000006',
      '98900000-0000-0000-0000-000000000007',
      '98900000-0000-0000-0000-000000000008'
    );

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_terminals
  FROM public.workspace_audit_logs
  WHERE event_type IN ('override.succeeded', 'override.denied', 'override.failed')
    AND correlation_id IN (
      '98900000-0000-0000-0000-000000000001',
      '98900000-0000-0000-0000-000000000006',
      '98900000-0000-0000-0000-000000000007',
      '98900000-0000-0000-0000-000000000008'
    );

  IF v_attempts <> 4 OR v_terminals <> 4 THEN
    RAISE EXCEPTION 'override attempted/terminal audit counts are incorrect: attempts %, terminals %', v_attempts, v_terminals;
  END IF;

  BEGIN
    UPDATE public.workspace_audit_logs
    SET outcome = 'tampered'
    WHERE correlation_id = '98900000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'workspace_audit_logs update was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Audit logs are immutable and cannot be updated or deleted' THEN
      RAISE EXCEPTION 'Unexpected audit update immutability error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    DELETE FROM public.workspace_audit_logs
    WHERE correlation_id = '98900000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'workspace_audit_logs delete was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Audit logs are immutable and cannot be updated or deleted' THEN
      RAISE EXCEPTION 'Unexpected audit delete immutability error: %', SQLERRM;
    END IF;
  END;
END;
$$;

SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

ROLLBACK;
