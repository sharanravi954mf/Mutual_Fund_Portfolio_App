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

UPDATE public.profiles
SET id = '93300000-0000-0000-0000-000000000001', role = 'advisor', full_name = 'Issue 32 Owner'
WHERE user_id = '93200000-0000-0000-0000-000000000001';

UPDATE public.profiles
SET id = '93300000-0000-0000-0000-000000000002', role = 'investor', full_name = 'Issue 32 Investor'
WHERE user_id = '93200000-0000-0000-0000-000000000002';

UPDATE public.profiles
SET id = '93300000-0000-0000-0000-000000000003', role = 'investor', full_name = 'Issue 32 Family Guest'
WHERE user_id = '93200000-0000-0000-0000-000000000003';

UPDATE public.profiles
SET id = '93300000-0000-0000-0000-000000000004', role = 'advisor', full_name = 'Issue 32 Owner B'
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
  supported_file_types
) VALUES
  ('93600000-0000-0000-0000-000000000001', '93400000-0000-0000-0000-000000000001', 'CAMS', ARRAY['statements@camsonline.com'], 20971519, ARRAY['CAS_PDF', 'DBF']),
  ('93600000-0000-0000-0000-000000000002', '93400000-0000-0000-0000-000000000002', 'CAMS', ARRAY['statements@camsonline.com'], 20971519, ARRAY['CAS_PDF', 'DBF']);

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
  ('93700000-0000-0000-0000-000000000002', '93400000-0000-0000-0000-000000000002', 'CAMS', 'owner-b@moneybowl.test', 'issue-32-connector-b', 'gmail', ARRAY['statements@camsonline.com'], 'active');

