-- Client Master is a READ_ONLY operation. These transient HTTP statuses can
-- safely use the existing bounded event-outbox retry path.
CREATE OR REPLACE FUNCTION public.finish_nse_ucc_verification(
  p_event_outbox_id pg_catalog.uuid, p_claim_token pg_catalog.uuid, p_call_id pg_catalog.uuid,
  p_response_payload pg_catalog.text, p_response_content_type pg_catalog.text,
  p_response_header_metadata pg_catalog.jsonb, p_http_status pg_catalog.int4,
  p_native_status_value pg_catalog.text, p_native_remark_category pg_catalog.text,
  p_normalized_outcome pg_catalog.text, p_error_category pg_catalog.text,
  p_timeout_occurred pg_catalog.bool, p_network_failure pg_catalog.bool,
  p_completed_at pg_catalog.timestamptz, p_elapsed_ms pg_catalog.int8,
  p_max_attempts pg_catalog.int4 DEFAULT 3
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_request public.integration_api_interactions;
  v_existing public.integration_api_interactions;
  v_event public.event_outbox;
  v_operation public.integration_operations;
  v_interaction public.integration_api_interactions;
  v_target_request public.integration_api_interactions;
  v_registration_json pg_catalog.jsonb;
  v_response_json pg_catalog.jsonb;
  v_exact_match pg_catalog.bool := false;
  v_retry_allowed pg_catalog.bool := false;
  v_retryable_http_status pg_catalog.bool := false;
  v_bytes pg_catalog.int8;
  v_hash pg_catalog.bytea;
  v_key pg_catalog.text := 'integration_payload_encryption_key_v1';
  v_state pg_catalog.text;
  v_event_status pg_catalog.text := 'completed';
BEGIN
  IF p_completed_at IS NULL OR p_elapsed_ms < 0 OR p_max_attempts < 1 OR p_max_attempts > 5
     OR p_normalized_outcome NOT IN ('SUCCESS', 'BUSINESS_FAILURE', 'HTTP_FAILURE', 'TRANSPORT_FAILURE') THEN
    RAISE EXCEPTION 'verification_result_invalid';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_call_id::pg_catalog.text, 0));
  SELECT * INTO v_request FROM public.integration_api_interactions interaction
  WHERE interaction.call_id = p_call_id AND interaction.phase = 'REQUEST';
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'integration_request_evidence_missing'; END IF;
  IF NOT public.integration_header_metadata_is_safe(p_response_header_metadata, 'RESULT') THEN
    RAISE EXCEPTION 'unsafe_response_header_metadata';
  END IF;

  v_bytes := pg_catalog.octet_length(pg_catalog.convert_to(COALESCE(p_response_payload, ''), 'UTF8'));
  v_hash := extensions.digest(pg_catalog.convert_to(COALESCE(p_response_payload, ''), 'UTF8'), 'sha256');
  SELECT * INTO v_existing FROM public.integration_api_interactions interaction
  WHERE interaction.call_id = p_call_id AND interaction.phase = 'RESULT';
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.integration_operation_id IS DISTINCT FROM v_request.integration_operation_id
       OR v_existing.attempt_number IS DISTINCT FROM v_request.attempt_number
       OR v_existing.correlation_id IS DISTINCT FROM v_request.correlation_id
       OR v_existing.response_hash IS DISTINCT FROM v_hash OR v_existing.response_bytes IS DISTINCT FROM v_bytes
       OR v_existing.response_content_type IS DISTINCT FROM p_response_content_type
       OR v_existing.response_header_metadata IS DISTINCT FROM p_response_header_metadata
       OR v_existing.http_status IS DISTINCT FROM p_http_status
       OR v_existing.native_status_value IS DISTINCT FROM p_native_status_value
       OR v_existing.native_remark_category IS DISTINCT FROM p_native_remark_category
       OR v_existing.normalized_outcome IS DISTINCT FROM p_normalized_outcome
       OR v_existing.error_category IS DISTINCT FROM p_error_category
       OR v_existing.timeout_occurred IS DISTINCT FROM COALESCE(p_timeout_occurred, false)
       OR v_existing.network_failure IS DISTINCT FROM COALESCE(p_network_failure, false)
       OR v_existing.completed_at IS DISTINCT FROM p_completed_at OR v_existing.elapsed_ms IS DISTINCT FROM p_elapsed_ms THEN
      RAISE EXCEPTION 'integration_result_idempotency_conflict';
    END IF;
    RETURN v_existing;
  END IF;

  SELECT * INTO v_event FROM public.event_outbox event WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token THEN
    RAISE EXCEPTION 'claim_not_owned';
  END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation
  WHERE operation.id = v_request.integration_operation_id FOR UPDATE;
  IF v_operation.state <> 'SUBMITTING' THEN RAISE EXCEPTION 'integration_operation_not_submitting'; END IF;
  SELECT * INTO v_target_request FROM public.integration_api_interactions interaction
  WHERE interaction.integration_operation_id = v_operation.reconciliation_target_operation_id
    AND interaction.phase = 'REQUEST'
  ORDER BY interaction.attempt_number DESC, interaction.created_at DESC LIMIT 1;
  IF v_target_request.id IS NULL THEN RAISE EXCEPTION 'nse_ucc_registration_request_evidence_missing'; END IF;
  v_registration_json := extensions.pgp_sym_decrypt(
    v_target_request.request_payload_ciphertext,
    public.integration_payload_encryption_key(v_target_request.payload_encryption_key_reference)
  )::pg_catalog.jsonb;

  IF p_http_status BETWEEN 200 AND 299 THEN
    BEGIN
      v_response_json := p_response_payload::pg_catalog.jsonb;
    EXCEPTION WHEN invalid_text_representation THEN
      v_response_json := '{}'::pg_catalog.jsonb;
    END;
    v_exact_match := v_response_json->>'response_status' = 'S' AND EXISTS (
      SELECT 1
      FROM pg_catalog.jsonb_array_elements(COALESCE(v_response_json->'report_data', '[]'::pg_catalog.jsonb)) AS report(record)
      WHERE pg_catalog.upper(pg_catalog.btrim(report.record->>'client_code')) =
              pg_catalog.upper(pg_catalog.btrim(v_registration_json->'reg_details'->0->>'client_code'))
        AND pg_catalog.upper(pg_catalog.btrim(COALESCE(report.record->>'primary_holder_pan', report.record->>'primary_pan'))) =
              pg_catalog.upper(pg_catalog.btrim(v_registration_json->'reg_details'->0->>'primary_holder_pan'))
    );
  END IF;

  IF p_normalized_outcome = 'SUCCESS'
     AND NOT (p_http_status BETWEEN 200 AND 299 AND v_exact_match AND p_native_status_value = 'S') THEN
    RAISE EXCEPTION 'verification_success_invariant_failed';
  END IF;
  IF p_normalized_outcome = 'BUSINESS_FAILURE'
     AND NOT (p_http_status BETWEEN 200 AND 299 AND NOT v_exact_match) THEN
    RAISE EXCEPTION 'verification_business_failure_invariant_failed';
  END IF;
  IF p_normalized_outcome = 'HTTP_FAILURE' AND (p_http_status IS NULL OR p_http_status BETWEEN 200 AND 299) THEN
    RAISE EXCEPTION 'verification_http_failure_invariant_failed';
  END IF;
  IF p_normalized_outcome = 'TRANSPORT_FAILURE' AND p_http_status IS NOT NULL THEN
    RAISE EXCEPTION 'verification_transport_failure_invariant_failed';
  END IF;

  v_retryable_http_status := p_normalized_outcome = 'HTTP_FAILURE'
    AND p_http_status = ANY (ARRAY[408, 429, 500, 502, 503, 504]::pg_catalog.int4[]);
  IF p_normalized_outcome = 'TRANSPORT_FAILURE' OR v_retryable_http_status THEN
    v_state := 'SUBMISSION_FAILED';
    v_retry_allowed := v_event.retry_count < p_max_attempts;
    v_event_status := 'failed';
  ELSIF p_normalized_outcome = 'SUCCESS' THEN
    v_state := 'SUCCESS';
  ELSIF p_normalized_outcome = 'BUSINESS_FAILURE' THEN
    v_state := 'BUSINESS_FAILED';
  ELSE
    v_state := 'HTTP_FAILED';
  END IF;

  INSERT INTO public.integration_api_interactions (
    workspace_id, integration_operation_id, integration_key, integration_environment, category,
    safety_class, operation_type, api_key, contract_version, endpoint_path, http_method,
    call_id, phase, attempt_number, correlation_id, payload_encryption_key_reference,
    payload_encryption_key_version, started_at, response_payload_ciphertext,
    response_header_metadata, response_content_type, response_bytes, response_hash,
    http_status, http_success, completed_at, elapsed_ms, native_status_field,
    native_status_value, native_remark_category, normalized_outcome, error_category,
    timeout_occurred, network_failure, ambiguous_outcome, reconciliation_required
  ) VALUES (
    v_request.workspace_id, v_request.integration_operation_id, v_request.integration_key,
    v_request.integration_environment, v_request.category, v_request.safety_class,
    v_request.operation_type, v_request.api_key, v_request.contract_version,
    v_request.endpoint_path, v_request.http_method, p_call_id, 'RESULT', v_request.attempt_number,
    v_request.correlation_id, v_key, 1, v_request.started_at,
    extensions.pgp_sym_encrypt(COALESCE(p_response_payload, ''), public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0'),
    p_response_header_metadata, p_response_content_type, v_bytes, v_hash, p_http_status,
    CASE WHEN p_http_status IS NULL THEN NULL ELSE p_http_status BETWEEN 200 AND 299 END,
    p_completed_at, p_elapsed_ms, CASE WHEN p_native_status_value IS NULL THEN NULL ELSE 'response_status' END,
    p_native_status_value, p_native_remark_category, p_normalized_outcome, p_error_category,
    COALESCE(p_timeout_occurred, false), COALESCE(p_network_failure, false), false, false
  ) RETURNING * INTO v_interaction;

  UPDATE public.integration_operations SET
    state = v_state,
    native_business_status = p_native_status_value,
    business_remark_category = p_native_remark_category,
    retry_allowed = v_retry_allowed,
    ambiguous_outcome = false,
    reconciliation_required = false,
    completed_at = p_completed_at,
    last_interaction_id = v_interaction.id
  WHERE id = v_operation.id;
  UPDATE public.event_outbox SET
    status = v_event_status,
    error_message = CASE WHEN v_event_status = 'failed' THEN
      CASE WHEN v_retry_allowed THEN 'verification_read_retryable' ELSE 'verification_read_attempts_exhausted' END
    ELSE NULL END,
    claimed_by = NULL,
    claim_token = NULL,
    claim_expires_at = NULL,
    updated_at = pg_catalog.now()
  WHERE id = v_event.id;
  RETURN v_interaction;
END;
$$;

-- A one-time, service-owned recovery for a historical terminal HTTP failure
-- created before the retryable-read policy existed. It never changes evidence
-- and only permits a remaining bounded retry of the same event.
CREATE OR REPLACE FUNCTION public.reopen_nse_ucc_retryable_http_verification(
  p_event_outbox_id pg_catalog.uuid,
  p_max_attempts pg_catalog.int4 DEFAULT 3
)
RETURNS public.integration_operations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event public.event_outbox;
  v_operation public.integration_operations;
  v_result public.integration_api_interactions;
BEGIN
  IF p_event_outbox_id IS NULL THEN RAISE EXCEPTION 'event_outbox_id_required'; END IF;
  IF p_max_attempts < 1 OR p_max_attempts > 5 THEN RAISE EXCEPTION 'invalid_max_attempts'; END IF;

  SELECT * INTO v_event FROM public.event_outbox event
  WHERE event.id = p_event_outbox_id FOR UPDATE;
  SELECT * INTO v_operation FROM public.integration_operations operation
  WHERE operation.id = v_event.entity_id FOR UPDATE;
  IF v_event.id IS NULL
     OR v_event.event_type <> 'integration.nse.ucc_verification_requested'
     OR v_event.entity_type <> 'integration_operation'
     OR v_event.status <> 'completed'
     OR v_event.retry_count >= p_max_attempts
     OR v_operation.id IS NULL
     OR v_operation.integration_key <> 'NSE_INVEST'
     OR v_operation.integration_environment <> 'UAT'
     OR v_operation.category <> 'RECONCILIATION'
     OR v_operation.safety_class <> 'READ_ONLY'
     OR v_operation.operation_type <> 'UCC_VERIFICATION'
     OR v_operation.api_key <> 'CLIENT_MASTER_REPORT'
     OR v_operation.state <> 'HTTP_FAILED'
     OR v_operation.retry_allowed
     OR v_operation.ambiguous_outcome
     OR v_operation.reconciliation_required THEN
    RAISE EXCEPTION 'nse_ucc_verification_http_reopen_not_eligible';
  END IF;

  SELECT * INTO v_result FROM public.integration_api_interactions interaction
  WHERE interaction.integration_operation_id = v_operation.id
    AND interaction.phase = 'RESULT'
  ORDER BY interaction.attempt_number DESC, interaction.created_at DESC LIMIT 1;
  IF v_result.id IS NULL
     OR v_result.normalized_outcome <> 'HTTP_FAILURE'
     OR v_result.http_status <> ALL (ARRAY[408, 429, 500, 502, 503, 504]::pg_catalog.int4[])
     OR v_result.ambiguous_outcome
     OR v_result.reconciliation_required
     OR NOT EXISTS (
       SELECT 1 FROM public.integration_api_interactions request
       WHERE request.call_id = v_result.call_id
         AND request.phase = 'REQUEST'
         AND request.integration_operation_id = v_operation.id
     ) THEN
    RAISE EXCEPTION 'nse_ucc_verification_http_reopen_not_eligible';
  END IF;

  -- The transition trigger accepts this guarded exception only within this
  -- service-owned function; direct state edits remain rejected.
  PERFORM pg_catalog.set_config('app.nse_ucc_retryable_http_reopen', 'enabled', true);
  UPDATE public.integration_operations SET
    state = 'SUBMISSION_FAILED',
    native_business_status = NULL,
    business_remark_category = 'verification_read_retryable_http',
    retry_allowed = true,
    ambiguous_outcome = false,
    reconciliation_required = false
  WHERE id = v_operation.id
  RETURNING * INTO v_operation;
  UPDATE public.event_outbox SET
    status = 'failed',
    error_message = 'verification_read_retryable',
    claimed_by = NULL,
    claim_token = NULL,
    claim_expires_at = NULL,
    updated_at = pg_catalog.now()
  WHERE id = v_event.id;
  RETURN v_operation;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_integration_operation_transition()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
     OR NEW.integration_account_id IS DISTINCT FROM OLD.integration_account_id
     OR NEW.integration_key IS DISTINCT FROM OLD.integration_key
     OR NEW.integration_environment IS DISTINCT FROM OLD.integration_environment
     OR NEW.category IS DISTINCT FROM OLD.category
     OR NEW.safety_class IS DISTINCT FROM OLD.safety_class
     OR NEW.operation_type IS DISTINCT FROM OLD.operation_type
     OR NEW.operation_purpose IS DISTINCT FROM OLD.operation_purpose
     OR NEW.api_key IS DISTINCT FROM OLD.api_key
     OR NEW.contract_version IS DISTINCT FROM OLD.contract_version
     OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
     OR NEW.reconciliation_target_operation_id IS DISTINCT FROM OLD.reconciliation_target_operation_id
     OR (
       NEW.reconciliation_resolution_operation_id IS DISTINCT FROM OLD.reconciliation_resolution_operation_id
       AND NOT (
         OLD.reconciliation_resolution_operation_id IS NULL
         AND NEW.reconciliation_resolution_operation_id IS NOT NULL
         AND OLD.state = 'RECONCILIATION_REQUIRED'
         AND NEW.state = 'SUCCESS'
       )
     )
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'integration_operation_identity_immutable';
  END IF;
  IF NEW.last_interaction_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.integration_api_interactions interaction
    WHERE interaction.id = NEW.last_interaction_id
      AND interaction.integration_operation_id = NEW.id
  ) THEN RAISE EXCEPTION 'integration_operation_interaction_mismatch'; END IF;
  IF NEW.state IS DISTINCT FROM OLD.state AND NOT (
    (OLD.state = 'PREPARED' AND NEW.state = 'QUEUED')
    OR (OLD.state IN ('QUEUED', 'SUBMISSION_FAILED') AND NEW.state = 'SUBMITTING')
    OR (OLD.state IN ('QUEUED', 'SUBMISSION_FAILED') AND NEW.state IN ('VALIDATION_FAILED', 'SUBMISSION_FAILED'))
    OR (OLD.state = 'SUBMITTING' AND NEW.state IN (
      'SUCCESS', 'BUSINESS_FAILED', 'HTTP_FAILED', 'SUBMISSION_FAILED', 'RECONCILIATION_REQUIRED'
    ))
    OR (
      OLD.state = 'RECONCILIATION_REQUIRED' AND NEW.state = 'SUCCESS'
      AND NEW.reconciliation_resolution_operation_id IS NOT NULL
      AND public.nse_ucc_verification_evidence_matches(
        OLD.id, NEW.reconciliation_resolution_operation_id
      )
    )
    OR (
      OLD.state = 'HTTP_FAILED'
      AND NEW.state = 'SUBMISSION_FAILED'
      AND OLD.integration_key = 'NSE_INVEST'
      AND OLD.integration_environment = 'UAT'
      AND OLD.category = 'RECONCILIATION'
      AND OLD.safety_class = 'READ_ONLY'
      AND OLD.operation_type = 'UCC_VERIFICATION'
      AND OLD.api_key = 'CLIENT_MASTER_REPORT'
      AND NEW.retry_allowed
      AND NOT NEW.ambiguous_outcome
      AND NOT NEW.reconciliation_required
      AND COALESCE(pg_catalog.current_setting('app.nse_ucc_retryable_http_reopen', true), '') = 'enabled'
    )
  ) THEN RAISE EXCEPTION 'invalid_integration_operation_transition'; END IF;
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.reopen_nse_ucc_retryable_http_verification(pg_catalog.uuid, pg_catalog.int4)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reopen_nse_ucc_retryable_http_verification(pg_catalog.uuid, pg_catalog.int4)
TO service_role;
