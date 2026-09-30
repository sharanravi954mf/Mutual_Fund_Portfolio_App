-- NSE-T002: account-scoped, read-only ORDER_STATUS reports.  The request and
-- sanitized observation tables are deliberately private; raw NSE data is kept
-- only in the existing encrypted append-only evidence ledger.
BEGIN;

CREATE TABLE public.nse_order_status_requests (
  integration_operation_id pg_catalog.uuid PRIMARY KEY REFERENCES public.integration_operations(id) ON DELETE RESTRICT,
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  integration_account_id pg_catalog.uuid NOT NULL REFERENCES public.integration_accounts(id) ON DELETE RESTRICT,
  from_date pg_catalog.date NOT NULL,
  to_date pg_catalog.date NOT NULL,
  trans_type pg_catalog.text NOT NULL CHECK (trans_type IN ('P','R','ALL')),
  order_type pg_catalog.text NOT NULL CHECK (order_type IN ('ALL','NRM','SIP','XSP','STP')),
  sub_order_type pg_catalog.text NOT NULL CHECK (sub_order_type IN ('ALL','NRM','SPOR','SWH','STP')),
  order_status pg_catalog.text CHECK (order_status IN ('All','VALID','INVALID')),
  settlement_type pg_catalog.text CHECK (settlement_type IN ('ALL','L0','L1','OTHERS')),
  order_ids pg_catalog.text[], member_unique_ids pg_catalog.text[],
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CHECK (to_date >= from_date AND to_date <= from_date + 6),
  CHECK (pg_catalog.coalesce(pg_catalog.cardinality(order_ids), 0) <= 50),
  CHECK (pg_catalog.coalesce(pg_catalog.cardinality(member_unique_ids), 0) <= 50),
  CHECK (order_ids IS NULL OR member_unique_ids IS NULL)
);
CREATE TABLE public.nse_order_status_observations (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  integration_operation_id pg_catalog.uuid NOT NULL REFERENCES public.integration_operations(id) ON DELETE RESTRICT,
  interaction_id pg_catalog.uuid NOT NULL REFERENCES public.integration_api_interactions(id) ON DELETE RESTRICT,
  native_status pg_catalog.text NOT NULL CHECK (native_status IN ('S','F')),
  record_count pg_catalog.int4 NOT NULL CHECK (record_count >= 0),
  projected_records pg_catalog.jsonb NOT NULL DEFAULT '[]'::pg_catalog.jsonb,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  UNIQUE (integration_operation_id, interaction_id),
  CHECK (pg_catalog.jsonb_typeof(projected_records) = 'array')
);
CREATE OR REPLACE FUNCTION public.reject_nse_order_status_storage_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$ BEGIN RAISE EXCEPTION 'nse_order_status_storage_append_only'; END; $$;
CREATE TRIGGER nse_order_status_requests_immutable BEFORE UPDATE OR DELETE ON public.nse_order_status_requests FOR EACH ROW EXECUTE FUNCTION public.reject_nse_order_status_storage_mutation();
CREATE TRIGGER nse_order_status_observations_immutable BEFORE UPDATE OR DELETE ON public.nse_order_status_observations FOR EACH ROW EXECUTE FUNCTION public.reject_nse_order_status_storage_mutation();
CREATE UNIQUE INDEX event_outbox_one_nse_order_status_idx ON public.event_outbox (entity_type, entity_id, event_type) WHERE event_type = 'integration.nse.order_status_requested' AND entity_type = 'integration_operation' AND status IN ('pending','processing','failed');

