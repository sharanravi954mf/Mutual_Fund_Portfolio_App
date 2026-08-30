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
  idempotent pg_catalog.bool,
  failure_code pg_catalog.text
) AS $$
DECLARE
  v_mailbox public.mailbox_connections;
  v_existing_document public.ingested_documents;
  v_correlation_document public.ingested_documents;
  v_provider_document public.ingested_documents;
  v_digest_document public.ingested_documents;
  v_existing_folio public.folio_references;
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
  v_amc_identity pg_catalog.text;
  v_incoming_fund_house pg_catalog.text;
  v_existing_fund_house pg_catalog.text;
  v_incoming_amc_key pg_catalog.text;
  v_existing_amc_key pg_catalog.text;
  v_amc_key pg_catalog.text;
  v_category pg_catalog.text;
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
  v_constraint_name pg_catalog.text;
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

  -- Issue #32 mutation lock order: run advisory, run row, attempt identity,
  -- provider identity, document correlation, content digest, investor graph.
  PERFORM public.assert_claimed_cams_kfintech_ingestion_run(
    p_workspace_id,
    p_mailbox_connection_id,
    p_ingestion_run_id,
    p_registrar
  );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_workspace_id::pg_catalog.text || ':' || p_mailbox_connection_id::pg_catalog.text || ':' || p_attachment_attempt_key, 0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_workspace_id::pg_catalog.text || ':' || p_mailbox_connection_id::pg_catalog.text || ':' || p_provider_message_id || ':' || p_provider_attachment_id, 0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_document_correlation_id::pg_catalog.text, 0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_workspace_id::pg_catalog.text || ':' || p_attachment_sha256, 0)
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
  INTO v_correlation_document
  FROM public.ingested_documents AS document
  WHERE document.correlation_id = p_document_correlation_id
  FOR UPDATE;

  SELECT *
  INTO v_provider_document
  FROM public.ingested_documents AS document
  WHERE document.workspace_id = p_workspace_id
    AND document.mailbox_connection_id = p_mailbox_connection_id
    AND document.provider_message_id = p_provider_message_id
    AND document.provider_attachment_id = p_provider_attachment_id
  FOR UPDATE;

  SELECT *
  INTO v_digest_document
  FROM public.ingested_documents AS document
  WHERE document.workspace_id = p_workspace_id
    AND document.sha256_hex = p_attachment_sha256
  FOR UPDATE;

  IF v_correlation_document.id IS NOT NULL THEN
    IF v_correlation_document.workspace_id IS DISTINCT FROM p_workspace_id
       OR v_correlation_document.mailbox_connection_id IS DISTINCT FROM p_mailbox_connection_id
       OR v_correlation_document.registrar IS DISTINCT FROM p_registrar
       OR v_correlation_document.provider_message_id IS DISTINCT FROM p_provider_message_id
       OR v_correlation_document.provider_attachment_id IS DISTINCT FROM p_provider_attachment_id THEN
      RAISE EXCEPTION 'correlation_conflict';
    END IF;
    IF v_correlation_document.sha256_hex IS DISTINCT FROM p_attachment_sha256 THEN
      v_log_id := public.record_cams_kfintech_ingestion_failure(
        p_workspace_id,
        p_mailbox_connection_id,
        p_ingestion_run_id,
        p_document_correlation_id,
        p_provider_message_id,
        p_provider_attachment_id,
        p_attachment_attempt_key,
        p_registrar,
        'attachment_hash_mismatch',
        p_attachment_sha256,
        p_storage_bucket,
        p_storage_object_path,
        p_detected_mime,
        p_file_type,
        p_size_bytes
      );
      RETURN QUERY SELECT v_correlation_document.id, v_log_id, NULL::pg_catalog.uuid, 0::pg_catalog.int4, true, 'attachment_hash_mismatch'::pg_catalog.text;
      RETURN;
    END IF;
    v_existing_document := v_correlation_document;
  END IF;

  IF v_provider_document.id IS NOT NULL THEN
    IF v_existing_document.id IS NOT NULL AND v_existing_document.id IS DISTINCT FROM v_provider_document.id THEN
      RAISE EXCEPTION 'correlation_conflict';
    END IF;
    IF v_provider_document.registrar IS DISTINCT FROM p_registrar
       OR v_provider_document.correlation_id IS DISTINCT FROM p_document_correlation_id THEN
      RAISE EXCEPTION 'correlation_conflict';
    END IF;
    IF v_provider_document.sha256_hex IS DISTINCT FROM p_attachment_sha256 THEN
      v_log_id := public.record_cams_kfintech_ingestion_failure(
        p_workspace_id,
        p_mailbox_connection_id,
        p_ingestion_run_id,
        p_document_correlation_id,
        p_provider_message_id,
        p_provider_attachment_id,
        p_attachment_attempt_key,
        p_registrar,
        'attachment_hash_mismatch',
        p_attachment_sha256,
        p_storage_bucket,
        p_storage_object_path,
        p_detected_mime,
        p_file_type,
        p_size_bytes
      );
      RETURN QUERY SELECT v_provider_document.id, v_log_id, NULL::pg_catalog.uuid, 0::pg_catalog.int4, true, 'attachment_hash_mismatch'::pg_catalog.text;
      RETURN;
    END IF;
    v_existing_document := v_provider_document;
  END IF;

  IF v_digest_document.id IS NOT NULL THEN
    IF v_existing_document.id IS NOT NULL AND v_existing_document.id IS DISTINCT FROM v_digest_document.id THEN
      v_log_id := public.record_cams_kfintech_ingestion_failure(
        p_workspace_id,
        p_mailbox_connection_id,
        p_ingestion_run_id,
        p_document_correlation_id,
        p_provider_message_id,
        p_provider_attachment_id,
        p_attachment_attempt_key,
        p_registrar,
        'duplicate_attachment',
        p_attachment_sha256,
        p_storage_bucket,
        p_storage_object_path,
        p_detected_mime,
        p_file_type,
        p_size_bytes
      );
      RETURN QUERY SELECT v_digest_document.id, v_log_id, NULL::pg_catalog.uuid, 0::pg_catalog.int4, true, 'duplicate_attachment'::pg_catalog.text;
      RETURN;
    END IF;
    IF v_digest_document.workspace_id IS DISTINCT FROM p_workspace_id
       OR v_digest_document.mailbox_connection_id IS DISTINCT FROM p_mailbox_connection_id
       OR v_digest_document.provider_message_id IS DISTINCT FROM p_provider_message_id
       OR v_digest_document.provider_attachment_id IS DISTINCT FROM p_provider_attachment_id THEN
      v_log_id := public.record_cams_kfintech_ingestion_failure(
        p_workspace_id,
        p_mailbox_connection_id,
        p_ingestion_run_id,
        p_document_correlation_id,
        p_provider_message_id,
        p_provider_attachment_id,
        p_attachment_attempt_key,
        p_registrar,
        'duplicate_attachment',
        p_attachment_sha256,
        p_storage_bucket,
        p_storage_object_path,
        p_detected_mime,
        p_file_type,
        p_size_bytes
      );
      RETURN QUERY SELECT v_digest_document.id, v_log_id, NULL::pg_catalog.uuid, 0::pg_catalog.int4, true, 'duplicate_attachment'::pg_catalog.text;
      RETURN;
    END IF;
    v_existing_document := v_digest_document;
  END IF;

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

    PERFORM public.record_cams_kfintech_ingestion_attempt(
      p_ingestion_run_id,
      p_workspace_id,
      p_mailbox_connection_id,
      p_provider_message_id,
      p_provider_attachment_id,
      p_attachment_attempt_key,
      p_document_correlation_id,
      v_existing_document.id,
      v_existing_document.ingestion_log_id,
      p_attachment_sha256,
      p_storage_bucket,
      p_storage_object_path,
      p_detected_mime,
      p_file_type,
      p_size_bytes,
      'succeeded',
      NULL
    );

    RETURN QUERY SELECT v_existing_document.id, v_existing_document.ingestion_log_id, v_outbox_id, v_count, true, NULL::pg_catalog.text;
    RETURN;
  END IF;

  BEGIN
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
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'ingested_documents_workspace_sha256_uidx' OR v_constraint_name = 'ingested_documents_workspace_id_sha256_hex_key' THEN
      RAISE EXCEPTION 'duplicate_attachment';
    ELSIF v_constraint_name = 'ingested_documents_provider_attachment_uidx' THEN
      RAISE EXCEPTION 'attachment_hash_mismatch';
    ELSIF v_constraint_name = 'ingested_documents_correlation_id_key' THEN
      RAISE EXCEPTION 'correlation_conflict';
    ELSE
      RAISE EXCEPTION 'persistence_conflict';
    END IF;
  END;

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
          (v_registrar_transaction_code IN ('BUY', 'PURCHASE', 'PUR', 'SIP', 'ADDITIONAL_PURCHASE', 'ADDITIONAL_PURCHASE_SYSTEMATIC', 'FRESH_PURCHASE_SYSTEMATIC', 'NFO_FP') AND v_tx ->> 'transactionType' = 'BUY' AND v_transaction_direction = 'INFLOW')
          OR (v_registrar_transaction_code IN ('SELL', 'REDEMPTION', 'RED', 'FULL_REDEMPTION') AND v_tx ->> 'transactionType' = 'SELL' AND v_transaction_direction = 'OUTFLOW')
          OR (v_registrar_transaction_code IN ('SWITCHIN', 'SWITCH_IN') AND v_tx ->> 'transactionType' = 'SWITCH' AND v_transaction_direction = 'INFLOW')
          OR (v_registrar_transaction_code IN ('SWITCHOUT', 'SWITCH_OUT', 'PARTIAL_SWITCH_OUT') AND v_tx ->> 'transactionType' = 'SWITCH' AND v_transaction_direction = 'OUTFLOW')
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

    v_incoming_fund_house := NULLIF(pg_catalog.regexp_replace(pg_catalog.btrim(COALESCE(v_tx ->> 'fundHouse', '')), '\s+', ' ', 'g'), '');
    v_category := NULLIF(pg_catalog.btrim(COALESCE(v_tx ->> 'category', '')), '');
    v_incoming_amc_key := public.normalize_cams_kfintech_amc_identity(v_incoming_fund_house);
    IF v_incoming_amc_key IS NULL THEN
      v_incoming_fund_house := NULL;
    END IF;

    SELECT NULLIF(pg_catalog.regexp_replace(pg_catalog.btrim(COALESCE(fund.fund_house, '')), '\s+', ' ', 'g'), '')
    INTO v_existing_fund_house
    FROM public.mutual_funds AS fund
    WHERE fund.scheme_code = v_tx ->> 'schemeCode'
    FOR UPDATE;
    v_existing_amc_key := public.normalize_cams_kfintech_amc_identity(v_existing_fund_house);
    IF v_existing_amc_key IS NULL THEN
      v_existing_fund_house := NULL;
    END IF;

    IF v_existing_amc_key IS NOT NULL
       AND v_incoming_amc_key IS NOT NULL
       AND v_existing_amc_key IS DISTINCT FROM v_incoming_amc_key THEN
      RAISE EXCEPTION 'amc_mapping_conflict';
    END IF;

    v_amc_identity := COALESCE(v_existing_fund_house, v_incoming_fund_house);
    v_amc_key := COALESCE(v_existing_amc_key, v_incoming_amc_key);
    IF v_amc_identity IS NULL THEN
      RAISE EXCEPTION 'amc_mapping_unresolved';
    END IF;

    INSERT INTO public.mutual_funds (
      scheme_code,
      scheme_name,
      fund_house,
      category
    ) VALUES (
      v_tx ->> 'schemeCode',
      COALESCE(v_tx ->> 'schemeName', v_tx ->> 'schemeCode'),
      v_amc_identity,
      v_category
    )
    ON CONFLICT (scheme_code) DO UPDATE
    SET scheme_name = EXCLUDED.scheme_name,
        fund_house = CASE
          WHEN public.normalize_cams_kfintech_amc_identity(public.mutual_funds.fund_house) IS NULL
          THEN EXCLUDED.fund_house
          ELSE public.mutual_funds.fund_house
        END,
        category = COALESCE(public.mutual_funds.category, EXCLUDED.category)
    RETURNING id INTO v_fund_id;

    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(p_registrar || ':' || v_normalized_folio, 0)
    );

    SELECT *
    INTO v_existing_folio
    FROM public.folio_references AS folio
    WHERE folio.registrar = p_registrar
      AND folio.normalized_folio_number = v_normalized_folio
    FOR UPDATE;

    IF v_existing_folio.id IS NULL THEN
      INSERT INTO public.folio_references (
        registrar,
        normalized_folio_number,
        amc_identity,
        source_folio_masked
      ) VALUES (
        p_registrar,
        v_normalized_folio,
        v_amc_identity,
        '****' || pg_catalog.right(v_normalized_folio, 4)
      )
      RETURNING id INTO v_folio_reference_id;
    ELSE
      IF public.normalize_cams_kfintech_amc_identity(v_existing_folio.amc_identity) IS DISTINCT FROM v_amc_key THEN
        RAISE EXCEPTION 'folio_relationship_conflict';
      END IF;
      v_folio_reference_id := v_existing_folio.id;
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
    JOIN public.portfolios AS portfolio
      ON portfolio.id = mapping.portfolio_id
    WHERE mapping.folio_reference_id = v_folio_reference_id
      AND portfolio.workspace_id = p_workspace_id;

    IF v_portfolio_count > 1 THEN
      RAISE EXCEPTION 'portfolio_mapping_ambiguous';
    ELSIF v_portfolio_count = 1 THEN
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
        folio_reference_id,
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
        v_folio_reference_id,
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

  PERFORM public.record_cams_kfintech_ingestion_attempt(
    p_ingestion_run_id,
    p_workspace_id,
    p_mailbox_connection_id,
    p_provider_message_id,
    p_provider_attachment_id,
    p_attachment_attempt_key,
    p_document_correlation_id,
    v_document_id,
    v_log_id,
    p_attachment_sha256,
    p_storage_bucket,
    p_storage_object_path,
    p_detected_mime,
    p_file_type,
    p_size_bytes,
    'succeeded',
    NULL
  );

  RETURN QUERY SELECT v_document_id, v_log_id, v_outbox_id, v_count, false, NULL::pg_catalog.text;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';
