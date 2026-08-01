-- Test Suite: Issue #32 CAMS/KFintech in-memory ingestion contracts.

BEGIN;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('93200000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue32-owner@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('93200000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue32-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('93200000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'issue32-family-guest@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('93200000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'issue32-owner-b@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now());

UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id IN (
  '93200000-0000-0000-0000-000000000001',
  '93200000-0000-0000-0000-000000000004'
);

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id IN (
  '93200000-0000-0000-0000-000000000002',
  '93200000-0000-0000-0000-000000000003'
);

UPDATE public.profiles SET id = '93300000-0000-0000-0000-000000000001', role = 'advisor', full_name = 'Issue 32 Owner'
WHERE user_id = '93200000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '93300000-0000-0000-0000-000000000002', role = 'investor', full_name = 'Issue 32 Investor'
WHERE user_id = '93200000-0000-0000-0000-000000000002';
UPDATE public.profiles SET id = '93300000-0000-0000-0000-000000000003', role = 'investor', full_name = 'Issue 32 Family Guest'
WHERE user_id = '93200000-0000-0000-0000-000000000003';
UPDATE public.profiles SET id = '93300000-0000-0000-0000-000000000004', role = 'advisor', full_name = 'Issue 32 Owner B'
WHERE user_id = '93200000-0000-0000-0000-000000000004';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('93400000-0000-0000-0000-000000000001', 'Issue 32 Workspace A', 'issue-32-workspace-a', '93300000-0000-0000-0000-000000000001', 'active'),
  ('93400000-0000-0000-0000-000000000002', 'Issue 32 Workspace B', 'issue-32-workspace-b', '93300000-0000-0000-0000-000000000004', 'active');

DELETE FROM public.workspace_memberships
WHERE profile_id IN (
  '93300000-0000-0000-0000-000000000001',
  '93300000-0000-0000-0000-000000000002',
  '93300000-0000-0000-0000-000000000003',
  '93300000-0000-0000-0000-000000000004'
);

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('93400000-0000-0000-0000-000000000001', '93300000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('93400000-0000-0000-0000-000000000001', '93300000-0000-0000-0000-000000000002', 'investor', 'active'),
  ('93400000-0000-0000-0000-000000000001', '93300000-0000-0000-0000-000000000003', 'investor', 'active'),
  ('93400000-0000-0000-0000-000000000002', '93300000-0000-0000-0000-000000000004', 'admin', 'active');

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('93200000-0000-0000-0000-000000000002', '93300000-0000-0000-0000-000000000002', 'verified_email', now(), 'active'),
  ('93200000-0000-0000-0000-000000000003', '93300000-0000-0000-0000-000000000003', 'verified_email', now(), 'active');

INSERT INTO public.profile_pan_records (
  id,
  profile_id,
  pan_ciphertext,
  pan_lookup_hmac,
  masked_pan,
  source,
  source_system,
  status,
  verified_at
) VALUES (
  '93210000-0000-0000-0000-000000000001',
  '93300000-0000-0000-0000-000000000002',
  extensions.pgp_sym_encrypt('QWERT1234Y', public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
  extensions.hmac('QWERT1234Y', public.pan_lookup_hmac_key(), 'sha256'),
  public.mask_pan('QWERT1234Y'),
  'INVESTOR',
  'MANUAL',
  'VERIFIED',
  now()
);

UPDATE public.profiles
SET canonical_pan_record_id = '93210000-0000-0000-0000-000000000001'
WHERE id = '93300000-0000-0000-0000-000000000002';

INSERT INTO public.family_delegations (id, workspace_id, owner_profile_id, delegate_profile_id, consent_status, is_active, expires_at)
VALUES (
  '93500000-0000-0000-0000-000000000001',
  '93400000-0000-0000-0000-000000000001',
  '93300000-0000-0000-0000-000000000002',
  '93300000-0000-0000-0000-000000000003',
  'accepted',
  true,
  now() + interval '7 days'
);

INSERT INTO public.registrar_configs (
  id,
  workspace_id,
  registrar,
  allowed_sender_addresses,
  max_attachment_bytes,
  max_messages_per_poll,
  max_attachments_per_message,
  max_attachments_per_run,
  total_bytes_per_run,
  supported_file_types,
  is_active
) VALUES
  ('93600000-0000-0000-0000-000000000001', '93400000-0000-0000-0000-000000000001', 'CAMS', ARRAY['workspace@camsonline.com'], 1024, 10, 2, 4, 4096, ARRAY['CAS_PDF', 'DBF'], true),
  ('93600000-0000-0000-0000-000000000004', '93400000-0000-0000-0000-000000000001', 'KFINTECH', ARRAY['workspace@kfintech.com'], 1024, 10, 2, 4, 4096, ARRAY['CAS_PDF', 'DBF'], true),
  ('93600000-0000-0000-0000-000000000002', NULL, 'CAMS', ARRAY['global@camsonline.com'], 2048, 20, 3, 6, 8192, ARRAY['DBF'], true),
  ('93600000-0000-0000-0000-000000000003', NULL, 'KFINTECH', ARRAY['inactive@kfintech.com'], 2048, 20, 3, 6, 8192, ARRAY['DBF'], false);

INSERT INTO public.mailbox_connections (
  id,
  workspace_id,
  registrar,
  mailbox_address,
  connector_ref,
  oauth_provider,
  allowed_sender_addresses,
  status
) VALUES
  ('93700000-0000-0000-0000-000000000001', '93400000-0000-0000-0000-000000000001', 'CAMS', 'owner@moneybowl.test', 'issue-32-connector-a', 'gmail', ARRAY['statements@camsonline.com'], 'active'),
  ('93700000-0000-0000-0000-000000000003', '93400000-0000-0000-0000-000000000001', 'KFINTECH', 'owner-kfin@moneybowl.test', 'issue-32-connector-kfin', 'gmail', ARRAY['statements@kfintech.com'], 'active'),
  ('93700000-0000-0000-0000-000000000002', '93400000-0000-0000-0000-000000000002', 'CAMS', 'owner-b@moneybowl.test', 'issue-32-connector-b', 'gmail', ARRAY['statements@camsonline.com'], 'active');

INSERT INTO public.mailbox_oauth_credentials (
  id,
  mailbox_connection_id,
  workspace_id,
  credential_ciphertext,
  credential_nonce,
  key_version,
  expires_at
) VALUES
  ('93800000-0000-0000-0000-000000000001', '93700000-0000-0000-0000-000000000001', '93400000-0000-0000-0000-000000000001', encode('ciphertext-a'::bytea, 'base64'), encode(repeat('n', 12)::bytea, 'base64'), 1, now() + interval '1 hour'),
  ('93800000-0000-0000-0000-000000000003', '93700000-0000-0000-0000-000000000003', '93400000-0000-0000-0000-000000000001', encode('ciphertext-k'::bytea, 'base64'), encode(repeat('k', 12)::bytea, 'base64'), 1, now() + interval '1 hour'),
  ('93800000-0000-0000-0000-000000000002', '93700000-0000-0000-0000-000000000002', '93400000-0000-0000-0000-000000000002', encode('ciphertext-b'::bytea, 'base64'), encode(repeat('m', 12)::bytea, 'base64'), 1, now() + interval '1 hour');

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id = 'ingested-documents'
      AND public = false
      AND file_size_limit = 20971519
      AND allowed_mime_types @> ARRAY['application/pdf', 'application/x-dbase', 'application/octet-stream']::pg_catalog.text[]
  ) THEN
    RAISE EXCEPTION 'Issue #32 private ingested-documents bucket contract missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname IN ('public', 'storage')
      AND tablename IN ('ingested_documents', 'mailbox_oauth_credentials', 'objects')
      AND (
        tablename <> 'objects'
        OR qual ILIKE '%ingested-documents%'
        OR with_check ILIKE '%ingested-documents%'
      )
  ) THEN
    RAISE EXCEPTION 'Issue #32 sensitive document or OAuth table exposes an RLS policy';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(class.relacl, pg_catalog.acldefault('r', class.relowner))
    ) AS acl
    WHERE class.oid IN (
      'public.registrar_configs'::pg_catalog.regclass,
      'public.mailbox_connections'::pg_catalog.regclass,
      'public.mailbox_oauth_credentials'::pg_catalog.regclass,
      'public.ingested_documents'::pg_catalog.regclass,
      'public.ingestion_logs'::pg_catalog.regclass,
      'public.cams_kfintech_ingestion_attempts'::pg_catalog.regclass
    )
      AND acl.grantee = 0
      AND acl.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ) THEN
    RAISE EXCEPTION 'Issue #32 sensitive table exposes PUBLIC table ACL';
  END IF;

  IF pg_catalog.has_table_privilege('anon', 'public.mailbox_oauth_credentials', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.mailbox_oauth_credentials', 'SELECT')
     OR pg_catalog.has_table_privilege('service_role', 'public.mailbox_oauth_credentials', 'UPDATE') THEN
    RAISE EXCEPTION 'Issue #32 OAuth credential table grants are incorrect';
  END IF;

  IF pg_catalog.has_table_privilege('anon', 'public.ingested_documents', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.ingested_documents', 'SELECT')
     OR pg_catalog.has_table_privilege('service_role', 'public.ingested_documents', 'INSERT')
     OR pg_catalog.has_table_privilege('service_role', 'public.ingested_documents', 'UPDATE')
     OR pg_catalog.has_table_privilege('service_role', 'public.ingested_documents', 'DELETE')
     OR pg_catalog.has_table_privilege('service_role', 'public.cams_kfintech_ingestion_runs', 'INSERT')
     OR pg_catalog.has_table_privilege('service_role', 'public.cams_kfintech_ingestion_runs', 'UPDATE')
     OR pg_catalog.has_table_privilege('service_role', 'public.cams_kfintech_ingestion_attempts', 'INSERT')
     OR pg_catalog.has_table_privilege('service_role', 'public.cams_kfintech_ingestion_attempts', 'UPDATE')
     OR pg_catalog.has_table_privilege('service_role', 'public.cams_kfintech_ingestion_attempts', 'DELETE') THEN
    RAISE EXCEPTION 'Issue #32 document table grants are incorrect';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM pg_catalog.pg_proc AS proc
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = proc.pronamespace
  WHERE namespace.nspname = 'public'
    AND proc.proname IN (
      'load_mailbox_oauth_credential_envelope',
      'replace_mailbox_oauth_credential_envelope',
      'claim_cams_kfintech_ingestion_run',
      'finalize_cams_kfintech_ingestion_run',
      'record_cams_kfintech_ingestion_failure',
      'persist_cams_kfintech_statement_ingestion'
    )
    AND proc.prosecdef
    AND proc.proconfig = ARRAY['search_path=""']::pg_catalog.text[];

  IF v_count <> 6 THEN
    RAISE EXCEPTION 'Issue #32 RPCs are not SECURITY DEFINER with empty search_path';
  END IF;

  IF pg_catalog.has_function_privilege('authenticated', 'public.load_mailbox_oauth_credential_envelope(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', 'public.load_mailbox_oauth_credential_envelope(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role', 'public.load_mailbox_oauth_credential_envelope(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Issue #32 credential load RPC privileges are incorrect';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'registrar_configs_global_registrar_uidx'
  )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND indexname = 'ingested_documents_provider_attachment_uidx'
     )
     OR NOT EXISTS (
	       SELECT 1 FROM pg_catalog.pg_indexes
	       WHERE schemaname = 'public'
         AND indexname = 'ingestion_logs_failure_run_attempt_uidx'
     )
     OR NOT EXISTS (
	     SELECT 1 FROM pg_catalog.pg_indexes
	     WHERE schemaname = 'public'
         AND indexname = 'cams_kfintech_ingestion_attempts_run_outcome_idx'
	     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND indexname = 'transactions_registrar_folio_txn_uidx'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND indexname = 'portfolio_folio_references_folio_idx'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND indexname = 'portfolio_folio_references_pair_uidx'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND indexname = 'portfolios_workspace_client_uidx'
     )
	     OR NOT EXISTS (
	       SELECT 1 FROM pg_catalog.pg_indexes
	       WHERE schemaname = 'public'
         AND indexname = 'event_outbox_statement_imported_uidx'
     ) THEN
    RAISE EXCEPTION 'Issue #32 idempotency/config indexes are missing';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated', 'public.cancel_order(pg_catalog.uuid, pg_catalog.text)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role', 'public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Issue #28-#31 regression guard failed for key RPC grants';
  END IF;
END;
$$;

DO $$
BEGIN
  INSERT INTO public.registrar_configs (
    workspace_id,
    registrar,
    allowed_sender_addresses
  ) VALUES (
    NULL,
    'CAMS',
    ARRAY['duplicate@camsonline.com']
  );
  RAISE EXCEPTION 'duplicate global registrar config accepted';
EXCEPTION
  WHEN unique_violation THEN
    NULL;
END;
$$;

SET ROLE authenticated;
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '93200000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM 1 FROM public.mailbox_oauth_credentials LIMIT 1;
  RAISE EXCEPTION 'family guest read OAuth credentials directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;
RESET ROLE;

SET ROLE service_role;
SELECT *
FROM public.load_mailbox_oauth_credential_envelope(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001'
);

DO $$
BEGIN
  PERFORM public.replace_mailbox_oauth_credential_envelope(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    encode('new-ciphertext'::bytea, 'base64'),
    encode('short'::bytea, 'base64'),
    1,
    now() + interval '2 hours'
  );
  RAISE EXCEPTION 'invalid credential nonce accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%oauth_credentials_unavailable%' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  PERFORM public.replace_mailbox_oauth_credential_envelope(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    'not valid base64',
    encode(repeat('r', 12)::bytea, 'base64'),
    1,
    now() + interval '2 hours'
  );
  RAISE EXCEPTION 'invalid credential ciphertext accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%oauth_credentials_unavailable%' THEN
      RAISE;
    END IF;
END;
$$;

SELECT public.replace_mailbox_oauth_credential_envelope(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  encode('new-ciphertext'::bytea, 'base64'),
  encode(repeat('r', 12)::bytea, 'base64'),
  1,
  now() + interval '2 hours'
);

DO $$
BEGIN
  UPDATE public.mailbox_oauth_credentials
  SET credential_ciphertext = encode('forged'::bytea, 'base64')
  WHERE id = '93800000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'service_role updated OAuth ciphertext directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;

RESET ROLE;

INSERT INTO public.mutual_funds (
  id,
  scheme_code,
  scheme_name,
  fund_house,
  category,
  current_nav,
  nav_date
) VALUES (
  '93220000-0000-0000-0000-000000000001',
  'MF32A',
  'Issue 32 Existing Growth Fund',
  'Money Bowl AMC',
  'Equity',
  999.0000,
  '2026-01-01'
);

INSERT INTO public.portfolios (
  id,
  client_id,
  workspace_id,
  total_invested_value,
  current_market_value
) VALUES
  ('93230000-0000-0000-0000-000000000001', '93300000-0000-0000-0000-000000000003', '93400000-0000-0000-0000-000000000001', 0.00, 0.00),
  ('93230000-0000-0000-0000-000000000002', '93300000-0000-0000-0000-000000000002', '93400000-0000-0000-0000-000000000002', 0.00, 0.00);

SET ROLE service_role;

SELECT public.claim_cams_kfintech_ingestion_run(
  run.workspace_id,
  run.mailbox_connection_id,
  run.ingestion_run_id,
  run.registrar
)
FROM (
  VALUES
    ('93400000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000100'::pg_catalog.uuid, 'CAMS'::pg_catalog.text),
    ('93400000-0000-0000-0000-000000000002'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000002'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000200'::pg_catalog.uuid, 'CAMS'::pg_catalog.text),
    ('93400000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000300'::pg_catalog.uuid, 'CAMS'::pg_catalog.text),
    ('93400000-0000-0000-0000-000000000002'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000002'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000306'::pg_catalog.uuid, 'CAMS'::pg_catalog.text),
    ('93400000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000400'::pg_catalog.uuid, 'CAMS'::pg_catalog.text),
    ('93400000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000003'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000401'::pg_catalog.uuid, 'KFINTECH'::pg_catalog.text),
    ('93400000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000502'::pg_catalog.uuid, 'CAMS'::pg_catalog.text),
    ('93400000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000503'::pg_catalog.uuid, 'CAMS'::pg_catalog.text),
    ('93400000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000504'::pg_catalog.uuid, 'CAMS'::pg_catalog.text),
    ('93400000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93700000-0000-0000-0000-000000000001'::pg_catalog.uuid, '93900000-0000-0000-0000-000000000505'::pg_catalog.uuid, 'CAMS'::pg_catalog.text)
) AS run(workspace_id, mailbox_connection_id, ingestion_run_id, registrar);

SELECT *
FROM public.persist_cams_kfintech_statement_ingestion(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000100',
  '93900000-0000-0000-0000-000000000101',
  'provider-message-a',
  'provider-attachment-a',
  '93400000-0000-0000-0000-000000000001:93700000-0000-0000-0000-000000000001:provider-message-a:provider-attachment-a:' || repeat('a', 64),
  'CAMS',
  repeat('a', 64),
  'ingested-documents',
  '93400000-0000-0000-0000-000000000001/93700000-0000-0000-0000-000000000001/' || repeat('a', 64),
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Issue 32 Imported Investor',
      'folioNumber', 'FOLIO-32-A',
      'schemeCode', 'MF32A',
      'schemeName', 'Issue 32 Growth Fund',
      'fundHouse', 'Money Bowl AMC',
      'category', 'Equity',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 10,
      'nav', 20,
      'amount', 200,
      'date', '2026-07-29',
      'sourceRowNumber', 1,
      'registrarTransactionId', 'CAMS-ROW-1'
    )
  )
);