CREATE OR REPLACE FUNCTION public.prepare_nse_order_status(
  p_workspace_id pg_catalog.uuid, p_investor_profile_id pg_catalog.uuid,
  p_from_date pg_catalog.date, p_to_date pg_catalog.date, p_trans_type pg_catalog.text,
  p_order_type pg_catalog.text, p_sub_order_type pg_catalog.text,
  p_order_status pg_catalog.text DEFAULT NULL, p_settlement_type pg_catalog.text DEFAULT NULL,
  p_order_ids pg_catalog.text[] DEFAULT NULL, p_member_unique_ids pg_catalog.text[] DEFAULT NULL
) RETURNS public.integration_operations LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_account public.integration_accounts; v_operation public.integration_operations;
BEGIN
  IF p_workspace_id IS NULL OR p_investor_profile_id IS NULL OR p_from_date IS NULL OR p_to_date IS NULL
     OR p_to_date < p_from_date OR p_to_date > p_from_date + 6 THEN RAISE EXCEPTION 'order_status_date_range_invalid'; END IF;
  IF p_trans_type NOT IN ('P','R','ALL') OR p_order_type NOT IN ('ALL','NRM','SIP','XSP','STP') OR p_sub_order_type NOT IN ('ALL','NRM','SPOR','SWH','STP')
     OR p_order_status IS NOT NULL AND p_order_status NOT IN ('All','VALID','INVALID')
     OR p_settlement_type IS NOT NULL AND p_settlement_type NOT IN ('ALL','L0','L1','OTHERS') THEN RAISE EXCEPTION 'order_status_filter_invalid'; END IF;
  IF pg_catalog.coalesce(pg_catalog.cardinality(p_order_ids),0) > 50 OR pg_catalog.coalesce(pg_catalog.cardinality(p_member_unique_ids),0) > 50 THEN RAISE EXCEPTION 'order_status_identifier_limit_exceeded'; END IF;
  IF p_order_ids IS NOT NULL AND p_member_unique_ids IS NOT NULL THEN p_member_unique_ids := NULL; END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.unnest(pg_catalog.coalesce(p_order_ids,p_member_unique_ids,ARRAY[]::pg_catalog.text[])) AS v(id) WHERE v.id !~ '^[A-Za-z0-9_-]{1,64}$') THEN RAISE EXCEPTION 'order_status_identifier_invalid'; END IF;
  SELECT * INTO v_account FROM public.integration_accounts account WHERE account.workspace_id=p_workspace_id AND account.investor_profile_id=p_investor_profile_id AND account.integration_key='NSE_INVEST' AND account.integration_environment='UAT' FOR UPDATE;
  IF v_account.id IS NULL OR v_account.state <> 'REGISTERED' OR NULLIF(pg_catalog.btrim(v_account.external_account_id),'') IS NULL THEN RAISE EXCEPTION 'order_status_registered_account_required'; END IF;
  INSERT INTO public.integration_operations (workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state)
  VALUES (p_workspace_id,v_account.id,'NSE_INVEST','UAT','RECONCILIATION','READ_ONLY','ORDER_STATUS_REPORT','ORDER_STATUS','NNF_1.9.7','PREPARED') RETURNING * INTO v_operation;
  INSERT INTO public.nse_order_status_requests (integration_operation_id,workspace_id,integration_account_id,from_date,to_date,trans_type,order_type,sub_order_type,order_status,settlement_type,order_ids,member_unique_ids)
  VALUES (v_operation.id,p_workspace_id,v_account.id,p_from_date,p_to_date,p_trans_type,p_order_type,p_sub_order_type,p_order_status,p_settlement_type,p_order_ids,p_member_unique_ids);
  UPDATE public.integration_operations SET state='QUEUED' WHERE id=v_operation.id RETURNING * INTO v_operation;
  INSERT INTO public.event_outbox (event_type,payload,status,entity_id,entity_type) VALUES ('integration.nse.order_status_requested',pg_catalog.jsonb_build_object('integration_operation_id',v_operation.id),'pending',v_operation.id,'integration_operation');
  RETURN v_operation;
END; $$;

CREATE OR REPLACE FUNCTION public.get_nse_order_status_source(p_integration_operation_id pg_catalog.uuid)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result pg_catalog.jsonb;
BEGIN
 SELECT pg_catalog.jsonb_build_object('operation_id',o.id,'workspace_id',o.workspace_id,'integration_account_id',o.integration_account_id,'correlation_id',o.correlation_id,'client_code',a.external_account_id,'from_date',r.from_date::pg_catalog.text,'to_date',r.to_date::pg_catalog.text,'trans_type',r.trans_type,'order_type',r.order_type,'sub_order_type',r.sub_order_type,'order_status',r.order_status,'settlement_type',r.settlement_type,'order_ids',r.order_ids,'member_unique_ids',r.member_unique_ids) INTO v_result
 FROM public.integration_operations o JOIN public.integration_accounts a ON a.id=o.integration_account_id JOIN public.nse_order_status_requests r ON r.integration_operation_id=o.id
 WHERE o.id=p_integration_operation_id AND o.integration_key='NSE_INVEST' AND o.integration_environment='UAT' AND o.category='RECONCILIATION' AND o.safety_class='READ_ONLY' AND o.operation_type='ORDER_STATUS_REPORT' AND o.api_key='ORDER_STATUS' AND o.contract_version='NNF_1.9.7' AND o.state IN ('QUEUED','SUBMISSION_FAILED') AND (o.state='QUEUED' OR o.retry_allowed);
 IF v_result IS NULL THEN RAISE EXCEPTION 'order_status_source_unavailable'; END IF; RETURN v_result;
