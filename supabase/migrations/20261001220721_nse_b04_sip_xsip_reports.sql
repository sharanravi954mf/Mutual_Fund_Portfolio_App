-- B04: nine independent evidence-only SIP/XSIP reports, NNF 1.9.7 pp164–180.
-- No schedule/business tables, financial projections or provider write APIs.
BEGIN;
CREATE FUNCTION public.nse_sip_xsip_reports_contract(p_api pg_catalog.text)
RETURNS pg_catalog.jsonb LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
 SELECT CASE p_api
 WHEN 'SIP_REG_REPORT' THEN '{"path":"/nsemfdesk/api/v2/reports/SIP_REG_REPORT","category":"SYSTEMATIC","fields":["status","member_code","client_code","client_name","pg_bank_ref_no","sip_reg_number","sip_reg_date","amc_name","rta_scheme_code","scheme_name","frequency_type","start_date","end_date","installments_amount","entry_by","dpc_flag","dp_trans","first_order_today","sub_broker_code","euin","euin_declaration","folio_number","remarks","sub_broker_arn_code","no_of_installments","exchange_remark","health_declaration_flag","nominee_dob","disclaimer_flag","internal_ref_no","primary_holder_email","primary_holder_mobile","second_holder_email","second_holder_mobile","third_holder_email","third_holder_mobile","member_unique_id"],"id":"sip_reg_number","selector":"sip_reg_id","days":31,"member":true,"distinct":["sip_reg_number"]}'::pg_catalog.jsonb
 WHEN 'SIP_CAN_REPORT' THEN '{"path":"/nsemfdesk/api/v2/reports/SIP_CAN_REPORT","category":"SYSTEMATIC","fields":["member_code","client_code","client_name","internal_ref_num","sip_registration_no","sip_registration_date","sip_cancellation_date","amc_name","scheme_code","scheme_name","frequency_type","start_date","end_date","next_due_date","no_of_installments_paid","installments_amt","total_installment_amt_paid","cancelled_by","sip_status","remark"],"id":"sip_registration_no","selector":"sip_reg_id","days":31,"member":false,"distinct":["sip_registration_no"]}'::pg_catalog.jsonb
 WHEN 'SIP_INST_DUE_REPORT' THEN '{"path":"/nsemfdesk/api/v2/reports/SIP_INST_DUE_REPORT","category":"SYSTEMATIC","fields":["member_code","client_code","client_name","internal_ref_no","sip_reg_number","reg_date","amc_name","scheme_code","scheme_name","frequency_type","installment_amt","due_date","prev_paid_date","no_of_installments_paid","total_installment_amt_paid","entry_by","dp_trans","first_order_today"],"id":"sip_reg_number","selector":"sip_reg_id","days":7,"member":false,"distinct":["sip_reg_number","due_date"]}'::pg_catalog.jsonb
 WHEN 'SIP_TOPUP_REPORT' THEN '{"path":"/nsemfdesk/api/v2/reports/SIP_TOPUP_REPORT","category":"SYSTEMATIC","fields":["member_code","client_code","client_name","reg_no","scheme_code","scheme_name","sip_xsip_amount","start_date","end_date","top_up_amount","date_of_activation","entry_by","principle_sip_reg_no","principle_sip_internal_ref_no","last_child_sip_reg_no","top_up_frequency","top_up_status"],"id":"reg_no","selector":"parent_sip_reg_id","days":31,"member":false,"distinct":["reg_no"]}'::pg_catalog.jsonb
 WHEN 'STEPUP_REG_REPORT' THEN '{"path":"/nsemfdesk/api/v2/reports/STEPUP_REG_REPORT","category":"SYSTEMATIC","fields":["status","member_code","client_code","client_name","sip_xsip_regn_number","sip_xsip_regn_date","sip_xsip_type","amc_name","rta_scheme_code","scheme_code","scheme_name","frequency_type","start_date","end_date","stepup_start__effective_date","stepup_enddate","stepup_frequency","stepup_amount","entry_by"],"id":"sip_xsip_regn_number","selector":"sip_reg_id","days":31,"member":false,"distinct":["sip_xsip_regn_number","sip_xsip_type","stepup_start__effective_date","stepup_enddate"]}'::pg_catalog.jsonb
 WHEN 'XSIP_REG_REPORT' THEN '{"path":"/nsemfdesk/api/v2/reports/XSIP_REG_REPORT","category":"SYSTEMATIC","fields":["status","member_code","client_code","client_name","pg_bank_ref_no","xsip_registration_no","xsip_registration_date","amc_name","rta_scheme_code","scheme_name","frequency_type","start_date","end_date","installments_amount","brokerage","entry_by","nse_mandate_id","dpc_flag","dp_trans","sub_broker","euin_no","euin_declaration","first_order_today","folio_number","remarks","sub_broker_arn","no_of_installments","exchange_remark","health_declaration_flag","nominee_dob","disclaimer_flag","internal_ref_no","primary_holder_email","primary_holder_mobile","second_holder_email","second_holder_mobile","third_holder_email","third_holder_mobile","member_unique_id"],"id":"xsip_registration_no","selector":"xsip_reg_id","days":31,"member":true,"distinct":["xsip_registration_no"]}'::pg_catalog.jsonb
 WHEN 'XSIP_CAN_REPORT' THEN '{"path":"/nsemfdesk/api/v2/reports/XSIP_CAN_REPORT","category":"SYSTEMATIC","fields":["status","member_code","client_code","client_name","internal_ref_num","xsip_registration_no","xsip_registration_date","xsip_cancellation_date","amc_name","scheme_code","scheme_name","frequency_type","start_date","end_date","next_due_date","no_of_installments_paid","installments_amt","brokerage","total_installment_amt_paid","cancelled_by","nse_mandate_id","remark"],"id":"xsip_registration_no","selector":"xsip_reg_id","days":31,"member":false,"distinct":["xsip_registration_no"]}'::pg_catalog.jsonb
 WHEN 'XSIP_INST_DUE_REPORT' THEN '{"path":"/nsemfdesk/api/v2/reports/XSIP_INST_DUE_REPORT","category":"SYSTEMATIC","fields":["member_code","client_code","client_name","internal_ref_no","sip_reg_number","reg_date","amc_name","scheme_code","scheme_name","frequency_type","installment_amt","due_date","prev_paid_date","no_of_installments_paid","total_installment_amt_paid","entry_by","mandate_id","dp_trans","first_order_today"],"id":"sip_reg_number","selector":"xsip_reg_id","days":7,"member":false,"distinct":["sip_reg_number","due_date"]}'::pg_catalog.jsonb
 WHEN 'XSIP_TOPUP_REPORT' THEN '{"path":"/nsemfdesk/api/v2/reports/XSIP_TOPUP_REPORT","category":"SYSTEMATIC","fields":["member_code","client_code","client_name","reg_no","scheme_code","scheme_name","sip_xsip_amount","start_date","end_date","top_up_amount","date_of_activation","entry_by","principle_sip_reg_no","principle_sip_internal_ref_no","last_child_sip_reg_no","top_up_frequency","top_up_status"],"id":"reg_no","selector":"parent_xsip_reg_id","days":31,"member":false,"distinct":["reg_no"]}'::pg_catalog.jsonb
 ELSE NULL END;
$$;
CREATE FUNCTION public.nse_b04_date(p_value pg_catalog.text,p_format pg_catalog.text)
RETURNS pg_catalog.date LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE v_date pg_catalog.date; v_pattern pg_catalog.text;
BEGIN
 v_pattern := CASE p_format WHEN 'DD-MM-YYYY' THEN '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
 WHEN 'DD/MM/YYYY' THEN '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' WHEN 'YYYY-MM-DD' THEN '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
 WHEN 'DD MON YYYY' THEN '^[0-9]{2} [A-Z]{3} [0-9]{4}$' END;
 IF p_value IS NULL OR v_pattern IS NULL OR p_value !~ v_pattern THEN RAISE EXCEPTION 'sip_xsip_reports_date_invalid'; END IF;
 v_date := pg_catalog.to_date(p_value,p_format);
 IF pg_catalog.to_char(v_date,p_format)<>p_value OR EXTRACT(YEAR FROM v_date)<1 THEN RAISE EXCEPTION 'sip_xsip_reports_date_invalid'; END IF;
 RETURN v_date;
END $$;
-- p_today is an explicit India market day. NULL is used only for historical
-- evidence interpretation; prepare/load/start recheck against the current day.
CREATE FUNCTION public.validate_nse_sip_xsip_reports_filters(p_api pg_catalog.text,p_filters pg_catalog.jsonb,
 p_today pg_catalog.date DEFAULT (pg_catalog.timezone('Asia/Kolkata',pg_catalog.now()))::pg_catalog.date)