SELECT *
FROM public.persist_cams_kfintech_statement_ingestion(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000100',
  '93900000-0000-0000-0000-000000000101',
  'provider-message-a',
  'provider-attachment-a',
  '93400000-0000-0000-0000-000000000001:93700000-0000-0000-0000-000000000001:provider-message-a:provider-attachment-a:' || repeat('a', 64),
  'CAMS',
  repeat('a', 64),
  'ingested-documents',
  '93400000-0000-0000-0000-000000000001/93700000-0000-0000-0000-000000000001/' || repeat('a', 64),
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Issue 32 Imported Investor',
      'folioNumber', 'FOLIO-32-A',
      'schemeCode', 'MF32A',
      'schemeName', 'Issue 32 Growth Fund',
      'fundHouse', 'Money Bowl AMC',
      'category', 'Equity',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 10,
      'nav', 20,
      'amount', 200,
      'date', '2026-07-29',
      'sourceRowNumber', 1,
      'registrarTransactionId', 'CAMS-ROW-1'
    )
  )
);

SELECT *
FROM public.persist_cams_kfintech_statement_ingestion(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000100',
  '93900000-0000-0000-0000-000000000102',
  'provider-message-a',
  'provider-attachment-b',
  '93400000-0000-0000-0000-000000000001:93700000-0000-0000-0000-000000000001:provider-message-a:provider-attachment-b:' || repeat('b', 64),
  'CAMS',
  repeat('b', 64),
  'ingested-documents',
  '93400000-0000-0000-0000-000000000001/93700000-0000-0000-0000-000000000001/' || repeat('b', 64),
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Issue 32 Imported Investor',
      'folioNumber', 'FOLIO-32-B',
      'schemeCode', 'MF32B',
      'schemeName', 'Issue 32 Balanced Fund',
      'fundHouse', 'Money Bowl AMC',
      'category', 'Hybrid',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 5,
      'nav', 10,
      'amount', 50,
      'date', '2026-07-29',
      'sourceRowNumber', 1,
      'registrarTransactionId', 'CAMS-ROW-2'
    )
  )
);

SELECT public.record_cams_kfintech_ingestion_failure(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000100',
  '93900000-0000-0000-0000-000000000103',
  'provider-message-a',
  'provider-attachment-failed',
  '93400000-0000-0000-0000-000000000001:93700000-0000-0000-0000-000000000001:provider-message-a:provider-attachment-failed:' || repeat('c', 64),
  'CAMS',
  'malware_detected',
  repeat('c', 64),
  'ingested-documents',
  '93400000-0000-0000-0000-000000000001/93700000-0000-0000-0000-000000000001/' || repeat('c', 64),
  'application/x-dbase',
  'DBF',
  1024
);

SELECT public.record_cams_kfintech_ingestion_failure(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000100',
  '93900000-0000-0000-0000-000000000103',
  'provider-message-a',
  'provider-attachment-failed',
  '93400000-0000-0000-0000-000000000001:93700000-0000-0000-0000-000000000001:provider-message-a:provider-attachment-failed:' || repeat('c', 64),
  'CAMS',
  'malware_detected',
  repeat('c', 64),
  'ingested-documents',
  '93400000-0000-0000-0000-000000000001/93700000-0000-0000-0000-000000000001/' || repeat('c', 64),
  'application/x-dbase',
  'DBF',
  1024
);

DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000100',
    '93900000-0000-0000-0000-000000000103',
    'provider-message-a',
    'provider-attachment-failed',
    '93400000-0000-0000-0000-000000000001:93700000-0000-0000-0000-000000000001:provider-message-a:provider-attachment-failed:' || repeat('c', 64),
    'CAMS',
    repeat('c', 64),
    'ingested-documents',
    '93400000-0000-0000-0000-000000000001/93700000-0000-0000-0000-000000000001/' || repeat('c', 64),
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'registrar', 'CAMS',
        'clientPan', 'QWERT1234Y',
        'investorName', 'Issue 32 Imported Investor',
        'folioNumber', 'FOLIO-32-C',
        'schemeCode', 'MF32C',
        'schemeName', 'Issue 32 Failed Fund',
        'fundHouse', 'Money Bowl AMC',
        'category', 'Debt',
        'transactionType', 'BUY',
        'transactionDirection', 'INFLOW',
        'registrarTransactionCode', 'BUY',
        'units', 1,
        'nav', 1,
        'amount', 1,
        'date', '2026-07-29',
        'sourceRowNumber', 1
      )
    )
  );
  RAISE EXCEPTION 'failed attempt replay returned idempotent success';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
      RAISE;
    END IF;
END;
$$;

RESET ROLE;

