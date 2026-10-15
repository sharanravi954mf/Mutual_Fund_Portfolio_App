-- NSE-T002 correction 003: bounded, read-only Order Status reporting.
-- This is deliberately independent of UCC reconciliation: it records no
-- canonical order mutation and never derives observations from NSE payloads.

CREATE OR REPLACE FUNCTION public.validate_integration_operation_scope()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.integration_accounts account
    WHERE account.id = NEW.integration_account_id
      AND account.workspace_id = NEW.workspace_id
      AND account.integration_key = NEW.integration_key
      AND account.integration_environment = NEW.integration_environment
  ) THEN RAISE EXCEPTION 'integration_operation_scope_mismatch'; END IF;

  IF NEW.operation_type = 'UCC_VERIFICATION' THEN
    IF NEW.category <> 'RECONCILIATION' OR NEW.safety_class <> 'READ_ONLY'
       OR NEW.api_key <> 'CLIENT_MASTER_REPORT'
       OR NEW.operation_purpose NOT IN ('POST_REGISTRATION_VERIFICATION', 'AMBIGUOUS_WRITE_RECONCILIATION')
       OR NEW.reconciliation_target_operation_id IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM public.integration_operations target
         WHERE target.id = NEW.reconciliation_target_operation_id
           AND target.workspace_id = NEW.workspace_id
           AND target.integration_account_id = NEW.integration_account_id
           AND target.integration_key = NEW.integration_key
           AND target.integration_environment = NEW.integration_environment
           AND target.operation_type = 'UCC_REGISTRATION'
           AND target.api_key = 'CLIENTCOMMON183'
       ) THEN
      RAISE EXCEPTION 'integration_reconciliation_target_mismatch';
    END IF;
  ELSIF NEW.operation_type = 'ORDER_STATUS_REPORT' THEN
    IF NEW.integration_key <> 'NSE_INVEST' OR NEW.integration_environment <> 'UAT'
       OR NEW.category <> 'RECONCILIATION' OR NEW.safety_class <> 'READ_ONLY'
       OR NEW.api_key <> 'ORDER_STATUS' OR NEW.contract_version <> 'NNF_1.9.7'
       OR NEW.operation_purpose IS NOT NULL
       OR NEW.reconciliation_target_operation_id IS NOT NULL
       OR NEW.reconciliation_resolution_operation_id IS NOT NULL THEN
      RAISE EXCEPTION 'nse_order_status_identity_invalid';
    END IF;
  ELSIF NEW.reconciliation_target_operation_id IS NOT NULL
        OR NEW.operation_purpose IS NOT NULL THEN
    RAISE EXCEPTION 'integration_reconciliation_target_unexpected';
  END IF;
  IF NEW.reconciliation_resolution_operation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.integration_operations resolution
    WHERE resolution.id = NEW.reconciliation_resolution_operation_id
      AND resolution.reconciliation_target_operation_id = NEW.id
      AND resolution.workspace_id = NEW.workspace_id
      AND resolution.integration_account_id = NEW.integration_account_id
      AND resolution.integration_key = NEW.integration_key
      AND resolution.integration_environment = NEW.integration_environment
      AND resolution.operation_type = 'UCC_VERIFICATION'
  ) THEN RAISE EXCEPTION 'integration_reconciliation_resolution_mismatch'; END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prepare_nse_order_status_read(
  p_integration_account_id pg_catalog.uuid,
  p_from_date pg_catalog.date,
  p_to_date pg_catalog.date,
  p_order_ids pg_catalog.jsonb DEFAULT NULL,
  p_member_unique_ids pg_catalog.jsonb DEFAULT NULL
)
RETURNS public.integration_operations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_account public.integration_accounts; v_operation public.integration_operations;
BEGIN
  -- Reject unsupported narrowing filters before an operation or event exists.
  IF p_integration_account_id IS NULL OR p_from_date IS NULL OR p_to_date IS NULL
     OR p_from_date > p_to_date OR p_to_date - p_from_date > 6
     OR p_order_ids IS NOT NULL OR p_member_unique_ids IS NOT NULL THEN
    RAISE EXCEPTION 'nse_order_status_read_filter_invalid';
  END IF;
  SELECT * INTO v_account FROM public.integration_accounts account
  WHERE account.id = p_integration_account_id FOR UPDATE;
  IF v_account.id IS NULL OR v_account.integration_key <> 'NSE_INVEST'
     OR v_account.integration_environment <> 'UAT' OR v_account.state <> 'REGISTERED'
     OR NULLIF(pg_catalog.btrim(v_account.external_account_id), '') IS NULL THEN
    RAISE EXCEPTION 'nse_order_status_read_account_invalid';
  END IF;
  INSERT INTO public.integration_operations (
    workspace_id, integration_account_id, integration_key, integration_environment,
    category, safety_class, operation_type, operation_purpose, api_key,
    contract_version, state, reconciliation_target_operation_id,
    reconciliation_resolution_operation_id
  ) VALUES (
    v_account.workspace_id, v_account.id, 'NSE_INVEST', 'UAT',
    'RECONCILIATION', 'READ_ONLY', 'ORDER_STATUS_REPORT', NULL, 'ORDER_STATUS',
    'NNF_1.9.7', 'PREPARED', NULL, NULL
  ) RETURNING * INTO v_operation;
  UPDATE public.integration_operations SET state = 'QUEUED'
  WHERE id = v_operation.id RETURNING * INTO v_operation;
  INSERT INTO public.event_outbox (event_type, payload, status, entity_id, entity_type)
  VALUES ('integration.nse.order_status_requested', pg_catalog.jsonb_build_object(
    'integration_operation_id', v_operation.id, 'from_date', p_from_date, 'to_date', p_to_date,
    'read_policy', 'READ_BOUNDED_3'
  ), 'pending', v_operation.id, 'integration_operation');
  RETURN v_operation;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_nse_order_status_event(
  p_event_outbox_id pg_catalog.uuid, p_max_attempts pg_catalog.int4 DEFAULT 3,
  p_lease_seconds pg_catalog.int4 DEFAULT 120
)
RETURNS TABLE (event_outbox_id pg_catalog.uuid, integration_operation_id pg_catalog.uuid,
  correlation_id pg_catalog.uuid, attempt pg_catalog.int4, claim_state pg_catalog.text,
  claim_token pg_catalog.uuid)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_event public.event_outbox; v_operation public.integration_operations;
