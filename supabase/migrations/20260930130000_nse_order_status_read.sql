-- NSE ORDER_STATUS is a bounded, service-owned read.  It deliberately has no
-- client facade and cannot accept canonical order or member identifiers.
BEGIN;

CREATE TABLE public.nse_order_status_requests (
  integration_operation_id pg_catalog.uuid PRIMARY KEY REFERENCES public.integration_operations(id) ON DELETE RESTRICT,
  from_date pg_catalog.date NOT NULL,
  to_date pg_catalog.date NOT NULL,
  trans_type pg_catalog.text NOT NULL CHECK (trans_type IN ('P', 'R', 'ALL')),
  order_type pg_catalog.text NOT NULL CHECK (order_type IN ('ALL', 'NRM', 'SIP', 'XSP', 'STP')),
  sub_order_type pg_catalog.text NOT NULL CHECK (sub_order_type IN ('ALL', 'NRM', 'SPOR', 'SWH', 'STP')),
  order_status pg_catalog.text CHECK (order_status IN ('All', 'VALID', 'INVALID')),
  settlement_type pg_catalog.text CHECK (settlement_type IN ('ALL', 'L0', 'L1', 'OTHERS')),
  order_ids pg_catalog.text[] CHECK (order_ids IS NULL OR pg_catalog.cardinality(order_ids) BETWEEN 1 AND 50),
  member_unique_ids pg_catalog.text[] CHECK (member_unique_ids IS NULL OR pg_catalog.cardinality(member_unique_ids) BETWEEN 1 AND 50),
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CHECK (to_date >= from_date AND to_date <= from_date + 6),
  CHECK (order_ids IS NULL OR member_unique_ids IS NULL)
);
CREATE TABLE public.nse_order_status_observations (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  integration_operation_id pg_catalog.uuid NOT NULL REFERENCES public.integration_operations(id) ON DELETE RESTRICT,
  interaction_id pg_catalog.uuid NOT NULL REFERENCES public.integration_api_interactions(id) ON DELETE RESTRICT,
  response_status pg_catalog.text CHECK (response_status IN ('S', 'F')),
  record_count pg_catalog.int4 NOT NULL CHECK (record_count >= 0),
  invalid_count pg_catalog.int4 NOT NULL CHECK (invalid_count >= 0 AND invalid_count <= record_count),
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  UNIQUE (interaction_id)
);
ALTER TABLE public.nse_order_status_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nse_order_status_observations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nse_order_status_requests, public.nse_order_status_observations FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.reject_nse_order_status_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$ BEGIN RAISE EXCEPTION 'nse_order_status_append_only'; END; $$;
CREATE TRIGGER nse_order_status_requests_append_only BEFORE UPDATE OR DELETE ON public.nse_order_status_requests FOR EACH ROW EXECUTE FUNCTION public.reject_nse_order_status_mutation();
CREATE TRIGGER nse_order_status_observations_append_only BEFORE UPDATE OR DELETE ON public.nse_order_status_observations FOR EACH ROW EXECUTE FUNCTION public.reject_nse_order_status_mutation();