DO $$
DECLARE
  v_docs_before pg_catalog.int4;
  v_events_before pg_catalog.int4;
  v_logs_before pg_catalog.int4;
  v_docs_after pg_catalog.int4;
  v_events_after pg_catalog.int4;
  v_logs_after pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_before
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000405';
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_events_before
  FROM public.event_outbox
  WHERE entity_type = 'ingested_document'
    AND event_type = 'statement.imported';
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_before
  FROM public.ingestion_logs
  WHERE correlation_id = '93900000-0000-0000-0000-000000000405';

  BEGIN
    PERFORM *
    FROM public.persist_cams_kfintech_statement_ingestion(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000400',
      '93900000-0000-0000-0000-000000000405',
      'provider-message-overlap',
      'provider-attachment-overlap',
      'overlap-attempt',
      'CAMS',
      repeat('8', 64),
      'ingested-documents',
      'negative/overlap',
      'application/x-dbase',
      'DBF',
      1024,
      '2026-07-29T00:00:00Z',
      pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'registrar', 'CAMS',
        'clientPan', 'QWERT1234Y',
        'investorName', 'Overlapping Statement',
        'folioNumber', 'FOLIO-32-A',
        'schemeCode', 'MF32A',
        'transactionType', 'BUY',
        'transactionDirection', 'INFLOW',
        'registrarTransactionCode', 'BUY',
        'units', 10,
        'nav', 20,
        'amount', 200,
        'date', '2026-07-29',
        'sourceRowNumber', 1,
        'registrarTransactionId', 'CAMS-ROW-1'
      ))
    );
    RAISE EXCEPTION 'duplicate registrar transaction across documents was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%persistence_conflict%' THEN
        RAISE;
      END IF;
  END;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_after
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000405';
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_events_after
  FROM public.event_outbox
  WHERE entity_type = 'ingested_document'
    AND event_type = 'statement.imported';
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_after
  FROM public.ingestion_logs
  WHERE correlation_id = '93900000-0000-0000-0000-000000000405';

  IF v_docs_after <> v_docs_before OR v_events_after <> v_events_before OR v_logs_after <> v_logs_before THEN
    RAISE EXCEPTION 'duplicate registrar transaction conflict left partial success side effects';
  END IF;
END;
$$;

SELECT *
FROM public.persist_cams_kfintech_statement_ingestion(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000400',
  '93900000-0000-0000-0000-000000000406',
  'provider-message-permitted-same-id',
  'provider-attachment-permitted-same-id',
  'permitted-same-id-attempt',
  'CAMS',
  repeat('9', 64),
  'ingested-documents',
  'permitted/same-id-different-folio',
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
    'registrar', 'CAMS',
    'clientPan', 'QWERT1234Y',
    'investorName', 'Permitted Same ID',
    'folioNumber', 'FOLIO-32-PERMITTED',
    'schemeCode', 'MF32PERM',
    'schemeName', 'Issue 32 Permitted Same ID Fund',
    'fundHouse', 'Money Bowl AMC',
    'category', 'Equity',
    'transactionType', 'BUY',
    'transactionDirection', 'INFLOW',
    'registrarTransactionCode', 'BUY',
    'units', 1,
    'nav', 1,
    'amount', 1,
    'date', '2026-07-29',
    'sourceRowNumber', 1,
    'registrarTransactionId', 'CAMS-ROW-1'
  ))
);

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.transactions AS transaction
  JOIN public.folio_references AS folio
    ON folio.id = transaction.source_folio_reference_id
  WHERE transaction.registrar = 'CAMS'
    AND transaction.registrar_transaction_id = 'CAMS-ROW-1'
    AND folio.normalized_folio_number IN ('FOLIO32A', 'FOLIO32PERMITTED');

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'same registrar transaction id in different folios was not permitted as expected: %', v_count;
  END IF;
END;
$$;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000510',
  'CAMS'
);

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000511',
  'CAMS'
);

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000512',
  'CAMS'
);

DO $$
DECLARE
  v_doc_a pg_catalog.uuid;
  v_doc_b pg_catalog.uuid;
  v_log_id pg_catalog.uuid;
  v_docs_before pg_catalog.int4;
  v_logs_before pg_catalog.int4;
  v_attempts_before pg_catalog.int4;
  v_docs_after pg_catalog.int4;
  v_logs_after pg_catalog.int4;
  v_attempts_after pg_catalog.int4;
  v_document_id pg_catalog.uuid;
  v_observed_sha pg_catalog.text;
  v_outcome pg_catalog.text;
BEGIN
  SELECT id INTO v_doc_a
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000101';

  SELECT id INTO v_doc_b
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000102';

  IF v_doc_a IS NULL OR v_doc_b IS NULL OR v_doc_a = v_doc_b THEN
    RAISE EXCEPTION 'canonical failure lineage fixtures missing';
  END IF;

  v_log_id := public.record_cams_kfintech_ingestion_failure(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000511',
    '93900000-0000-0000-0000-000000000101',
    'provider-message-a',
    'provider-attachment-a',
    'same-correlation-provider-attempt',
    'CAMS',
    'parse_failed',
    repeat('a', 64),
    'ingested-documents',
    'failure/same-correlation-provider',
    'application/x-dbase',
    'DBF',
    1024
  );

  SELECT log.document_id
  INTO v_document_id
  FROM public.ingestion_logs AS log
  WHERE log.id = v_log_id;

  IF v_document_id IS DISTINCT FROM v_doc_a THEN
    RAISE EXCEPTION 'same correlation/provider did not keep document A: %', v_document_id;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_before FROM public.ingestion_logs;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_attempts_before FROM public.cams_kfintech_ingestion_attempts;

  BEGIN
    PERFORM public.record_cams_kfintech_ingestion_failure(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000510',
      '93900000-0000-0000-0000-000000000101',
      'provider-message-a',
      'provider-attachment-b',
      'different-correlation-provider-attempt',
      'CAMS',
      'parse_failed',
      repeat('b', 64),
      'ingested-documents',
      'failure/different-correlation-provider',
      'application/x-dbase',
      'DBF',
      1024
    );
    RAISE EXCEPTION 'different correlation/provider documents were accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
        RAISE;
      END IF;
  END;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_after FROM public.ingestion_logs;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_attempts_after FROM public.cams_kfintech_ingestion_attempts;

  IF v_logs_after <> v_logs_before OR v_attempts_after <> v_attempts_before THEN
    RAISE EXCEPTION 'correlation/provider conflict left failure lineage side effects';
  END IF;

  v_log_id := public.record_cams_kfintech_ingestion_failure(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000510',
    '93900000-0000-0000-0000-000000000512',
    'provider-message-a',
    'provider-attachment-a',
    'provider-changed-digest-attempt',
    'CAMS',
    'attachment_hash_mismatch',
    repeat('b', 64),
    'ingested-documents',
    'failure/provider-changed-digest',
    'application/x-dbase',
    'DBF',
    1024
  );

  SELECT attempt.document_id, attempt.observed_sha256_hex
  INTO v_document_id, v_observed_sha
  FROM public.cams_kfintech_ingestion_attempts AS attempt
  WHERE attempt.ingestion_log_id = v_log_id;

  IF v_document_id IS DISTINCT FROM v_doc_a OR v_observed_sha <> repeat('b', 64) THEN
    RAISE EXCEPTION 'provider changed digest rebound lineage: %, %', v_document_id, v_observed_sha;
  END IF;

  v_log_id := public.record_cams_kfintech_ingestion_failure(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000510',
    '93900000-0000-0000-0000-000000000513',
    'duplicate-provider-message',
    'duplicate-provider-attachment',
    'duplicate-provider-attempt',
    'CAMS',
    'duplicate_attachment',
    repeat('a', 64),
    'ingested-documents',
    'failure/duplicate-provider',
    'application/x-dbase',
    'DBF',
    1024
  );

  SELECT attempt.document_id, attempt.outcome
  INTO v_document_id, v_outcome
  FROM public.cams_kfintech_ingestion_attempts AS attempt
  WHERE attempt.ingestion_log_id = v_log_id;

  IF v_document_id IS DISTINCT FROM v_doc_a OR v_outcome <> 'duplicate' THEN
    RAISE EXCEPTION 'duplicate digest did not reference canonical document A: %, %', v_document_id, v_outcome;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_before FROM public.ingested_documents;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_before FROM public.ingestion_logs;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_attempts_before FROM public.cams_kfintech_ingestion_attempts;

  BEGIN
    PERFORM public.record_cams_kfintech_ingestion_failure(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000510',
      '93900000-0000-0000-0000-000000000101',
      'new-conflicting-digest-message',
      'new-conflicting-digest-attachment',
      'correlation-digest-conflict-attempt',
      'CAMS',
      'duplicate_attachment',
      repeat('b', 64),
      'ingested-documents',
      'failure/correlation-digest-conflict',
      'application/x-dbase',
      'DBF',
      1024
    );
    RAISE EXCEPTION 'correlation A and digest B failure lineage was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    PERFORM public.record_cams_kfintech_ingestion_failure(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000512',
      '93900000-0000-0000-0000-000000000514',
      'provider-message-a',
      'provider-attachment-a',
      'provider-changed-digest-wrong-code',
      'CAMS',
      'parse_failed',
      repeat('c', 64),
      'ingested-documents',
      'failure/provider-changed-wrong-code',
      'application/x-dbase',
      'DBF',
      1024
    );
    RAISE EXCEPTION 'provider changed digest accepted a non-hash-mismatch code';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%attachment_hash_mismatch%' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    PERFORM public.record_cams_kfintech_ingestion_failure(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000512',
      '93900000-0000-0000-0000-000000000515',
      'duplicate-wrong-code-message',
      'duplicate-wrong-code-attachment',
      'duplicate-wrong-code-attempt',
      'CAMS',
      'parse_failed',
      repeat('a', 64),
      'ingested-documents',
      'failure/duplicate-wrong-code',
      'application/x-dbase',
      'DBF',
      1024
    );
    RAISE EXCEPTION 'duplicate digest accepted a non-duplicate code';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%duplicate_attachment%' THEN
        RAISE;
      END IF;
  END;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_after FROM public.ingested_documents;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_after FROM public.ingestion_logs;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_attempts_after FROM public.cams_kfintech_ingestion_attempts;

  IF v_docs_after <> v_docs_before
     OR v_logs_after <> v_logs_before
     OR v_attempts_after <> v_attempts_before THEN
    RAISE EXCEPTION 'contradictory canonical failure lineage was not fully rolled back';
  END IF;
END;
$$;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000520',
  'CAMS'
);

DO $$
DECLARE
  v_log_id pg_catalog.uuid;
  v_replay_id pg_catalog.uuid;
  v_logs_before pg_catalog.int4;
  v_attempts_before pg_catalog.int4;
  v_logs_after pg_catalog.int4;
  v_attempts_after pg_catalog.int4;
  v_variant pg_catalog.text;
  v_sha pg_catalog.text;
  v_bucket pg_catalog.text;
  v_path pg_catalog.text;
  v_mime pg_catalog.text;
  v_file_type pg_catalog.text;
  v_size pg_catalog.int4;
  v_message pg_catalog.text;
  v_attachment pg_catalog.text;
  v_correlation pg_catalog.uuid;
  v_attempt_key pg_catalog.text;