RETURNS pg_catalog.void LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE v_from pg_catalog.date; v_to pg_catalog.date; v_contract pg_catalog.jsonb;
BEGIN
 v_contract:=public.nse_sip_xsip_reports_contract(p_api);
 IF v_contract IS NULL OR pg_catalog.jsonb_typeof(p_filters) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'sip_xsip_reports_filters_invalid'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(p_filters) k WHERE k NOT IN ('from_date','to_date'))
 OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_each(p_filters) WHERE pg_catalog.jsonb_typeof(value)<>'string') THEN RAISE EXCEPTION 'sip_xsip_reports_filters_invalid'; END IF;
 IF p_filters='{}'::pg_catalog.jsonb THEN RETURN; END IF;
 BEGIN
  v_from:=public.nse_b04_date(p_filters->>'from_date','DD-MM-YYYY'); v_to:=public.nse_b04_date(p_filters->>'to_date','DD-MM-YYYY');
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'sip_xsip_reports_filters_invalid'; END;
 IF v_to<=v_from OR v_to-v_from>(v_contract->>'days')::pg_catalog.int4
  OR ((v_contract->>'days')::pg_catalog.int4=7 AND p_today IS NOT NULL AND v_from<p_today) THEN RAISE EXCEPTION 'sip_xsip_reports_filters_invalid'; END IF;
END $$;
CREATE FUNCTION public.nse_sip_xsip_registration_fields(p_api pg_catalog.text)
RETURNS pg_catalog.text[] LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
 SELECT CASE p_api WHEN 'SIP_REG_REPORT' THEN ARRAY['sip_reg_number','sip_reg_date']
 WHEN 'XSIP_REG_REPORT' THEN ARRAY['xsip_registration_no','xsip_registration_date'] END
 || ARRAY['member_unique_id','member_code','rta_scheme_code','frequency_type','start_date','end_date','installments_amount'];
$$;
-- Native registration IDs outrank member IDs; member IDs outrank UCC. Native
-- reg/parent selectors stay disabled. Member-only requests require owned lineage.
CREATE FUNCTION public.nse_sip_xsip_reports_request(p_api pg_catalog.text,p_filters pg_catalog.jsonb,p_identity pg_catalog.jsonb)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE v_ids pg_catalog.text; v_rows pg_catalog.jsonb; v_row pg_catalog.jsonb; v_fields pg_catalog.text[];
 v_seen pg_catalog.text[]:=ARRAY[]::pg_catalog.text[]; v_regs pg_catalog.text[]:=ARRAY[]::pg_catalog.text[];
BEGIN
 PERFORM public.validate_nse_sip_xsip_reports_filters(p_api,p_filters,NULL);
 IF p_identity->>'client_code' IS NULL OR p_identity->>'client_code' !~ '^[A-Za-z0-9_-]{1,20}$'
 OR pg_catalog.jsonb_typeof(p_identity->'selectors') IS DISTINCT FROM 'object'
 OR pg_catalog.jsonb_typeof(p_identity->'selectors'->'rows') IS DISTINCT FROM 'array'
 OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(p_identity->'selectors') k WHERE k NOT IN ('mode','rows')) THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
 v_rows:=p_identity->'selectors'->'rows';
 IF p_identity->'selectors'->>'mode'='client' AND v_rows='[]'::pg_catalog.jsonb THEN
  RETURN p_filters||pg_catalog.jsonb_build_object('client_code',p_identity->>'client_code');
 END IF;
 IF p_identity->'selectors'->>'mode' IS DISTINCT FROM 'member' OR p_api NOT IN ('SIP_REG_REPORT','XSIP_REG_REPORT')
  OR pg_catalog.jsonb_array_length(v_rows) NOT BETWEEN 1 AND 50 OR NOT(p_filters ?& ARRAY['from_date','to_date']) THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
 v_fields:=public.nse_sip_xsip_registration_fields(p_api);
 FOR v_row IN SELECT value FROM pg_catalog.jsonb_array_elements(v_rows) LOOP
  IF pg_catalog.jsonb_typeof(v_row) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
  IF NOT(v_row ?& v_fields) OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_each(v_row) WHERE NOT(key=ANY(v_fields)) OR pg_catalog.jsonb_typeof(value)<>'string' OR value #>> '{}' !~ '[^[:space:]]')
   OR v_row->>'member_unique_id' !~ '^[A-Za-z0-9_-]{1,100}$' OR v_row->>v_fields[1] !~ '^[0-9]+$' OR v_row->>'member_code' !~ '^[0-9]+$'
   OR v_row->>'member_unique_id'=ANY(v_seen) OR v_row->>v_fields[1]=ANY(v_regs) THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
  v_seen:=pg_catalog.array_append(v_seen,v_row->>'member_unique_id'); v_regs:=pg_catalog.array_append(v_regs,v_row->>v_fields[1]);
 END LOOP;
 v_ids:=pg_catalog.array_to_string(v_seen,',');
 RETURN p_filters||pg_catalog.jsonb_build_object('member_unique_ids',v_ids);
END $$;

CREATE FUNCTION public.inspect_nse_sip_xsip_reports_response(p_api pg_catalog.text,p_payload pg_catalog.text,p_request pg_catalog.jsonb,p_identity pg_catalog.jsonb)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE v_json pg_catalog.jsonb; v_row pg_catalog.jsonb; v_owned pg_catalog.jsonb; v_contract pg_catalog.jsonb;
 v_fields pg_catalog.text[]; v_registration_fields pg_catalog.text[]; v_count pg_catalog.numeric; v_id pg_catalog.text; v_key pg_catalog.text;
 v_seen pg_catalog.text[]:=ARRAY[]::pg_catalog.text[]; v_member_code pg_catalog.text;
 v_result pg_catalog.jsonb:='{"native_status":null,"category":"sip_xsip_reports_response_invalid","success":false,"record_count":0}';
 v_row_error pg_catalog.jsonb;