INSERT INTO public.mailbox_oauth_credentials (
  id,
  mailbox_connection_id,
  workspace_id,
  access_token_ciphertext,
  refresh_token_ciphertext,
  nonce,
  key_version,
  expires_at
) VALUES
  ('93800000-0000-0000-0000-000000000001', '93700000-0000-0000-0000-000000000001', '93400000-0000-0000-0000-000000000001', 'ciphertext-access-a', 'ciphertext-refresh-a', 'nonce-a', 1, now() + interval '1 hour'),
  ('93800000-0000-0000-0000-000000000002', '93700000-0000-0000-0000-000000000002', '93400000-0000-0000-0000-000000000002', 'ciphertext-access-b', 'ciphertext-refresh-b', 'nonce-b', 1, now() + interval '1 hour');

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

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = class.relnamespace
    WHERE namespace.nspname = 'public'
      AND class.relname IN (
        'registrar_configs',
        'mailbox_connections',
        'mailbox_oauth_credentials',
        'ingested_documents',
        'ingestion_logs'
      )
      AND class.relrowsecurity
    GROUP BY namespace.nspname
    HAVING pg_catalog.count(*) = 5
  ) THEN
    RAISE EXCEPTION 'Issue #32 sensitive tables are not all protected by RLS';
  END IF;

  IF pg_catalog.has_table_privilege('anon', 'public.mailbox_oauth_credentials', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.mailbox_oauth_credentials', 'SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.mailbox_oauth_credentials', 'SELECT') THEN
    RAISE EXCEPTION 'Issue #32 OAuth credential table grants are incorrect';
  END IF;

  IF pg_catalog.has_table_privilege('anon', 'public.ingested_documents', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.ingested_documents', 'SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.ingested_documents', 'INSERT') THEN
    RAISE EXCEPTION 'Issue #32 document table grants are incorrect';
  END IF;

  IF pg_catalog.has_table_privilege('service_role', 'public.ingestion_logs', 'INSERT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.ingestion_logs', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'public.ingestion_logs', 'SELECT') THEN
    RAISE EXCEPTION 'Issue #32 ingestion log grants are incorrect';
  END IF;

  IF pg_catalog.has_function_privilege(
       'anon',
       'public.persist_cams_kfintech_statement_ingestion(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.int4, pg_catalog.timestamptz, jsonb)',
       'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'public.persist_cams_kfintech_statement_ingestion(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.int4, pg_catalog.timestamptz, jsonb)',
       'EXECUTE'
     )
     OR NOT pg_catalog.has_function_privilege(
       'service_role',
       'public.persist_cams_kfintech_statement_ingestion(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.int4, pg_catalog.timestamptz, jsonb)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Issue #32 persist RPC privileges are incorrect';
  END IF;

  IF pg_catalog.has_function_privilege(
       'anon',
       'public.record_cams_kfintech_ingestion_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.int4)',
       'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'public.record_cams_kfintech_ingestion_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.int4)',
       'EXECUTE'
     )
     OR NOT pg_catalog.has_function_privilege(
       'service_role',
       'public.record_cams_kfintech_ingestion_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.int4)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Issue #32 failure RPC privileges are incorrect';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM pg_catalog.pg_proc AS proc
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = proc.pronamespace
  WHERE namespace.nspname = 'public'
    AND proc.proname IN (
      'record_cams_kfintech_ingestion_failure',
      'persist_cams_kfintech_statement_ingestion'
    )
    AND proc.prosecdef
    AND proc.proconfig = ARRAY['search_path=""']::pg_catalog.text[];

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Issue #32 RPCs are not SECURITY DEFINER with empty search_path';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'ingested_documents_workspace_sha256_uidx'
  )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND indexname = 'transactions_source_document_row_uidx'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_indexes
       WHERE schemaname = 'public'
         AND indexname = 'event_outbox_statement_imported_uidx'
     ) THEN
    RAISE EXCEPTION 'Issue #32 idempotency indexes are missing';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated', 'public.cancel_order(pg_catalog.uuid, pg_catalog.text)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role', 'public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Issue #28-#31 regression guard failed for key RPC grants';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'order_requests';

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Issue #30 order_requests policy count regressed: %', v_count;
  END IF;
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

DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '93200000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM 1 FROM public.ingested_documents LIMIT 1;
  RAISE EXCEPTION 'family guest read ingested documents directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;
RESET ROLE;

SET ROLE anon;
DO $$
BEGIN
  PERFORM 1 FROM public.mailbox_oauth_credentials LIMIT 1;
  RAISE EXCEPTION 'anon read OAuth credentials directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;
RESET ROLE;

SET ROLE service_role;
SELECT *
FROM public.persist_cams_kfintech_statement_ingestion(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000001',
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
  '93900000-0000-0000-0000-000000000001',
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
  '93400000-0000-0000-0000-000000000002',
  '93700000-0000-0000-0000-000000000002',
  '93900000-0000-0000-0000-000000000002',
  'CAMS',
  repeat('a', 64),
  'ingested-documents',
  '93400000-0000-0000-0000-000000000002/93700000-0000-0000-0000-000000000002/' || repeat('a', 64),
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
      'units', 5,
      'nav', 10,
      'amount', 50,
      'date', '2026-07-29',
      'sourceRowNumber', 1,
      'registrarTransactionId', 'CAMS-ROW-B'
    )
  )
);

DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '93400000-0000-0000-0000-000000000002',
    '93700000-0000-0000-0000-000000000002',
    '93900000-0000-0000-0000-000000000001',
    'CAMS',
    repeat('b', 64),
    'ingested-documents',
    '93400000-0000-0000-0000-000000000002/93700000-0000-0000-0000-000000000002/' || repeat('b', 64),
    'application/x-dbase',
    'DBF',
    1024,
    '2026-07-29T00:00:00Z',
    pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'registrar', 'CAMS',
        'clientPan', 'ABCDE1234F',
        'investorName', 'Issue 32 Imported Investor',
        'folioNumber', 'FOLIO-32-CONFLICT',
        'schemeCode', 'MF32C',
        'schemeName', 'Issue 32 Conflict Fund',
        'fundHouse', 'Money Bowl AMC',
        'category', 'Debt',
        'transactionType', 'BUY',
        'units', 1,
        'nav', 1,
        'amount', 1,
        'date', '2026-07-29',
        'sourceRowNumber', 1
      )
    )
  );
  RAISE EXCEPTION 'cross-workspace correlation conflict was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%correlation_conflict%' THEN
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
    '93900000-0000-0000-0000-000000000003',
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
        'investorName', 'Issue 32 Bad Investor',
        'folioNumber', 'FOLIO-32-BAD',
        'schemeName', 'Issue 32 Missing Scheme',
        'fundHouse', 'Money Bowl AMC',
        'category', 'Debt',
        'transactionType', 'BUY',
        'units', 1,
        'nav', 1,
        'amount', 1,
        'date', '2026-07-29',
        'sourceRowNumber', 1
      )
    )
  );
  RAISE EXCEPTION 'invalid parsed transaction persisted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%parse_failed%' THEN
      RAISE;
    END IF;
END;
$$;

SELECT public.record_cams_kfintech_ingestion_failure(
  '93400000-0000-0000-0000-000000000001',
  '93700000-0000-0000-0000-000000000001',
  '93900000-0000-0000-0000-000000000004',
  'CAMS',
  'malware_detected',
  repeat('d', 64),
  'ingested-documents',
  '93400000-0000-0000-0000-000000000001/93700000-0000-0000-0000-000000000001/' || repeat('d', 64),
  'application/x-dbase',
  'DBF',
  1024
);

DO $$
BEGIN
  INSERT INTO public.ingestion_logs (status)
  VALUES ('FAILED');
  RAISE EXCEPTION 'service_role inserted ingestion_logs directly';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END;
$$;
RESET ROLE;

DO $$
DECLARE
  v_count pg_catalog.int4;
  v_log_id pg_catalog.uuid;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.ingested_documents
  WHERE sha256_hex = repeat('a', 64);

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'same attachment hash did not remain workspace-scoped: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000001'
    AND processing_status = 'completed';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'idempotent retry created duplicate or incomplete document: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.transactions AS transaction
  JOIN public.ingested_documents AS document
    ON document.id = transaction.source_document_id
  WHERE document.correlation_id = '93900000-0000-0000-0000-000000000001';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'idempotent retry created duplicate transactions: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.event_outbox AS event
  JOIN public.ingested_documents AS document
    ON document.id = event.entity_id
  WHERE document.correlation_id = '93900000-0000-0000-0000-000000000001'
    AND event.entity_type = 'ingested_document'
    AND event.event_type = 'statement.imported';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'statement.imported outbox event is not unique: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000003';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'invalid parsed transaction left document artifact: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.transactions
  WHERE source_attachment_sha256 = repeat('c', 64);

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'invalid parsed transaction left transaction artifact: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.ingestion_logs
  WHERE correlation_id = '93900000-0000-0000-0000-000000000004'
    AND status = 'FAILED'
    AND failure_code = 'malware_detected';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'failure lineage log was not written exactly once: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.ingested_documents
  WHERE correlation_id = '93900000-0000-0000-0000-000000000004'
    AND processing_status = 'failed';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'failed document lineage was not written exactly once: %', v_count;
  END IF;

  SELECT id
  INTO v_log_id
  FROM public.ingestion_logs
  WHERE correlation_id = '93900000-0000-0000-0000-000000000001'
  LIMIT 1;

  BEGIN
    UPDATE public.ingestion_logs
    SET records_processed = 99
    WHERE id = v_log_id;
    RAISE EXCEPTION 'ingestion_logs update was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%ingestion_logs_immutable%' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    DELETE FROM public.ingestion_logs
    WHERE id = v_log_id;
    RAISE EXCEPTION 'ingestion_logs delete was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%ingestion_logs_immutable%' THEN
        RAISE;
      END IF;
  END;
END;
$$;

ROLLBACK;