BEGIN
  v_log_id := public.record_cams_kfintech_ingestion_failure(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000520',
    '93900000-0000-0000-0000-000000000520',
    'failure-replay-message',
    'failure-replay-attachment',
    'failure-replay-attempt',
    'CAMS',
    'parse_failed',
    repeat('4', 64),
    'ingested-documents',
    'failure/replay',
    'application/x-dbase',
    'DBF',
    1024
  );

  v_replay_id := public.record_cams_kfintech_ingestion_failure(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000520',
    '93900000-0000-0000-0000-000000000520',
    'failure-replay-message',
    'failure-replay-attachment',
    'failure-replay-attempt',
    'CAMS',
    'parse_failed',
    repeat('4', 64),
    'ingested-documents',
    'failure/replay',
    'application/x-dbase',
    'DBF',
    1024
  );

  IF v_replay_id IS DISTINCT FROM v_log_id THEN
    RAISE EXCEPTION 'identical failure replay returned a different log id';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_before
  FROM public.ingestion_logs
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000520';

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_attempts_before
  FROM public.cams_kfintech_ingestion_attempts
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000520';

  FOR v_variant IN
    SELECT * FROM pg_catalog.unnest(ARRAY[
      'digest',
      'storage_path',
      'bucket',
      'mime',
      'file_type',
      'size',
      'provider_message',
      'provider_attachment',
      'document_correlation',
      'attachment_attempt_key'
    ]::pg_catalog.text[])
  LOOP
    v_sha := repeat('4', 64);
    v_bucket := 'ingested-documents';
    v_path := 'failure/replay';
    v_mime := 'application/x-dbase';
    v_file_type := 'DBF';
    v_size := 1024;
    v_message := 'failure-replay-message';
    v_attachment := 'failure-replay-attachment';
    v_correlation := '93900000-0000-0000-0000-000000000520';
    v_attempt_key := 'failure-replay-attempt';

    IF v_variant = 'digest' THEN
      v_sha := repeat('5', 64);
    ELSIF v_variant = 'storage_path' THEN
      v_path := 'failure/replay-changed';
    ELSIF v_variant = 'bucket' THEN
      v_bucket := 'other-ingested-documents';
    ELSIF v_variant = 'mime' THEN
      v_mime := 'application/pdf';
    ELSIF v_variant = 'file_type' THEN
      v_file_type := 'CAS_PDF';
    ELSIF v_variant = 'size' THEN
      v_size := 2048;
    ELSIF v_variant = 'provider_message' THEN
      v_message := 'failure-replay-message-changed';
    ELSIF v_variant = 'provider_attachment' THEN
      v_attachment := 'failure-replay-attachment-changed';
    ELSIF v_variant = 'document_correlation' THEN
      v_correlation := '93900000-0000-0000-0000-000000000521';
    ELSIF v_variant = 'attachment_attempt_key' THEN
      v_attempt_key := 'failure-replay-attempt-changed';
    END IF;

    BEGIN
      PERFORM public.record_cams_kfintech_ingestion_failure(
        '93400000-0000-0000-0000-000000000001',
        '93700000-0000-0000-0000-000000000001',
        '93900000-0000-0000-0000-000000000520',
        v_correlation,
        v_message,
        v_attachment,
        v_attempt_key,
        'CAMS',
        'parse_failed',
        v_sha,
        v_bucket,
        v_path,
        v_mime,
        v_file_type,
        v_size
      );
      RAISE EXCEPTION 'contradictory failure replay accepted variant %', v_variant;
    EXCEPTION
      WHEN others THEN
        IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
          RAISE;
        END IF;
    END;

    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_after
    FROM public.ingestion_logs
    WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000520';

    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_attempts_after
    FROM public.cams_kfintech_ingestion_attempts
    WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000520';

    IF v_logs_after <> v_logs_before OR v_attempts_after <> v_attempts_before THEN
      RAISE EXCEPTION 'contradictory failure replay variant % left extra lineage rows', v_variant;
    END IF;
  END LOOP;

  IF v_logs_before <> 1 OR v_attempts_before <> 1 THEN
    RAISE EXCEPTION 'failure replay did not preserve exactly one log and attempt: %, %', v_logs_before, v_attempts_before;
  END IF;
END;
$$;

DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000002',
    '93700000-0000-0000-0000-000000000002',
    '93900000-0000-0000-0000-000000000200',
    '93900000-0000-0000-0000-000000000101',
    'provider-message-other',
    'provider-attachment-other',
    '93400000-0000-0000-0000-000000000002:93700000-0000-0000-0000-000000000002:provider-message-other:provider-attachment-other:' || repeat('d', 64),
    'CAMS',
    repeat('d', 64),
    'ingested-documents',
    '93400000-0000-0000-0000-000000000002/93700000-0000-0000-0000-000000000002/' || repeat('d', 64),
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'registrar', 'CAMS',
        'clientPan', 'QWERT1234Y',
        'investorName', 'Issue 32 Imported Investor',
        'folioNumber', 'FOLIO-32-D',
        'schemeCode', 'MF32D',
        'schemeName', 'Issue 32 Conflict Fund',
        'fundHouse', 'Money Bowl AMC',
        'category', 'Debt',
        'transactionType', 'BUY',
        'transactionDirection', 'INFLOW',
        'registrarTransactionCode', 'BUY',
        'units', 1,
        'nav', 1,
        'amount', 1,
        'date', '2026-07-29',
        'sourceRowNumber', 1
      )
    )
  );
  RAISE EXCEPTION 'correlation reuse across workspace was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
      RAISE;
    END IF;
END;
$$;

RESET ROLE;

INSERT INTO public.ingested_documents (
  workspace_id,
  mailbox_connection_id,
  ingestion_run_id,
  provider_message_id,
  provider_attachment_id,
  attachment_attempt_key,
  registrar,
  storage_bucket,
  storage_object_path,
  sha256_hex,
  detected_mime,
  file_type,
  size_bytes,
  received_at,
  processing_status,
  correlation_id
) VALUES (
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000100',
  'provider-message-a',
  'provider-attachment-processing',
  '93400000-0000-0000-0000-000000000001:93700000-0000-0000-0000-000000000001:provider-message-a:provider-attachment-processing:' || repeat('e', 64),
  'CAMS',
  'ingested-documents',
  '93400000-0000-0000-0000-000000000001/93700000-0000-0000-0000-000000000001/' || repeat('e', 64),
  repeat('e', 64),
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  'processing',
  '93900000-0000-0000-0000-000000000104'
);

SET ROLE service_role;
DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000400',
    '93900000-0000-0000-0000-000000000403',
    'provider-message-invalid-direction',
    'provider-attachment-invalid-direction',
    'invalid-direction-attempt',
    'CAMS',
    repeat('7', 64),
    'ingested-documents',
    'negative/invalid-direction',
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Invalid Direction',
      'folioNumber', 'FOLIO-BAD-DIRECTION',
      'schemeCode', 'MF32NEG',
      'transactionType', 'BUY',
      'transactionDirection', 'OUTFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 1,
      'nav', 1,
      'amount', 1,
      'date', '2026-07-29',
      'sourceRowNumber', 1
    ))
  );
  RAISE EXCEPTION 'invalid registrar code and direction combination was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%parse_failed%' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000100',
    '93900000-0000-0000-0000-000000000104',
    'provider-message-a',
    'provider-attachment-processing',
    '93400000-0000-0000-0000-000000000001:93700000-0000-0000-0000-000000000001:provider-message-a:provider-attachment-processing:' || repeat('e', 64),
    'CAMS',
    repeat('e', 64),
    'ingested-documents',
    '93400000-0000-0000-0000-000000000001/93700000-0000-0000-0000-000000000001/' || repeat('e', 64),
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'registrar', 'CAMS',
        'clientPan', 'QWERT1234Y',
        'investorName', 'Issue 32 Imported Investor',
        'folioNumber', 'FOLIO-32-E',
        'schemeCode', 'MF32E',
        'schemeName', 'Issue 32 Processing Fund',
        'fundHouse', 'Money Bowl AMC',
        'category', 'Debt',
        'transactionType', 'BUY',
        'transactionDirection', 'INFLOW',
        'registrarTransactionCode', 'BUY',
        'units', 1,
        'nav', 1,
        'amount', 1,
        'date', '2026-07-29',
        'sourceRowNumber', 1
      )
    )
  );
  RAISE EXCEPTION 'processing document replay returned idempotent success';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%processing_incomplete%' THEN
      RAISE;
    END IF;
END;
$$;
RESET ROLE;

DO $$
DECLARE
  v_count pg_catalog.int4;
  v_log_id pg_catalog.uuid;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.ingested_documents
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000100'
    AND processing_status = 'completed';

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'two valid attachments in one run did not both complete: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.transactions AS transaction
  JOIN public.ingested_documents AS document
    ON document.id = transaction.source_document_id
  WHERE document.ingestion_run_id = '93900000-0000-0000-0000-000000000100'
    AND document.processing_status = 'completed';

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'valid attachments did not create exactly two transactions: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.event_outbox AS event
  JOIN public.ingested_documents AS document
    ON document.id = event.entity_id
  WHERE document.ingestion_run_id = '93900000-0000-0000-0000-000000000100'
    AND event.entity_type = 'ingested_document'
    AND event.event_type = 'statement.imported';

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'statement.imported event count is wrong: %', v_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.mutual_funds
    WHERE scheme_code = 'MF32A'
      AND (current_nav <> 999.0000 OR nav_date <> '2026-01-01'::pg_catalog.date)
  ) THEN
    RAISE EXCEPTION 'historical statement NAV overwrote current mutual_funds NAV/date';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.transactions AS transaction
  JOIN public.folio_references AS folio
    ON folio.id = transaction.source_folio_reference_id
  WHERE transaction.source_document_id IS NOT NULL
    AND folio.registrar = 'CAMS'
    AND folio.normalized_folio_number IN ('FOLIO32A', 'FOLIO32B');

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'folio lineage is not visible from imported transactions: %', v_count;
  END IF;

  SELECT pg_catalog.count(DISTINCT mapping.portfolio_id)::pg_catalog.int4 INTO v_count
  FROM public.portfolio_folio_references AS mapping
  JOIN public.folio_references AS folio
    ON folio.id = mapping.folio_reference_id
  JOIN public.portfolios AS portfolio
    ON portfolio.id = mapping.portfolio_id
  WHERE portfolio.workspace_id = '93400000-0000-0000-0000-000000000001'
    AND portfolio.client_id = '93300000-0000-0000-0000-000000000002'
    AND folio.normalized_folio_number IN ('FOLIO32A', 'FOLIO32B');

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'two folios did not reuse one canonical investor workspace portfolio: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.portfolio_folio_references AS mapping
  JOIN public.folio_references AS folio
    ON folio.id = mapping.folio_reference_id
  WHERE folio.normalized_folio_number IN ('FOLIO32A', 'FOLIO32B');

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'two folios did not produce two folio mappings: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.portfolios
  WHERE workspace_id = '93400000-0000-0000-0000-000000000001'
    AND client_id = '93300000-0000-0000-0000-000000000002';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'canonical investor workspace portfolio count is wrong: %', v_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.portfolio_folio_references AS mapping
    JOIN public.folio_references AS folio
      ON folio.id = mapping.folio_reference_id
    WHERE folio.normalized_folio_number IN ('FOLIO32A', 'FOLIO32B')
      AND mapping.portfolio_id IN (
        '93230000-0000-0000-0000-000000000001',
        '93230000-0000-0000-0000-000000000002'
      )
  ) THEN
    RAISE EXCEPTION 'folio mapping reused another investor or workspace portfolio';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.mutual_funds
    WHERE scheme_code = 'MF32B'
      AND (current_nav IS NOT NULL OR nav_date IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'unknown scheme received fabricated market NAV/date';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.transactions AS transaction
  JOIN public.folio_references AS folio
    ON folio.id = transaction.source_folio_reference_id
  WHERE transaction.registrar = 'CAMS'
    AND transaction.registrar_transaction_id IN ('CAMS-ROW-1', 'CAMS-ROW-2')
    AND transaction.registrar_transaction_code = 'BUY'
    AND transaction.transaction_direction = 'INFLOW'
    AND transaction.nav_at_transaction > 0
    AND folio.normalized_folio_number IN ('FOLIO32A', 'FOLIO32B');

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'registrar source code or direction did not persist for BUY rows: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.ingestion_logs
  WHERE attachment_attempt_key LIKE '%provider-attachment-failed%'
    AND failure_code = 'malware_detected';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'repeated identical failure created duplicate logs: %', v_count;
  END IF;

  SELECT id INTO v_log_id
  FROM public.ingestion_logs
  WHERE correlation_id = '93900000-0000-0000-0000-000000000101'
  LIMIT 1;

  BEGIN
    UPDATE public.ingestion_logs SET records_processed = 99 WHERE id = v_log_id;
    RAISE EXCEPTION 'ingestion_logs update was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%ingestion_logs_immutable%' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    DELETE FROM public.ingestion_logs WHERE id = v_log_id;
    RAISE EXCEPTION 'ingestion_logs delete was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%ingestion_logs_immutable%' THEN
        RAISE;
      END IF;
  END;
END;
$$;

SET ROLE service_role;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000505',
  'CAMS'
);