BEGIN
 v_contract:=public.nse_sip_xsip_reports_contract(p_api);
 IF v_contract IS NULL THEN RETURN v_result; END IF;
 BEGIN
  IF p_request IS DISTINCT FROM public.nse_sip_xsip_reports_request(p_api,p_request-'client_code'-'member_unique_ids',p_identity) THEN RETURN v_result; END IF;
  v_json:=p_payload::pg_catalog.jsonb;
 EXCEPTION WHEN OTHERS THEN RETURN v_result; END;
 IF pg_catalog.jsonb_typeof(v_json) IS DISTINCT FROM 'object' THEN RETURN v_result; END IF;
 IF v_json->>'response_status' IN ('S','F') THEN v_result:=v_result||pg_catalog.jsonb_build_object('native_status',v_json->>'response_status'); END IF;
 -- Unlike B01/B02/B03, these nine samples omit error_remark entirely. Unknown
 -- diagnostic fields/values and all uncharacterized F shapes fail closed.
 IF v_json ? 'error_remark' THEN RETURN v_result||'{"category":"sip_xsip_reports_unknown_diagnostic"}'::pg_catalog.jsonb; END IF;
 IF NOT(v_json ?& ARRAY['response_status','report_data_total','report_data'])
 OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(v_json) k WHERE k NOT IN ('response_status','report_data_total','report_data'))
 OR v_json->>'response_status' IS DISTINCT FROM 'S' OR pg_catalog.jsonb_typeof(v_json->'report_data') IS DISTINCT FROM 'array'
 OR pg_catalog.jsonb_typeof(v_json->'report_data_total') NOT IN ('string','number') THEN RETURN v_result; END IF;
 IF pg_catalog.jsonb_typeof(v_json->'report_data_total')='string' AND v_json->>'report_data_total' !~ '^[0-9]+$' THEN RETURN v_result; END IF;
 BEGIN v_count:=(v_json->>'report_data_total')::pg_catalog.numeric; EXCEPTION WHEN OTHERS THEN RETURN v_result; END;
 IF v_count IS NULL OR v_count<0 OR v_count>10000 OR v_count<>pg_catalog.trunc(v_count) OR v_count<>pg_catalog.jsonb_array_length(v_json->'report_data') THEN RETURN v_result; END IF;
 SELECT pg_catalog.array_agg(value) INTO v_fields FROM pg_catalog.jsonb_array_elements_text(v_contract->'fields');
 v_id:=v_contract->>'id'; v_registration_fields:=public.nse_sip_xsip_registration_fields(p_api);
 v_row_error:=v_result||'{"category":"sip_xsip_reports_row_scope_invalid"}'::pg_catalog.jsonb;
 FOR v_row IN SELECT value FROM pg_catalog.jsonb_array_elements(v_json->'report_data') LOOP
  IF pg_catalog.jsonb_typeof(v_row) IS DISTINCT FROM 'object' THEN RETURN v_row_error; END IF;
  IF NOT(v_row ?& v_fields) OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_each(v_row) WHERE NOT(key=ANY(v_fields)) OR pg_catalog.jsonb_typeof(value)<>'string')
   OR v_row->>'client_code' IS DISTINCT FROM p_identity->>'client_code' OR v_row->>'member_code' !~ '^[0-9]+$' OR v_row->>v_id !~ '^[0-9]+$'
   OR (v_member_code IS NOT NULL AND v_member_code<>v_row->>'member_code') THEN RETURN v_row_error; END IF;
  v_member_code:=v_row->>'member_code';
  SELECT pg_catalog.jsonb_agg(v_row->value ORDER BY ord)::pg_catalog.text INTO v_key FROM pg_catalog.jsonb_array_elements_text(v_contract->'distinct') WITH ORDINALITY x(value,ord);
  IF v_key=ANY(v_seen) THEN RETURN v_result||'{"category":"sip_xsip_reports_duplicate_rows"}'::pg_catalog.jsonb; END IF;
  v_seen:=pg_catalog.array_append(v_seen,v_key);
  IF p_identity->'selectors'->>'mode'='member' THEN
   SELECT r INTO v_owned FROM pg_catalog.jsonb_array_elements(p_identity->'selectors'->'rows') r WHERE r->>'member_unique_id'=v_row->>'member_unique_id';
   IF v_owned IS NULL OR EXISTS(SELECT 1 FROM pg_catalog.unnest(v_registration_fields) k WHERE v_owned->>k IS DISTINCT FROM v_row->>k) THEN RETURN v_row_error; END IF;
  END IF;
 END LOOP;
 IF p_identity->'selectors'->>'mode'='member' AND v_count>0 AND v_count<>pg_catalog.jsonb_array_length(p_identity->'selectors'->'rows') THEN
  RETURN v_result||'{"category":"sip_xsip_reports_incomplete_selection"}'::pg_catalog.jsonb; END IF;
 RETURN v_result||pg_catalog.jsonb_build_object('success',true,'record_count',v_count,'category',CASE WHEN v_count=0 THEN 'sip_xsip_reports_no_records' ELSE 'sip_xsip_reports_report_received' END);
END $$;

-- Only immutable same-account/same-endpoint B04 registration RESULT positions
-- can supply member references. Account-only source prevents lineage recursion.
CREATE FUNCTION public.nse_sip_xsip_reports_selection(p_workspace_id pg_catalog.uuid,p_account_id pg_catalog.uuid,p_api pg_catalog.text,p_selection pg_catalog.jsonb)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result public.integration_api_interactions; v_request public.integration_api_interactions;
 v_report pg_catalog.jsonb; v_request_json pg_catalog.jsonb; v_identity pg_catalog.jsonb; v_check pg_catalog.jsonb; v_row pg_catalog.jsonb; v_index pg_catalog.jsonb;
 v_ucc pg_catalog.text; v_rows pg_catalog.jsonb:='[]'; v_seen pg_catalog.text[]:=ARRAY[]::pg_catalog.text[]; v_fields pg_catalog.text[];
BEGIN
 IF public.nse_sip_xsip_reports_contract(p_api) IS NULL THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
 IF p_selection='null'::pg_catalog.jsonb THEN RETURN '{"mode":"client","rows":[]}'::pg_catalog.jsonb; END IF;
 IF p_api NOT IN ('SIP_REG_REPORT','XSIP_REG_REPORT') OR pg_catalog.jsonb_typeof(p_selection) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
 IF NOT(p_selection ?& ARRAY['result_id','row_indices','selector']) OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(p_selection) k WHERE k NOT IN ('result_id','row_indices','selector'))
 OR p_selection->>'selector' IS DISTINCT FROM 'member' OR pg_catalog.jsonb_typeof(p_selection->'result_id') IS DISTINCT FROM 'string'
 OR p_selection->>'result_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 OR pg_catalog.jsonb_typeof(p_selection->'row_indices') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
 IF pg_catalog.jsonb_array_length(p_selection->'row_indices') NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
 SELECT external_account_id INTO v_ucc FROM public.integration_accounts WHERE id=p_account_id AND workspace_id=p_workspace_id
  AND state='REGISTERED' AND integration_key='NSE_INVEST' AND integration_environment='UAT';
 SELECT i.* INTO v_result FROM public.integration_api_interactions i JOIN public.integration_operations o ON o.id=i.integration_operation_id
 WHERE i.id=(p_selection->>'result_id')::pg_catalog.uuid AND i.phase='RESULT' AND i.normalized_outcome='SUCCESS'
  AND i.workspace_id=p_workspace_id AND i.integration_key='NSE_INVEST' AND i.integration_environment='UAT' AND i.safety_class='READ_ONLY'
  AND i.contract_version='NNF_1.9.7' AND i.http_success AND i.http_status BETWEEN 200 AND 299
  AND i.operation_type='SIP_XSIP_REPORTS' AND i.api_key=p_api AND i.endpoint_path=public.nse_sip_xsip_reports_contract(p_api)->>'path' AND i.http_method='POST'
  AND o.workspace_id=p_workspace_id AND o.integration_account_id=p_account_id AND o.integration_environment='UAT' AND o.integration_key='NSE_INVEST'
  AND o.operation_type='SIP_XSIP_REPORTS' AND o.api_key=p_api AND o.state='SUCCESS' AND o.last_interaction_id=i.id;
 IF v_result.id IS NULL OR v_ucc IS NULL THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
 SELECT * INTO v_request FROM public.integration_api_interactions WHERE call_id=v_result.call_id AND phase='REQUEST'
  AND integration_operation_id=v_result.integration_operation_id AND workspace_id=p_workspace_id AND api_key=p_api
  AND integration_environment='UAT' AND endpoint_path=v_result.endpoint_path AND http_method='POST';
 IF v_request.id IS NULL THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
 BEGIN
  v_request_json:=extensions.pgp_sym_decrypt(v_request.request_payload_ciphertext,public.integration_payload_encryption_key(v_request.payload_encryption_key_reference))::pg_catalog.jsonb;
  v_report:=extensions.pgp_sym_decrypt(v_result.response_payload_ciphertext,public.integration_payload_encryption_key(v_result.payload_encryption_key_reference))::pg_catalog.jsonb;
  v_identity:=public.nse_sip_xsip_reports_identity(v_result.integration_operation_id);
  v_check:=public.inspect_nse_sip_xsip_reports_response(p_api,v_report::pg_catalog.text,v_request_json,v_identity);
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END;
 IF (v_check->>'success')::pg_catalog.bool IS DISTINCT FROM true OR v_request_json->>'client_code' IS DISTINCT FROM v_ucc
  OR v_identity->'selectors' IS DISTINCT FROM '{"mode":"client","rows":[]}'::pg_catalog.jsonb THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
 v_fields:=public.nse_sip_xsip_registration_fields(p_api);
 FOR v_index IN SELECT value FROM pg_catalog.jsonb_array_elements(p_selection->'row_indices') LOOP
  IF pg_catalog.jsonb_typeof(v_index) IS DISTINCT FROM 'number' OR v_index::pg_catalog.text !~ '^[0-9]{1,9}$' OR v_index::pg_catalog.text=ANY(v_seen) THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
  IF (v_index::pg_catalog.text)::pg_catalog.int4>=pg_catalog.jsonb_array_length(v_report->'report_data') THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
  v_seen:=pg_catalog.array_append(v_seen,v_index::pg_catalog.text);
  v_row:=v_report->'report_data'->((v_index::pg_catalog.text)::pg_catalog.int4);
  IF (SELECT count(*) FROM pg_catalog.jsonb_array_elements(v_report->'report_data') r WHERE r->>'member_unique_id'=v_row->>'member_unique_id')<>1 THEN RAISE EXCEPTION 'sip_xsip_reports_selection_invalid'; END IF;
  v_rows:=v_rows||pg_catalog.jsonb_build_array((SELECT pg_catalog.jsonb_object_agg(key,value) FROM pg_catalog.jsonb_each(v_row) WHERE key=ANY(v_fields)));
 END LOOP;
 v_identity:=v_identity||pg_catalog.jsonb_build_object('selectors',pg_catalog.jsonb_build_object('mode','member','rows',v_rows));
 -- Reuse strict owned-row validation; these dates only exercise shape here.
 PERFORM public.nse_sip_xsip_reports_request(p_api,'{"from_date":"01-01-2025","to_date":"02-01-2025"}',v_identity);
 RETURN v_identity->'selectors';