END; $$;

CREATE OR REPLACE FUNCTION public.recover_expired_nse_order_status_events(p_event_outbox_id pg_catalog.uuid,p_max_attempts pg_catalog.int4 DEFAULT 3)
RETURNS pg_catalog.text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE e public.event_outbox; o public.integration_operations; retry pg_catalog.bool;
BEGIN
 IF p_max_attempts NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'invalid_max_attempts'; END IF;
 SELECT * INTO e FROM public.event_outbox WHERE id=p_event_outbox_id FOR UPDATE;
 IF e.id IS NULL OR e.event_type<>'integration.nse.order_status_requested' OR e.status<>'processing' OR e.claim_expires_at>pg_catalog.now() THEN RETURN 'no_recovery_required'; END IF;
 SELECT * INTO o FROM public.integration_operations WHERE id=e.entity_id FOR UPDATE; retry:=e.retry_count<p_max_attempts;
 IF o.id IS NULL OR o.operation_type<>'ORDER_STATUS_REPORT' THEN RETURN 'no_recovery_required'; END IF;
 UPDATE public.integration_operations SET state='SUBMISSION_FAILED',retry_allowed=retry,business_remark_category='order_status_read_lease_expired',completed_at=pg_catalog.now(),ambiguous_outcome=false,reconciliation_required=false WHERE id=o.id;
 UPDATE public.event_outbox SET status='failed',error_message=CASE WHEN retry THEN 'order_status_read_retryable' ELSE 'order_status_read_attempts_exhausted' END,claimed_by=NULL,claim_token=NULL,claim_expires_at=NULL,updated_at=pg_catalog.now() WHERE id=e.id;
 RETURN CASE WHEN retry THEN 'safe_read_retry_available' ELSE 'order_status_attempts_exhausted' END;
END; $$;

