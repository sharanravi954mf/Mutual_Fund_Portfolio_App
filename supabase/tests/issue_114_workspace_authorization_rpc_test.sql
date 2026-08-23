-- Regression: Issue #114 authenticated workspace authorization RPC.

BEGIN;

INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) VALUES
  ('91500000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
    'issue114-rpc-advisor@moneybowl.test', '{}', '{}', pg_catalog.now(), pg_catalog.now()),
  ('91500000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
    'issue114-rpc-admin@moneybowl.test', '{}', '{}', pg_catalog.now(), pg_catalog.now()),
  ('91500000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
    'issue114-rpc-investor@moneybowl.test', '{}', '{}', pg_catalog.now(), pg_catalog.now()),
  ('91500000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
    'issue114-rpc-inactive@moneybowl.test', '{}', '{}', pg_catalog.now(), pg_catalog.now()),
  ('91500000-0000-0000-0000-000000000005', 'authenticated', 'authenticated',
    'issue114-rpc-ended@moneybowl.test', '{}', '{}', pg_catalog.now(), pg_catalog.now());

UPDATE public.profiles
SET id = CASE user_id
    WHEN '91500000-0000-0000-0000-000000000001' THEN '91510000-0000-0000-0000-000000000001'::pg_catalog.uuid
    WHEN '91500000-0000-0000-0000-000000000002' THEN '91510000-0000-0000-0000-000000000002'::pg_catalog.uuid
    WHEN '91500000-0000-0000-0000-000000000003' THEN '91510000-0000-0000-0000-000000000003'::pg_catalog.uuid
    WHEN '91500000-0000-0000-0000-000000000004' THEN '91510000-0000-0000-0000-000000000004'::pg_catalog.uuid
    WHEN '91500000-0000-0000-0000-000000000005' THEN '91510000-0000-0000-0000-000000000005'::pg_catalog.uuid
  END,
  role = CASE user_id
    WHEN '91500000-0000-0000-0000-000000000001' THEN 'advisor'
    WHEN '91500000-0000-0000-0000-000000000002' THEN 'admin'
    ELSE 'investor'
  END
WHERE user_id IN (
  '91500000-0000-0000-0000-000000000001',
  '91500000-0000-0000-0000-000000000002',
  '91500000-0000-0000-0000-000000000003',
  '91500000-0000-0000-0000-000000000004',
  '91500000-0000-0000-0000-000000000005'
);

DELETE FROM public.workspace_memberships
WHERE profile_id IN (
  '91510000-0000-0000-0000-000000000001',
  '91510000-0000-0000-0000-000000000002',
  '91510000-0000-0000-0000-000000000003',
  '91510000-0000-0000-0000-000000000004',
  '91510000-0000-0000-0000-000000000005'
);

INSERT INTO public.workspaces (
  id, name, slug, owner_profile_id, workspace_status
) VALUES
  ('91520000-0000-0000-0000-000000000001', 'Issue 114 RPC Active',
    'issue-114-rpc-active', '91510000-0000-0000-0000-000000000001', 'active'),
  ('91520000-0000-0000-0000-000000000002', 'Issue 114 RPC Inactive',
    'issue-114-rpc-inactive', '91510000-0000-0000-0000-000000000001', 'suspended');

INSERT INTO public.workspace_memberships (
  workspace_id, profile_id, role, status, ended_at
) VALUES
  ('91520000-0000-0000-0000-000000000001',
    '91510000-0000-0000-0000-000000000001', 'advisor', 'active', NULL),
  ('91520000-0000-0000-0000-000000000001',
    '91510000-0000-0000-0000-000000000002', 'admin', 'active', NULL),
  ('91520000-0000-0000-0000-000000000001',
    '91510000-0000-0000-0000-000000000003', 'investor', 'active', NULL),
  ('91520000-0000-0000-0000-000000000001',
    '91510000-0000-0000-0000-000000000004', 'advisor', 'inactive', NULL),
  ('91520000-0000-0000-0000-000000000001',
    '91510000-0000-0000-0000-000000000005', 'advisor', 'active', pg_catalog.now()),
  ('91520000-0000-0000-0000-000000000002',
    '91510000-0000-0000-0000-000000000001', 'advisor', 'active', NULL);

DO $$
DECLARE
  v_table pg_catalog.text;