CREATE OR REPLACE FUNCTION public.prepare_nse_order_status(
  p_workspace_id pg_catalog.uuid, p_investor_profile_id pg_catalog.uuid,
  p_from_date pg_catalog.date, p_to_date pg_catalog.date, p_trans_type pg_catalog.text,
  p_order_type pg_catalog.text, p_sub_order_type pg_catalog.text,
  p_order_status pg_catalog.text DEFAULT NULL, p_settlement_type pg_catalog.text DEFAULT NULL,
  p_order_ids pg_catalog.text[] DEFAULT NULL, p_member_unique_ids pg_catalog.text[] DEFAULT NULL
) RETURNS public.integration_operations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_account public.integration_accounts; v_operation public.integration_operations; v_ids pg_catalog.text[];
BEGIN
  -- Service-only provenance boundary: callers may never smuggle canonical IDs.
  IF p_order_ids IS NOT NULL OR p_member_unique_ids IS NOT NULL THEN RAISE EXCEPTION 'order_status_id_scope_not_supported'; END IF;
  IF p_from_date IS NULL OR p_to_date IS NULL OR p_to_date < p_from_date OR p_to_date > p_from_date + 6 THEN RAISE EXCEPTION 'order_status_date_range_invalid'; END IF;
  IF p_trans_type NOT IN ('P', 'R', 'ALL') OR p_order_type NOT IN ('ALL', 'NRM', 'SIP', 'XSP', 'STP') OR p_sub_order_type NOT IN ('ALL', 'NRM', 'SPOR', 'SWH', 'STP') OR (p_order_status IS NOT NULL AND p_order_status NOT IN ('All', 'VALID', 'INVALID')) OR (p_settlement_type IS NOT NULL AND p_settlement_type NOT IN ('ALL', 'L0', 'L1', 'OTHERS')) THEN RAISE EXCEPTION 'order_status_filter_invalid'; END IF;
  SELECT * INTO v_account FROM public.integration_accounts account WHERE account.workspace_id = p_workspace_id AND account.investor_profile_id = p_investor_profile_id AND account.integration_key = 'NSE_INVEST' AND account.integration_environment = 'UAT' AND account.state = 'REGISTERED' AND NULLIF(pg_catalog.btrim(account.external_account_id), '') IS NOT NULL FOR UPDATE;
  IF v_account.id IS NULL THEN RAISE EXCEPTION 'order_status_registered_nse_uat_account_required'; END IF;
  INSERT INTO public.integration_operations (workspace_id, integration_account_id, integration_key, integration_environment, category, safety_class, operation_type, operation_purpose, api_key, contract_version, state)
  VALUES (p_workspace_id, v_account.id, 'NSE_INVEST', 'UAT', 'RECONCILIATION', 'READ_ONLY', 'ORDER_STATUS', 'ORDER_STATUS_READ', 'ORDER_STATUS_REPORT', 'NSEMF_V2', 'PREPARED') RETURNING * INTO v_operation;
  INSERT INTO public.nse_order_status_requests (integration_operation_id, from_date, to_date, trans_type, order_type, sub_order_type, order_status, settlement_type, order_ids, member_unique_ids)
  VALUES (v_operation.id, p_from_date, p_to_date, p_trans_type, p_order_type, p_sub_order_type, p_order_status, p_settlement_type, NULL, NULL);
  UPDATE public.integration_operations SET state = 'QUEUED' WHERE id = v_operation.id RETURNING * INTO v_operation;
  INSERT INTO public.event_outbox (event_type, payload, status, entity_id, entity_type) VALUES ('integration.nse.order_status_requested', pg_catalog.jsonb_build_object('integration_operation_id', v_operation.id), 'pending', v_operation.id, 'integration_operation');
  RETURN v_operation;
END; $$;

CREATE OR REPLACE FUNCTION public.get_nse_order_status_source(p_integration_operation_id pg_catalog.uuid) RETURNS pg_catalog.jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ DECLARE v_source pg_catalog.jsonb;
BEGIN
  SELECT pg_catalog.jsonb_build_object('client_code', account.external_account_id, 'from_date', pg_catalog.to_char(request.from_date, 'YYYY-MM-DD'), 'to_date', pg_catalog.to_char(request.to_date, 'YYYY-MM-DD'), 'trans_type', request.trans_type, 'order_type', request.order_type, 'sub_order_type', request.sub_order_type, 'order_status', request.order_status, 'settlement_type', request.settlement_type, 'order_ids', request.order_ids)
  INTO v_source FROM public.integration_operations operation JOIN public.integration_accounts account ON account.id = operation.integration_account_id JOIN public.nse_order_status_requests request ON request.integration_operation_id = operation.id
  WHERE operation.id = p_integration_operation_id AND operation.integration_key = 'NSE_INVEST' AND operation.integration_environment = 'UAT' AND operation.category = 'RECONCILIATION' AND operation.safety_class = 'READ_ONLY' AND operation.operation_type = 'ORDER_STATUS' AND account.state = 'REGISTERED' AND NULLIF(pg_catalog.btrim(account.external_account_id), '') IS NOT NULL;
  IF v_source IS NULL THEN RAISE EXCEPTION 'order_status_source_unavailable'; END IF; RETURN v_source;