CREATE OR REPLACE FUNCTION public.claim_nse_order_status_event(p_event_outbox_id pg_catalog.uuid,p_max_attempts pg_catalog.int4 DEFAULT 3,p_lease_seconds pg_catalog.int4 DEFAULT 120)
RETURNS TABLE(event_outbox_id pg_catalog.uuid,integration_operation_id pg_catalog.uuid,attempt pg_catalog.int4,claim_state pg_catalog.text,claim_token pg_catalog.uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE e public.event_outbox; o public.integration_operations;
BEGIN
 IF p_max_attempts NOT BETWEEN 1 AND 5 OR p_lease_seconds NOT BETWEEN 15 AND 900 THEN RAISE EXCEPTION 'order_status_claim_input_invalid'; END IF;
 WITH candidate AS (SELECT event.id,pg_catalog.gen_random_uuid() token FROM public.event_outbox event JOIN public.integration_operations op ON op.id=event.entity_id WHERE event.id=p_event_outbox_id AND event.event_type='integration.nse.order_status_requested' AND event.entity_type='integration_operation' AND event.retry_count<p_max_attempts AND ((event.status='pending' AND op.state='QUEUED') OR (event.status='failed' AND op.state='SUBMISSION_FAILED' AND op.retry_allowed)) FOR UPDATE OF event SKIP LOCKED)
 UPDATE public.event_outbox event SET status='processing',retry_count=event.retry_count+1,claimed_at=pg_catalog.now(),claimed_by=candidate.token,claim_token=candidate.token,claim_expires_at=pg_catalog.now()+(p_lease_seconds::pg_catalog.text||' seconds')::pg_catalog.interval,error_message=NULL,updated_at=pg_catalog.now() FROM candidate WHERE event.id=candidate.id RETURNING event.* INTO e;
 IF e.id IS NULL THEN RETURN QUERY SELECT NULL::pg_catalog.uuid,NULL::pg_catalog.uuid,0::pg_catalog.int4,'no_event'::pg_catalog.text,NULL::pg_catalog.uuid; RETURN; END IF;
 SELECT * INTO o FROM public.integration_operations WHERE id=e.entity_id; RETURN QUERY SELECT e.id,o.id,e.retry_count,CASE WHEN e.retry_count=1 THEN 'newly_claimed' ELSE 'safe_retry_claimed' END,e.claim_token;
END; $$;

CREATE OR REPLACE FUNCTION public.start_nse_order_status(p_event_outbox_id pg_catalog.uuid,p_claim_token pg_catalog.uuid,p_call_id pg_catalog.uuid,p_request_payload pg_catalog.text,p_request_header_metadata pg_catalog.jsonb,p_started_at pg_catalog.timestamptz)
RETURNS public.integration_api_interactions LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE e public.event_outbox; o public.integration_operations; x public.integration_api_interactions; b pg_catalog.int8; h pg_catalog.bytea; k pg_catalog.text:='integration_payload_encryption_key_v1'; j pg_catalog.jsonb;
BEGIN
 IF p_call_id IS NULL OR p_started_at IS NULL OR NULLIF(p_request_payload,'') IS NULL THEN RAISE EXCEPTION 'order_status_request_incomplete'; END IF;
 BEGIN j:=p_request_payload::pg_catalog.jsonb; EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'order_status_request_invalid'; END;
 IF pg_catalog.jsonb_typeof(j)<>'object' OR j ? 'date_type' OR j->>'client_code' !~ '^[A-Z0-9]{1,10}$' OR NOT public.integration_header_metadata_is_safe(p_request_header_metadata,'REQUEST') OR p_request_header_metadata->>'content_type' IS DISTINCT FROM 'application/json' OR p_request_header_metadata->>'accept' IS DISTINCT FROM 'application/json' THEN RAISE EXCEPTION 'order_status_request_invalid'; END IF;
 SELECT * INTO e FROM public.event_outbox WHERE id=p_event_outbox_id FOR UPDATE;
 IF e.id IS NULL OR e.event_type<>'integration.nse.order_status_requested' OR e.status<>'processing' OR e.claim_token IS DISTINCT FROM p_claim_token OR e.claim_expires_at<=pg_catalog.now() THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
 SELECT * INTO o FROM public.integration_operations WHERE id=e.entity_id FOR UPDATE;
 IF o.operation_type<>'ORDER_STATUS_REPORT' OR o.api_key<>'ORDER_STATUS' OR o.category<>'RECONCILIATION' OR o.safety_class<>'READ_ONLY' OR o.contract_version<>'NNF_1.9.7' OR o.state NOT IN ('QUEUED','SUBMISSION_FAILED') OR (o.state='SUBMISSION_FAILED' AND NOT o.retry_allowed) THEN RAISE EXCEPTION 'integration_operation_not_order_status'; END IF;
 b:=pg_catalog.octet_length(pg_catalog.convert_to(p_request_payload,'UTF8')); h:=extensions.digest(pg_catalog.convert_to(p_request_payload,'UTF8'),'sha256');
 SELECT * INTO x FROM public.integration_api_interactions WHERE call_id=p_call_id AND phase='REQUEST';
 IF x.id IS NOT NULL THEN IF x.integration_operation_id IS DISTINCT FROM o.id OR x.request_hash IS DISTINCT FROM h OR x.request_header_metadata IS DISTINCT FROM p_request_header_metadata THEN RAISE EXCEPTION 'integration_request_idempotency_conflict'; END IF; RETURN x; END IF;
 INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,request_payload_ciphertext,request_header_metadata,request_content_type,request_bytes,request_hash,started_at,normalized_outcome)
 VALUES(o.workspace_id,o.id,o.integration_key,o.integration_environment,o.category,o.safety_class,o.operation_type,o.api_key,o.contract_version,'/nsemfdesk/api/v2/reports/ORDER_STATUS','POST',p_call_id,'REQUEST',e.retry_count,o.correlation_id,k,1,extensions.pgp_sym_encrypt(p_request_payload,public.integration_payload_encryption_key(k),'cipher-algo=aes256, compress-algo=0'),p_request_header_metadata,'application/json',b,h,p_started_at,'REQUEST_RECORDED') RETURNING * INTO x;
 UPDATE public.integration_operations SET state='SUBMITTING',attempt_count=e.retry_count,retry_allowed=false,submitted_at=p_started_at,completed_at=NULL,last_interaction_id=x.id WHERE id=o.id; RETURN x;
END; $$;

