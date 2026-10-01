-- Controlled DEV UAT on 2026-10-01 observed FUND_ORDER failure with
-- response_status=F, zero count, empty array data, and exact no-records remark.
-- Preserve the literal only in encrypted RESULT evidence and expose a safe category.
-- Do not infer pg_bank_refno semantics or retry/probe provider variants from this result.
BEGIN;

CREATE OR REPLACE FUNCTION public.inspect_nse_order_funding_response(p_api pg_catalog.text,p_payload pg_catalog.text,p_request pg_catalog.jsonb,p_identity pg_catalog.jsonb)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE v_json pg_catalog.jsonb; v_row pg_catalog.jsonb; v_required pg_catalog.text[]; v_key pg_catalog.jsonb;
 v_seen pg_catalog.jsonb[] := ARRAY[]::pg_catalog.jsonb[]; v_native pg_catalog.text; v_count pg_catalog.numeric;
 v_result pg_catalog.jsonb := '{"native_status":null,"category":"order_funding_response_invalid","success":false,"record_count":0}';
BEGIN
 IF public.nse_order_funding_contract(p_api) IS NULL THEN RETURN v_result; END IF;
 BEGIN v_json := p_payload::pg_catalog.jsonb; EXCEPTION WHEN OTHERS THEN RETURN v_result; END;
 IF pg_catalog.jsonb_path_exists(v_json,'$.** ? (@ > 1.7976931348623157e308 || @ < -1.7976931348623157e308)'::pg_catalog.jsonpath) THEN RETURN v_result; END IF;
 IF pg_catalog.jsonb_typeof(v_json) IS DISTINCT FROM 'object' OR v_json->>'response_status' IS NULL OR v_json->>'response_status' NOT IN ('S','F') THEN RETURN v_result; END IF;
 v_native := v_json->>'response_status'; v_result := v_result||pg_catalog.jsonb_build_object('native_status',v_native);
 IF v_native='F' AND p_api='ORDER_LIFECYCLE' THEN RETURN v_result||'{"category":"order_funding_business_failed"}'::pg_catalog.jsonb; END IF;
 IF pg_catalog.jsonb_typeof(v_json->'error_remark') IS DISTINCT FROM 'string'
  OR pg_catalog.jsonb_typeof(v_json->'report_data_total') IS NULL
  OR pg_catalog.jsonb_typeof(v_json->'report_data_total') NOT IN ('string','number') THEN RETURN v_result; END IF;
 IF pg_catalog.jsonb_typeof(v_json->'report_data_total')='string' AND v_json->>'report_data_total' !~ '^[0-9]+$' THEN RETURN v_result; END IF;
 BEGIN v_count := (v_json->>'report_data_total')::pg_catalog.numeric; EXCEPTION WHEN OTHERS THEN RETURN v_result; END;
 IF v_count<0 OR v_count>10000 OR v_count<>pg_catalog.trunc(v_count) THEN RETURN v_result; END IF;
 IF v_native='F' THEN
  IF v_count=0 AND v_json->'report_data'='""'::pg_catalog.jsonb THEN RETURN v_result||'{"category":"order_funding_business_failed"}'::pg_catalog.jsonb; END IF;
  IF p_api='FUND_AGE' AND v_count=0 AND v_json->'report_data'='[]'::pg_catalog.jsonb
    AND v_json->>'error_remark'='amc_code value is not valid.' THEN
    RETURN v_result||'{"category":"order_funding_amc_code_invalid"}'::pg_catalog.jsonb;
  END IF;
  IF p_api='FUND_ORDER' AND v_count=0 AND v_json->'report_data'='[]'::pg_catalog.jsonb
    AND v_json->>'error_remark'='No record(s) found' THEN
    RETURN v_result||'{"category":"order_funding_no_records"}'::pg_catalog.jsonb;
  END IF;
  RETURN v_result;
 END IF;
 IF pg_catalog.jsonb_typeof(v_json->'report_data') IS DISTINCT FROM 'array' THEN RETURN v_result; END IF;
 IF v_count<>pg_catalog.jsonb_array_length(v_json->'report_data')
  OR (v_json->>'error_remark'<>'' AND NOT(
    (p_api IN ('ORDER_LIFECYCLE','TRANSACTION_DETAIL') AND v_count=0 AND v_json->>'error_remark'='No record(s) found.')
    OR (p_api='FUND_AGE' AND v_count=0)
  )) THEN RETURN v_result; END IF;
 v_required := CASE p_api
  WHEN 'ORDER_LIFECYCLE' THEN ARRAY['client_code','product_type','product_id','order_status','payment_status','reconciliation_status']
  WHEN 'TRANSACTION_DETAIL' THEN ARRAY['client_code','primary_holder_pan','product_type','product_id','sip_registration_no','order_status','payment_status','reconciliation_status']
  WHEN 'FUND_ORDER' THEN ARRAY['clientcode','cfppgbankrefno','utrno','id','totalamount','totalallocatedamount','remainingamount','mappedorders','settledorders','allotmentorders']
  WHEN 'FUND_AGE' THEN ARRAY['clientcode','orderno','date','schemecode','orderstatus','funds_received_status'] END;
 FOR v_row IN SELECT value FROM pg_catalog.jsonb_array_elements(v_json->'report_data') LOOP
  IF pg_catalog.jsonb_typeof(v_row) IS DISTINCT FROM 'object' THEN RETURN v_result||'{"category":"order_funding_row_scope_invalid"}'::pg_catalog.jsonb; END IF;
  IF NOT(v_row ?& v_required) OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_each(v_row) WHERE pg_catalog.jsonb_typeof(value)<>'string')
   OR (v_row->>CASE WHEN p_api IN ('FUND_ORDER','FUND_AGE') THEN 'clientcode' ELSE 'client_code' END) IS DISTINCT FROM p_identity->>'client_code'
   OR (p_api IN ('ORDER_LIFECYCLE','TRANSACTION_DETAIL') AND v_row->>'product_id' !~ '^[A-Za-z0-9_-]+$')
   OR (p_api='ORDER_LIFECYCLE' AND (v_row->>'product_type' NOT IN ('PUR','RED','SWITCH','SIP','STP','SWP','MANDATE','SIP CANCEL','XSIP CANCEL','STP CANCEL','SWP CANCEL')
     OR (p_request ? 'product_id' AND (v_row->>'product_type' IS DISTINCT FROM p_request->>'Product_type'
       OR NOT(v_row->>'product_id'=ANY(pg_catalog.string_to_array(p_request->>'product_id',',')))))))
   OR (p_api='TRANSACTION_DETAIL' AND (v_row->>'primary_holder_pan' IS DISTINCT FROM p_identity->>'pan'
     OR v_row->>'product_type' !~ '[^[:space:]]' OR (p_request ? 'order_id' AND NOT(v_row->>'product_id'=ANY(pg_catalog.string_to_array(p_request->>'order_id',','))))))
   OR (p_api='FUND_ORDER' AND (v_row->>'cfppgbankrefno' !~ '^[A-Za-z0-9_-]+$' OR v_row->>'id' !~ '^[A-Za-z0-9_-]+$' OR v_row->>'utrno' !~ '[^[:space:]]'))
   OR (p_api='FUND_AGE' AND (v_row->>'orderno' !~ '^[A-Za-z0-9_-]+$' OR v_row->>'schemecode' !~ '[^[:space:]]'
     OR v_row->>'date' IS DISTINCT FROM pg_catalog.replace(p_request->>'date','-','/'))) THEN
    RETURN v_result||'{"category":"order_funding_row_scope_invalid"}'::pg_catalog.jsonb;
  END IF;
  v_key := CASE WHEN p_api IN ('ORDER_LIFECYCLE','TRANSACTION_DETAIL') THEN pg_catalog.jsonb_build_array(v_row->>'product_type',v_row->>'product_id') ELSE v_row END;
  IF v_key=ANY(v_seen) THEN RETURN v_result||'{"category":"order_funding_duplicate_rows"}'::pg_catalog.jsonb; END IF;
  v_seen := pg_catalog.array_append(v_seen,v_key);
 END LOOP;
 RETURN pg_catalog.jsonb_build_object('native_status','S','category',CASE
  WHEN p_api IN ('ORDER_LIFECYCLE','TRANSACTION_DETAIL') AND v_count=0 AND v_json->>'error_remark'='No record(s) found.' THEN 'order_funding_no_records'
  WHEN v_count=0 AND v_json->>'error_remark'<>'' THEN 'order_funding_empty_success_diagnostic'
  ELSE 'order_funding_report_received' END,'success',true,'record_count',v_count);
