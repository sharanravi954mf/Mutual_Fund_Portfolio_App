-- Issue #32: CAMS/KFintech in-memory ingestion worker contracts.

BEGIN;

CREATE TABLE IF NOT EXISTS public.registrar_configs (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id pg_catalog.uuid REFERENCES public.workspaces(id) ON DELETE CASCADE,
  registrar pg_catalog.text NOT NULL CHECK (registrar IN ('CAMS', 'KFINTECH')),
  allowed_sender_addresses pg_catalog.text[] NOT NULL CHECK (pg_catalog.array_length(allowed_sender_addresses, 1) > 0),
  max_attachment_bytes pg_catalog.int4 NOT NULL DEFAULT 20971519 CHECK (max_attachment_bytes > 0 AND max_attachment_bytes < 20971520),
  max_messages_per_poll pg_catalog.int4 NOT NULL DEFAULT 25 CHECK (max_messages_per_poll > 0 AND max_messages_per_poll <= 100),
  max_attachments_per_message pg_catalog.int4 NOT NULL DEFAULT 5 CHECK (max_attachments_per_message > 0 AND max_attachments_per_message <= 25),
  max_attachments_per_run pg_catalog.int4 NOT NULL DEFAULT 25 CHECK (max_attachments_per_run > 0 AND max_attachments_per_run <= 100),
  total_bytes_per_run pg_catalog.int4 NOT NULL DEFAULT 20971519 CHECK (total_bytes_per_run > 0 AND total_bytes_per_run < 20971520),
  supported_file_types pg_catalog.text[] NOT NULL DEFAULT ARRAY['CAS_PDF', 'DBF']::pg_catalog.text[],
  is_active pg_catalog.bool NOT NULL DEFAULT true,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  UNIQUE (workspace_id, registrar)
);

CREATE TABLE IF NOT EXISTS public.mailbox_connections (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  registrar pg_catalog.text NOT NULL CHECK (registrar IN ('CAMS', 'KFINTECH')),
  mailbox_address pg_catalog.text NOT NULL,
  connector_ref pg_catalog.text NOT NULL,
  oauth_provider pg_catalog.text NOT NULL,
  status pg_catalog.text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'reauthorization_required')),
  allowed_sender_addresses pg_catalog.text[] NOT NULL,
  last_polled_at pg_catalog.timestamptz,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  UNIQUE (workspace_id, connector_ref)
);