DO $$
BEGIN
  PERFORM public.finalize_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000505',
    'CAMS'
  );
  RAISE EXCEPTION 'claimed zero-attempt completion was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%processing_incomplete%' THEN
      RAISE;
    END IF;
END;
$$;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000506',
  'CAMS'
);

SELECT *
FROM public.finalize_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000506',
  'CAMS',
  'attachment_limit_exceeded',
  NULL,
  0
);

RESET ROLE;

DO $$
DECLARE
  v_status pg_catalog.text;
  v_attempted pg_catalog.int4;
BEGIN
  SELECT status, attempted_attachment_count
  INTO v_status, v_attempted
  FROM public.cams_kfintech_ingestion_runs
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000506';

  IF v_status <> 'stopped' OR v_attempted <> 0 THEN
    RAISE EXCEPTION 'zero-attempt stop did not finalize as stopped: %, %', v_status, v_attempted;
  END IF;
END;
$$;

SET ROLE service_role;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000530',
  'CAMS'
);

SELECT *
FROM public.finalize_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000530',
  'CAMS',
  'attachment_too_large',
  NULL,
  0
);

DO $$
BEGIN
  PERFORM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000531',
    'CAMS'
  );
  PERFORM public.finalize_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000531',
    'CAMS',
    'unsupported_stop_reason',
    NULL,
    0
  );
  RAISE EXCEPTION 'unknown stopped reason was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%unsupported_stopped_reason%' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  PERFORM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000532',
    'CAMS'
  );
  PERFORM public.finalize_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000532',
    'CAMS',
    NULL,
    'sender_not_allowed',
    0
  );
  RAISE EXCEPTION 'unknown run failure code was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%unsupported_run_failure_code%' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  PERFORM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000533',
    'CAMS'
  );
  PERFORM public.finalize_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000533',
    'CAMS',
    'attachment_too_large',
    'mailbox_poll_failed',
    0
  );
  RAISE EXCEPTION 'stop and run failure supplied together were accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
      RAISE;
    END IF;
END;
$$;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000534',
  'CAMS'
);

RESET ROLE;

DO $$
DECLARE
  v_document_id pg_catalog.uuid;
  v_log_id pg_catalog.uuid;
BEGIN
  SELECT id, ingestion_log_id
  INTO v_document_id, v_log_id
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000101';

  PERFORM public.record_cams_kfintech_ingestion_attempt(
    '93900000-0000-0000-0000-000000000534',
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    'completed-reason-message',
    'completed-reason-attachment',
    'completed-reason-attempt',
    '93900000-0000-0000-0000-000000000534',
    v_document_id,
    v_log_id,
    repeat('a', 64),
    'ingested-documents',
    'finalizer/completed-reason',
    'application/x-dbase',
    'DBF',
    1024,
    'succeeded',
    NULL
  );
END;
$$;

SET ROLE service_role;

DO $$
BEGIN
  PERFORM public.finalize_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000534',
    'CAMS',
    'attachment_limit_exceeded',
    NULL,
    1
  );
  RAISE EXCEPTION 'completed run with stopped reason was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  PERFORM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000535',
    'CAMS'
  );
  PERFORM public.finalize_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000535',
    'CAMS',
    NULL,
    NULL,
    0
  );
  RAISE EXCEPTION 'failed run without legitimate basis was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%processing_incomplete%' THEN
      RAISE;
    END IF;
END;
$$;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000536',
  'CAMS'
);

SELECT *
FROM public.finalize_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000536',
  'CAMS',
  NULL,
  'mailbox_poll_failed',
  0
);

SELECT *
FROM public.finalize_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000536',
  'CAMS',
  NULL,
  'mailbox_poll_failed',
  0
);

DO $$
BEGIN
  PERFORM public.finalize_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000536',
    'CAMS',
    'attachment_limit_exceeded',
    NULL,
    0
  );
  RAISE EXCEPTION 'contradictory terminal finalizer replay was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%ingestion_run_finalized%' THEN
      RAISE;
    END IF;
END;
$$;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000508',
  'CAMS'
);

SELECT *
FROM public.finalize_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000508',
  'CAMS',
  NULL,
  'attempt_lineage_incomplete',
  1
);

RESET ROLE;

DO $$
DECLARE
  v_status pg_catalog.text;
  v_observed pg_catalog.int4;
  v_durable pg_catalog.int4;
  v_gap pg_catalog.int4;
  v_failure_code pg_catalog.text;
BEGIN
  SELECT status, observed_attachment_count, durable_attempt_count, lineage_gap_count, run_failure_code
  INTO v_status, v_observed, v_durable, v_gap, v_failure_code
  FROM public.cams_kfintech_ingestion_runs
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000508';

  IF v_status <> 'failed'
     OR v_observed <> 1
     OR v_durable <> 0
     OR v_gap <> 1
     OR v_failure_code <> 'attempt_lineage_incomplete' THEN
    RAISE EXCEPTION 'lineage gap without durable success did not fail run: %, %, %, %, %', v_status, v_observed, v_durable, v_gap, v_failure_code;
  END IF;
END;
$$;

SET ROLE service_role;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000509',
  'CAMS'
);

RESET ROLE;

DO $$
DECLARE
  v_document_id pg_catalog.uuid;
  v_log_id pg_catalog.uuid;
BEGIN
  SELECT id, ingestion_log_id
  INTO v_document_id, v_log_id
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000101';

  PERFORM public.record_cams_kfintech_ingestion_attempt(
    '93900000-0000-0000-0000-000000000509',
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    'lineage-gap-success-message',
    'lineage-gap-success-attachment',
    'lineage-gap-success-attempt',
    '93900000-0000-0000-0000-000000000509',
    v_document_id,
    v_log_id,
    repeat('a', 64),
    'ingested-documents',
    'lineage-gap/success',
    'application/x-dbase',
    'DBF',
    1024,
    'succeeded',
    NULL
  );
END;
$$;

SET ROLE service_role;

SELECT *
FROM public.finalize_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000509',
  'CAMS',
  NULL,
  'attempt_lineage_incomplete',
  2
);

RESET ROLE;

DO $$
DECLARE
  v_status pg_catalog.text;
  v_observed pg_catalog.int4;
  v_durable pg_catalog.int4;
  v_gap pg_catalog.int4;
  v_failure_code pg_catalog.text;
BEGIN
  SELECT status, observed_attachment_count, durable_attempt_count, lineage_gap_count, run_failure_code
  INTO v_status, v_observed, v_durable, v_gap, v_failure_code
  FROM public.cams_kfintech_ingestion_runs
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000509';

  IF v_status <> 'partially_failed'
     OR v_observed <> 2
     OR v_durable <> 1
     OR v_gap <> 1
     OR v_failure_code <> 'attempt_lineage_incomplete' THEN
    RAISE EXCEPTION 'lineage gap with durable success did not partially fail run: %, %, %, %, %', v_status, v_observed, v_durable, v_gap, v_failure_code;
  END IF;
END;
$$;

SET ROLE service_role;
SELECT *
FROM public.persist_cams_kfintech_statement_ingestion(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000400',
  '93900000-0000-0000-0000-000000000401',
  'provider-message-switch-cams',
  'provider-attachment-switch-cams',
  'switch-cams-attempt',
  'CAMS',
  repeat('5', 64),
  'ingested-documents',
  'switch/cams',
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Switch Investor',
      'folioNumber', 'FOLIO-SWITCH-CAMS',
      'schemeCode', 'MF32SWC',
      'schemeName', 'Issue 32 CAMS Switch Fund',
      'fundHouse', 'Money Bowl AMC',
      'category', 'Hybrid',
      'transactionType', 'SWITCH',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'SWITCH_IN',
      'units', 7,
      'nav', 10,
      'amount', 70,
      'date', '2026-07-29',
      'sourceRowNumber', 1,
      'registrarTransactionId', 'CAMS-SW-IN'
    ),
    pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Switch Investor',
      'folioNumber', 'FOLIO-SWITCH-CAMS',
      'schemeCode', 'MF32SWC',
      'schemeName', 'Issue 32 CAMS Switch Fund',
      'fundHouse', 'Money Bowl AMC',
      'category', 'Hybrid',
      'transactionType', 'SWITCH',
      'transactionDirection', 'OUTFLOW',
      'registrarTransactionCode', 'SWITCH_OUT',
      'units', 7,
      'nav', 10,
      'amount', 70,
      'date', '2026-07-29',
      'sourceRowNumber', 2,
      'registrarTransactionId', 'CAMS-SW-OUT'
    )
  )
);

SELECT *
FROM public.persist_cams_kfintech_statement_ingestion(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000003',
  '93900000-0000-0000-0000-000000000401',
  '93900000-0000-0000-0000-000000000402',
  'provider-message-switch-kfin',
  'provider-attachment-switch-kfin',
  'switch-kfin-attempt',
  'KFINTECH',
  repeat('6', 64),
  'ingested-documents',
  'switch/kfintech',
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      'registrar', 'KFINTECH',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Switch Investor',
      'folioNumber', 'KFOLIO-SWITCH',
      'schemeCode', 'MF32SWK',
      'schemeName', 'Issue 32 KFin Switch Fund',
      'fundHouse', 'Money Bowl AMC',
      'category', 'Hybrid',
      'transactionType', 'SWITCH',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'SI',
      'units', 3,
      'nav', 12,
      'amount', 36,
      'date', '2026-07-29',
      'sourceRowNumber', 1,
      'registrarTransactionId', 'KFIN-SW-IN'
    ),
    pg_catalog.jsonb_build_object(
      'registrar', 'KFINTECH',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Switch Investor',
      'folioNumber', 'KFOLIO-SWITCH',
      'schemeCode', 'MF32SWK',
      'schemeName', 'Issue 32 KFin Switch Fund',
      'fundHouse', 'Money Bowl AMC',
      'category', 'Hybrid',
      'transactionType', 'SWITCH',
      'transactionDirection', 'OUTFLOW',
      'registrarTransactionCode', 'SO',
      'units', 3,
      'nav', 12,
      'amount', 36,
      'date', '2026-07-29',
      'sourceRowNumber', 2,
      'registrarTransactionId', 'KFIN-SW-OUT'
    )
  )
);

RESET ROLE;

DO $$
DECLARE
  v_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.transactions
  WHERE registrar = 'CAMS'
    AND transaction_type = 'SWITCH'
    AND registrar_transaction_id IN ('CAMS-SW-IN', 'CAMS-SW-OUT')
    AND (
      (registrar_transaction_id = 'CAMS-SW-IN' AND registrar_transaction_code = 'SWITCH_IN' AND transaction_direction = 'INFLOW')
      OR (registrar_transaction_id = 'CAMS-SW-OUT' AND registrar_transaction_code = 'SWITCH_OUT' AND transaction_direction = 'OUTFLOW')
    );

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'CAMS switch-in and switch-out did not persist distinctly: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.transactions
  WHERE registrar = 'KFINTECH'
    AND transaction_type = 'SWITCH'
    AND registrar_transaction_id IN ('KFIN-SW-IN', 'KFIN-SW-OUT')
    AND (
      (registrar_transaction_id = 'KFIN-SW-IN' AND registrar_transaction_code = 'SI' AND transaction_direction = 'INFLOW')
      OR (registrar_transaction_id = 'KFIN-SW-OUT' AND registrar_transaction_code = 'SO' AND transaction_direction = 'OUTFLOW')
    );

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'KFintech switch-in and switch-out did not persist distinctly: %', v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.event_outbox AS event
    JOIN public.ingested_documents AS document
      ON document.id = event.entity_id
    WHERE document.correlation_id = '93900000-0000-0000-0000-000000000401'
      AND event.payload -> 'transaction_lineage' @> '[{"registrar_transaction_code":"SWITCH_IN","transaction_direction":"INFLOW"},{"registrar_transaction_code":"SWITCH_OUT","transaction_direction":"OUTFLOW"}]'::jsonb
  ) THEN
    RAISE EXCEPTION 'statement.imported payload made CAMS switch legs indistinguishable';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.event_outbox AS event
    JOIN public.ingested_documents AS document
      ON document.id = event.entity_id
    WHERE document.correlation_id = '93900000-0000-0000-0000-000000000402'
      AND event.payload -> 'transaction_lineage' @> '[{"registrar_transaction_code":"SI","transaction_direction":"INFLOW"},{"registrar_transaction_code":"SO","transaction_direction":"OUTFLOW"}]'::jsonb
  ) THEN
    RAISE EXCEPTION 'statement.imported payload made KFintech switch legs indistinguishable';
  END IF;
