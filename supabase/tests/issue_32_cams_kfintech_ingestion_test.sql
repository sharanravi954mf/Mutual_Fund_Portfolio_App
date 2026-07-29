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
  extensions.pgp_sym_encrypt('ABCDE1234F', public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
  extensions.hmac('ABCDE1234F', public.pan_lookup_hmac_key(), 'sha256'),
  public.mask_pan('ABCDE1234F'),
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
      'public.ingestion_logs'::pg_catalog.regclass
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
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.ingested_documents', 'INSERT') THEN
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
      'record_cams_kfintech_ingestion_failure',
      'persist_cams_kfintech_statement_ingestion'
    )
    AND proc.prosecdef
    AND proc.proconfig = ARRAY['search_path=""']::pg_catalog.text[];

  IF v_count <> 4 THEN
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
         AND indexname = 'ingested_documents_attachment_attempt_uidx'
     )
     OR NOT EXISTS (
	       SELECT 1 FROM pg_catalog.pg_indexes
	       WHERE schemaname = 'public'
	         AND indexname = 'ingestion_logs_failure_attempt_uidx'
	     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND indexname = 'transactions_registrar_folio_txn_uidx'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND indexname = 'portfolio_folio_references_folio_uidx'
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
      'clientPan', 'ABCDE1234F',
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
      'clientPan', 'ABCDE1234F',
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
      'clientPan', 'ABCDE1234F',
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
        'clientPan', 'ABCDE1234F',
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
  RAISE EXCEPTION 'failed document replay returned idempotent success';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%previous_ingestion_failed%' THEN
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
        'clientPan', 'ABCDE1234F',
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
    'clientPan', 'ABCDE1234F',
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
        'clientPan', 'ABCDE1234F',
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
      'clientPan', 'ABCDE1234F',
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
        'clientPan', 'ABCDE1234F',
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
      'clientPan', 'ABCDE1234F',
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
      'clientPan', 'ABCDE1234F',
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
  '93900000-0000-0000-0000-000000000400',
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
      'clientPan', 'ABCDE1234F',
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
      'clientPan', 'ABCDE1234F',
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
    '93900000-0000-0000-0000-000000000300',
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
      'clientPan', 'ABCDE1234F',
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
  extensions.pgp_sym_encrypt('ABCDE1234F', public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
  extensions.hmac('ABCDE1234F', public.pan_lookup_hmac_key(), 'sha256'),
  public.mask_pan('ABCDE1234F'),
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
      'clientPan', 'ABCDE1234F',
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
          'clientPan', 'ABCDE1234F',
          'investorName', 'Duplicate Row',
          'folioNumber', 'FOLIO-DUP',
          'schemeCode', 'MF32NEG',
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
          'clientPan', 'ABCDE1234F',
          'investorName', 'Duplicate Row',
          'folioNumber', 'FOLIO-DUP',
          'schemeCode', 'MF32NEG',
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
          'clientPan', 'ABCDE1234F',
          'investorName', 'Duplicate Registrar Transaction',
          'folioNumber', 'FOLIO-DUP-TXN',
          'schemeCode', 'MF32NEG',
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
          'clientPan', 'ABCDE1234F',
          'investorName', 'Duplicate Registrar Transaction',
          'folioNumber', 'FOLIO-DUP-TXN',
          'schemeCode', 'MF32NEG',
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
      GROUP BY mapping.folio_reference_id
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