END; $$;

CREATE OR REPLACE FUNCTION public.claim_nse_order_status_event(p_event_outbox_id pg_catalog.uuid, p_max_attempts pg_catalog.int4 DEFAULT 3, p_lease_seconds pg_catalog.int4 DEFAULT 120)
RETURNS TABLE(event_outbox_id pg_catalog.uuid, integration_operation_id pg_catalog.uuid, correlation_id pg_catalog.uuid, attempt pg_catalog.int4, claim_state pg_catalog.text, claim_token pg_catalog.uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ DECLARE v_event public.event_outbox; v_operation public.integration_operations;
BEGIN
  IF p_event_outbox_id IS NULL OR p_max_attempts NOT BETWEEN 1 AND 3 OR p_lease_seconds NOT BETWEEN 15 AND 900 THEN RAISE EXCEPTION 'order_status_claim_input_invalid'; END IF;
  UPDATE public.event_outbox event SET status = 'processing', retry_count = event.retry_count + 1, claim_token = pg_catalog.gen_random_uuid(), claim_expires_at = pg_catalog.now() + (p_lease_seconds::pg_catalog.text || ' seconds')::pg_catalog.interval, claimed_at = pg_catalog.now(), updated_at = pg_catalog.now()
  WHERE event.id = p_event_outbox_id AND event.event_type = 'integration.nse.order_status_requested' AND event.entity_type = 'integration_operation' AND event.retry_count < p_max_attempts AND event.status IN ('pending', 'failed') RETURNING * INTO v_event;
  IF v_event.id IS NULL THEN RETURN QUERY SELECT NULL::pg_catalog.uuid, NULL::pg_catalog.uuid, NULL::pg_catalog.uuid, 0::pg_catalog.int4, 'no_event'::pg_catalog.text, NULL::pg_catalog.uuid; RETURN; END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id = v_event.entity_id FOR UPDATE;
  UPDATE public.integration_operations SET state = 'SUBMITTING' WHERE id = v_operation.id;
  RETURN QUERY SELECT v_event.id, v_operation.id, v_operation.correlation_id, v_event.retry_count, CASE WHEN v_event.retry_count = 1 THEN 'newly_claimed' ELSE 'safe_retry_claimed' END, v_event.claim_token;
END; $$;

CREATE OR REPLACE FUNCTION public.recover_expired_nse_order_status_events(p_event_outbox_id pg_catalog.uuid, p_max_attempts pg_catalog.int4 DEFAULT 3) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ BEGIN
  UPDATE public.event_outbox SET status = CASE WHEN retry_count >= p_max_attempts THEN 'failed' ELSE 'pending' END, claim_token = NULL, claim_expires_at = NULL, updated_at = pg_catalog.now() WHERE id = p_event_outbox_id AND event_type = 'integration.nse.order_status_requested' AND status = 'processing' AND claim_expires_at <= pg_catalog.now();
END; $$;

CREATE OR REPLACE FUNCTION public.start_nse_order_status(p_event_outbox_id pg_catalog.uuid, p_claim_token pg_catalog.uuid, p_call_id pg_catalog.uuid, p_request_payload pg_catalog.text, p_request_header_metadata pg_catalog.jsonb, p_started_at pg_catalog.timestamptz) RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ DECLARE v_event public.event_outbox; v_operation public.integration_operations; v_row public.integration_api_interactions; v_key pg_catalog.text := 'integration_payload_encryption_key_v1';
BEGIN
  SELECT * INTO v_event FROM public.event_outbox WHERE id = p_event_outbox_id FOR UPDATE; IF v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token OR p_call_id IS NULL OR p_started_at IS NULL OR NULLIF(p_request_payload, '') IS NULL THEN RAISE EXCEPTION 'order_status_request_not_claimed'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id = v_event.entity_id; IF v_operation.state <> 'SUBMITTING' THEN RAISE EXCEPTION 'order_status_operation_not_submitting'; END IF;
  INSERT INTO public.integration_api_interactions (workspace_id, integration_operation_id, integration_key, integration_environment, category, safety_class, operation_type, api_key, contract_version, endpoint_path, http_method, call_id, phase, attempt_number, correlation_id, payload_encryption_key_reference, payload_encryption_key_version, request_payload_ciphertext, request_header_metadata, request_content_type, request_bytes, request_hash, started_at, normalized_outcome) VALUES (v_operation.workspace_id, v_operation.id, v_operation.integration_key, v_operation.integration_environment, v_operation.category, v_operation.safety_class, v_operation.operation_type, v_operation.api_key, v_operation.contract_version, '/nsemfdesk/api/v2/reports/ORDER_STATUS', 'POST', p_call_id, 'REQUEST', v_event.retry_count, v_operation.correlation_id, v_key, 1, extensions.pgp_sym_encrypt(p_request_payload, public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0'), p_request_header_metadata, 'application/json', pg_catalog.octet_length(pg_catalog.convert_to(p_request_payload, 'UTF8')), extensions.digest(pg_catalog.convert_to(p_request_payload, 'UTF8'), 'sha256'), p_started_at, 'REQUEST_RECORDED') RETURNING * INTO v_row; RETURN v_row;
END; $$;

CREATE OR REPLACE FUNCTION public.finish_nse_order_status(p_event_outbox_id pg_catalog.uuid, p_claim_token pg_catalog.uuid, p_call_id pg_catalog.uuid, p_response_payload pg_catalog.text, p_response_content_type pg_catalog.text, p_response_header_metadata pg_catalog.jsonb, p_http_status pg_catalog.int4, p_native_status_value pg_catalog.text, p_native_remark_category pg_catalog.text, p_normalized_outcome pg_catalog.text, p_error_category pg_catalog.text, p_timeout_occurred pg_catalog.bool, p_network_failure pg_catalog.bool, p_completed_at pg_catalog.timestamptz, p_elapsed_ms pg_catalog.int8, p_max_attempts pg_catalog.int4, p_record_count pg_catalog.int4, p_invalid_count pg_catalog.int4) RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ DECLARE v_event public.event_outbox; v_operation public.integration_operations; v_request public.integration_api_interactions; v_result public.integration_api_interactions; v_key pg_catalog.text := 'integration_payload_encryption_key_v1'; v_state pg_catalog.text; v_retry pg_catalog.bool;
BEGIN
  SELECT * INTO v_event FROM public.event_outbox WHERE id = p_event_outbox_id FOR UPDATE; IF v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token THEN RAISE EXCEPTION 'order_status_result_not_claimed'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id = v_event.entity_id FOR UPDATE; SELECT * INTO v_request FROM public.integration_api_interactions WHERE call_id = p_call_id AND phase = 'REQUEST' AND integration_operation_id = v_operation.id; IF v_request.id IS NULL THEN RAISE EXCEPTION 'order_status_request_evidence_missing'; END IF;
  IF p_normalized_outcome NOT IN ('SUCCESS', 'BUSINESS_FAILURE', 'HTTP_FAILURE', 'TRANSPORT_FAILURE') OR p_record_count < 0 OR p_invalid_count < 0 OR p_invalid_count > p_record_count THEN RAISE EXCEPTION 'order_status_result_invalid'; END IF;
  v_retry := p_normalized_outcome = 'TRANSPORT_FAILURE' OR (p_normalized_outcome = 'HTTP_FAILURE' AND p_http_status = ANY (ARRAY[408,429,500,502,503,504]::pg_catalog.int4[])); v_state := CASE WHEN p_normalized_outcome = 'SUCCESS' THEN 'SUCCESS' WHEN p_normalized_outcome = 'BUSINESS_FAILURE' THEN 'BUSINESS_FAILED' WHEN v_retry THEN 'SUBMISSION_FAILED' ELSE 'HTTP_FAILED' END;
  INSERT INTO public.integration_api_interactions (workspace_id, integration_operation_id, integration_key, integration_environment, category, safety_class, operation_type, api_key, contract_version, endpoint_path, http_method, call_id, phase, attempt_number, correlation_id, payload_encryption_key_reference, payload_encryption_key_version, response_payload_ciphertext, response_header_metadata, response_content_type, response_bytes, response_hash, http_status, http_success, started_at, completed_at, elapsed_ms, native_status_value, native_remark_category, normalized_outcome, error_category, timeout_occurred, network_failure) VALUES (v_request.workspace_id, v_operation.id, v_request.integration_key, v_request.integration_environment, v_request.category, v_request.safety_class, v_request.operation_type, v_request.api_key, v_request.contract_version, v_request.endpoint_path, v_request.http_method, p_call_id, 'RESULT', v_request.attempt_number, v_request.correlation_id, v_key, 1, extensions.pgp_sym_encrypt(COALESCE(p_response_payload, ''), public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0'), p_response_header_metadata, p_response_content_type, pg_catalog.octet_length(pg_catalog.convert_to(COALESCE(p_response_payload, ''), 'UTF8')), extensions.digest(pg_catalog.convert_to(COALESCE(p_response_payload, ''), 'UTF8'), 'sha256'), p_http_status, p_http_status BETWEEN 200 AND 299, v_request.started_at, p_completed_at, p_elapsed_ms, p_native_status_value, p_native_remark_category, p_normalized_outcome, p_error_category, COALESCE(p_timeout_occurred, false), COALESCE(p_network_failure, false)) RETURNING * INTO v_result;
  INSERT INTO public.nse_order_status_observations (integration_operation_id, interaction_id, response_status, record_count, invalid_count) VALUES (v_operation.id, v_result.id, p_native_status_value, p_record_count, p_invalid_count);
  UPDATE public.integration_operations SET state = v_state, native_business_status = p_native_status_value, business_remark_category = p_native_remark_category, retry_allowed = v_retry AND v_event.retry_count < p_max_attempts, completed_at = p_completed_at, last_interaction_id = v_result.id WHERE id = v_operation.id;
  UPDATE public.event_outbox SET status = CASE WHEN v_retry AND v_event.retry_count < p_max_attempts THEN 'failed' ELSE 'completed' END, claim_token = NULL, claim_expires_at = NULL, updated_at = pg_catalog.now() WHERE id = v_event.id; RETURN v_result;
END; $$;

REVOKE ALL ON FUNCTION public.prepare_nse_order_status(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.date, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text[], pg_catalog.text[]) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_nse_order_status_source(pg_catalog.uuid), public.claim_nse_order_status_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4), public.recover_expired_nse_order_status_events(pg_catalog.uuid, pg_catalog.int4), public.start_nse_order_status(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb, pg_catalog.timestamptz), public.finish_nse_order_status(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.timestamptz, pg_catalog.int8, pg_catalog.int4, pg_catalog.int4, pg_catalog.int4) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_nse_order_status(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.date, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text[], pg_catalog.text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_nse_order_status_source(pg_catalog.uuid), public.claim_nse_order_status_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4), public.recover_expired_nse_order_status_events(pg_catalog.uuid, pg_catalog.int4), public.start_nse_order_status(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb, pg_catalog.timestamptz), public.finish_nse_order_status(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.timestamptz, pg_catalog.int8, pg_catalog.int4, pg_catalog.int4, pg_catalog.int4) TO service_role;
COMMIT;