END $$;
CREATE UNIQUE INDEX event_outbox_one_sip_xsip_reports_idx ON public.event_outbox(entity_id)
  WHERE event_type='integration.nse.sip_xsip_reports_requested';
CREATE FUNCTION public.guard_nse_sip_xsip_reports_context()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF TG_OP <> 'INSERT' AND OLD.event_type='integration.nse.sip_xsip_reports_requested' THEN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'sip_xsip_reports_context_immutable'; END IF;
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.event_type IS DISTINCT FROM OLD.event_type OR NEW.entity_id IS DISTINCT FROM OLD.entity_id
      OR NEW.entity_type IS DISTINCT FROM OLD.entity_type OR NEW.payload IS DISTINCT FROM OLD.payload OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'sip_xsip_reports_context_immutable'; END IF;
  ELSIF TG_OP='UPDATE' AND NEW.event_type='integration.nse.sip_xsip_reports_requested' THEN RAISE EXCEPTION 'sip_xsip_reports_context_immutable';
  END IF;
  IF TG_OP='INSERT' AND NEW.event_type='integration.nse.sip_xsip_reports_requested' THEN
    IF NEW.entity_type IS DISTINCT FROM 'integration_operation' OR pg_catalog.jsonb_typeof(NEW.payload) IS DISTINCT FROM 'object'
      OR NOT (NEW.payload ?& ARRAY['integration_operation_id','api','filters','pan_record_id','selection','identity_ciphertext','identity_key_reference'])
      OR NEW.payload->>'integration_operation_id' IS DISTINCT FROM NEW.entity_id::pg_catalog.text
      OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(NEW.payload) k WHERE k NOT IN ('integration_operation_id','api','filters','pan_record_id','selection','identity_ciphertext','identity_key_reference'))
      OR NOT EXISTS(SELECT 1 FROM public.integration_operations o JOIN public.integration_accounts a ON a.id=o.integration_account_id
        JOIN public.profiles p ON p.id=a.investor_profile_id JOIN public.profile_pan_records pan ON pan.id=p.canonical_pan_record_id AND pan.profile_id=p.id
        WHERE o.id=NEW.entity_id AND o.integration_key='NSE_INVEST' AND o.integration_environment='UAT'
          AND o.operation_type='SIP_XSIP_REPORTS' AND o.safety_class='READ_ONLY' AND o.contract_version='NNF_1.9.7'
          AND o.api_key=NEW.payload->>'api' AND o.category=public.nse_sip_xsip_reports_contract(o.api_key)->>'category'
          AND pan.id::pg_catalog.text=NEW.payload->>'pan_record_id' AND pan.status='VERIFIED') THEN RAISE EXCEPTION 'sip_xsip_reports_context_invalid'; END IF;
    IF NEW.payload->>'identity_key_reference' IS DISTINCT FROM 'integration_payload_encryption_key_v1'
      OR pg_catalog.jsonb_typeof(NEW.payload->'identity_ciphertext') IS DISTINCT FROM 'string'
      OR NEW.payload->>'identity_ciphertext' !~ '^[0-9a-f]+$' THEN RAISE EXCEPTION 'sip_xsip_reports_context_invalid'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.integration_operations o JOIN public.integration_accounts a ON a.id=o.integration_account_id
      JOIN public.profile_pan_records pan ON pan.id::pg_catalog.text=NEW.payload->>'pan_record_id' AND pan.profile_id=a.investor_profile_id
      WHERE o.id=NEW.entity_id AND extensions.pgp_sym_decrypt(pg_catalog.decode(NEW.payload->>'identity_ciphertext','hex'),
        public.integration_payload_encryption_key(NEW.payload->>'identity_key_reference'))::pg_catalog.jsonb =
        pg_catalog.jsonb_build_object('client_code',a.external_account_id,'pan',extensions.pgp_sym_decrypt(pan.pan_ciphertext,public.pan_encryption_key()),'selectors',public.nse_sip_xsip_reports_selection(o.workspace_id,a.id,o.api_key,NEW.payload->'selection'))) THEN
      RAISE EXCEPTION 'sip_xsip_reports_context_invalid'; END IF;
    PERFORM public.validate_nse_sip_xsip_reports_filters(NEW.payload->>'api',NEW.payload->'filters');
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER nse_sip_xsip_reports_context_guard BEFORE INSERT OR UPDATE OR DELETE ON public.event_outbox
  FOR EACH ROW EXECUTE FUNCTION public.guard_nse_sip_xsip_reports_context();

-- Encrypted immutable trusted identity snapshot survives source changes and key
-- reference rotation. It is not a vendor request or an observation table.
CREATE FUNCTION public.nse_sip_xsip_reports_identity(p_operation_id pg_catalog.uuid)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_identity pg_catalog.jsonb;
BEGIN
  SELECT extensions.pgp_sym_decrypt(pg_catalog.decode(e.payload->>'identity_ciphertext','hex'),
    public.integration_payload_encryption_key(e.payload->>'identity_key_reference'))::pg_catalog.jsonb
  INTO v_identity FROM public.event_outbox e JOIN public.integration_operations o ON o.id=e.entity_id
  WHERE o.id=p_operation_id AND o.operation_type='SIP_XSIP_REPORTS' AND e.event_type='integration.nse.sip_xsip_reports_requested';
  IF v_identity IS NULL THEN RAISE EXCEPTION 'sip_xsip_reports_identity_invalid'; END IF;
  RETURN v_identity;
END $$;

CREATE FUNCTION public.get_nse_sip_xsip_reports_source(p_integration_operation_id pg_catalog.uuid)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_operation public.integration_operations; v_account public.integration_accounts; v_context pg_catalog.jsonb; v_request pg_catalog.jsonb; v_identity pg_catalog.jsonb;
BEGIN
  SELECT * INTO v_operation FROM public.integration_operations WHERE id=p_integration_operation_id
    AND integration_key='NSE_INVEST' AND integration_environment='UAT' AND operation_type='SIP_XSIP_REPORTS'
    AND safety_class='READ_ONLY' AND contract_version='NNF_1.9.7' AND category=public.nse_sip_xsip_reports_contract(api_key)->>'category';
  SELECT payload INTO v_context FROM public.event_outbox WHERE entity_id=v_operation.id AND event_type='integration.nse.sip_xsip_reports_requested';
  SELECT * INTO v_account FROM public.integration_accounts WHERE id=v_operation.integration_account_id AND workspace_id=v_operation.workspace_id
    AND state='REGISTERED' AND integration_key='NSE_INVEST' AND integration_environment='UAT';
  IF v_context IS NULL OR v_account.id IS NULL OR v_account.external_account_id IS NULL OR v_account.external_account_id !~ '^[A-Za-z0-9_-]{1,20}$'
    OR NOT EXISTS(SELECT 1 FROM public.workspaces WHERE id=v_account.workspace_id AND workspace_status='active')
    OR NOT EXISTS(SELECT 1 FROM public.workspace_memberships WHERE workspace_id=v_account.workspace_id AND profile_id=v_account.investor_profile_id
      AND role='investor' AND status='active' AND ended_at IS NULL)
    OR NOT EXISTS(SELECT 1 FROM public.profiles p JOIN public.profile_pan_records pan ON pan.id=p.canonical_pan_record_id AND pan.profile_id=p.id
      WHERE p.id=v_account.investor_profile_id AND pan.status='VERIFIED' AND pan.id::pg_catalog.text=v_context->>'pan_record_id')
    OR EXISTS(SELECT 1 FROM public.integration_accounts a WHERE a.id<>v_account.id AND a.integration_key='NSE_INVEST'
      AND a.integration_environment='UAT' AND a.external_account_id=v_account.external_account_id) THEN RAISE EXCEPTION 'sip_xsip_reports_account_scope_invalid'; END IF;
  PERFORM public.validate_nse_sip_xsip_reports_filters(v_operation.api_key,v_context->'filters');
  v_identity := public.nse_sip_xsip_reports_identity(v_operation.id);
  IF v_identity->>'client_code' IS DISTINCT FROM v_account.external_account_id
    OR NOT EXISTS(SELECT 1 FROM public.profile_pan_records pan WHERE pan.id::pg_catalog.text=v_context->>'pan_record_id'
      AND extensions.pgp_sym_decrypt(pan.pan_ciphertext,public.pan_encryption_key())=v_identity->>'pan') THEN
    RAISE EXCEPTION 'sip_xsip_reports_identity_changed'; END IF;
  IF v_identity->'selectors' IS DISTINCT FROM public.nse_sip_xsip_reports_selection(v_account.workspace_id,v_account.id,v_operation.api_key,v_context->'selection') THEN
    RAISE EXCEPTION 'sip_xsip_reports_identity_changed'; END IF;
  v_request := public.nse_sip_xsip_reports_request(v_operation.api_key,v_context->'filters',v_identity);
  RETURN v_identity || pg_catalog.jsonb_build_object('operation_id',v_operation.id,'workspace_id',v_operation.workspace_id,
    'integration_account_id',v_account.id,'api',v_operation.api_key,'request',v_request,'today',pg_catalog.to_char(pg_catalog.timezone('Asia/Kolkata',pg_catalog.now()),'YYYY-MM-DD'));