BEGIN
  IF NOT pg_catalog.has_function_privilege(
      'authenticated',
      'public.authorize_cams_kfintech_workspace(pg_catalog.uuid)',
      'EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
      'anon',
      'public.authorize_cams_kfintech_workspace(pg_catalog.uuid)',
      'EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
      'service_role',
      'public.authorize_cams_kfintech_workspace(pg_catalog.uuid)',
      'EXECUTE'
    ) THEN
    RAISE EXCEPTION 'issue_114_workspace_authorization_rpc_acl_invalid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure
    WHERE procedure.oid =
      'public.authorize_cams_kfintech_workspace(pg_catalog.uuid)'::pg_catalog.regprocedure
      AND (
        NOT procedure.prosecdef
        OR procedure.provolatile <> 's'
        OR procedure.prorettype <> 'pg_catalog.bool'::pg_catalog.regtype
        OR procedure.proconfig IS DISTINCT FROM ARRAY['search_path=""']
      )
  ) THEN
    RAISE EXCEPTION 'issue_114_workspace_authorization_rpc_security_contract_invalid';
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'workspaces',
    'profiles',
    'workspace_memberships',
    'mailbox_oauth_credentials',
    'mailbox_oauth_authorization_states'
  ] LOOP
    IF pg_catalog.has_table_privilege(
      'service_role', 'public.' || v_table, 'SELECT'
    ) THEN
      RAISE EXCEPTION 'issue_114_service_role_protected_table_select:%', v_table;
    END IF;
  END LOOP;
END;
$$;

CREATE TEMP TABLE issue_114_authorization_results (
  actor_role pg_catalog.text PRIMARY KEY,
  authorized pg_catalog.bool NOT NULL
) ON COMMIT DROP;
GRANT INSERT, SELECT ON TABLE issue_114_authorization_results TO authenticated;

SET ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', '91500000-0000-0000-0000-000000000001', true
);
SELECT pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
INSERT INTO issue_114_authorization_results
VALUES ('advisor', public.authorize_cams_kfintech_workspace(
  '91520000-0000-0000-0000-000000000001'
));

SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', '91500000-0000-0000-0000-000000000002', true
);
INSERT INTO issue_114_authorization_results
VALUES ('admin', public.authorize_cams_kfintech_workspace(
  '91520000-0000-0000-0000-000000000001'
));
RESET ROLE;

DO $$
BEGIN
  IF (SELECT pg_catalog.count(*) FROM issue_114_authorization_results
      WHERE authorized) <> 2 THEN
    RAISE EXCEPTION 'issue_114_valid_advisor_or_admin_denied';
  END IF;
END;
$$;

SET ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', '91500000-0000-0000-0000-000000000003', true
);
DO $$
BEGIN
  PERFORM public.authorize_cams_kfintech_workspace(
    '91520000-0000-0000-0000-000000000001'
  );
  RAISE EXCEPTION 'issue_114_investor_authorized';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not_authorized%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

SET ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', '91500000-0000-0000-0000-000000000004', true
);
DO $$
BEGIN
  PERFORM public.authorize_cams_kfintech_workspace(
    '91520000-0000-0000-0000-000000000001'
  );
  RAISE EXCEPTION 'issue_114_inactive_membership_authorized';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not_authorized%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

SET ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', '91500000-0000-0000-0000-000000000005', true
);
DO $$
BEGIN
  PERFORM public.authorize_cams_kfintech_workspace(
    '91520000-0000-0000-0000-000000000001'
  );
  RAISE EXCEPTION 'issue_114_ended_membership_authorized';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not_authorized%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

SET ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', '91500000-0000-0000-0000-000000000001', true
);
DO $$
BEGIN
  PERFORM public.authorize_cams_kfintech_workspace(
    '91520000-0000-0000-0000-000000000002'
  );
  RAISE EXCEPTION 'issue_114_inactive_workspace_authorized';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not_authorized%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

SET ROLE authenticated;
SELECT pg_catalog.set_config('request.jwt.claim.sub', '', true);
DO $$
BEGIN
  PERFORM public.authorize_cams_kfintech_workspace(
    '91520000-0000-0000-0000-000000000001'
  );
  RAISE EXCEPTION 'issue_114_missing_jwt_authorized';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not_authorized%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

SET ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', '91500000-0000-0000-0000-000000000099', true
);
DO $$
BEGIN
  PERFORM public.authorize_cams_kfintech_workspace(
    '91520000-0000-0000-0000-000000000001'
  );
  RAISE EXCEPTION 'issue_114_invalid_jwt_identity_authorized';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not_authorized%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

ROLLBACK;