CREATE TABLE IF NOT EXISTS public.mailbox_oauth_credentials (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  mailbox_connection_id pg_catalog.uuid NOT NULL UNIQUE REFERENCES public.mailbox_connections(id) ON DELETE CASCADE,
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  credential_ciphertext pg_catalog.text NOT NULL,
  credential_nonce pg_catalog.text NOT NULL,
  key_version pg_catalog.int4 NOT NULL DEFAULT 1 CHECK (key_version = 1),
  expires_at pg_catalog.timestamptz,
  refreshed_at pg_catalog.timestamptz,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE IF NOT EXISTS public.ingested_documents (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  mailbox_connection_id pg_catalog.uuid NOT NULL REFERENCES public.mailbox_connections(id) ON DELETE RESTRICT,
  ingestion_run_id pg_catalog.uuid NOT NULL,
  provider_message_id pg_catalog.text NOT NULL,
  provider_attachment_id pg_catalog.text NOT NULL,
  attachment_attempt_key pg_catalog.text NOT NULL,
  registrar pg_catalog.text NOT NULL CHECK (registrar IN ('CAMS', 'KFINTECH')),
  storage_bucket pg_catalog.text NOT NULL,
  storage_object_path pg_catalog.text NOT NULL,
  sha256_hex pg_catalog.text NOT NULL CHECK (sha256_hex ~ '^[0-9a-f]{64}$'),
  detected_mime pg_catalog.text NOT NULL,
  file_type pg_catalog.text NOT NULL CHECK (file_type IN ('CAS_PDF', 'DBF')),
  size_bytes pg_catalog.int4 NOT NULL CHECK (size_bytes > 0 AND size_bytes < 20971520),
  received_at pg_catalog.timestamptz NOT NULL,
  processing_status pg_catalog.text NOT NULL DEFAULT 'stored'
    CHECK (processing_status IN ('stored', 'processing', 'completed', 'failed')),
  correlation_id pg_catalog.uuid NOT NULL UNIQUE,
  ingestion_log_id pg_catalog.uuid REFERENCES public.ingestion_logs(id) ON DELETE SET NULL,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  UNIQUE (workspace_id, sha256_hex),
  UNIQUE (storage_bucket, storage_object_path)
);

ALTER TABLE public.ingestion_logs
  ADD COLUMN IF NOT EXISTS workspace_id pg_catalog.uuid REFERENCES public.workspaces(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS mailbox_connection_id pg_catalog.uuid REFERENCES public.mailbox_connections(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS document_id pg_catalog.uuid REFERENCES public.ingested_documents(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ingestion_run_id pg_catalog.uuid,
  ADD COLUMN IF NOT EXISTS provider_message_id pg_catalog.text,
  ADD COLUMN IF NOT EXISTS provider_attachment_id pg_catalog.text,
  ADD COLUMN IF NOT EXISTS attachment_attempt_key pg_catalog.text,
  ADD COLUMN IF NOT EXISTS registrar pg_catalog.text,
  ADD COLUMN IF NOT EXISTS attachment_sha256 pg_catalog.text,
  ADD COLUMN IF NOT EXISTS storage_bucket pg_catalog.text,
  ADD COLUMN IF NOT EXISTS storage_object_path pg_catalog.text,
  ADD COLUMN IF NOT EXISTS detected_mime pg_catalog.text,
  ADD COLUMN IF NOT EXISTS file_type pg_catalog.text,
  ADD COLUMN IF NOT EXISTS size_bytes pg_catalog.int4,
  ADD COLUMN IF NOT EXISTS correlation_id pg_catalog.uuid,
  ADD COLUMN IF NOT EXISTS failure_code pg_catalog.text;

ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS registrar pg_catalog.text,
  ADD COLUMN IF NOT EXISTS source_document_id pg_catalog.uuid REFERENCES public.ingested_documents(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS source_row_number pg_catalog.int4,
  ADD COLUMN IF NOT EXISTS source_attachment_sha256 pg_catalog.text,
  ADD COLUMN IF NOT EXISTS registrar_transaction_id pg_catalog.text,
  ADD COLUMN IF NOT EXISTS registrar_transaction_code pg_catalog.text,
  ADD COLUMN IF NOT EXISTS transaction_direction pg_catalog.text,
  ADD COLUMN IF NOT EXISTS source_folio_reference_id pg_catalog.uuid REFERENCES public.folio_references(id) ON DELETE RESTRICT;

ALTER TABLE public.mutual_funds
  ALTER COLUMN current_nav DROP NOT NULL,
  ALTER COLUMN nav_date DROP NOT NULL;

ALTER TABLE public.portfolio_folio_references
  DROP CONSTRAINT IF EXISTS portfolio_folio_references_pkey;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conname = 'transactions_issue32_direction_check'
      AND conrelid = 'public.transactions'::pg_catalog.regclass
  ) THEN
    ALTER TABLE public.transactions
      ADD CONSTRAINT transactions_issue32_direction_check
      CHECK (
        transaction_direction IS NULL
        OR transaction_direction IN ('INFLOW', 'OUTFLOW')
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conname = 'transactions_issue32_source_lineage_check'
      AND conrelid = 'public.transactions'::pg_catalog.regclass
  ) THEN
    ALTER TABLE public.transactions
      ADD CONSTRAINT transactions_issue32_source_lineage_check
      CHECK (
        source_document_id IS NULL
        OR (
          registrar IN ('CAMS', 'KFINTECH')
          AND source_folio_reference_id IS NOT NULL
          AND source_row_number IS NOT NULL
          AND registrar_transaction_code IS NOT NULL
          AND registrar_transaction_code = pg_catalog.upper(pg_catalog.btrim(registrar_transaction_code))
          AND transaction_direction IN ('INFLOW', 'OUTFLOW')
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.ingestion_logs AS log
    WHERE log.status = 'FAILED'
      AND log.attachment_attempt_key IS NOT NULL
      AND log.workspace_id IS NOT NULL
      AND log.mailbox_connection_id IS NOT NULL
      AND log.failure_code IS NOT NULL
    GROUP BY log.workspace_id, log.mailbox_connection_id, log.attachment_attempt_key, log.failure_code
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'issue_32_preflight_duplicate_failure_lineage';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.transactions AS transaction
    WHERE transaction.source_document_id IS NOT NULL
      AND transaction.source_row_number IS NOT NULL
    GROUP BY transaction.source_document_id, transaction.source_row_number
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'issue_32_preflight_duplicate_document_source_row';
  END IF;

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

  IF EXISTS (
    SELECT 1
    FROM public.portfolio_folio_references AS mapping
    GROUP BY mapping.folio_reference_id
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'issue_32_preflight_duplicate_folio_mapping';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.portfolio_folio_references AS mapping
    GROUP BY mapping.portfolio_id, mapping.folio_reference_id
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'issue_32_preflight_duplicate_portfolio_folio_pair';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.portfolios AS portfolio
    WHERE portfolio.workspace_id IS NOT NULL
    GROUP BY portfolio.workspace_id, portfolio.client_id
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'issue_32_preflight_duplicate_portfolio_identity';
  END IF;

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
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS registrar_configs_global_registrar_uidx
  ON public.registrar_configs(registrar)
  WHERE workspace_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ingested_documents_workspace_sha256_uidx
  ON public.ingested_documents(workspace_id, sha256_hex);

CREATE UNIQUE INDEX IF NOT EXISTS ingested_documents_attachment_attempt_uidx
  ON public.ingested_documents(workspace_id, mailbox_connection_id, provider_message_id, provider_attachment_id, sha256_hex);

CREATE UNIQUE INDEX IF NOT EXISTS ingestion_logs_failure_attempt_uidx
  ON public.ingestion_logs(workspace_id, mailbox_connection_id, attachment_attempt_key, failure_code)
  WHERE status = 'FAILED' AND attachment_attempt_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS transactions_source_document_row_uidx
  ON public.transactions(source_document_id, source_row_number)
  WHERE source_document_id IS NOT NULL AND source_row_number IS NOT NULL;

DROP INDEX IF EXISTS public.transactions_source_document_registrar_txn_uidx;

CREATE UNIQUE INDEX IF NOT EXISTS transactions_registrar_folio_txn_uidx
  ON public.transactions(registrar, source_folio_reference_id, registrar_transaction_id)
  WHERE registrar_transaction_id IS NOT NULL
    AND source_folio_reference_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS portfolio_folio_references_pair_uidx
  ON public.portfolio_folio_references(portfolio_id, folio_reference_id);

CREATE UNIQUE INDEX IF NOT EXISTS portfolio_folio_references_folio_uidx
  ON public.portfolio_folio_references(folio_reference_id);

CREATE UNIQUE INDEX IF NOT EXISTS portfolios_workspace_client_uidx
  ON public.portfolios(workspace_id, client_id)
  WHERE workspace_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS transactions_source_folio_reference_idx
  ON public.transactions(source_folio_reference_id)
  WHERE source_folio_reference_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS event_outbox_statement_imported_uidx
  ON public.event_outbox(entity_type, entity_id, event_type)
  WHERE event_type = 'statement.imported';

CREATE INDEX IF NOT EXISTS ingestion_logs_correlation_idx
  ON public.ingestion_logs(correlation_id);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'ingested-documents',
  'ingested-documents',
  false,
  20971519,
  ARRAY[
    'application/pdf',
    'application/x-dbase',
    'application/dbase',
    'application/vnd.dbf',
    'application/octet-stream'
  ]::pg_catalog.text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

ALTER TABLE public.registrar_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mailbox_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mailbox_oauth_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ingested_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ingestion_logs ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.prevent_ingestion_log_modification()
RETURNS pg_catalog.trigger AS $$
BEGIN
  RAISE EXCEPTION 'ingestion_logs_immutable';
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS enforce_ingestion_logs_immutability ON public.ingestion_logs;
CREATE TRIGGER enforce_ingestion_logs_immutability
  BEFORE UPDATE OR DELETE ON public.ingestion_logs
  FOR EACH ROW EXECUTE FUNCTION public.prevent_ingestion_log_modification();

CREATE OR REPLACE FUNCTION public.load_mailbox_oauth_credential_envelope(
  p_workspace_id pg_catalog.uuid,
  p_mailbox_connection_id pg_catalog.uuid
)
RETURNS TABLE (
  credential_ciphertext pg_catalog.text,
  credential_nonce pg_catalog.text,
  key_version pg_catalog.int4,
  expires_at pg_catalog.timestamptz
) AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.mailbox_connections AS mailbox
    WHERE mailbox.id = p_mailbox_connection_id
      AND mailbox.workspace_id = p_workspace_id
      AND mailbox.status = 'active'
  ) THEN
    RAISE EXCEPTION 'mailbox_connection_not_found';
  END IF;

  RETURN QUERY
  SELECT credentials.credential_ciphertext,
         credentials.credential_nonce,
         credentials.key_version,
         credentials.expires_at
  FROM public.mailbox_oauth_credentials AS credentials
  WHERE credentials.workspace_id = p_workspace_id
    AND credentials.mailbox_connection_id = p_mailbox_connection_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable';
  END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.replace_mailbox_oauth_credential_envelope(
  p_workspace_id pg_catalog.uuid,
  p_mailbox_connection_id pg_catalog.uuid,
  p_credential_ciphertext pg_catalog.text,
  p_credential_nonce pg_catalog.text,
  p_key_version pg_catalog.int4,
  p_expires_at pg_catalog.timestamptz DEFAULT NULL
)
RETURNS pg_catalog.void AS $$
BEGIN
  IF p_key_version <> 1 THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable';
  END IF;
  IF p_credential_ciphertext IS NULL OR p_credential_ciphertext = '' THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable';
  END IF;
  BEGIN
    IF p_credential_nonce IS NULL OR pg_catalog.octet_length(pg_catalog.decode(p_credential_nonce, 'base64')) <> 12 THEN
      RAISE EXCEPTION 'oauth_credentials_unavailable';
    END IF;
    PERFORM pg_catalog.decode(p_credential_ciphertext, 'base64');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable';
  END;

  IF NOT EXISTS (
    SELECT 1
    FROM public.mailbox_connections AS mailbox
    WHERE mailbox.id = p_mailbox_connection_id
      AND mailbox.workspace_id = p_workspace_id
      AND mailbox.status = 'active'
  ) THEN
    RAISE EXCEPTION 'mailbox_connection_not_found';
  END IF;

  UPDATE public.mailbox_oauth_credentials AS credentials
  SET credential_ciphertext = p_credential_ciphertext,
      credential_nonce = p_credential_nonce,
      key_version = p_key_version,
      expires_at = p_expires_at,
      refreshed_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  WHERE credentials.workspace_id = p_workspace_id
    AND credentials.mailbox_connection_id = p_mailbox_connection_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable';
  END IF;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.record_cams_kfintech_ingestion_failure(
  p_workspace_id pg_catalog.uuid,
  p_mailbox_connection_id pg_catalog.uuid,
  p_ingestion_run_id pg_catalog.uuid,
  p_document_correlation_id pg_catalog.uuid,
  p_provider_message_id pg_catalog.text,
  p_provider_attachment_id pg_catalog.text,
  p_attachment_attempt_key pg_catalog.text,
  p_registrar pg_catalog.text,
  p_failure_code pg_catalog.text,
  p_attachment_sha256 pg_catalog.text DEFAULT NULL,
  p_storage_bucket pg_catalog.text DEFAULT NULL,
  p_storage_object_path pg_catalog.text DEFAULT NULL,
  p_detected_mime pg_catalog.text DEFAULT NULL,
  p_file_type pg_catalog.text DEFAULT NULL,
  p_size_bytes pg_catalog.int4 DEFAULT NULL
)
RETURNS pg_catalog.uuid AS $$
DECLARE
  v_log_id pg_catalog.uuid;
BEGIN
  IF p_workspace_id IS NULL OR p_mailbox_connection_id IS NULL OR p_ingestion_run_id IS NULL OR p_document_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;
  IF p_registrar NOT IN ('CAMS', 'KFINTECH') THEN
    RAISE EXCEPTION 'unsupported_registrar';
  END IF;
  IF p_failure_code IS NULL OR pg_catalog.btrim(p_failure_code) = '' THEN
    RAISE EXCEPTION 'failure_code_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.mailbox_connections AS mailbox
    WHERE mailbox.id = p_mailbox_connection_id
      AND mailbox.workspace_id = p_workspace_id
      AND mailbox.registrar = p_registrar
  ) THEN
    RAISE EXCEPTION 'mailbox_connection_not_found';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_workspace_id::pg_catalog.text || ':' || p_mailbox_connection_id::pg_catalog.text || ':' || COALESCE(p_attachment_attempt_key, p_document_correlation_id::pg_catalog.text), 0)
  );

  SELECT log.id
  INTO v_log_id
  FROM public.ingestion_logs AS log
  WHERE log.workspace_id = p_workspace_id
    AND log.mailbox_connection_id = p_mailbox_connection_id
    AND log.status = 'FAILED'
    AND log.failure_code = p_failure_code
    AND (
      (p_attachment_attempt_key IS NOT NULL AND log.attachment_attempt_key = p_attachment_attempt_key)
      OR log.correlation_id = p_document_correlation_id
    )
  ORDER BY log.started_at ASC
  LIMIT 1;

  IF v_log_id IS NOT NULL THEN
    RETURN v_log_id;
  END IF;

  INSERT INTO public.ingestion_logs (
    completed_at,
    status,
    records_processed,
    error_message,
    log_details,
    workspace_id,
    mailbox_connection_id,
    registrar,
    attachment_sha256,
    storage_bucket,
    storage_object_path,
    detected_mime,
    file_type,
    size_bytes,
    ingestion_run_id,
    provider_message_id,
    provider_attachment_id,
    attachment_attempt_key,
    correlation_id,
    failure_code
  ) VALUES (
    pg_catalog.now(),
    'FAILED',
    0,
    p_failure_code,
    pg_catalog.jsonb_build_object(
      'failure_code', p_failure_code,
      'ingestion_run_id', p_ingestion_run_id,
      'provider_message_id', p_provider_message_id,
      'provider_attachment_id', p_provider_attachment_id
    ),
    p_workspace_id,
    p_mailbox_connection_id,
    p_registrar,
    p_attachment_sha256,
    p_storage_bucket,
    p_storage_object_path,
    p_detected_mime,
    p_file_type,
    p_size_bytes,
    p_ingestion_run_id,
    p_provider_message_id,
    p_provider_attachment_id,
    p_attachment_attempt_key,
    p_document_correlation_id,
    p_failure_code
  )
  RETURNING id INTO v_log_id;

  IF p_attachment_sha256 IS NOT NULL
     AND p_storage_bucket IS NOT NULL
     AND p_storage_object_path IS NOT NULL
     AND p_detected_mime IS NOT NULL
     AND p_file_type IS NOT NULL
     AND p_size_bytes IS NOT NULL
     AND p_provider_message_id IS NOT NULL
     AND p_provider_attachment_id IS NOT NULL
     AND p_attachment_attempt_key IS NOT NULL THEN
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
      correlation_id,
      ingestion_log_id
    ) VALUES (
      p_workspace_id,
      p_mailbox_connection_id,
      p_ingestion_run_id,
      p_provider_message_id,
      p_provider_attachment_id,
      p_attachment_attempt_key,
      p_registrar,
      p_storage_bucket,
      p_storage_object_path,
      p_attachment_sha256,
      p_detected_mime,
      p_file_type,
      p_size_bytes,
      pg_catalog.now(),
      'failed',
      p_document_correlation_id,
      v_log_id
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN v_log_id;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.persist_cams_kfintech_statement_ingestion(
  p_workspace_id pg_catalog.uuid,
  p_mailbox_connection_id pg_catalog.uuid,
  p_ingestion_run_id pg_catalog.uuid,
  p_document_correlation_id pg_catalog.uuid,
  p_provider_message_id pg_catalog.text,
  p_provider_attachment_id pg_catalog.text,
  p_attachment_attempt_key pg_catalog.text,
  p_registrar pg_catalog.text,
  p_attachment_sha256 pg_catalog.text,
  p_storage_bucket pg_catalog.text,
  p_storage_object_path pg_catalog.text,
  p_detected_mime pg_catalog.text,
  p_file_type pg_catalog.text,
  p_size_bytes pg_catalog.int4,
  p_received_at pg_catalog.timestamptz,
  p_transactions jsonb
)
RETURNS TABLE (
  document_id pg_catalog.uuid,
  ingestion_log_id pg_catalog.uuid,
  outbox_event_id pg_catalog.uuid,
  transaction_count pg_catalog.int4,
  idempotent pg_catalog.bool
) AS $$
DECLARE
  v_mailbox public.mailbox_connections;
  v_existing_document public.ingested_documents;
  v_document_id pg_catalog.uuid;
  v_log_id pg_catalog.uuid;
  v_outbox_id pg_catalog.uuid;
  v_tx jsonb;
  v_profile_id pg_catalog.uuid;
  v_profile_count pg_catalog.int4;
  v_workspace_count pg_catalog.int4;
  v_fund_id pg_catalog.uuid;
  v_portfolio_id pg_catalog.uuid;
  v_portfolio_count pg_catalog.int4;
  v_folio_reference_id pg_catalog.uuid;
  v_normalized_pan pg_catalog.text;
  v_normalized_folio pg_catalog.text;
  v_pan_hmac bytea;
  v_row_number pg_catalog.int4 := 0;
  v_source_row_number pg_catalog.int4;
  v_registrar_transaction_id pg_catalog.text;
  v_registrar_transaction_code pg_catalog.text;
  v_transaction_direction pg_catalog.text;
  v_seen_source_rows pg_catalog.int4[] := ARRAY[]::pg_catalog.int4[];
  v_seen_registrar_transactions pg_catalog.text[] := ARRAY[]::pg_catalog.text[];
  v_transaction_lineage jsonb := '[]'::jsonb;
  v_count pg_catalog.int4 := 0;
  v_expected_count pg_catalog.int4;
BEGIN
  IF p_workspace_id IS NULL OR p_mailbox_connection_id IS NULL OR p_ingestion_run_id IS NULL OR p_document_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;
  IF p_provider_message_id IS NULL OR p_provider_message_id = '' OR p_provider_attachment_id IS NULL OR p_provider_attachment_id = '' OR p_attachment_attempt_key IS NULL OR p_attachment_attempt_key = '' THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;
  IF p_registrar NOT IN ('CAMS', 'KFINTECH') THEN
    RAISE EXCEPTION 'unsupported_registrar';
  END IF;
  IF p_attachment_sha256 IS NULL OR p_attachment_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'attachment_hash_mismatch';
  END IF;
  IF p_file_type NOT IN ('CAS_PDF', 'DBF') THEN
    RAISE EXCEPTION 'unsupported_statement_format';
  END IF;
  IF p_size_bytes IS NULL OR p_size_bytes <= 0 OR p_size_bytes >= 20971520 THEN
    RAISE EXCEPTION 'attachment_too_large';
  END IF;
  IF p_transactions IS NULL OR pg_catalog.jsonb_typeof(p_transactions) <> 'array'
     OR pg_catalog.jsonb_array_length(p_transactions) = 0 THEN
    RAISE EXCEPTION 'parse_failed';
  END IF;
  v_expected_count := pg_catalog.jsonb_array_length(p_transactions);

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_workspace_id::pg_catalog.text || ':' || p_mailbox_connection_id::pg_catalog.text || ':' || p_attachment_attempt_key, 0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_document_correlation_id::pg_catalog.text, 0)
  );

  SELECT *
  INTO v_mailbox
  FROM public.mailbox_connections AS mailbox
  WHERE mailbox.id = p_mailbox_connection_id
    AND mailbox.workspace_id = p_workspace_id
    AND mailbox.registrar = p_registrar
    AND mailbox.status = 'active'
  FOR SHARE;

  IF v_mailbox.id IS NULL THEN
    RAISE EXCEPTION 'mailbox_connection_not_found';
  END IF;

  SELECT *
  INTO v_existing_document
  FROM public.ingested_documents AS document
  WHERE document.correlation_id = p_document_correlation_id
     OR (
       document.workspace_id = p_workspace_id
       AND document.mailbox_connection_id = p_mailbox_connection_id
       AND document.provider_message_id = p_provider_message_id
       AND document.provider_attachment_id = p_provider_attachment_id
       AND document.sha256_hex = p_attachment_sha256
     )
  ORDER BY document.created_at ASC
  LIMIT 1;

  IF v_existing_document.id IS NOT NULL THEN
    IF v_existing_document.workspace_id IS DISTINCT FROM p_workspace_id
       OR v_existing_document.mailbox_connection_id IS DISTINCT FROM p_mailbox_connection_id
       OR v_existing_document.registrar IS DISTINCT FROM p_registrar
       OR v_existing_document.sha256_hex IS DISTINCT FROM p_attachment_sha256
       OR v_existing_document.provider_message_id IS DISTINCT FROM p_provider_message_id
       OR v_existing_document.provider_attachment_id IS DISTINCT FROM p_provider_attachment_id THEN
      RAISE EXCEPTION 'correlation_conflict';
    END IF;

    IF v_existing_document.processing_status = 'failed' THEN
      RAISE EXCEPTION 'previous_ingestion_failed';
    END IF;
    IF v_existing_document.processing_status <> 'completed' THEN
      RAISE EXCEPTION 'processing_incomplete';
    END IF;

    SELECT event.id
    INTO v_outbox_id
    FROM public.event_outbox AS event
    WHERE event.entity_type = 'ingested_document'
      AND event.entity_id = v_existing_document.id
      AND event.event_type = 'statement.imported';

    SELECT pg_catalog.count(*)::pg_catalog.int4
    INTO v_count
    FROM public.transactions AS transaction
    WHERE transaction.source_document_id = v_existing_document.id;

    IF v_existing_document.ingestion_log_id IS NULL OR v_outbox_id IS NULL OR v_count <> v_expected_count THEN
      RAISE EXCEPTION 'processing_incomplete';
    END IF;

    RETURN QUERY SELECT v_existing_document.id, v_existing_document.ingestion_log_id, v_outbox_id, v_count, true;
    RETURN;
  END IF;

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
    p_workspace_id,
    p_mailbox_connection_id,
    p_ingestion_run_id,
    p_provider_message_id,
    p_provider_attachment_id,
    p_attachment_attempt_key,
    p_registrar,
    p_storage_bucket,
    p_storage_object_path,
    p_attachment_sha256,
    p_detected_mime,
    p_file_type,
    p_size_bytes,
    COALESCE(p_received_at, pg_catalog.now()),
    'processing',
    p_document_correlation_id
  )
  RETURNING id INTO v_document_id;

  FOR v_tx IN SELECT * FROM pg_catalog.jsonb_array_elements(p_transactions) LOOP
    v_row_number := v_row_number + 1;
    v_profile_id := NULL;
    v_portfolio_id := NULL;
    v_folio_reference_id := NULL;
    v_registrar_transaction_id := NULL;
    v_registrar_transaction_code := NULL;
    v_transaction_direction := NULL;

    IF COALESCE(v_tx ->> 'folioNumber', '') = ''
       OR COALESCE(v_tx ->> 'schemeCode', '') = ''
       OR COALESCE(v_tx ->> 'transactionType', '') NOT IN ('BUY', 'SELL', 'SWITCH')
       OR COALESCE(v_tx ->> 'transactionDirection', '') NOT IN ('INFLOW', 'OUTFLOW')
       OR COALESCE(v_tx ->> 'registrarTransactionCode', '') = ''
       OR COALESCE(v_tx ->> 'date', '') = ''
       OR COALESCE(v_tx ->> 'clientPan', '') = ''
       OR COALESCE(v_tx ->> 'sourceRowNumber', '') !~ '^[0-9]+$'
       OR COALESCE(v_tx ->> 'amount', '') !~ '^[0-9]+(\.[0-9]+)?$'
       OR COALESCE(v_tx ->> 'units', '') !~ '^[0-9]+(\.[0-9]+)?$'
       OR COALESCE(v_tx ->> 'nav', '') !~ '^[0-9]+(\.[0-9]+)?$'
       OR (v_tx ->> 'amount')::pg_catalog.numeric <= 0
       OR (v_tx ->> 'units')::pg_catalog.numeric <= 0
       OR (v_tx ->> 'nav')::pg_catalog.numeric <= 0 THEN
      RAISE EXCEPTION 'parse_failed';
    END IF;
    v_source_row_number := (v_tx ->> 'sourceRowNumber')::pg_catalog.int4;
    IF v_source_row_number <= 0 THEN
      RAISE EXCEPTION 'parse_failed';
    END IF;
    IF v_source_row_number = ANY(v_seen_source_rows) THEN
      RAISE EXCEPTION 'persistence_conflict';
    END IF;
    v_seen_source_rows := pg_catalog.array_append(v_seen_source_rows, v_source_row_number);

    v_normalized_folio := pg_catalog.upper(pg_catalog.regexp_replace(v_tx ->> 'folioNumber', '[^A-Za-z0-9]', '', 'g'));
    IF v_normalized_folio = '' THEN
      RAISE EXCEPTION 'parse_failed';
    END IF;

    v_registrar_transaction_code := pg_catalog.upper(pg_catalog.btrim(v_tx ->> 'registrarTransactionCode'));
    IF v_registrar_transaction_code = '' OR v_registrar_transaction_code <> (v_tx ->> 'registrarTransactionCode') THEN
      RAISE EXCEPTION 'parse_failed';
    END IF;
    v_transaction_direction := v_tx ->> 'transactionDirection';

    IF NOT (
      (
        p_registrar = 'CAMS'
        AND (
          (v_registrar_transaction_code IN ('BUY', 'PURCHASE', 'PUR', 'SIP') AND v_tx ->> 'transactionType' = 'BUY' AND v_transaction_direction = 'INFLOW')
          OR (v_registrar_transaction_code IN ('SELL', 'REDEMPTION', 'RED') AND v_tx ->> 'transactionType' = 'SELL' AND v_transaction_direction = 'OUTFLOW')
          OR (v_registrar_transaction_code IN ('SWITCHIN', 'SWITCH_IN') AND v_tx ->> 'transactionType' = 'SWITCH' AND v_transaction_direction = 'INFLOW')
          OR (v_registrar_transaction_code IN ('SWITCHOUT', 'SWITCH_OUT') AND v_tx ->> 'transactionType' = 'SWITCH' AND v_transaction_direction = 'OUTFLOW')
        )
      )
      OR (
        p_registrar = 'KFINTECH'
        AND (
          (v_registrar_transaction_code IN ('P', 'PURCHASE', 'ADDITIONAL_PURCHASE', 'SIP') AND v_tx ->> 'transactionType' = 'BUY' AND v_transaction_direction = 'INFLOW')
          OR (v_registrar_transaction_code IN ('R', 'REDEMPTION', 'FULL_REDEMPTION') AND v_tx ->> 'transactionType' = 'SELL' AND v_transaction_direction = 'OUTFLOW')
          OR (v_registrar_transaction_code IN ('SI', 'SWITCH_IN') AND v_tx ->> 'transactionType' = 'SWITCH' AND v_transaction_direction = 'INFLOW')
          OR (v_registrar_transaction_code IN ('SO', 'SWITCH_OUT') AND v_tx ->> 'transactionType' = 'SWITCH' AND v_transaction_direction = 'OUTFLOW')
        )
      )
    ) THEN
      RAISE EXCEPTION 'parse_failed';
    END IF;

    v_registrar_transaction_id := NULLIF(pg_catalog.btrim(COALESCE(v_tx ->> 'registrarTransactionId', '')), '');
    IF v_registrar_transaction_id IS NOT NULL THEN
      IF v_normalized_folio || ':' || v_registrar_transaction_id = ANY(v_seen_registrar_transactions) THEN
        RAISE EXCEPTION 'persistence_conflict';
      END IF;
      v_seen_registrar_transactions := pg_catalog.array_append(v_seen_registrar_transactions, v_normalized_folio || ':' || v_registrar_transaction_id);
    END IF;

    v_normalized_pan := public.normalize_pan(v_tx ->> 'clientPan');
    IF v_normalized_pan IS NULL THEN
      RAISE EXCEPTION 'parse_failed';
    END IF;

    v_pan_hmac := extensions.hmac(v_normalized_pan, public.pan_lookup_hmac_key(), 'sha256');
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(pg_catalog.encode(v_pan_hmac, 'hex'), 0));

    SELECT pg_catalog.count(DISTINCT profile.id)::pg_catalog.int4
    INTO v_profile_count
    FROM public.profile_pan_records AS pan_record
    JOIN public.profiles AS profile
      ON profile.id = pan_record.profile_id
     AND profile.canonical_pan_record_id = pan_record.id
    WHERE pan_record.pan_lookup_hmac = v_pan_hmac
      AND pan_record.status = 'VERIFIED'
      AND profile.role IN ('client', 'investor');

    IF v_profile_count = 0 THEN
      RAISE EXCEPTION 'investor_mapping_unresolved';
    ELSIF v_profile_count > 1 THEN
      RAISE EXCEPTION 'investor_mapping_ambiguous';
    END IF;

    SELECT profile.id
    INTO v_profile_id
    FROM public.profile_pan_records AS pan_record
    JOIN public.profiles AS profile
      ON profile.id = pan_record.profile_id
     AND profile.canonical_pan_record_id = pan_record.id
    WHERE pan_record.pan_lookup_hmac = v_pan_hmac
      AND pan_record.status = 'VERIFIED'
      AND profile.role IN ('client', 'investor');

    SELECT pg_catalog.count(*)::pg_catalog.int4
    INTO v_workspace_count
    FROM public.workspace_memberships AS membership
    WHERE membership.workspace_id = p_workspace_id
      AND membership.profile_id = v_profile_id
      AND membership.status = 'active'
      AND membership.ended_at IS NULL
      AND membership.role IN ('investor', 'client');

    IF v_workspace_count <> 1 THEN
      RAISE EXCEPTION 'investor_workspace_relationship_required';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(p_workspace_id::pg_catalog.text || ':' || v_profile_id::pg_catalog.text, 0)
    );

    INSERT INTO public.mutual_funds (
      scheme_code,
      scheme_name,
      fund_house,
      category
    ) VALUES (
      v_tx ->> 'schemeCode',
      COALESCE(v_tx ->> 'schemeName', v_tx ->> 'schemeCode'),
      COALESCE(v_tx ->> 'fundHouse', 'Mutual Fund'),
      COALESCE(v_tx ->> 'category', 'Mutual Fund')
    )
    ON CONFLICT (scheme_code) DO UPDATE
    SET scheme_name = EXCLUDED.scheme_name,
        fund_house = COALESCE(public.mutual_funds.fund_house, EXCLUDED.fund_house),
        category = COALESCE(public.mutual_funds.category, EXCLUDED.category)
    RETURNING id INTO v_fund_id;

    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(p_registrar || ':' || v_normalized_folio, 0)
    );

    INSERT INTO public.folio_references (
      registrar,
      normalized_folio_number,
      amc_identity,
      source_folio_masked
    ) VALUES (
      p_registrar,
      v_normalized_folio,
      COALESCE(v_tx ->> 'fundHouse', p_registrar),
      '****' || pg_catalog.right(v_normalized_folio, 4)
    )
    ON CONFLICT (registrar, normalized_folio_number) DO NOTHING;

    SELECT folio.id
    INTO v_folio_reference_id
    FROM public.folio_references AS folio
    WHERE folio.registrar = p_registrar
      AND folio.normalized_folio_number = v_normalized_folio
    FOR UPDATE;

    IF v_folio_reference_id IS NULL THEN
      RAISE EXCEPTION 'folio_relationship_conflict';
    END IF;

    SELECT pg_catalog.count(*)::pg_catalog.int4
    INTO v_portfolio_count
    FROM public.portfolios AS portfolio
    WHERE portfolio.workspace_id = p_workspace_id
      AND portfolio.client_id = v_profile_id;

    IF v_portfolio_count > 1 THEN
      RAISE EXCEPTION 'portfolio_mapping_ambiguous';
    ELSIF v_portfolio_count = 1 THEN
      SELECT portfolio.id
      INTO v_portfolio_id
      FROM public.portfolios AS portfolio
      WHERE portfolio.workspace_id = p_workspace_id
        AND portfolio.client_id = v_profile_id
      FOR UPDATE;
    ELSE
      INSERT INTO public.portfolios (
        client_id,
        workspace_id,
        total_invested_value,
        current_market_value
      ) VALUES (
        v_profile_id,
        p_workspace_id,
        0.00,
        0.00
      )
      RETURNING id INTO v_portfolio_id;
    END IF;

    SELECT pg_catalog.count(*)::pg_catalog.int4
    INTO v_portfolio_count
    FROM public.portfolio_folio_references AS mapping
    WHERE mapping.folio_reference_id = v_folio_reference_id;

    IF v_portfolio_count > 0 THEN
      SELECT portfolio.id
      INTO v_portfolio_id
      FROM public.portfolio_folio_references AS mapping
      JOIN public.portfolios AS portfolio
        ON portfolio.id = mapping.portfolio_id
      WHERE mapping.folio_reference_id = v_folio_reference_id
        AND portfolio.client_id = v_profile_id
        AND portfolio.workspace_id = p_workspace_id;

      IF v_portfolio_id IS NULL THEN
        RAISE EXCEPTION 'folio_relationship_conflict';
      END IF;
    ELSE
      INSERT INTO public.portfolio_folio_references (
        portfolio_id,
        folio_reference_id
      ) VALUES (
        v_portfolio_id,
        v_folio_reference_id
      );
    END IF;

    BEGIN
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
        v_tx ->> 'transactionType',
        (v_tx ->> 'units')::pg_catalog.numeric,
        (v_tx ->> 'nav')::pg_catalog.numeric,
        (v_tx ->> 'amount')::pg_catalog.numeric,
        (v_tx ->> 'date')::pg_catalog.date,
        p_registrar,
        v_document_id,
        v_source_row_number,
        p_attachment_sha256,
        v_registrar_transaction_id,
        v_registrar_transaction_code,
        v_transaction_direction,
        v_folio_reference_id
      );
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'persistence_conflict';
    END;

    v_transaction_lineage := v_transaction_lineage || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'source_row_number', v_source_row_number,
        'folio_reference_id', v_folio_reference_id,
        'registrar_transaction_id', v_registrar_transaction_id,
        'registrar_transaction_code', v_registrar_transaction_code,
        'transaction_type', v_tx ->> 'transactionType',
        'transaction_direction', v_transaction_direction
      )
    );

    v_count := v_count + 1;
  END LOOP;

  IF v_count <> v_expected_count THEN
    RAISE EXCEPTION 'persistence_conflict';
  END IF;

  INSERT INTO public.ingestion_logs (
    completed_at,
    status,
    records_processed,
    log_details,
    workspace_id,
    mailbox_connection_id,
    document_id,
    registrar,
    attachment_sha256,
    storage_bucket,
    storage_object_path,
    detected_mime,
    file_type,
    size_bytes,
    ingestion_run_id,
    provider_message_id,
    provider_attachment_id,
    attachment_attempt_key,
    correlation_id
  ) VALUES (
    pg_catalog.now(),
    'SUCCESS',
    v_count,
    pg_catalog.jsonb_build_object(
      'event_type', 'statement.imported',
      'registrar', p_registrar,
      'transaction_count', v_count,
      'transaction_lineage', v_transaction_lineage,
      'ingestion_run_id', p_ingestion_run_id,
      'provider_message_id', p_provider_message_id,
      'provider_attachment_id', p_provider_attachment_id
    ),
    p_workspace_id,
    p_mailbox_connection_id,
    v_document_id,
    p_registrar,
    p_attachment_sha256,
    p_storage_bucket,
    p_storage_object_path,
    p_detected_mime,
    p_file_type,
    p_size_bytes,
    p_ingestion_run_id,
    p_provider_message_id,
    p_provider_attachment_id,
    p_attachment_attempt_key,
    p_document_correlation_id
  )
  RETURNING id INTO v_log_id;

  UPDATE public.ingested_documents
  SET processing_status = 'completed',
      ingestion_log_id = v_log_id,
      updated_at = pg_catalog.now()
  WHERE id = v_document_id;

  INSERT INTO public.event_outbox (
    event_type,
    entity_id,
    entity_type,
    payload,
    status
  ) VALUES (
    'statement.imported',
    v_document_id,
    'ingested_document',
    pg_catalog.jsonb_build_object(
      'document_id', v_document_id,
      'workspace_id', p_workspace_id,
      'mailbox_connection_id', p_mailbox_connection_id,
      'ingestion_run_id', p_ingestion_run_id,
      'provider_message_id', p_provider_message_id,
      'provider_attachment_id', p_provider_attachment_id,
      'registrar', p_registrar,
      'sha256', p_attachment_sha256,
      'transaction_count', v_count,
      'transaction_lineage', v_transaction_lineage
    ),
    'pending'
  )
  ON CONFLICT (entity_type, entity_id, event_type) WHERE event_type = 'statement.imported' DO NOTHING;

  SELECT event.id
  INTO v_outbox_id
  FROM public.event_outbox AS event
  WHERE event.entity_type = 'ingested_document'
    AND event.entity_id = v_document_id
    AND event.event_type = 'statement.imported';

  RETURN QUERY SELECT v_document_id, v_log_id, v_outbox_id, v_count, false;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON TABLE public.registrar_configs FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.mailbox_connections FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.mailbox_oauth_credentials FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.ingested_documents FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.ingestion_logs FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.registrar_configs TO service_role;
GRANT SELECT ON TABLE public.mailbox_connections TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.ingested_documents TO service_role;

REVOKE ALL ON FUNCTION public.prevent_ingestion_log_modification() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.load_mailbox_oauth_credential_envelope(pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.replace_mailbox_oauth_credential_envelope(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.int4, pg_catalog.timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_cams_kfintech_ingestion_failure(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.int4
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.persist_cams_kfintech_statement_ingestion(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.int4,
  pg_catalog.timestamptz,
  jsonb
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.load_mailbox_oauth_credential_envelope(pg_catalog.uuid, pg_catalog.uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.replace_mailbox_oauth_credential_envelope(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.int4, pg_catalog.timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_cams_kfintech_ingestion_failure(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.int4
) TO service_role;
GRANT EXECUTE ON FUNCTION public.persist_cams_kfintech_statement_ingestion(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.int4,
  pg_catalog.timestamptz,
  jsonb
) TO service_role;

COMMIT;