END $$;

CREATE FUNCTION public.prepare_nse_sip_xsip_reports(p_workspace_id pg_catalog.uuid,p_integration_account_id pg_catalog.uuid,
  p_api pg_catalog.text,p_filters pg_catalog.jsonb DEFAULT '{}'::pg_catalog.jsonb,p_request_id pg_catalog.uuid DEFAULT pg_catalog.gen_random_uuid(),p_selection pg_catalog.jsonb DEFAULT 'null'::pg_catalog.jsonb)
RETURNS public.integration_operations LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_account public.integration_accounts; v_operation public.integration_operations; v_context pg_catalog.jsonb; v_pan_id pg_catalog.uuid; v_identity pg_catalog.jsonb;
BEGIN
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'sip_xsip_reports_request_id_required'; END IF;
  PERFORM public.validate_nse_sip_xsip_reports_filters(p_api,p_filters);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::pg_catalog.text,1));
  SELECT * INTO v_account FROM public.integration_accounts WHERE id=p_integration_account_id AND workspace_id=p_workspace_id
    AND integration_key='NSE_INVEST' AND integration_environment='UAT' FOR UPDATE;
  IF v_account.id IS NULL THEN RAISE EXCEPTION 'sip_xsip_reports_account_scope_invalid'; END IF;
  SELECT canonical_pan_record_id INTO v_pan_id FROM public.profiles WHERE id=v_account.investor_profile_id;
  v_context := pg_catalog.jsonb_build_object('integration_operation_id',p_request_id,'api',p_api,'filters',p_filters,'pan_record_id',v_pan_id,'selection',p_selection);
  SELECT * INTO v_operation FROM public.integration_operations WHERE id=p_request_id;
  IF v_operation.id IS NOT NULL THEN
    IF v_operation.integration_account_id IS DISTINCT FROM v_account.id OR v_operation.operation_type<>'SIP_XSIP_REPORTS' OR v_operation.api_key<>p_api
      OR NOT EXISTS(SELECT 1 FROM public.event_outbox WHERE entity_id=v_operation.id AND event_type='integration.nse.sip_xsip_reports_requested' AND payload - 'identity_ciphertext' - 'identity_key_reference'=v_context) THEN
      RAISE EXCEPTION 'sip_xsip_reports_prepare_conflict'; END IF;
    PERFORM public.get_nse_sip_xsip_reports_source(v_operation.id); RETURN v_operation;
  END IF;
  SELECT pg_catalog.jsonb_build_object('client_code',v_account.external_account_id,'pan',extensions.pgp_sym_decrypt(pan.pan_ciphertext,public.pan_encryption_key()),'selectors',public.nse_sip_xsip_reports_selection(p_workspace_id,v_account.id,p_api,p_selection))
    INTO v_identity FROM public.profile_pan_records pan WHERE pan.id=v_pan_id AND pan.profile_id=v_account.investor_profile_id AND pan.status='VERIFIED';
  IF v_identity IS NULL OR v_identity->>'pan' !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' THEN RAISE EXCEPTION 'sip_xsip_reports_identity_invalid'; END IF;
  v_context := v_context || pg_catalog.jsonb_build_object('identity_key_reference','integration_payload_encryption_key_v1','identity_ciphertext',
    pg_catalog.encode(extensions.pgp_sym_encrypt(v_identity::pg_catalog.text,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),
      'cipher-algo=aes256, compress-algo=0'),'hex'));
  INSERT INTO public.integration_operations(id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state)
  VALUES(p_request_id,v_account.workspace_id,v_account.id,'NSE_INVEST','UAT',public.nse_sip_xsip_reports_contract(p_api)->>'category','READ_ONLY','SIP_XSIP_REPORTS',p_api,'NNF_1.9.7','PREPARED') RETURNING * INTO v_operation;
  INSERT INTO public.event_outbox(event_type,payload,status,entity_id,entity_type)
  VALUES('integration.nse.sip_xsip_reports_requested',v_context,'pending',v_operation.id,'integration_operation');
  PERFORM public.get_nse_sip_xsip_reports_source(v_operation.id);
  UPDATE public.integration_operations SET state='QUEUED' WHERE id=v_operation.id RETURNING * INTO v_operation;
  RETURN v_operation;
END $$;