END;
$$;

SET ROLE service_role;
DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000300',
    '93900000-0000-0000-0000-000000000301',
    'provider-message-negative',
    'provider-attachment-no-pan',
    'no-pan-attempt',
    'CAMS',
    repeat('1', 64),
    'ingested-documents',
    'negative/no-pan',
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'ZZZZZ9999Z',
      'investorName', 'No Mapping',
      'folioNumber', 'FOLIO-NO-PAN',
      'schemeCode', 'MF32NEG',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 1,
      'nav', 1,
      'amount', 1,
      'date', '2026-07-29',
      'sourceRowNumber', 1
    ))
  );
  RAISE EXCEPTION 'missing PAN mapping was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%investor_mapping_unresolved%' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000002',
    '93700000-0000-0000-0000-000000000002',
    '93900000-0000-0000-0000-000000000306',
    '93900000-0000-0000-0000-000000000302',
    'provider-message-negative',
    'provider-attachment-wrong-workspace',
    'wrong-workspace-attempt',
    'CAMS',
    repeat('2', 64),
    'ingested-documents',
    'negative/wrong-workspace',
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Wrong Workspace',
      'folioNumber', 'FOLIO-WRONG-WS',
      'schemeCode', 'MF32NEG',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 1,
      'nav', 1,
      'amount', 1,
      'date', '2026-07-29',
      'sourceRowNumber', 1
    ))
  );
  RAISE EXCEPTION 'investor outside target workspace was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%investor_workspace_relationship_required%' THEN
      RAISE;
    END IF;
END;
$$;

RESET ROLE;

INSERT INTO public.profile_pan_records (
  id,
  profile_id,
  pan_ciphertext,
  pan_lookup_hmac,
  masked_pan,
  source,
  source_system,
  status,
  verified_at
) VALUES (
  '93210000-0000-0000-0000-000000000002',
  '93300000-0000-0000-0000-000000000003',
  extensions.pgp_sym_encrypt('QWERT1234Y', public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
  extensions.hmac('QWERT1234Y', public.pan_lookup_hmac_key(), 'sha256'),
  public.mask_pan('QWERT1234Y'),
  'INVESTOR',
  'MANUAL',
  'VERIFIED',
  now()
);

UPDATE public.profiles
SET canonical_pan_record_id = '93210000-0000-0000-0000-000000000002'
WHERE id = '93300000-0000-0000-0000-000000000003';

SET ROLE service_role;

DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000300',
    '93900000-0000-0000-0000-000000000303',
    'provider-message-negative',
    'provider-attachment-ambiguous-pan',
    'ambiguous-pan-attempt',
    'CAMS',
    repeat('3', 64),
    'ingested-documents',
    'negative/ambiguous-pan',
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Ambiguous PAN',
      'folioNumber', 'FOLIO-AMBIG',
      'schemeCode', 'MF32NEG',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 1,
      'nav', 1,
      'amount', 1,
      'date', '2026-07-29',
      'sourceRowNumber', 1
    ))
  );
  RAISE EXCEPTION 'ambiguous PAN mapping was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%investor_mapping_ambiguous%' THEN
      RAISE;
    END IF;
END;
$$;

RESET ROLE;

UPDATE public.profiles
SET canonical_pan_record_id = NULL
WHERE id = '93300000-0000-0000-0000-000000000003';

UPDATE public.profile_pan_records
SET status = 'SUPERSEDED'
WHERE id = '93210000-0000-0000-0000-000000000002';

RESET ROLE;

DO $$
DECLARE
  v_docs_before pg_catalog.int4;
  v_events_before pg_catalog.int4;
  v_docs_after pg_catalog.int4;
  v_events_after pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_before
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000304';
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_events_before
  FROM public.event_outbox
  WHERE entity_type = 'ingested_document'
    AND event_type = 'statement.imported';

  BEGIN
    PERFORM *
    FROM public.persist_cams_kfintech_statement_ingestion(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000300',
      '93900000-0000-0000-0000-000000000304',
      'provider-message-negative',
      'provider-attachment-duplicate-row',
      'duplicate-row-attempt',
      'CAMS',
      repeat('4', 64),
      'ingested-documents',
      'negative/duplicate-row',
      'application/x-dbase',
      'DBF',
      1024,
      '2026-07-29T00:00:00Z',
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'registrar', 'CAMS',
          'clientPan', 'QWERT1234Y',
          'investorName', 'Duplicate Row',
          'folioNumber', 'FOLIO-DUP',
          'schemeCode', 'MF32NEG',
          'fundHouse', 'Money Bowl AMC',
          'transactionType', 'BUY',
          'transactionDirection', 'INFLOW',
          'registrarTransactionCode', 'BUY',
          'units', 1,
          'nav', 1,
          'amount', 1,
          'date', '2026-07-29',
          'sourceRowNumber', 1,
          'registrarTransactionId', 'DUP-TXN-1'
        ),
        pg_catalog.jsonb_build_object(
          'registrar', 'CAMS',
          'clientPan', 'QWERT1234Y',
          'investorName', 'Duplicate Row',
          'folioNumber', 'FOLIO-DUP',
          'schemeCode', 'MF32NEG',
          'fundHouse', 'Money Bowl AMC',
          'transactionType', 'BUY',
          'transactionDirection', 'INFLOW',
          'registrarTransactionCode', 'BUY',
          'units', 1,
          'nav', 1,
          'amount', 1,
          'date', '2026-07-29',
          'sourceRowNumber', 1,
          'registrarTransactionId', 'DUP-TXN-2'
        )
      )
    );
    RAISE EXCEPTION 'duplicate source row was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%persistence_conflict%' THEN
        RAISE;
      END IF;
  END;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_after
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000304';
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_events_after
  FROM public.event_outbox
  WHERE entity_type = 'ingested_document'
    AND event_type = 'statement.imported';

  IF v_docs_after <> v_docs_before OR v_events_after <> v_events_before THEN
    RAISE EXCEPTION 'duplicate row conflict created document or event side effects';
  END IF;
END;
$$;

DO $$
DECLARE
  v_docs_before pg_catalog.int4;
  v_events_before pg_catalog.int4;
  v_docs_after pg_catalog.int4;
  v_events_after pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_before
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000305';
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_events_before
  FROM public.event_outbox
  WHERE entity_type = 'ingested_document'
    AND event_type = 'statement.imported';

  BEGIN
    PERFORM *
    FROM public.persist_cams_kfintech_statement_ingestion(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000300',
      '93900000-0000-0000-0000-000000000305',
      'provider-message-negative',
      'provider-attachment-duplicate-txn',
      'duplicate-txn-attempt',
      'CAMS',
      repeat('0', 64),
      'ingested-documents',
      'negative/duplicate-txn',
      'application/x-dbase',
      'DBF',
      1024,
      '2026-07-29T00:00:00Z',
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'registrar', 'CAMS',
          'clientPan', 'QWERT1234Y',
          'investorName', 'Duplicate Registrar Transaction',
          'folioNumber', 'FOLIO-DUP-TXN',
          'schemeCode', 'MF32NEG',
          'fundHouse', 'Money Bowl AMC',
          'transactionType', 'BUY',
          'transactionDirection', 'INFLOW',
          'registrarTransactionCode', 'BUY',
          'units', 1,
          'nav', 1,
          'amount', 1,
          'date', '2026-07-29',
          'sourceRowNumber', 1,
          'registrarTransactionId', 'DUP-TXN-SAME'
        ),
        pg_catalog.jsonb_build_object(
          'registrar', 'CAMS',
          'clientPan', 'QWERT1234Y',
          'investorName', 'Duplicate Registrar Transaction',
          'folioNumber', 'FOLIO-DUP-TXN',
          'schemeCode', 'MF32NEG',
          'fundHouse', 'Money Bowl AMC',
          'transactionType', 'BUY',
          'transactionDirection', 'INFLOW',
          'registrarTransactionCode', 'BUY',
          'units', 1,
          'nav', 1,
          'amount', 1,
          'date', '2026-07-29',
          'sourceRowNumber', 2,
          'registrarTransactionId', 'DUP-TXN-SAME'
        )
      )
    );
    RAISE EXCEPTION 'duplicate registrar transaction id in one attachment was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%persistence_conflict%' THEN
        RAISE;
      END IF;
  END;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_after
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000305';
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_events_after
  FROM public.event_outbox
  WHERE entity_type = 'ingested_document'
    AND event_type = 'statement.imported';

  IF v_docs_after <> v_docs_before OR v_events_after <> v_events_before THEN
    RAISE EXCEPTION 'duplicate registrar transaction conflict created document or event side effects';
  END IF;
END;
$$;

SET ROLE service_role;

DO $$
DECLARE
  v_replay_state pg_catalog.text;
BEGIN
  SELECT replay_state
  INTO v_replay_state
  FROM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000100',
    'CAMS'
  );

  IF v_replay_state <> 'active_in_progress' THEN
    RAISE EXCEPTION 'duplicate active run claim did not return active_in_progress: %', v_replay_state;
  END IF;
END;
$$;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000100',
  'CAMS'
);

DO $$
BEGIN
  PERFORM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000002',
    '93700000-0000-0000-0000-000000000002',
    '93900000-0000-0000-0000-000000000100',
    'CAMS'
  );
  RAISE EXCEPTION 'ingestion run rebound to another workspace was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
      RAISE;
    END IF;
END;
$$;

SELECT *
FROM public.finalize_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000100',
  'CAMS',
  NULL,
  NULL,
  3
);

RESET ROLE;

DO $$
DECLARE
  v_status pg_catalog.text;
  v_attempted pg_catalog.int4;
  v_success pg_catalog.int4;
  v_failed pg_catalog.int4;
BEGIN
  SELECT status, attempted_attachment_count, successful_attachment_count, failed_attachment_count
  INTO v_status, v_attempted, v_success, v_failed
  FROM public.cams_kfintech_ingestion_runs
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000100';

  IF v_status <> 'partially_failed' OR v_attempted <> 3 OR v_success <> 2 OR v_failed <> 1 THEN
    RAISE EXCEPTION 'run finalisation did not derive lineage counts: %, %, %, %', v_status, v_attempted, v_success, v_failed;
  END IF;
END;
$$;

SET ROLE service_role;

SELECT public.claim_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000501',
  'CAMS'
);

SELECT *
FROM public.finalize_cams_kfintech_ingestion_run(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000501',
  'CAMS',
  NULL,
  'mailbox_poll_failed',
  0
);

RESET ROLE;

DO $$
DECLARE
  v_status pg_catalog.text;
  v_attempted pg_catalog.int4;
  v_failure_code pg_catalog.text;
