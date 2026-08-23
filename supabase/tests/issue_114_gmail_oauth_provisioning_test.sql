-- Test Suite: Issue #114 secure initial Gmail OAuth provisioning.

BEGIN;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('91400000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue114-advisor@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('91400000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue114-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now());

UPDATE public.profiles SET id = '91410000-0000-0000-0000-000000000001', role = 'advisor'
WHERE user_id = '91400000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '91410000-0000-0000-0000-000000000002', role = 'investor'
WHERE user_id = '91400000-0000-0000-0000-000000000002';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES ('91420000-0000-0000-0000-000000000001', 'Issue 114 Workspace',
  'issue-114-workspace', '91410000-0000-0000-0000-000000000001', 'active');

DELETE FROM public.workspace_memberships
WHERE profile_id IN ('91410000-0000-0000-0000-000000000001', '91410000-0000-0000-0000-000000000002');
INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('91420000-0000-0000-0000-000000000001', '91410000-0000-0000-0000-000000000001', 'advisor', 'active'),
  ('91420000-0000-0000-0000-000000000001', '91410000-0000-0000-0000-000000000002', 'investor', 'active');

INSERT INTO public.mailbox_connections (
  id, workspace_id, registrar, mailbox_address, connector_ref,
  oauth_provider, allowed_sender_addresses, status
) VALUES (
  '91430000-0000-0000-0000-000000000001',
  '91420000-0000-0000-0000-000000000001', 'CAMS',
  'issue114@moneybowl.test', 'gmail:me', 'gmail',
  ARRAY['statements@example.test'], 'active'
);

CREATE TEMP TABLE issue_114_context (
  authorization_id pg_catalog.uuid,
  credential_nonce pg_catalog.text
) ON COMMIT DROP;
GRANT SELECT, INSERT, UPDATE ON TABLE issue_114_context TO authenticated, service_role;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name IN ('mailbox_oauth_authorization_states', 'mailbox_oauth_credentials')
      AND column_name IN ('state', 'authorization_code', 'access_token', 'refresh_token')
  ) THEN
    RAISE EXCEPTION 'Issue #114 plaintext OAuth persistence column detected';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS class
    WHERE class.oid = 'public.mailbox_oauth_authorization_states'::pg_catalog.regclass
      AND class.relrowsecurity
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies
    WHERE schemaname = 'public' AND tablename = 'mailbox_oauth_authorization_states'
  ) THEN
    RAISE EXCEPTION 'Issue #114 OAuth state table must be inaccessible behind RLS/RPCs';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated',
      'public.begin_mailbox_oauth_authorization(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.text,pg_catalog.timestamptz)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon',
      'public.begin_mailbox_oauth_authorization(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.text,pg_catalog.timestamptz)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role',
      'public.consume_mailbox_oauth_authorization(pg_catalog.text,pg_catalog.text)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated',
      'public.consume_mailbox_oauth_authorization(pg_catalog.text,pg_catalog.text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Issue #114 OAuth RPC grants are not least privilege';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc
    WHERE oid IN (
      'public.begin_mailbox_oauth_authorization(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.text,pg_catalog.timestamptz)'::pg_catalog.regprocedure,
      'public.consume_mailbox_oauth_authorization(pg_catalog.text,pg_catalog.text)'::pg_catalog.regprocedure,
      'public.complete_mailbox_oauth_authorization(pg_catalog.uuid,pg_catalog.text,pg_catalog.text,pg_catalog.int4,pg_catalog.timestamptz)'::pg_catalog.regprocedure,
      'public.revoke_mailbox_oauth_credential(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text)'::pg_catalog.regprocedure
    ) AND (NOT prosecdef OR proconfig IS DISTINCT FROM ARRAY['search_path=""'])
  ) THEN
    RAISE EXCEPTION 'Issue #114 OAuth RPC SECURITY DEFINER/search_path contract missing';
  END IF;
END;
$$;

SET ROLE authenticated;
SELECT pg_catalog.set_config('request.jwt.claim.sub', '91400000-0000-0000-0000-000000000001', true);
SELECT pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
INSERT INTO issue_114_context (authorization_id)
SELECT authorization_id
FROM public.begin_mailbox_oauth_authorization(
  '91420000-0000-0000-0000-000000000001',
  '91430000-0000-0000-0000-000000000001',
  pg_catalog.repeat('a', 64),
  'https://dev.example.test/functions/v1/cams-kfintech-ingestion/oauth/callback',
  pg_catalog.now() + pg_catalog.interval '5 minutes'
);
RESET ROLE;

DO $$
BEGIN
  IF (SELECT flow_kind FROM public.mailbox_oauth_authorization_states
      WHERE state_hash = pg_catalog.repeat('a', 64)) <> 'first_time' THEN
    RAISE EXCEPTION 'Issue #114 first-time flow not classified';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.mailbox_oauth_authorization_states
    WHERE state_hash = pg_catalog.repeat('a', 64)
      AND state_hash <> pg_catalog.repeat('a', 64)
  ) THEN
    RAISE EXCEPTION 'Issue #114 state digest persistence mismatch';
  END IF;
END;
$$;

SET ROLE service_role;
SELECT * FROM public.consume_mailbox_oauth_authorization(
  pg_catalog.repeat('a', 64),
  'https://dev.example.test/functions/v1/cams-kfintech-ingestion/oauth/callback'
);
RESET ROLE;