BEGIN
  IF p_event_outbox_id IS NULL OR p_max_attempts <> 3
     OR p_lease_seconds < 15 OR p_lease_seconds > 900 THEN
    RAISE EXCEPTION 'nse_order_status_claim_invalid';
  END IF;
  WITH candidate AS (
    SELECT event.id, pg_catalog.gen_random_uuid() AS token
    FROM public.event_outbox event JOIN public.integration_operations operation ON operation.id = event.entity_id
    WHERE event.id = p_event_outbox_id AND event.event_type = 'integration.nse.order_status_requested'
      AND event.entity_type = 'integration_operation' AND event.retry_count < 3
      AND operation.operation_type = 'ORDER_STATUS_REPORT' AND operation.category = 'RECONCILIATION'
      AND operation.integration_key = 'NSE_INVEST' AND operation.integration_environment = 'UAT'
      AND operation.safety_class = 'READ_ONLY' AND operation.api_key = 'ORDER_STATUS'
      AND operation.contract_version = 'NNF_1.9.7' AND operation.operation_purpose IS NULL
      AND operation.reconciliation_target_operation_id IS NULL
      AND operation.reconciliation_resolution_operation_id IS NULL
      AND ((event.status = 'pending' AND operation.state = 'QUEUED')
        OR (event.status = 'failed' AND operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed))
    FOR UPDATE OF event SKIP LOCKED
  ) UPDATE public.event_outbox event SET status = 'processing', retry_count = event.retry_count + 1,
    claimed_at = pg_catalog.now(), claimed_by = candidate.token, claim_token = candidate.token,
    claim_expires_at = pg_catalog.now() + (p_lease_seconds::pg_catalog.text || ' seconds')::pg_catalog.interval,
    error_message = NULL, updated_at = pg_catalog.now()
  FROM candidate WHERE event.id = candidate.id RETURNING event.* INTO v_event;
  IF v_event.id IS NULL THEN
    RETURN QUERY SELECT NULL::pg_catalog.uuid, NULL::pg_catalog.uuid, NULL::pg_catalog.uuid,
      0::pg_catalog.int4, 'no_event'::pg_catalog.text, NULL::pg_catalog.uuid; RETURN;
  END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id = v_event.entity_id;
  -- Claim is an outbox lease only: the operation remains QUEUED until REQUEST evidence exists.
  RETURN QUERY SELECT v_event.id, v_operation.id, v_operation.correlation_id, v_event.retry_count,
    CASE WHEN v_event.retry_count = 1 THEN 'newly_claimed' ELSE 'safe_retry_claimed' END, v_event.claim_token;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_nse_order_status_read(
  p_event_outbox_id pg_catalog.uuid, p_claim_token pg_catalog.uuid, p_call_id pg_catalog.uuid,
  p_request_payload pg_catalog.text, p_request_header_metadata pg_catalog.jsonb,
  p_started_at pg_catalog.timestamptz
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_event public.event_outbox; v_operation public.integration_operations;
  v_existing public.integration_api_interactions; v_json pg_catalog.jsonb;
  v_hash pg_catalog.bytea; v_bytes pg_catalog.int8; v_key pg_catalog.text := 'integration_payload_encryption_key_v1';
BEGIN
  IF p_call_id IS NULL OR p_started_at IS NULL OR NULLIF(p_request_payload, '') IS NULL THEN
    RAISE EXCEPTION 'nse_order_status_request_incomplete';
  END IF;
  BEGIN v_json := p_request_payload::pg_catalog.jsonb; EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'nse_order_status_request_invalid'; END;
  IF pg_catalog.jsonb_typeof(v_json) <> 'object' OR public.integration_payload_has_forbidden_key(v_json)
     OR v_json ? 'date_type' OR COALESCE(v_json->'order_ids', 'null'::pg_catalog.jsonb) <> 'null'::pg_catalog.jsonb
     OR COALESCE(v_json->'member_unique_ids', 'null'::pg_catalog.jsonb) <> 'null'::pg_catalog.jsonb THEN
    RAISE EXCEPTION 'nse_order_status_request_invalid';
  END IF;
  IF NOT public.integration_header_metadata_is_safe(p_request_header_metadata, 'REQUEST')
     OR p_request_header_metadata->>'content_type' IS DISTINCT FROM 'application/json'
     OR p_request_header_metadata->>'accept' IS DISTINCT FROM 'application/json' THEN RAISE EXCEPTION 'unsafe_request_header_metadata'; END IF;
  v_bytes := pg_catalog.octet_length(pg_catalog.convert_to(p_request_payload, 'UTF8'));
  v_hash := extensions.digest(pg_catalog.convert_to(p_request_payload, 'UTF8'), 'sha256');
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_call_id::pg_catalog.text, 0));
  SELECT * INTO v_event FROM public.event_outbox event WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.event_type <> 'integration.nse.order_status_requested'
     OR v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token
     OR v_event.claim_expires_at <= pg_catalog.now() THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation WHERE operation.id = v_event.entity_id FOR UPDATE;
  IF v_operation.integration_key <> 'NSE_INVEST' OR v_operation.integration_environment <> 'UAT'
     OR v_operation.category <> 'RECONCILIATION' OR v_operation.safety_class <> 'READ_ONLY'
     OR v_operation.operation_type <> 'ORDER_STATUS_REPORT' OR v_operation.api_key <> 'ORDER_STATUS'
     OR v_operation.contract_version <> 'NNF_1.9.7' OR v_operation.operation_purpose IS NOT NULL
     OR v_operation.reconciliation_target_operation_id IS NOT NULL
     OR v_operation.reconciliation_resolution_operation_id IS NOT NULL THEN RAISE EXCEPTION 'nse_order_status_identity_invalid'; END IF;
  SELECT * INTO v_existing FROM public.integration_api_interactions interaction WHERE interaction.call_id = p_call_id AND interaction.phase = 'REQUEST';
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.integration_operation_id IS DISTINCT FROM v_operation.id OR v_existing.attempt_number <> v_event.retry_count
       OR v_existing.correlation_id IS DISTINCT FROM v_operation.correlation_id OR v_existing.request_hash IS DISTINCT FROM v_hash
       OR v_existing.request_bytes IS DISTINCT FROM v_bytes OR v_existing.request_header_metadata IS DISTINCT FROM p_request_header_metadata
       OR v_existing.started_at IS DISTINCT FROM p_started_at THEN RAISE EXCEPTION 'integration_request_idempotency_conflict'; END IF;
    RETURN v_existing;
  END IF;
  IF v_operation.state NOT IN ('QUEUED', 'SUBMISSION_FAILED') OR (v_operation.state = 'SUBMISSION_FAILED' AND NOT v_operation.retry_allowed) THEN RAISE EXCEPTION 'nse_order_status_not_startable'; END IF;
  INSERT INTO public.integration_api_interactions (workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,request_payload_ciphertext,request_header_metadata,request_content_type,request_bytes,request_hash,started_at,normalized_outcome)
  VALUES (v_operation.workspace_id,v_operation.id,v_operation.integration_key,v_operation.integration_environment,v_operation.category,v_operation.safety_class,v_operation.operation_type,v_operation.api_key,v_operation.contract_version,'/nsemfdesk/api/v2/reports/order_status','POST',p_call_id,'REQUEST',v_event.retry_count,v_operation.correlation_id,v_key,1,extensions.pgp_sym_encrypt(p_request_payload,public.integration_payload_encryption_key(v_key),'cipher-algo=aes256, compress-algo=0'),p_request_header_metadata,'application/json',v_bytes,v_hash,p_started_at,'REQUEST_RECORDED') RETURNING * INTO v_existing;
  UPDATE public.integration_operations SET state = 'SUBMITTING', attempt_count = v_event.retry_count,
    retry_allowed = false, ambiguous_outcome = false, reconciliation_required = false,
    submitted_at = p_started_at, completed_at = NULL, last_interaction_id = v_existing.id WHERE id = v_operation.id;
  RETURN v_existing;
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_nse_order_status_read(
  p_event_outbox_id pg_catalog.uuid, p_claim_token pg_catalog.uuid, p_call_id pg_catalog.uuid,
  p_response_payload pg_catalog.text, p_response_content_type pg_catalog.text,
  p_response_header_metadata pg_catalog.jsonb, p_http_status pg_catalog.int4,
  p_native_status_value pg_catalog.text, p_native_remark_category pg_catalog.text,
  p_normalized_outcome pg_catalog.text, p_error_category pg_catalog.text,
  p_timeout_occurred pg_catalog.bool, p_network_failure pg_catalog.bool,
  p_completed_at pg_catalog.timestamptz, p_elapsed_ms pg_catalog.int8
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_request public.integration_api_interactions; v_existing public.integration_api_interactions;
  v_event public.event_outbox; v_operation public.integration_operations; v_result public.integration_api_interactions;
  v_hash pg_catalog.bytea; v_bytes pg_catalog.int8; v_key pg_catalog.text := 'integration_payload_encryption_key_v1'; v_state pg_catalog.text;
BEGIN
  IF p_completed_at IS NULL OR p_elapsed_ms < 0 OR p_normalized_outcome NOT IN ('SUCCESS','BUSINESS_FAILURE','HTTP_FAILURE','TRANSPORT_FAILURE') THEN RAISE EXCEPTION 'nse_order_status_result_invalid'; END IF;
  IF NOT public.integration_header_metadata_is_safe(p_response_header_metadata, 'RESULT') THEN RAISE EXCEPTION 'unsafe_response_header_metadata'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_call_id::pg_catalog.text, 0));
  SELECT * INTO v_request FROM public.integration_api_interactions WHERE call_id = p_call_id AND phase = 'REQUEST';
  IF v_request.id IS NULL OR v_request.operation_type <> 'ORDER_STATUS_REPORT' OR v_request.api_key <> 'ORDER_STATUS' THEN RAISE EXCEPTION 'integration_request_evidence_missing'; END IF;
  v_bytes := pg_catalog.octet_length(pg_catalog.convert_to(COALESCE(p_response_payload,''),'UTF8')); v_hash := extensions.digest(pg_catalog.convert_to(COALESCE(p_response_payload,''),'UTF8'),'sha256');
  SELECT * INTO v_existing FROM public.integration_api_interactions WHERE call_id = p_call_id AND phase = 'RESULT';
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.response_hash IS DISTINCT FROM v_hash OR v_existing.response_bytes IS DISTINCT FROM v_bytes OR v_existing.response_content_type IS DISTINCT FROM p_response_content_type OR v_existing.response_header_metadata IS DISTINCT FROM p_response_header_metadata OR v_existing.http_status IS DISTINCT FROM p_http_status OR v_existing.native_status_value IS DISTINCT FROM p_native_status_value OR v_existing.native_remark_category IS DISTINCT FROM p_native_remark_category OR v_existing.normalized_outcome IS DISTINCT FROM p_normalized_outcome OR v_existing.error_category IS DISTINCT FROM p_error_category OR v_existing.timeout_occurred IS DISTINCT FROM COALESCE(p_timeout_occurred,false) OR v_existing.network_failure IS DISTINCT FROM COALESCE(p_network_failure,false) OR v_existing.completed_at IS DISTINCT FROM p_completed_at OR v_existing.elapsed_ms IS DISTINCT FROM p_elapsed_ms THEN RAISE EXCEPTION 'integration_result_idempotency_conflict'; END IF;
    RETURN v_existing;
  END IF;
  SELECT * INTO v_event FROM public.event_outbox WHERE id = p_event_outbox_id FOR UPDATE;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id = v_request.integration_operation_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token OR v_operation.state <> 'SUBMITTING' THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
  IF v_operation.integration_key <> 'NSE_INVEST' OR v_operation.integration_environment <> 'UAT'
     OR v_operation.category <> 'RECONCILIATION' OR v_operation.safety_class <> 'READ_ONLY'
     OR v_operation.operation_type <> 'ORDER_STATUS_REPORT' OR v_operation.api_key <> 'ORDER_STATUS'
     OR v_operation.contract_version <> 'NNF_1.9.7' OR v_operation.operation_purpose IS NOT NULL
     OR v_operation.reconciliation_target_operation_id IS NOT NULL
     OR v_operation.reconciliation_resolution_operation_id IS NOT NULL THEN
    RAISE EXCEPTION 'nse_order_status_identity_invalid';
  END IF;
  v_state := CASE p_normalized_outcome WHEN 'SUCCESS' THEN 'SUCCESS' WHEN 'BUSINESS_FAILURE' THEN 'BUSINESS_FAILED' WHEN 'HTTP_FAILURE' THEN 'HTTP_FAILED' ELSE 'SUBMISSION_FAILED' END;
  INSERT INTO public.integration_api_interactions (workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,started_at,response_payload_ciphertext,response_header_metadata,response_content_type,response_bytes,response_hash,http_status,http_success,completed_at,elapsed_ms,native_status_field,native_status_value,native_remark_category,normalized_outcome,error_category,timeout_occurred,network_failure,ambiguous_outcome,reconciliation_required)
  VALUES (v_request.workspace_id,v_request.integration_operation_id,v_request.integration_key,v_request.integration_environment,v_request.category,v_request.safety_class,v_request.operation_type,v_request.api_key,v_request.contract_version,v_request.endpoint_path,v_request.http_method,p_call_id,'RESULT',v_request.attempt_number,v_request.correlation_id,v_key,1,v_request.started_at,extensions.pgp_sym_encrypt(COALESCE(p_response_payload,''),public.integration_payload_encryption_key(v_key),'cipher-algo=aes256, compress-algo=0'),p_response_header_metadata,p_response_content_type,v_bytes,v_hash,p_http_status,CASE WHEN p_http_status IS NULL THEN NULL ELSE p_http_status BETWEEN 200 AND 299 END,p_completed_at,p_elapsed_ms,CASE WHEN p_native_status_value IS NULL THEN NULL ELSE 'response_status' END,p_native_status_value,p_native_remark_category,p_normalized_outcome,p_error_category,COALESCE(p_timeout_occurred,false),COALESCE(p_network_failure,false),false,false) RETURNING * INTO v_result;
  UPDATE public.integration_operations SET state=v_state, native_business_status=p_native_status_value, business_remark_category=p_native_remark_category, retry_allowed=false, ambiguous_outcome=false, reconciliation_required=false, completed_at=p_completed_at,last_interaction_id=v_result.id WHERE id=v_operation.id;
  UPDATE public.event_outbox SET status='completed', error_message=NULL, claimed_by=NULL, claim_token=NULL, claim_expires_at=NULL, updated_at=pg_catalog.now() WHERE id=v_event.id;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.recover_expired_nse_order_status_event(p_event_outbox_id pg_catalog.uuid)