BEGIN
  SELECT status, attempted_attachment_count, run_failure_code
  INTO v_status, v_attempted, v_failure_code
  FROM public.cams_kfintech_ingestion_runs
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000501';

  IF v_status <> 'failed' OR v_attempted <> 0 OR v_failure_code <> 'mailbox_poll_failed' THEN
    RAISE EXCEPTION 'poll-level failure did not finalize as failed run-level code: %, %, %', v_status, v_attempted, v_failure_code;
  END IF;
END;
$$;

UPDATE public.mailbox_connections
SET status = 'disabled'
WHERE id = '93700000-0000-0000-0000-000000000001';

SET ROLE service_role;

DO $$
DECLARE
  v_replay_state pg_catalog.text;
BEGIN
  SELECT replay_state
  INTO v_replay_state
  FROM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000501',
    'CAMS'
  );

  IF v_replay_state <> 'terminal_replay' THEN
    RAISE EXCEPTION 'disabled mailbox blocked terminal replay: %', v_replay_state;
  END IF;
END;
$$;

RESET ROLE;

UPDATE public.mailbox_connections
SET status = 'reauthorization_required'
WHERE id = '93700000-0000-0000-0000-000000000001';

SET ROLE service_role;

DO $$
DECLARE
  v_replay_state pg_catalog.text;
BEGIN
  SELECT replay_state
  INTO v_replay_state
  FROM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000501',
    'CAMS'
  );

  IF v_replay_state <> 'terminal_replay' THEN
    RAISE EXCEPTION 'reauthorization mailbox blocked terminal replay: %', v_replay_state;
  END IF;
END;
$$;

DO $$
BEGIN
  PERFORM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000002',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000501',
    'CAMS'
  );
  RAISE EXCEPTION 'terminal replay accepted conflicting workspace';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  PERFORM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000002',
    '93900000-0000-0000-0000-000000000501',
    'CAMS'
  );
  RAISE EXCEPTION 'terminal replay accepted conflicting mailbox';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  PERFORM public.claim_cams_kfintech_ingestion_run(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000501',
    'KFINTECH'
  );
  RAISE EXCEPTION 'terminal replay accepted conflicting registrar';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
      RAISE;
    END IF;
END;
$$;

RESET ROLE;

DO $$
BEGIN
  DELETE FROM public.mailbox_connections
  WHERE id = '93700000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'referenced mailbox deletion was accepted';
EXCEPTION
  WHEN foreign_key_violation THEN
    NULL;
END;
$$;

UPDATE public.mailbox_connections
SET status = 'active'
WHERE id = '93700000-0000-0000-0000-000000000001';

SET ROLE service_role;

DO $$
BEGIN
  INSERT INTO public.ingested_documents (
    workspace_id, mailbox_connection_id, ingestion_run_id, provider_message_id,
    provider_attachment_id, attachment_attempt_key, registrar, storage_bucket,
    storage_object_path, sha256_hex, detected_mime, file_type, size_bytes,
    received_at, processing_status, correlation_id
  ) VALUES (
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000777',
    'forged-message',
    'forged-attachment',
    'forged-attempt',
    'CAMS',
    'ingested-documents',
    'forged/path',
    repeat('7', 64),
    'application/x-dbase',
    'DBF',
    1024,
    now(),
    'completed',
    '93900000-0000-0000-0000-000000000777'
  );
  RAISE EXCEPTION 'service_role inserted forged ingested document directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;

DO $$
BEGIN
  UPDATE public.ingested_documents
  SET processing_status = 'failed', sha256_hex = repeat('8', 64)
  WHERE correlation_id = '93900000-0000-0000-0000-000000000101';
  RAISE EXCEPTION 'service_role mutated ingested document directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;

DO $$
BEGIN
  INSERT INTO public.cams_kfintech_ingestion_runs (
    ingestion_run_id, workspace_id, mailbox_connection_id, registrar
  ) VALUES (
    '93900000-0000-0000-0000-000000000778',
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    'CAMS'
  );
  RAISE EXCEPTION 'service_role inserted forged ingestion run directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;

DO $$
BEGIN
  UPDATE public.cams_kfintech_ingestion_runs
  SET status = 'completed'
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000100';
  RAISE EXCEPTION 'service_role mutated ingestion run directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;

DO $$
BEGIN
  INSERT INTO public.cams_kfintech_ingestion_attempts (
    ingestion_run_id, workspace_id, mailbox_connection_id, provider_message_id,
    provider_attachment_id, attachment_attempt_key, document_correlation_id,
    outcome, failure_code
  ) VALUES (
    '93900000-0000-0000-0000-000000000100',
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    'forged-attempt-message',
    'forged-attempt-attachment',
    'forged-attempt-key',
    '93900000-0000-0000-0000-000000000779',
    'failed',
    'malware_detected'
  );
  RAISE EXCEPTION 'service_role inserted forged attempt directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;

DO $$
BEGIN
  UPDATE public.cams_kfintech_ingestion_attempts
  SET failure_code = 'parse_failed'
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000100';
  RAISE EXCEPTION 'service_role updated attempt directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;

DO $$
BEGIN
  DELETE FROM public.cams_kfintech_ingestion_attempts
  WHERE ingestion_run_id = '93900000-0000-0000-0000-000000000100';
  RAISE EXCEPTION 'service_role deleted attempt directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;

RESET ROLE;

DO $$
DECLARE
  v_attempt_id pg_catalog.uuid;
  v_replay_id pg_catalog.uuid;
BEGIN
  SELECT attempt.id
  INTO v_attempt_id
  FROM public.cams_kfintech_ingestion_attempts AS attempt
  LIMIT 1;

  IF v_attempt_id IS NULL THEN
    RAISE EXCEPTION 'attempt immutability test did not find an attempt row';
  END IF;

  BEGIN
    UPDATE public.cams_kfintech_ingestion_attempts
    SET failure_code = COALESCE(failure_code, 'parse_failed')
    WHERE id = v_attempt_id;
    RAISE EXCEPTION 'owner updated attempt directly';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%cams_kfintech_ingestion_attempts_immutable%' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    DELETE FROM public.cams_kfintech_ingestion_attempts
    WHERE id = v_attempt_id;
    RAISE EXCEPTION 'owner deleted attempt directly';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%cams_kfintech_ingestion_attempts_immutable%' THEN
        RAISE;
      END IF;
  END;

  v_replay_id := public.record_cams_kfintech_ingestion_attempt(
    '93900000-0000-0000-0000-000000000505',
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    'helper-replay-message',
    'helper-replay-attachment',
    'helper-replay-attempt',
    '93900000-0000-0000-0000-000000000505',
    NULL,
    NULL,
    repeat('9', 64),
    'ingested-documents',
    'helper/replay',
    'application/x-dbase',
    'DBF',
    1024,
    'failed',
    'parse_failed'
  );

  IF v_replay_id IS DISTINCT FROM public.record_cams_kfintech_ingestion_attempt(
    '93900000-0000-0000-0000-000000000505',
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    'helper-replay-message',
    'helper-replay-attachment',
    'helper-replay-attempt',
    '93900000-0000-0000-0000-000000000505',
    NULL,
    NULL,
    repeat('9', 64),
    'ingested-documents',
    'helper/replay',
    'application/x-dbase',
    'DBF',
    1024,
    'failed',
    'parse_failed'
  ) THEN
    RAISE EXCEPTION 'identical attempt replay did not return the same attempt id';
  END IF;

  BEGIN
    PERFORM public.record_cams_kfintech_ingestion_attempt(
      '93900000-0000-0000-0000-000000000505',
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      'helper-replay-message',
      'helper-replay-attachment',
      'helper-replay-attempt',
      '93900000-0000-0000-0000-000000000505',
      NULL,
      NULL,
      repeat('9', 64),
      'ingested-documents',
      'helper/replay-changed',
      'application/x-dbase',
      'DBF',
      1024,
      'failed',
      'parse_failed'
    );
    RAISE EXCEPTION 'contradictory attempt replay was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
        RAISE;
      END IF;
  END;
END;
$$;

DO $$
DECLARE
  v_docs_before pg_catalog.int4;
  v_logs_before pg_catalog.int4;
  v_events_before pg_catalog.int4;
  v_attempts_before pg_catalog.int4;
  v_docs_after pg_catalog.int4;
  v_logs_after pg_catalog.int4;
  v_events_after pg_catalog.int4;
  v_attempts_after pg_catalog.int4;
  v_failure_code pg_catalog.text;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_before FROM public.ingested_documents;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_before FROM public.ingestion_logs;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_events_before FROM public.event_outbox;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_attempts_before FROM public.cams_kfintech_ingestion_attempts;

  BEGIN
    SELECT failure_code INTO v_failure_code
    FROM public.persist_cams_kfintech_statement_ingestion(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000502',
      '93900000-0000-0000-0000-000000000101',
      'provider-message-a',
      'provider-attachment-a',
      'provider-identity-changed-digest',
      'CAMS',
      repeat('b', 64),
      'ingested-documents',
      'changed/provider-digest',
      'application/x-dbase',
      'DBF',
      1024,
      '2026-07-29T00:00:00Z',
      pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'registrar', 'CAMS',
        'clientPan', 'QWERT1234Y',
        'investorName', 'Changed Digest',
        'folioNumber', 'FOLIO-32-A',
        'schemeCode', 'MF32A',
        'fundHouse', 'Money Bowl AMC',
        'transactionType', 'BUY',
        'transactionDirection', 'INFLOW',
        'registrarTransactionCode', 'BUY',
        'units', 1,
        'nav', 1,
        'amount', 1,
        'date', '2026-07-29',
        'sourceRowNumber', 1
      ))
    );
    IF v_failure_code <> 'attachment_hash_mismatch' THEN
      RAISE EXCEPTION 'same provider changed bytes did not return attachment_hash_mismatch: %', v_failure_code;
    END IF;
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%attachment_hash_mismatch%' AND SQLERRM NOT LIKE '%correlation_conflict%' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    SELECT failure_code INTO v_failure_code
    FROM public.persist_cams_kfintech_statement_ingestion(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000502',
      '93900000-0000-0000-0000-000000000502',
      'provider-message-digest-dup',
      'provider-attachment-digest-dup',
      'digest-duplicate-attempt',
      'CAMS',
      repeat('a', 64),
      'ingested-documents',
      'duplicate/digest',
      'application/x-dbase',
      'DBF',
      1024,
      '2026-07-29T00:00:00Z',
      pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'registrar', 'CAMS',
        'clientPan', 'QWERT1234Y',
        'investorName', 'Digest Duplicate',
        'folioNumber', 'FOLIO-DIGEST-DUP',
        'schemeCode', 'MF32A',
        'fundHouse', 'Money Bowl AMC',
        'transactionType', 'BUY',
        'transactionDirection', 'INFLOW',
        'registrarTransactionCode', 'BUY',
        'units', 1,
        'nav', 1,
        'amount', 1,
        'date', '2026-07-29',
        'sourceRowNumber', 1
      ))
    );
    IF v_failure_code <> 'duplicate_attachment' THEN
      RAISE EXCEPTION 'same digest under different provider identity did not return duplicate_attachment: %', v_failure_code;
    END IF;
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%duplicate_attachment%' AND SQLERRM NOT LIKE '%correlation_conflict%' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    PERFORM public.record_cams_kfintech_ingestion_failure(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000502',
      '93900000-0000-0000-0000-000000000101',
      'provider-message-a',
      'provider-attachment-a',
      'failure-provider-digest-conflict',
      'CAMS',
      'attachment_hash_mismatch',
      repeat('b', 64),
      'ingested-documents',
      'failure/changed-provider-digest',
      'application/x-dbase',
      'DBF',
      1024
    );
    RAISE EXCEPTION 'failure lineage accepted provider digest contradiction';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%attachment_hash_mismatch%' AND SQLERRM NOT LIKE '%correlation_conflict%' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    PERFORM public.record_cams_kfintech_ingestion_failure(
      '93400000-0000-0000-0000-000000000001',
      '93700000-0000-0000-0000-000000000001',
      '93900000-0000-0000-0000-000000000502',
      '93900000-0000-0000-0000-000000000502',
      'provider-message-digest-dup',
      'provider-attachment-digest-dup',
      'failure-duplicate-digest-attempt',
      'CAMS',
      'duplicate_attachment',
      repeat('a', 64),
      'ingested-documents',
      'failure/duplicate-digest',
      'application/x-dbase',
      'DBF',
      1024
    );
    RAISE EXCEPTION 'failure lineage accepted duplicate digest as a new document';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%duplicate_attachment%' AND SQLERRM NOT LIKE '%correlation_conflict%' THEN
        RAISE;
      END IF;
  END;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_docs_after FROM public.ingested_documents;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_logs_after FROM public.ingestion_logs;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_events_after FROM public.event_outbox;
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_attempts_after FROM public.cams_kfintech_ingestion_attempts;

  IF v_docs_after <> v_docs_before
     OR v_logs_after <> v_logs_before + 1
     OR v_attempts_after <> v_attempts_before + 1
     OR v_events_after <> v_events_before THEN
    RAISE EXCEPTION 'provider identity conflicts did not preserve durable attempt lineage without document/event side effects';
  END IF;