CREATE OR REPLACE FUNCTION public.finish_nse_order_status(p_event_outbox_id pg_catalog.uuid,p_claim_token pg_catalog.uuid,p_call_id pg_catalog.uuid,p_response_payload pg_catalog.text,p_response_content_type pg_catalog.text,p_response_header_metadata pg_catalog.jsonb,p_http_status pg_catalog.int4,p_native_status_value pg_catalog.text,p_native_remark_category pg_catalog.text,p_normalized_outcome pg_catalog.text,p_error_category pg_catalog.text,p_timeout_occurred pg_catalog.bool,p_network_failure pg_catalog.bool,p_completed_at pg_catalog.timestamptz,p_elapsed_ms pg_catalog.int8,p_max_attempts pg_catalog.int4 DEFAULT 3)
RETURNS public.integration_api_interactions LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE q public.integration_api_interactions; x public.integration_api_interactions; e public.event_outbox; o public.integration_operations; b pg_catalog.int8; h pg_catalog.bytea; k pg_catalog.text:='integration_payload_encryption_key_v1'; retry pg_catalog.bool:=false; v_state pg_catalog.text; event_state pg_catalog.text:='completed'; response pg_catalog.jsonb; rows pg_catalog.jsonb:='[]'::pg_catalog.jsonb; cnt pg_catalog.int4:=0;
BEGIN
 IF p_completed_at IS NULL OR p_elapsed_ms<0 OR p_max_attempts NOT BETWEEN 1 AND 5 OR p_normalized_outcome NOT IN ('SUCCESS','BUSINESS_FAILURE','HTTP_FAILURE','TRANSPORT_FAILURE') OR NOT public.integration_header_metadata_is_safe(p_response_header_metadata,'RESULT') THEN RAISE EXCEPTION 'order_status_result_invalid'; END IF;
 SELECT * INTO q FROM public.integration_api_interactions WHERE call_id=p_call_id AND phase='REQUEST'; IF q.id IS NULL THEN RAISE EXCEPTION 'integration_request_evidence_missing'; END IF;
 b:=pg_catalog.octet_length(pg_catalog.convert_to(pg_catalog.coalesce(p_response_payload,''),'UTF8')); h:=extensions.digest(pg_catalog.convert_to(pg_catalog.coalesce(p_response_payload,''),'UTF8'),'sha256');
 SELECT * INTO x FROM public.integration_api_interactions WHERE call_id=p_call_id AND phase='RESULT'; IF x.id IS NOT NULL THEN RETURN x; END IF;
 SELECT * INTO e FROM public.event_outbox WHERE id=p_event_outbox_id FOR UPDATE; IF e.id IS NULL OR e.status<>'processing' OR e.claim_token IS DISTINCT FROM p_claim_token THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
 SELECT * INTO o FROM public.integration_operations WHERE id=q.integration_operation_id FOR UPDATE; IF o.state<>'SUBMITTING' OR o.operation_type<>'ORDER_STATUS_REPORT' THEN RAISE EXCEPTION 'integration_operation_not_submitting'; END IF;
 IF p_http_status BETWEEN 200 AND 299 THEN BEGIN response:=p_response_payload::pg_catalog.jsonb; EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'order_status_response_invalid'; END; IF response->>'response_status' NOT IN ('S','F') THEN RAISE EXCEPTION 'order_status_response_invalid'; END IF; IF pg_catalog.jsonb_typeof(pg_catalog.coalesce(response->'report_data','[]'::pg_catalog.jsonb))<>'array' THEN RAISE EXCEPTION 'order_status_response_invalid'; END IF; SELECT pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object('order_id',row.value->'order_id','member_unique_id',row.value->'member_unique_id','order_status',row.value->'order_status','product_code',row.value->'product_code','product_name',row.value->'product_name','amount',row.value->'amount','units',row.value->'units','transaction_type',row.value->'transaction_type','order_type',row.value->'order_type','sub_order_type',row.value->'sub_order_type','settlement_type',row.value->'settlement_type','order_date',row.value->'order_date'))),'[]'::pg_catalog.jsonb),pg_catalog.count(*)::pg_catalog.int4 INTO rows,cnt FROM pg_catalog.jsonb_array_elements(pg_catalog.coalesce(response->'report_data','[]'::pg_catalog.jsonb)) row(value); END IF;
 IF (p_normalized_outcome='SUCCESS' AND NOT(p_http_status BETWEEN 200 AND 299 AND p_native_status_value='S')) OR (p_normalized_outcome='BUSINESS_FAILURE' AND NOT(p_http_status BETWEEN 200 AND 299 AND p_native_status_value='F')) OR (p_normalized_outcome='HTTP_FAILURE' AND (p_http_status IS NULL OR p_http_status BETWEEN 200 AND 299)) OR (p_normalized_outcome='TRANSPORT_FAILURE' AND p_http_status IS NOT NULL) THEN RAISE EXCEPTION 'order_status_outcome_invariant_failed'; END IF;
 IF p_normalized_outcome='TRANSPORT_FAILURE' OR (p_normalized_outcome='HTTP_FAILURE' AND p_http_status=ANY(ARRAY[408,429,500,502,503,504]::pg_catalog.int4[])) THEN v_state:='SUBMISSION_FAILED'; retry:=e.retry_count<p_max_attempts; event_state:='failed'; ELSIF p_normalized_outcome='SUCCESS' THEN v_state:='SUCCESS'; ELSIF p_normalized_outcome='BUSINESS_FAILURE' THEN v_state:='BUSINESS_FAILED'; ELSE v_state:='HTTP_FAILED'; END IF;
 INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,started_at,response_payload_ciphertext,response_header_metadata,response_content_type,response_bytes,response_hash,http_status,http_success,completed_at,elapsed_ms,native_status_field,native_status_value,native_remark_category,normalized_outcome,error_category,timeout_occurred,network_failure,ambiguous_outcome,reconciliation_required) VALUES(q.workspace_id,q.integration_operation_id,q.integration_key,q.integration_environment,q.category,q.safety_class,q.operation_type,q.api_key,q.contract_version,q.endpoint_path,q.http_method,p_call_id,'RESULT',q.attempt_number,q.correlation_id,k,1,q.started_at,extensions.pgp_sym_encrypt(pg_catalog.coalesce(p_response_payload,''),public.integration_payload_encryption_key(k),'cipher-algo=aes256, compress-algo=0'),p_response_header_metadata,p_response_content_type,b,h,p_http_status,CASE WHEN p_http_status IS NULL THEN NULL ELSE p_http_status BETWEEN 200 AND 299 END,p_completed_at,p_elapsed_ms,'response_status',p_native_status_value,p_native_remark_category,p_normalized_outcome,p_error_category,pg_catalog.coalesce(p_timeout_occurred,false),pg_catalog.coalesce(p_network_failure,false),false,false) RETURNING * INTO x;
 IF p_normalized_outcome='SUCCESS' THEN INSERT INTO public.nse_order_status_observations(integration_operation_id,interaction_id,native_status,record_count,projected_records) VALUES(o.id,x.id,'S',cnt,rows); END IF;
 UPDATE public.integration_operations SET state=v_state,retry_allowed=retry,native_business_status=p_native_status_value,business_remark_category=p_native_remark_category,completed_at=p_completed_at,last_interaction_id=x.id,ambiguous_outcome=false,reconciliation_required=false WHERE id=o.id;
 UPDATE public.event_outbox SET status=event_state,error_message=CASE WHEN event_state='failed' THEN CASE WHEN retry THEN 'order_status_read_retryable' ELSE 'order_status_read_attempts_exhausted' END ELSE NULL END,claimed_by=NULL,claim_token=NULL,claim_expires_at=NULL,updated_at=pg_catalog.now() WHERE id=e.id; RETURN x;