END $$;

-- Shared bounded-read mechanics, derived from the existing PROV_ORDERS lifecycle.
CREATE OR REPLACE FUNCTION public.recover_expired_nse_order_funding_events(
  p_event_outbox_id pg_catalog.uuid,
  p_max_attempts pg_catalog.int4 DEFAULT 3
)
RETURNS pg_catalog.text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event public.event_outbox;
  v_operation public.integration_operations;
  v_request public.integration_api_interactions;
  v_result_id pg_catalog.uuid;
  v_retry_allowed pg_catalog.bool;
  v_completed_at pg_catalog.timestamptz := pg_catalog.now();
  v_key pg_catalog.text := 'integration_payload_encryption_key_v1';
  v_empty_hash pg_catalog.bytea := extensions.digest(''::pg_catalog.bytea, 'sha256');
BEGIN
  IF p_event_outbox_id IS NULL THEN RAISE EXCEPTION 'event_outbox_id_required'; END IF;
  IF p_max_attempts IS NULL OR p_max_attempts < 1 OR p_max_attempts > 3 THEN RAISE EXCEPTION 'invalid_max_attempts'; END IF;
  SELECT * INTO v_event FROM public.event_outbox event
  WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.event_type <> 'integration.nse.order_funding_requested'
     OR v_event.entity_type <> 'integration_operation' OR v_event.status <> 'processing'
     OR v_event.claim_expires_at IS NULL OR v_event.claim_expires_at > pg_catalog.now() THEN RETURN 'no_recovery_required'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation
  WHERE operation.id = v_event.entity_id FOR UPDATE;
  IF v_operation.id IS NULL OR v_operation.operation_type <> 'ORDER_FUNDING'
     OR v_operation.safety_class <> 'READ_ONLY' THEN RETURN 'no_recovery_required'; END IF;
  v_retry_allowed := v_event.retry_count < p_max_attempts;
  IF v_operation.state = 'QUEUED' OR (v_operation.state = 'SUBMISSION_FAILED' AND v_operation.retry_allowed) THEN
    UPDATE public.integration_operations SET state = 'SUBMISSION_FAILED',
      attempt_count = GREATEST(attempt_count, v_event.retry_count), retry_allowed = v_retry_allowed,
      business_remark_category = 'order_funding_pre_request_claim_expired',
      native_business_status = NULL, ambiguous_outcome = false, reconciliation_required = false,
      completed_at = v_completed_at
    WHERE id = v_operation.id;
  ELSIF v_operation.state = 'SUBMITTING' THEN
    SELECT * INTO v_request FROM public.integration_api_interactions request
    WHERE request.integration_operation_id = v_operation.id AND request.phase = 'REQUEST'
      AND NOT EXISTS (
        SELECT 1 FROM public.integration_api_interactions result
        WHERE result.call_id = request.call_id AND result.phase = 'RESULT'
      )
    ORDER BY request.attempt_number DESC, request.created_at DESC LIMIT 1;
    IF v_request.id IS NULL THEN RETURN 'no_recovery_required'; END IF;
    INSERT INTO public.integration_api_interactions (
      workspace_id, integration_operation_id, integration_key, integration_environment,
      category, safety_class, operation_type, api_key, contract_version, endpoint_path,
      http_method, call_id, phase, attempt_number, correlation_id,
      payload_encryption_key_reference, payload_encryption_key_version, started_at,
      response_payload_ciphertext, response_header_metadata, response_content_type,
      response_bytes, response_hash, http_status, http_success, completed_at, elapsed_ms,
      normalized_outcome, error_category, timeout_occurred, network_failure,
      ambiguous_outcome, reconciliation_required
    ) VALUES (
      v_request.workspace_id, v_request.integration_operation_id, v_request.integration_key,
      v_request.integration_environment, v_request.category, v_request.safety_class,
      v_request.operation_type, v_request.api_key, v_request.contract_version,
      v_request.endpoint_path, v_request.http_method, v_request.call_id, 'RESULT',
      v_request.attempt_number, v_request.correlation_id, v_key, 1, v_request.started_at,
      extensions.pgp_sym_encrypt('', public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0'),
      '{}'::pg_catalog.jsonb, NULL, 0, v_empty_hash, NULL, NULL, v_completed_at,
      GREATEST(0::pg_catalog.int8, (EXTRACT(EPOCH FROM (v_completed_at - v_request.started_at)) * 1000)::pg_catalog.int8),
      'TRANSPORT_FAILURE', 'order_funding_read_lease_expired', false, false, false, false
    ) RETURNING id INTO v_result_id;
    UPDATE public.integration_operations SET state = 'SUBMISSION_FAILED',
      attempt_count = GREATEST(attempt_count, v_event.retry_count), retry_allowed = v_retry_allowed,
      business_remark_category = 'order_funding_read_lease_expired',
      native_business_status = NULL, ambiguous_outcome = false, reconciliation_required = false,
      completed_at = v_completed_at, last_interaction_id = v_result_id
    WHERE id = v_operation.id;
  ELSE
    RETURN 'no_recovery_required';
  END IF;
  UPDATE public.event_outbox SET status = 'failed',
    error_message = CASE WHEN v_retry_allowed THEN 'order_funding_read_retryable' ELSE 'order_funding_read_attempts_exhausted' END,
    claimed_by = NULL, claim_token = NULL, claim_expires_at = NULL, updated_at = pg_catalog.now()
  WHERE id = v_event.id;
  RETURN CASE WHEN v_retry_allowed THEN 'safe_read_retry_available' ELSE 'order_funding_attempts_exhausted' END;
END;
$$;

COMMIT;