END;
$$;

DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000503',
    '93900000-0000-0000-0000-000000000503',
    'provider-message-amc-conflict',
    'provider-attachment-amc-conflict',
    'amc-conflict-attempt',
    'CAMS',
    repeat('d', 64),
    'ingested-documents',
    'amc/conflict',
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'AMC Conflict',
      'folioNumber', 'FOLIO-32-A',
      'schemeCode', 'MF32AMCCONFLICT',
      'fundHouse', 'Different AMC',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 1,
      'nav', 1,
      'amount', 1,
      'date', '2026-07-29',
      'sourceRowNumber', 1
    ))
  );
  RAISE EXCEPTION 'folio reused with conflicting AMC identity';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%folio_relationship_conflict%' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000504',
    '93900000-0000-0000-0000-000000000504',
    'provider-message-missing-amc',
    'provider-attachment-missing-amc',
    'missing-amc-attempt',
    'CAMS',
    repeat('1', 64),
    'ingested-documents',
    'amc/missing',
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'QWERT1234Y',
      'investorName', 'Missing AMC',
      'folioNumber', 'FOLIO-MISSING-AMC',
      'schemeCode', 'MF32MISSINGAMC',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 1,
      'nav', 1,
      'amount', 1,
      'date', '2026-07-29',
      'sourceRowNumber', 1
    ))
  );
  RAISE EXCEPTION 'missing AMC mapping was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%amc_mapping_unresolved%' THEN
      RAISE;
    END IF;
END;
$$;

INSERT INTO public.mutual_funds (scheme_code, scheme_name, fund_house, category)
VALUES ('MF32TRUST', 'Issue 32 Trusted AMC Fund', 'Trusted AMC', 'Equity');

SELECT *
FROM public.persist_cams_kfintech_statement_ingestion(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000505',
  '93900000-0000-0000-0000-000000000505',
  'provider-message-trusted-amc',
  'provider-attachment-trusted-amc',
  'trusted-amc-attempt',
  'CAMS',
  repeat('f', 64),
  'ingested-documents',
  'amc/trusted',
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
    'registrar', 'CAMS',
    'clientPan', 'QWERT1234Y',
    'investorName', 'Trusted AMC',
    'folioNumber', 'FOLIO-TRUSTED-AMC',
    'schemeCode', 'MF32TRUST',
    'transactionType', 'BUY',
    'transactionDirection', 'INFLOW',
    'registrarTransactionCode', 'BUY',
    'units', 1,
    'nav', 1,
    'amount', 1,
    'date', '2026-07-29',
    'sourceRowNumber', 1
  ))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.folio_references
    WHERE registrar = 'CAMS'
      AND normalized_folio_number = 'FOLIOTRUSTEDAMC'
      AND amc_identity = 'Trusted AMC'
  ) THEN
    RAISE EXCEPTION 'trusted scheme AMC identity was not persisted on new folio';
  END IF;
END;
$$;

RESET ROLE;

SET ROLE authenticated;
DO $$
BEGIN
  INSERT INTO public.ingested_documents (
    workspace_id, mailbox_connection_id, ingestion_run_id, provider_message_id,
    provider_attachment_id, attachment_attempt_key, registrar, storage_bucket,
    storage_object_path, sha256_hex, detected_mime, file_type, size_bytes,
    received_at, processing_status, correlation_id
  ) VALUES (
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    '93900000-0000-0000-0000-000000000779',
    'authenticated-forged-message',
    'authenticated-forged-attachment',
    'authenticated-forged-attempt',
    'CAMS',
    'ingested-documents',
    'authenticated/forged',
    repeat('9', 64),
    'application/x-dbase',
    'DBF',
    1024,
    now(),
    'completed',
    '93900000-0000-0000-0000-000000000779'
  );
  RAISE EXCEPTION 'authenticated inserted forged ingested document directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;
DO $$
BEGIN
  INSERT INTO public.cams_kfintech_ingestion_runs (
    ingestion_run_id, workspace_id, mailbox_connection_id, registrar
  ) VALUES (
    '93900000-0000-0000-0000-000000000780',
    '93400000-0000-0000-0000-000000000001',
    '93700000-0000-0000-0000-000000000001',
    'CAMS'
  );
  RAISE EXCEPTION 'authenticated inserted forged ingestion run directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;
RESET ROLE;

DROP INDEX IF EXISTS public.portfolio_folio_references_folio_uidx;
DO $$
DECLARE
  v_existing_folio_id pg_catalog.uuid;
BEGIN
  SELECT id INTO v_existing_folio_id
  FROM public.folio_references
  WHERE registrar = 'CAMS'
    AND normalized_folio_number = 'FOLIO32A';

  INSERT INTO public.portfolio_folio_references (portfolio_id, folio_reference_id)
  VALUES ('93230000-0000-0000-0000-000000000001', v_existing_folio_id);

  BEGIN
    IF EXISTS (
      SELECT 1
      FROM public.portfolio_folio_references AS mapping
      JOIN public.portfolios AS portfolio
        ON portfolio.id = mapping.portfolio_id
      WHERE portfolio.workspace_id IS NOT NULL
      GROUP BY portfolio.workspace_id, mapping.folio_reference_id
      HAVING pg_catalog.count(*) > 1
    ) THEN
      RAISE EXCEPTION 'issue_32_preflight_duplicate_folio_mapping';
    END IF;
    RAISE EXCEPTION 'duplicate folio mapping preflight did not fire';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%issue_32_preflight_duplicate_folio_mapping%' THEN
        RAISE;
      END IF;
  END;
END;
$$;

DROP INDEX IF EXISTS public.portfolios_workspace_client_uidx;
DO $$
BEGIN
  INSERT INTO public.portfolios (client_id, workspace_id, total_invested_value, current_market_value)
  VALUES ('93300000-0000-0000-0000-000000000002', '93400000-0000-0000-0000-000000000001', 0.00, 0.00);

  BEGIN
    IF EXISTS (
      SELECT 1
      FROM public.portfolios AS portfolio
      WHERE portfolio.workspace_id IS NOT NULL
      GROUP BY portfolio.workspace_id, portfolio.client_id
      HAVING pg_catalog.count(*) > 1
    ) THEN
      RAISE EXCEPTION 'issue_32_preflight_duplicate_portfolio_identity';
    END IF;
    RAISE EXCEPTION 'duplicate portfolio identity preflight did not fire';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%issue_32_preflight_duplicate_portfolio_identity%' THEN
        RAISE;
      END IF;
  END;
END;
$$;

DROP INDEX IF EXISTS public.transactions_registrar_folio_txn_uidx;
DO $$
DECLARE
  v_document_id pg_catalog.uuid;
  v_folio_id pg_catalog.uuid;
  v_fund_id pg_catalog.uuid;
  v_portfolio_id pg_catalog.uuid;
BEGIN
  SELECT id INTO v_document_id
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000406';
  SELECT id INTO v_folio_id
  FROM public.folio_references
  WHERE registrar = 'CAMS'
    AND normalized_folio_number = 'FOLIO32A';
  SELECT id INTO v_fund_id
  FROM public.mutual_funds
  WHERE scheme_code = 'MF32A';
  SELECT id INTO v_portfolio_id
  FROM public.portfolios
  WHERE workspace_id = '93400000-0000-0000-0000-000000000001'
    AND client_id = '93300000-0000-0000-0000-000000000002'
  LIMIT 1;

  INSERT INTO public.transactions (
    portfolio_id,
    mutual_fund_id,
    transaction_type,
    units,
    nav_at_transaction,
    amount,
    execution_date,
    registrar,
    source_document_id,
    source_row_number,
    source_attachment_sha256,
    registrar_transaction_id,
    registrar_transaction_code,
    transaction_direction,
    folio_reference_id,
    source_folio_reference_id
  ) VALUES (
    v_portfolio_id,
    v_fund_id,
    'BUY',
    1,
    1,
    1,
    '2026-07-29',
    'CAMS',
    v_document_id,
    99,
    repeat('9', 64),
    'CAMS-ROW-1',
    'BUY',
    'INFLOW',
    v_folio_id,
    v_folio_id
  );

  BEGIN
    IF EXISTS (
      SELECT 1
      FROM public.transactions AS transaction
      WHERE transaction.registrar IN ('CAMS', 'KFINTECH')
        AND transaction.source_folio_reference_id IS NOT NULL
        AND transaction.registrar_transaction_id IS NOT NULL
      GROUP BY transaction.registrar, transaction.source_folio_reference_id, transaction.registrar_transaction_id
      HAVING pg_catalog.count(*) > 1
    ) THEN
      RAISE EXCEPTION 'issue_32_preflight_duplicate_registrar_transaction_identity';
    END IF;
    RAISE EXCEPTION 'duplicate registrar transaction identity preflight did not fire';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%issue_32_preflight_duplicate_registrar_transaction_identity%' THEN
        RAISE;
      END IF;
  END;
END;
$$;

DROP INDEX IF EXISTS public.event_outbox_statement_imported_uidx;
DO $$
DECLARE
  v_document_id pg_catalog.uuid;
BEGIN
  SELECT id INTO v_document_id
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000401';

  INSERT INTO public.event_outbox (event_type, entity_id, entity_type, payload, status)
  VALUES ('statement.imported', v_document_id, 'ingested_document', pg_catalog.jsonb_build_object('duplicate', true), 'pending');

  BEGIN
    IF EXISTS (
      SELECT 1
      FROM public.event_outbox AS event
      WHERE event.event_type = 'statement.imported'
        AND event.entity_type IS NOT NULL
        AND event.entity_id IS NOT NULL
      GROUP BY event.entity_type, event.entity_id, event.event_type
      HAVING pg_catalog.count(*) > 1
    ) THEN
      RAISE EXCEPTION 'issue_32_preflight_duplicate_statement_imported_event';
    END IF;
    RAISE EXCEPTION 'duplicate statement.imported event preflight did not fire';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%issue_32_preflight_duplicate_statement_imported_event%' THEN
        RAISE;
      END IF;
  END;
END;
$$;
RESET ROLE;

ROLLBACK;