END; $$;

ALTER TABLE public.nse_order_status_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nse_order_status_observations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nse_order_status_requests,public.nse_order_status_observations FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reject_nse_order_status_storage_mutation(),public.prepare_nse_order_status(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.date,pg_catalog.date,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text[],pg_catalog.text[]),public.get_nse_order_status_source(pg_catalog.uuid),public.recover_expired_nse_order_status_events(pg_catalog.uuid,pg_catalog.int4),public.claim_nse_order_status_event(pg_catalog.uuid,pg_catalog.int4,pg_catalog.int4),public.start_nse_order_status(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.jsonb,pg_catalog.timestamptz),public.finish_nse_order_status(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.text,pg_catalog.jsonb,pg_catalog.int4,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.bool,pg_catalog.bool,pg_catalog.timestamptz,pg_catalog.int8,pg_catalog.int4) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_nse_order_status(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.date,pg_catalog.date,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text[],pg_catalog.text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_nse_order_status_source(pg_catalog.uuid),public.recover_expired_nse_order_status_events(pg_catalog.uuid,pg_catalog.int4),public.claim_nse_order_status_event(pg_catalog.uuid,pg_catalog.int4,pg_catalog.int4),public.start_nse_order_status(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.jsonb,pg_catalog.timestamptz),public.finish_nse_order_status(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.text,pg_catalog.jsonb,pg_catalog.int4,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.bool,pg_catalog.bool,pg_catalog.timestamptz,pg_catalog.int8,pg_catalog.int4) TO service_role;
COMMIT;