RETURNS pg_catalog.text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_event public.event_outbox; v_operation public.integration_operations; v_request public.integration_api_interactions; v_retry pg_catalog.bool; v_now pg_catalog.timestamptz := pg_catalog.now();
BEGIN
  SELECT * INTO v_event FROM public.event_outbox WHERE id=p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.event_type <> 'integration.nse.order_status_requested' OR v_event.status <> 'processing' OR v_event.claim_expires_at > v_now THEN RETURN 'no_recovery_required'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_event.entity_id FOR UPDATE;
  IF v_operation.integration_key <> 'NSE_INVEST' OR v_operation.integration_environment <> 'UAT'
     OR v_operation.category <> 'RECONCILIATION' OR v_operation.safety_class <> 'READ_ONLY'
     OR v_operation.operation_type <> 'ORDER_STATUS_REPORT' OR v_operation.api_key <> 'ORDER_STATUS'
     OR v_operation.contract_version <> 'NNF_1.9.7' OR v_operation.operation_purpose IS NOT NULL
     OR v_operation.reconciliation_target_operation_id IS NOT NULL
     OR v_operation.reconciliation_resolution_operation_id IS NOT NULL
     OR v_operation.state NOT IN ('QUEUED','SUBMITTING') THEN RETURN 'no_recovery_required'; END IF;
  v_retry := v_event.retry_count < 3;
  SELECT * INTO v_request FROM public.integration_api_interactions WHERE integration_operation_id=v_operation.id AND phase='REQUEST' ORDER BY attempt_number DESC, created_at DESC LIMIT 1;
  IF v_operation.state='SUBMITTING' AND v_request.id IS NOT NULL THEN
    INSERT INTO public.integration_api_interactions (workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,started_at,response_payload_ciphertext,response_header_metadata,response_bytes,response_hash,completed_at,elapsed_ms,normalized_outcome,error_category,timeout_occurred,network_failure,ambiguous_outcome,reconciliation_required)
    VALUES(v_request.workspace_id,v_request.integration_operation_id,v_request.integration_key,v_request.integration_environment,v_request.category,v_request.safety_class,v_request.operation_type,v_request.api_key,v_request.contract_version,v_request.endpoint_path,v_request.http_method,v_request.call_id,'RESULT',v_request.attempt_number,v_request.correlation_id,'integration_payload_encryption_key_v1',1,v_request.started_at,extensions.pgp_sym_encrypt('',public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'),'{}'::pg_catalog.jsonb,0,extensions.digest(''::pg_catalog.bytea,'sha256'),v_now,GREATEST(0::pg_catalog.int8,(EXTRACT(EPOCH FROM (v_now-v_request.started_at))*1000)::pg_catalog.int8),'TRANSPORT_FAILURE','order_status_read_lease_expired',false,false,false,false);
  END IF;
  UPDATE public.integration_operations SET state='SUBMISSION_FAILED',attempt_count=GREATEST(attempt_count,v_event.retry_count),retry_allowed=v_retry,business_remark_category='order_status_read_lease_expired',ambiguous_outcome=false,reconciliation_required=false,completed_at=v_now WHERE id=v_operation.id;
  UPDATE public.event_outbox SET status='failed',error_message=CASE WHEN v_retry THEN 'order_status_read_retryable' ELSE 'order_status_read_attempts_exhausted' END,claimed_by=NULL,claim_token=NULL,claim_expires_at=NULL,updated_at=v_now WHERE id=v_event.id;
  RETURN CASE WHEN v_retry THEN 'safe_read_retry_available' ELSE 'read_attempts_exhausted' END;
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_nse_order_status_read(pg_catalog.uuid,pg_catalog.date,pg_catalog.date,pg_catalog.jsonb,pg_catalog.jsonb), public.claim_nse_order_status_event(pg_catalog.uuid,pg_catalog.int4,pg_catalog.int4), public.start_nse_order_status_read(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.jsonb,pg_catalog.timestamptz), public.finish_nse_order_status_read(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.text,pg_catalog.jsonb,pg_catalog.int4,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.bool,pg_catalog.bool,pg_catalog.timestamptz,pg_catalog.int8), public.recover_expired_nse_order_status_event(pg_catalog.uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.prepare_nse_order_status_read(pg_catalog.uuid,pg_catalog.date,pg_catalog.date,pg_catalog.jsonb,pg_catalog.jsonb), public.claim_nse_order_status_event(pg_catalog.uuid,pg_catalog.int4,pg_catalog.int4), public.start_nse_order_status_read(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.jsonb,pg_catalog.timestamptz), public.finish_nse_order_status_read(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.text,pg_catalog.jsonb,pg_catalog.int4,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.bool,pg_catalog.bool,pg_catalog.timestamptz,pg_catalog.int8), public.recover_expired_nse_order_status_event(pg_catalog.uuid) TO service_role;