UPDATE public.workspace_memberships
SET status = 'suspended'
WHERE workspace_id = '91420000-0000-0000-0000-000000000001'
  AND profile_id = '91410000-0000-0000-0000-000000000001';
SET ROLE service_role;
DO $$
BEGIN
  PERFORM public.complete_mailbox_oauth_authorization(
    (SELECT authorization_id FROM issue_114_context),
    pg_catalog.encode('encrypted-envelope-only'::pg_catalog.bytea, 'base64'),
    pg_catalog.encode(pg_catalog.repeat('n', 12)::pg_catalog.bytea, 'base64'),
    1,
    pg_catalog.now() + pg_catalog.interval '1 hour'
  );
  RAISE EXCEPTION 'Issue #114 callback completed after actor authorization ended';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not_authorized%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;
UPDATE public.workspace_memberships
SET status = 'active'
WHERE workspace_id = '91420000-0000-0000-0000-000000000001'
  AND profile_id = '91410000-0000-0000-0000-000000000001';

SET ROLE service_role;
SELECT public.complete_mailbox_oauth_authorization(
  (SELECT authorization_id FROM issue_114_context),
  pg_catalog.encode('encrypted-envelope-only'::pg_catalog.bytea, 'base64'),
  pg_catalog.encode(pg_catalog.repeat('n', 12)::pg_catalog.bytea, 'base64'),
  1,
  pg_catalog.now() + pg_catalog.interval '1 hour'
);
RESET ROLE;

UPDATE issue_114_context
SET credential_nonce = (
  SELECT credential_nonce FROM public.mailbox_oauth_credentials
  WHERE mailbox_connection_id = '91430000-0000-0000-0000-000000000001'
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.mailbox_oauth_credentials
    WHERE mailbox_connection_id = '91430000-0000-0000-0000-000000000001'
      AND credential_ciphertext = pg_catalog.encode('encrypted-envelope-only'::pg_catalog.bytea, 'base64')
  ) THEN
    RAISE EXCEPTION 'Issue #114 encrypted first write missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_audit_logs
    WHERE target_id = '91430000-0000-0000-0000-000000000001'
      AND event_type = 'mailbox.oauth.authorization_completed'
      AND payload = '{"flow_kind":"first_time"}'::pg_catalog.jsonb
  ) THEN
    RAISE EXCEPTION 'Issue #114 completion audit missing or contains unexpected data';
  END IF;
END;
$$;

SET ROLE service_role;
DO $$
BEGIN
  PERFORM public.consume_mailbox_oauth_authorization(
    pg_catalog.repeat('a', 64),
    'https://dev.example.test/functions/v1/cams-kfintech-ingestion/oauth/callback'
  );
  RAISE EXCEPTION 'Issue #114 replayed state accepted';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%oauth_state_replayed%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

INSERT INTO public.mailbox_oauth_authorization_states (
  state_hash, workspace_id, mailbox_connection_id, actor_profile_id,
  redirect_uri, flow_kind, expires_at
) VALUES (
  pg_catalog.repeat('b', 64),
  '91420000-0000-0000-0000-000000000001',
  '91430000-0000-0000-0000-000000000001',
  '91410000-0000-0000-0000-000000000001',
  'https://dev.example.test/functions/v1/cams-kfintech-ingestion/oauth/callback',
  'reauthorization', pg_catalog.now() - pg_catalog.interval '1 second'
);
SET ROLE service_role;
DO $$
BEGIN
  PERFORM public.consume_mailbox_oauth_authorization(
    pg_catalog.repeat('b', 64),
    'https://dev.example.test/functions/v1/cams-kfintech-ingestion/oauth/callback'
  );
  RAISE EXCEPTION 'Issue #114 expired state accepted';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%oauth_state_expired%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

SET ROLE authenticated;
SELECT pg_catalog.set_config('request.jwt.claim.sub', '91400000-0000-0000-0000-000000000002', true);
SELECT pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
DO $$
BEGIN
  PERFORM public.begin_mailbox_oauth_authorization(
    '91420000-0000-0000-0000-000000000001',
    '91430000-0000-0000-0000-000000000001', pg_catalog.repeat('c', 64),
    'https://dev.example.test/functions/v1/cams-kfintech-ingestion/oauth/callback',
    pg_catalog.now() + pg_catalog.interval '5 minutes'
  );
  RAISE EXCEPTION 'Issue #114 investor initiated mailbox provisioning';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not_authorized%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

SET ROLE authenticated;
SELECT pg_catalog.set_config('request.jwt.claim.sub', '91400000-0000-0000-0000-000000000001', true);
SELECT pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
SELECT public.revoke_mailbox_oauth_credential(
  '91420000-0000-0000-0000-000000000001',
  '91430000-0000-0000-0000-000000000001',
  (SELECT credential_nonce FROM issue_114_context)
);
RESET ROLE;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.mailbox_oauth_credentials
      WHERE mailbox_connection_id = '91430000-0000-0000-0000-000000000001')
     OR NOT EXISTS (SELECT 1 FROM public.mailbox_connections
      WHERE id = '91430000-0000-0000-0000-000000000001'
        AND status = 'reauthorization_required') THEN
    RAISE EXCEPTION 'Issue #114 deterministic revocation state missing';
  END IF;
END;
$$;

ROLLBACK;