-- Shared bounded-read mechanics, derived from the existing PROV_ORDERS lifecycle.
CREATE OR REPLACE FUNCTION public.recover_expired_nse_sip_xsip_reports_events(
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
  IF v_event.id IS NULL OR v_event.event_type <> 'integration.nse.sip_xsip_reports_requested'
     OR v_event.entity_type <> 'integration_operation' OR v_event.status <> 'processing'
     OR v_event.claim_expires_at IS NULL OR v_event.claim_expires_at > pg_catalog.now() THEN RETURN 'no_recovery_required'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation
  WHERE operation.id = v_event.entity_id FOR UPDATE;
  IF v_operation.id IS NULL OR v_operation.operation_type <> 'SIP_XSIP_REPORTS'
     OR v_operation.safety_class <> 'READ_ONLY' THEN RETURN 'no_recovery_required'; END IF;
  v_retry_allowed := v_event.retry_count < p_max_attempts;
  IF v_operation.state = 'QUEUED' OR (v_operation.state = 'SUBMISSION_FAILED' AND v_operation.retry_allowed) THEN
    UPDATE public.integration_operations SET state = 'SUBMISSION_FAILED',
      attempt_count = GREATEST(attempt_count, v_event.retry_count), retry_allowed = v_retry_allowed,
      business_remark_category = 'sip_xsip_reports_pre_request_claim_expired',
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
      'TRANSPORT_FAILURE', 'sip_xsip_reports_read_lease_expired', false, false, false, false
    ) RETURNING id INTO v_result_id;
    UPDATE public.integration_operations SET state = 'SUBMISSION_FAILED',
      attempt_count = GREATEST(attempt_count, v_event.retry_count), retry_allowed = v_retry_allowed,
      business_remark_category = 'sip_xsip_reports_read_lease_expired',
      native_business_status = NULL, ambiguous_outcome = false, reconciliation_required = false,
      completed_at = v_completed_at, last_interaction_id = v_result_id
    WHERE id = v_operation.id;
  ELSE
    RETURN 'no_recovery_required';
  END IF;
  UPDATE public.event_outbox SET status = 'failed',
    error_message = CASE WHEN v_retry_allowed THEN 'sip_xsip_reports_read_retryable' ELSE 'sip_xsip_reports_read_attempts_exhausted' END,
    claimed_by = NULL, claim_token = NULL, claim_expires_at = NULL, updated_at = pg_catalog.now()
  WHERE id = v_event.id;
  RETURN CASE WHEN v_retry_allowed THEN 'safe_read_retry_available' ELSE 'sip_xsip_reports_attempts_exhausted' END;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_nse_sip_xsip_reports_event(
  p_event_outbox_id pg_catalog.uuid,
  p_max_attempts pg_catalog.int4 DEFAULT 3,
  p_lease_seconds pg_catalog.int4 DEFAULT 120
)
RETURNS TABLE (
  event_outbox_id pg_catalog.uuid, integration_operation_id pg_catalog.uuid,
  correlation_id pg_catalog.uuid, attempt pg_catalog.int4, claim_state pg_catalog.text,
  claim_token pg_catalog.uuid
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_event public.event_outbox; v_operation public.integration_operations;
BEGIN
  IF p_event_outbox_id IS NULL THEN RAISE EXCEPTION 'event_outbox_id_required'; END IF;
  IF p_max_attempts IS NULL OR p_max_attempts < 1 OR p_max_attempts > 3 THEN RAISE EXCEPTION 'invalid_max_attempts'; END IF;
  IF p_lease_seconds IS NULL OR p_lease_seconds < 15 OR p_lease_seconds > 900 THEN RAISE EXCEPTION 'invalid_lease_seconds'; END IF;
  WITH candidate AS (
    SELECT event.id, pg_catalog.gen_random_uuid() AS token
    FROM public.event_outbox event JOIN public.integration_operations operation ON operation.id = event.entity_id
    WHERE event.id = p_event_outbox_id
      AND event.event_type = 'integration.nse.sip_xsip_reports_requested'
      AND event.entity_type = 'integration_operation' AND event.retry_count < p_max_attempts
      AND operation.operation_type = 'SIP_XSIP_REPORTS' AND operation.safety_class = 'READ_ONLY'
      AND public.nse_sip_xsip_reports_contract(operation.api_key) IS NOT NULL AND operation.integration_key = 'NSE_INVEST'
      AND operation.integration_environment = 'UAT' AND operation.category = public.nse_sip_xsip_reports_contract(operation.api_key)->>'category'
      AND operation.contract_version = 'NNF_1.9.7'
      AND (
        (event.status = 'pending' AND operation.state = 'QUEUED')
        OR (event.status = 'failed' AND operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed
          AND event.updated_at <= pg_catalog.now() - pg_catalog.make_interval(secs => 30))
      )
    FOR UPDATE OF event SKIP LOCKED
  ) UPDATE public.event_outbox event SET
    status = 'processing', retry_count = event.retry_count + 1, claimed_at = pg_catalog.now(),
    claimed_by = candidate.token, claim_token = candidate.token,
    claim_expires_at = pg_catalog.now() + (p_lease_seconds::pg_catalog.text || ' seconds')::pg_catalog.interval,
    error_message = NULL, updated_at = pg_catalog.now()
  FROM candidate WHERE event.id = candidate.id RETURNING event.* INTO v_event;
  IF v_event.id IS NULL THEN
    RETURN QUERY SELECT NULL::pg_catalog.uuid, NULL::pg_catalog.uuid, NULL::pg_catalog.uuid,
      0::pg_catalog.int4, 'no_event'::pg_catalog.text, NULL::pg_catalog.uuid;
    RETURN;
  END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id = v_event.entity_id;
  RETURN QUERY SELECT v_event.id, v_operation.id, v_operation.correlation_id,
    v_event.retry_count,
    CASE WHEN v_event.retry_count = 1 THEN 'newly_claimed' ELSE 'safe_retry_claimed' END,
    v_event.claim_token;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_nse_sip_xsip_reports(
  p_event_outbox_id pg_catalog.uuid, p_claim_token pg_catalog.uuid,
  p_call_id pg_catalog.uuid, p_request_payload pg_catalog.text,
  p_request_header_metadata pg_catalog.jsonb, p_started_at pg_catalog.timestamptz
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_event public.event_outbox; v_operation public.integration_operations;
  v_json pg_catalog.jsonb; v_existing public.integration_api_interactions;
  v_bytes pg_catalog.int8; v_hash pg_catalog.bytea; v_key pg_catalog.text := 'integration_payload_encryption_key_v1';
BEGIN
  IF p_call_id IS NULL OR p_started_at IS NULL OR NULLIF(p_request_payload, '') IS NULL THEN RAISE EXCEPTION 'sip_xsip_reports_request_incomplete'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_call_id::pg_catalog.text, 0));
  BEGIN v_json := p_request_payload::pg_catalog.jsonb; EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'sip_xsip_reports_request_invalid_json'; END;
  IF NOT public.integration_header_metadata_is_safe(p_request_header_metadata, 'REQUEST')
     OR p_request_header_metadata->>'content_type' IS DISTINCT FROM 'application/json'
     OR p_request_header_metadata->>'accept' IS DISTINCT FROM 'application/json' THEN RAISE EXCEPTION 'unsafe_request_header_metadata'; END IF;
  v_bytes := pg_catalog.octet_length(pg_catalog.convert_to(p_request_payload, 'UTF8'));
  v_hash := extensions.digest(pg_catalog.convert_to(p_request_payload, 'UTF8'), 'sha256');
  SELECT * INTO v_event FROM public.event_outbox event WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.event_type <> 'integration.nse.sip_xsip_reports_requested'
     OR v_event.status <> 'processing' OR v_event.claim_token IS NULL OR v_event.claim_token IS DISTINCT FROM p_claim_token
     OR v_event.claim_expires_at IS NULL OR v_event.claim_expires_at <= pg_catalog.now() THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation WHERE operation.id = v_event.entity_id FOR UPDATE;
  IF v_operation.operation_type <> 'SIP_XSIP_REPORTS' OR public.nse_sip_xsip_reports_contract(v_operation.api_key) IS NULL
     OR v_operation.category IS DISTINCT FROM public.nse_sip_xsip_reports_contract(v_operation.api_key)->>'category' OR v_operation.safety_class <> 'READ_ONLY'
     OR v_operation.contract_version <> 'NNF_1.9.7' THEN RAISE EXCEPTION 'integration_operation_not_sip_xsip_reports'; END IF;
  SELECT * INTO v_existing FROM public.integration_api_interactions interaction WHERE interaction.call_id = p_call_id AND interaction.phase = 'REQUEST';
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.integration_operation_id IS DISTINCT FROM v_operation.id
       OR v_existing.attempt_number IS DISTINCT FROM v_event.retry_count
       OR v_existing.correlation_id IS DISTINCT FROM v_operation.correlation_id
       OR v_existing.endpoint_path <> (public.nse_sip_xsip_reports_contract(v_operation.api_key)->>'path')
       OR v_existing.http_method <> 'POST' OR v_existing.request_content_type <> 'application/json'
       OR v_existing.request_hash IS DISTINCT FROM v_hash OR v_existing.request_bytes IS DISTINCT FROM v_bytes
       OR v_existing.request_header_metadata IS DISTINCT FROM p_request_header_metadata
       OR v_existing.started_at IS DISTINCT FROM p_started_at THEN RAISE EXCEPTION 'integration_request_idempotency_conflict'; END IF;
    RETURN v_existing;
  END IF;
  IF v_operation.state NOT IN ('QUEUED', 'SUBMISSION_FAILED')
     OR (v_operation.state = 'SUBMISSION_FAILED' AND NOT v_operation.retry_allowed) THEN
    RAISE EXCEPTION 'integration_operation_not_sip_xsip_reports';
  END IF;
  IF v_json IS DISTINCT FROM public.get_nse_sip_xsip_reports_source(v_operation.id)->'request' THEN
    RAISE EXCEPTION 'sip_xsip_reports_request_scope_mismatch';
  END IF;
  INSERT INTO public.integration_api_interactions (
    workspace_id, integration_operation_id, integration_key, integration_environment,
    category, safety_class, operation_type, api_key, contract_version, endpoint_path,
    http_method, call_id, phase, attempt_number, correlation_id,
    payload_encryption_key_reference, payload_encryption_key_version,
    request_payload_ciphertext, request_header_metadata, request_content_type,
    request_bytes, request_hash, started_at, normalized_outcome
  ) VALUES (
    v_operation.workspace_id, v_operation.id, v_operation.integration_key, v_operation.integration_environment,
    v_operation.category, v_operation.safety_class, v_operation.operation_type, v_operation.api_key,
    v_operation.contract_version, (public.nse_sip_xsip_reports_contract(v_operation.api_key)->>'path'), 'POST',
    p_call_id, 'REQUEST', v_event.retry_count, v_operation.correlation_id, v_key, 1,
    extensions.pgp_sym_encrypt(p_request_payload, public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0'),
    p_request_header_metadata, 'application/json', v_bytes, v_hash, p_started_at, 'REQUEST_RECORDED'
  ) RETURNING * INTO v_existing;
  UPDATE public.integration_operations SET state = 'SUBMITTING', attempt_count = v_event.retry_count,
    native_business_status = NULL, business_remark_category = NULL, retry_allowed = false,
    ambiguous_outcome = false, reconciliation_required = false, submitted_at = p_started_at,
    completed_at = NULL, last_interaction_id = v_existing.id
  WHERE id = v_operation.id;
  RETURN v_existing;
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_nse_sip_xsip_reports(
  p_event_outbox_id pg_catalog.uuid, p_claim_token pg_catalog.uuid, p_call_id pg_catalog.uuid,
  p_response_payload pg_catalog.text, p_response_content_type pg_catalog.text,
  p_response_header_metadata pg_catalog.jsonb, p_http_status pg_catalog.int4,
  p_native_status_value pg_catalog.text, p_native_remark_category pg_catalog.text,
  p_normalized_outcome pg_catalog.text, p_error_category pg_catalog.text,
  p_timeout_occurred pg_catalog.bool, p_network_failure pg_catalog.bool,
  p_completed_at pg_catalog.timestamptz, p_elapsed_ms pg_catalog.int8,
  p_max_attempts pg_catalog.int4 DEFAULT 3,
  p_response_body_base64 pg_catalog.text DEFAULT NULL
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_request public.integration_api_interactions;
  v_existing public.integration_api_interactions;
  v_event public.event_outbox;
  v_operation public.integration_operations;
  v_interaction public.integration_api_interactions;
  v_request_json pg_catalog.jsonb;
  v_response_raw pg_catalog.bytea;
  v_response_text pg_catalog.text;
  v_observation pg_catalog.jsonb;
  v_retry_allowed pg_catalog.bool := false;
  v_retryable_http_status pg_catalog.bool := false;
  v_bytes pg_catalog.int8;
  v_hash pg_catalog.bytea;
  v_key pg_catalog.text := 'integration_payload_encryption_key_v1';
  v_state pg_catalog.text;
  v_event_status pg_catalog.text := 'completed';
BEGIN
  IF p_call_id IS NULL OR p_completed_at IS NULL OR p_elapsed_ms IS NULL OR p_elapsed_ms < 0
     OR p_max_attempts IS NULL OR p_max_attempts < 1 OR p_max_attempts > 3 OR p_normalized_outcome IS NULL
     OR p_normalized_outcome NOT IN ('SUCCESS', 'BUSINESS_FAILURE', 'HTTP_FAILURE', 'TRANSPORT_FAILURE') THEN
    RAISE EXCEPTION 'sip_xsip_reports_result_invalid';
  END IF;

  IF p_response_body_base64 IS NULL THEN
    v_response_raw := pg_catalog.convert_to(COALESCE(p_response_payload,''),'UTF8');
  ELSE
    IF pg_catalog.length(p_response_body_base64)>1398104 OR p_response_body_base64 !~ '^[A-Za-z0-9+/]*={0,2}$' THEN
      RAISE EXCEPTION 'sip_xsip_reports_result_bytes_invalid'; END IF;
    BEGIN v_response_raw := pg_catalog.decode(p_response_body_base64,'base64');
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'sip_xsip_reports_result_bytes_invalid'; END;
    IF pg_catalog.replace(pg_catalog.encode(v_response_raw,'base64'),E'\n','') <> p_response_body_base64 THEN
      RAISE EXCEPTION 'sip_xsip_reports_result_bytes_invalid'; END IF;
  END IF;
  IF pg_catalog.octet_length(v_response_raw)>1048576 THEN RAISE EXCEPTION 'sip_xsip_reports_result_too_large'; END IF;
  BEGIN v_response_text := pg_catalog.convert_from(v_response_raw,'UTF8');
  EXCEPTION WHEN character_not_in_repertoire OR untranslatable_character THEN v_response_text := NULL; END;
  IF COALESCE(v_response_text,'') IS DISTINCT FROM p_response_payload
    OR (p_http_status IS NULL AND pg_catalog.octet_length(v_response_raw)<>0) THEN
    RAISE EXCEPTION 'sip_xsip_reports_result_bytes_mismatch'; END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_call_id::pg_catalog.text, 0));
  SELECT * INTO v_request FROM public.integration_api_interactions interaction
  WHERE interaction.call_id = p_call_id AND interaction.phase = 'REQUEST';
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'integration_request_evidence_missing'; END IF;
  IF NOT public.integration_header_metadata_is_safe(p_response_header_metadata, 'RESULT') THEN
    RAISE EXCEPTION 'unsafe_response_header_metadata';
  END IF;

  SELECT * INTO v_event FROM public.event_outbox WHERE id=p_event_outbox_id FOR UPDATE;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_request.integration_operation_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.entity_id IS DISTINCT FROM v_operation.id
    OR v_event.event_type <> 'integration.nse.sip_xsip_reports_requested' OR v_event.entity_type <> 'integration_operation'
    OR v_request.operation_type <> 'SIP_XSIP_REPORTS' OR v_request.api_key IS DISTINCT FROM v_operation.api_key
    OR v_request.safety_class <> 'READ_ONLY' OR v_request.integration_environment <> 'UAT'
    OR v_request.integration_key <> 'NSE_INVEST' THEN RAISE EXCEPTION 'sip_xsip_reports_result_scope_mismatch'; END IF;
  v_request_json := extensions.pgp_sym_decrypt(v_request.request_payload_ciphertext,
    public.integration_payload_encryption_key(v_request.payload_encryption_key_reference))::pg_catalog.jsonb;
  IF p_http_status BETWEEN 200 AND 299 THEN
    v_observation := public.inspect_nse_sip_xsip_reports_response(v_operation.api_key,v_response_text,v_request_json,public.nse_sip_xsip_reports_identity(v_operation.id));
    IF p_normalized_outcome IS DISTINCT FROM (CASE WHEN (v_observation->>'success')::pg_catalog.bool THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END)
      OR p_native_status_value IS DISTINCT FROM v_observation->>'native_status'
      OR p_native_remark_category IS DISTINCT FROM v_observation->>'category' THEN
      -- Two runtimes may disagree on malformed/precision-edge JSON. Preserve
      -- the original bytes and fail closed; never turn a parser disagreement
      -- into missing RESULT evidence or a trusted successful observation.
      p_native_status_value := v_observation->>'native_status';
      p_native_remark_category := 'sip_xsip_reports_interpretation_mismatch';
      p_normalized_outcome := 'BUSINESS_FAILURE';
      p_error_category := 'sip_xsip_reports_interpretation_mismatch';
    END IF;
  ELSIF p_http_status IS NOT NULL THEN
    IF p_http_status NOT BETWEEN 100 AND 599 OR p_normalized_outcome <> 'HTTP_FAILURE'
      OR p_native_status_value IS NOT NULL OR p_native_remark_category IS DISTINCT FROM 'sip_xsip_reports_http_failure' THEN
      RAISE EXCEPTION 'sip_xsip_reports_result_classification_mismatch';
    END IF;
  ELSE
    IF p_normalized_outcome <> 'TRANSPORT_FAILURE' OR p_native_status_value IS NOT NULL
      OR p_native_remark_category IS DISTINCT FROM 'sip_xsip_reports_transport_failed' OR COALESCE(p_response_payload,'') <> '' THEN
      RAISE EXCEPTION 'sip_xsip_reports_result_classification_mismatch';
    END IF;
  END IF;
  IF (p_normalized_outcome = 'SUCCESS' AND p_error_category IS NOT NULL)
    OR (p_normalized_outcome IN ('BUSINESS_FAILURE','HTTP_FAILURE') AND p_error_category IS DISTINCT FROM p_native_remark_category)
    OR (p_normalized_outcome = 'TRANSPORT_FAILURE' AND (p_error_category IS NULL OR p_error_category NOT IN
      ('nse_request_timeout','nse_network_error','nse_response_invalid','nse_response_too_large','nse_request_invalid')))
    OR (p_http_status IS NOT NULL AND (COALESCE(p_timeout_occurred,false) OR COALESCE(p_network_failure,false))) THEN
    RAISE EXCEPTION 'sip_xsip_reports_result_metadata_invalid';
  END IF;
  v_bytes := pg_catalog.octet_length(v_response_raw);
  IF v_bytes>1048576 THEN RAISE EXCEPTION 'sip_xsip_reports_result_too_large'; END IF;
  v_hash := extensions.digest(v_response_raw, 'sha256');
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

  IF v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token
    OR v_event.claim_token IS NULL OR v_event.claim_expires_at IS NULL OR v_event.claim_expires_at <= pg_catalog.now()
    OR v_event.retry_count <> v_request.attempt_number THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
  IF v_operation.state <> 'SUBMITTING' THEN RAISE EXCEPTION 'integration_operation_not_submitting'; END IF;
  v_retryable_http_status := p_normalized_outcome = 'HTTP_FAILURE'
    AND p_http_status = ANY (ARRAY[408, 429, 500, 502, 503, 504]::pg_catalog.int4[]);
  IF p_normalized_outcome = 'TRANSPORT_FAILURE' OR v_retryable_http_status THEN
    v_state := 'SUBMISSION_FAILED';
    v_retry_allowed := v_event.retry_count < p_max_attempts AND (v_retryable_http_status OR p_error_category IN ('nse_request_timeout','nse_network_error'));
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
    CASE WHEN v_response_text IS NULL THEN extensions.pgp_sym_encrypt_bytea(v_response_raw, public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0')
    ELSE extensions.pgp_sym_encrypt(v_response_text, public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0') END,
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
      CASE WHEN v_retry_allowed THEN 'sip_xsip_reports_read_retryable' ELSE 'sip_xsip_reports_read_attempts_exhausted' END
    ELSE NULL END,
    claimed_by = NULL,
    claim_token = NULL,
    claim_expires_at = NULL,
    updated_at = pg_catalog.now()
  WHERE id = v_event.id;
  RETURN v_interaction;
END;
$$;


-- Service-only, account/workspace-bound safe summary; raw evidence never leaves
-- this function. No duplicate observation storage or unscoped decrypt RPC.
CREATE FUNCTION public.get_nse_sip_xsip_reports_summary(p_workspace_id pg_catalog.uuid, p_integration_account_id pg_catalog.uuid, p_operation_id pg_catalog.uuid)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result public.integration_api_interactions; v_request public.integration_api_interactions; v_summary pg_catalog.jsonb;
BEGIN
  SELECT i.* INTO v_result FROM public.integration_operations o
  JOIN public.integration_api_interactions i ON i.id=o.last_interaction_id
  WHERE o.id=p_operation_id AND o.workspace_id=p_workspace_id AND o.integration_account_id=p_integration_account_id
    AND o.integration_key='NSE_INVEST' AND o.integration_environment='UAT' AND o.operation_type='SIP_XSIP_REPORTS'
    AND public.nse_sip_xsip_reports_contract(o.api_key) IS NOT NULL AND o.contract_version='NNF_1.9.7' AND o.safety_class='READ_ONLY'
    AND o.state='SUCCESS' AND i.phase='RESULT' AND i.normalized_outcome='SUCCESS';
  IF v_result.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_request FROM public.integration_api_interactions WHERE call_id=v_result.call_id AND phase='REQUEST';
  v_summary := public.inspect_nse_sip_xsip_reports_response(v_result.api_key,
    extensions.pgp_sym_decrypt(v_result.response_payload_ciphertext,public.integration_payload_encryption_key(v_result.payload_encryption_key_reference)),
    extensions.pgp_sym_decrypt(v_request.request_payload_ciphertext,public.integration_payload_encryption_key(v_request.payload_encryption_key_reference))::pg_catalog.jsonb,public.nse_sip_xsip_reports_identity(p_operation_id));
  IF NOT (v_summary->>'success')::pg_catalog.bool THEN RAISE EXCEPTION 'sip_xsip_reports_evidence_invalid'; END IF;
  RETURN v_summary || pg_catalog.jsonb_build_object('operation_id',p_operation_id,'workspace_id',p_workspace_id,
    'integration_account_id',p_integration_account_id,'api',v_result.api_key,'result_interaction_id',v_result.id,'observed_at',v_result.completed_at);
END;
$$;
REVOKE ALL ON FUNCTION public.recover_expired_nse_sip_xsip_reports_events(pg_catalog.uuid, pg_catalog.int4) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recover_expired_nse_sip_xsip_reports_events(pg_catalog.uuid, pg_catalog.int4) TO service_role;
REVOKE ALL ON FUNCTION public.claim_nse_sip_xsip_reports_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_nse_sip_xsip_reports_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4) TO service_role;
REVOKE ALL ON FUNCTION public.start_nse_sip_xsip_reports(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb, pg_catalog.timestamptz) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.start_nse_sip_xsip_reports(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb, pg_catalog.timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.finish_nse_sip_xsip_reports(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.timestamptz, pg_catalog.int8, pg_catalog.int4, pg_catalog.text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finish_nse_sip_xsip_reports(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.timestamptz, pg_catalog.int8, pg_catalog.int4, pg_catalog.text) TO service_role;
REVOKE ALL ON FUNCTION public.get_nse_sip_xsip_reports_summary(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nse_sip_xsip_reports_summary(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) TO service_role;



REVOKE ALL ON FUNCTION public.nse_sip_xsip_reports_selection(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.jsonb),
 public.nse_sip_xsip_reports_contract(pg_catalog.text),
 public.validate_nse_sip_xsip_reports_filters(pg_catalog.text,pg_catalog.jsonb,pg_catalog.date),
 public.guard_nse_sip_xsip_reports_context(), public.nse_sip_xsip_reports_identity(pg_catalog.uuid),
 public.inspect_nse_sip_xsip_reports_response(pg_catalog.text,pg_catalog.text,pg_catalog.jsonb,pg_catalog.jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.prepare_nse_sip_xsip_reports(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.jsonb,pg_catalog.uuid,pg_catalog.jsonb),
 public.get_nse_sip_xsip_reports_source(pg_catalog.uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_nse_sip_xsip_reports(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.jsonb,pg_catalog.uuid,pg_catalog.jsonb),
 public.get_nse_sip_xsip_reports_source(pg_catalog.uuid) TO service_role;
-- Expired retry claims before REQUEST must remain discoverable by the dispatcher.
CREATE OR REPLACE FUNCTION public.list_dispatchable_outbox_events(
  p_event_types pg_catalog.text[],
  p_limit pg_catalog.int4 DEFAULT 10,
  p_retry_delay_seconds pg_catalog.int4 DEFAULT 30
)
RETURNS TABLE (
  event_outbox_id pg_catalog.uuid,
  event_type pg_catalog.text,
  event_status pg_catalog.text,
  retry_count pg_catalog.int4,
  claim_expires_at pg_catalog.timestamptz,
  created_at pg_catalog.timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_event_types IS NULL
     OR pg_catalog.cardinality(p_event_types) < 1
     OR pg_catalog.cardinality(p_event_types) > 32 THEN
    RAISE EXCEPTION 'dispatch_event_types_invalid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.unnest(p_event_types) AS requested(event_type)
    WHERE NULLIF(pg_catalog.btrim(requested.event_type), '') IS NULL
       OR requested.event_type !~ '^[a-z0-9][a-z0-9_.-]{0,99}$'
  ) THEN
    RAISE EXCEPTION 'dispatch_event_type_invalid';
  END IF;

  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 50 THEN
    RAISE EXCEPTION 'dispatch_limit_invalid';
  END IF;

  IF p_retry_delay_seconds IS NULL
     OR p_retry_delay_seconds < 0
     OR p_retry_delay_seconds > 3600 THEN
    RAISE EXCEPTION 'dispatch_retry_delay_invalid';
  END IF;

  RETURN QUERY
  SELECT
    event.id,
    event.event_type,
    event.status,
    event.retry_count,
    event.claim_expires_at,
    event.created_at
  FROM public.event_outbox AS event
  JOIN public.integration_operations AS operation
    ON event.entity_type = 'integration_operation'
   AND operation.id = event.entity_id
  WHERE event.event_type = ANY (p_event_types)
    AND NOT operation.ambiguous_outcome
    AND NOT operation.reconciliation_required
    AND (
      (
        event.status = 'pending'
        AND operation.state = 'QUEUED'
      )
      OR (
        event.status = 'failed'
        AND operation.state = 'SUBMISSION_FAILED'
        AND operation.retry_allowed
        AND event.updated_at <= pg_catalog.now()
          - pg_catalog.make_interval(secs => p_retry_delay_seconds)
      )
      OR (
        event.status = 'processing'
        AND event.claim_expires_at IS NOT NULL
        AND event.claim_expires_at <= pg_catalog.now()
        AND (operation.state IN ('QUEUED', 'SUBMITTING')
          OR (operation.operation_type IN ('ORDER_STATUS','PROV_ORDERS','CLIENT_READINESS','ORDER_FUNDING','SETTLEMENT_REDEMPTION','SIP_XSIP_REPORTS') AND operation.safety_class = 'READ_ONLY'
            AND operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed))
      )
    )
  ORDER BY
    CASE WHEN event.status = 'processing' THEN 0 ELSE 1 END,
    event.created_at,
    event.id
  LIMIT p_limit;
END;
$$;


REVOKE ALL ON FUNCTION public.nse_b04_date(pg_catalog.text,pg_catalog.text), public.nse_sip_xsip_reports_request(pg_catalog.text,pg_catalog.jsonb,pg_catalog.jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.nse_sip_xsip_registration_fields(pg_catalog.text) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
