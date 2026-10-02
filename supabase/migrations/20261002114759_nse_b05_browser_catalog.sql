-- B05 browser catalog; STP due requires service-owned evidence selection and stays unavailable.
BEGIN;
CREATE OR REPLACE FUNCTION nse_app.catalog() RETURNS TABLE(kind text, api text, family text, options_type text)
LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
 VALUES
 ('read_order_status','ORDER_STATUS','ORDER_STATUS','dates'),
 ('read_prov_orders','PROV_ORDERS','PROV_ORDERS','dates'),
 ('read_client_authorization','CLIENT_AUTHORIZATION','CLIENT_READINESS','dates'),
 ('read_client_detail','CLIENT_DETAIL','CLIENT_READINESS','dates'),
 ('read_two_fa','TWO_FA','CLIENT_READINESS','dates'),
 ('read_client_kyc_report','CLIENT_KYC_REPORT','CLIENT_READINESS','none'),
 ('read_fatca_report','FATCA_REPORT','CLIENT_READINESS','none'),
 ('read_elog_report','ELOG_REPORT','CLIENT_READINESS','none'),
 ('read_order_lifecycle','ORDER_LIFECYCLE','ORDER_FUNDING','dates'),
 ('read_transaction_detail','TRANSACTION_DETAIL','ORDER_FUNDING','dates'),
 ('read_fund_order','FUND_ORDER','ORDER_FUNDING','dates'),
 ('read_fund_age','FUND_AGE','ORDER_FUNDING','date'),
 ('read_allotment_statement','ALLOTMENT_STATEMENT','SETTLEMENT_REDEMPTION','settlement'),
 ('read_redemption_statement','REDEMPTION_STATEMENT','SETTLEMENT_REDEMPTION','settlement'),
 ('read_redemption_payout','REDEMPTION_PAYOUT','SETTLEMENT_REDEMPTION','settlement'),
 ('read_redemption_payout_non_demat','REDEMPTION_PAYOUT_NON_DEMAT','SETTLEMENT_REDEMPTION','settlement'),
 ('read_sip_reg_report','SIP_REG_REPORT','SIP_XSIP_REPORTS','optional_dates'),
 ('read_sip_can_report','SIP_CAN_REPORT','SIP_XSIP_REPORTS','optional_dates'),
 ('read_sip_inst_due_report','SIP_INST_DUE_REPORT','SIP_XSIP_REPORTS','optional_dates'),
 ('read_sip_topup_report','SIP_TOPUP_REPORT','SIP_XSIP_REPORTS','optional_dates'),
 ('read_stepup_reg_report','STEPUP_REG_REPORT','SIP_XSIP_REPORTS','optional_dates'),
 ('read_xsip_reg_report','XSIP_REG_REPORT','SIP_XSIP_REPORTS','optional_dates'),
 ('read_xsip_can_report','XSIP_CAN_REPORT','SIP_XSIP_REPORTS','optional_dates'),
 ('read_xsip_inst_due_report','XSIP_INST_DUE_REPORT','SIP_XSIP_REPORTS','optional_dates'),
 ('read_xsip_topup_report','XSIP_TOPUP_REPORT','SIP_XSIP_REPORTS','optional_dates'),
 ('read_stp_reg_report','STP_REG_REPORT','STP_SWP_REPORTS','optional_dates'),
 ('read_stp_can_report','STP_CAN_REPORT','STP_SWP_REPORTS','optional_dates'),
 ('read_stp_inst_due_report','STP_INST_DUE_REPORT','STP_SWP_REPORTS','optional_dates'),
 ('read_swp_reg_report','SWP_REG_REPORT','STP_SWP_REPORTS','optional_dates'),
 ('read_swp_can_report','SWP_CAN_REPORT','STP_SWP_REPORTS','optional_dates'),
 ('read_swp_inst_due_report','SWP_INST_DUE_REPORT','STP_SWP_REPORTS','optional_dates'),
 ('read_sip_amc_pause_report','SIP_AMC_PAUSE_REPORT','STP_SWP_REPORTS','optional_dates');
$$;
CREATE OR REPLACE FUNCTION nse_app.compile(p_command jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE c record; o jsonb; f jsonb:='{}'::jsonb; d1 date; d2 date; allowed text[]; gap integer; x jsonb;
BEGIN
 IF pg_catalog.jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR NOT(p_command ?& ARRAY['kind','options'])
   OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(p_command) k WHERE k NOT IN ('kind','options'))
   OR pg_catalog.jsonb_typeof(p_command->'kind') IS DISTINCT FROM 'string'
   OR pg_catalog.jsonb_typeof(p_command->'options') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
 SELECT * INTO c FROM nse_app.catalog() WHERE kind=p_command->>'kind';
 IF c.kind IS NULL THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
 o:=p_command->'options';
 allowed:=CASE c.options_type WHEN 'none' THEN ARRAY[]::text[] WHEN 'date' THEN ARRAY['date']
   WHEN 'settlement' THEN ARRAY['from','to','source_operation_id','row_indices'] ELSE ARRAY['from','to'] END;
 IF EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(o) k WHERE NOT(k=ANY(allowed))) THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
 IF c.options_type='date' THEN
   d1:=nse_app.iso_date(o->'date'); f:=pg_catalog.jsonb_build_object('date',pg_catalog.to_char(d1,'DD-MM-YYYY'));
 ELSIF c.options_type IN ('dates','settlement') OR (c.options_type='optional_dates' AND o<>'{}'::jsonb) THEN
   d1:=nse_app.iso_date(o->'from'); d2:=nse_app.iso_date(o->'to'); gap:=d2-d1;
   IF gap<0 OR (c.family IN ('ORDER_STATUS','PROV_ORDERS') AND gap>6)
      OR (c.family='CLIENT_READINESS' AND gap>7)
      OR (c.family='ORDER_FUNDING' AND gap>CASE WHEN c.api='FUND_ORDER' THEN 31 ELSE 7 END)
      OR (c.family='SETTLEMENT_REDEMPTION' AND gap>30) THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
   f:=pg_catalog.jsonb_build_object('from_date',pg_catalog.to_char(d1,CASE WHEN c.family IN ('ORDER_STATUS','PROV_ORDERS') THEN 'YYYY-MM-DD' WHEN c.api='SIP_AMC_PAUSE_REPORT' THEN 'DD/MM/YYYY' ELSE 'DD-MM-YYYY' END),
     'to_date',pg_catalog.to_char(d2,CASE WHEN c.family IN ('ORDER_STATUS','PROV_ORDERS') THEN 'YYYY-MM-DD' WHEN c.api='SIP_AMC_PAUSE_REPORT' THEN 'DD/MM/YYYY' ELSE 'DD-MM-YYYY' END));
 END IF;
 IF c.family IN ('ORDER_STATUS','PROV_ORDERS') THEN
   f:=f||'{"trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}'::jsonb;
   IF c.api='PROV_ORDERS' THEN f:=f||'{"date_type":"REQUEST DATE"}'::jsonb; END IF;
 ELSIF c.api='CLIENT_AUTHORIZATION' THEN f:=f||'{"date_type":"AUTH_SENT_DATE"}'::jsonb;
 ELSIF c.api='CLIENT_DETAIL' THEN f:=f||'{"date_type":"MODIFIED_DATE"}'::jsonb;
 ELSIF c.api='TRANSACTION_DETAIL' THEN f:=f||'{"date_type":"REQUEST_DATE"}'::jsonb;
 ELSIF c.api IN ('REDEMPTION_PAYOUT','REDEMPTION_PAYOUT_NON_DEMAT') THEN f:=f||'{"report_type":"Order Date"}'::jsonb;
 ELSIF c.api='ALLOTMENT_STATEMENT' THEN f:=f||'{"date_type":"ORD_DATE"}'::jsonb;
 END IF;
 IF c.family='SIP_XSIP_REPORTS' THEN PERFORM public.validate_nse_sip_xsip_reports_filters(c.api,f); END IF;
 IF c.family='STP_SWP_REPORTS' THEN PERFORM public.validate_nse_stp_swp_reports_filters(c.api,f); END IF;
 IF c.options_type='settlement' THEN
   IF pg_catalog.jsonb_typeof(o->'source_operation_id') IS DISTINCT FROM 'string'
      OR o->>'source_operation_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR pg_catalog.jsonb_typeof(o->'row_indices') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
   IF pg_catalog.jsonb_array_length(o->'row_indices') NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
   FOR x IN SELECT value FROM pg_catalog.jsonb_array_elements(o->'row_indices') LOOP
     IF pg_catalog.jsonb_typeof(x)<>'number' OR x::text !~ '^[0-9]{1,5}$' THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
   END LOOP;
   IF (SELECT count(DISTINCT value) FROM pg_catalog.jsonb_array_elements(o->'row_indices'))<>pg_catalog.jsonb_array_length(o->'row_indices') THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
 END IF;
 RETURN pg_catalog.jsonb_build_object('api',c.api,'family',c.family,'filters',f);
EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'INVALID_COMMAND';
END $$;
CREATE OR REPLACE FUNCTION public.get_nse_read_context_v1(p_target_ref uuid,p_command jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE s jsonb; a public.integration_accounts; gate nse_app.dev_access; c record; caps jsonb:='[]'::jsonb; reason text; compiled jsonb; eligibility jsonb; ver jsonb; verification_state text;
BEGIN
 BEGIN s:=nse_app.scope(p_target_ref); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('NOT_AUTHORIZED'); END;
 SELECT * INTO a FROM public.integration_accounts WHERE id=(s->>'account')::uuid;
 SELECT * INTO gate FROM nse_app.dev_access WHERE workspace_id=(s->>'workspace')::uuid;
 FOR c IN SELECT * FROM nse_app.catalog() LOOP
   reason:=nse_app.prerequisite(s,c.family);
   IF reason IS NULL AND NOT COALESCE(gate.enabled,false) THEN reason:='FEATURE_DISABLED'; END IF;
   IF reason IS NULL AND c.family='SETTLEMENT_REDEMPTION' THEN
     reason:=CASE WHEN EXISTS(SELECT 1 FROM public.nse_order_status_observations WHERE integration_account_id=a.id AND record_count>0)
       THEN 'OWNED_ORDER_SELECTION_REQUIRED' ELSE 'POSITIVE_OWNED_ORDER_EVIDENCE_REQUIRED' END;
   END IF;
   IF reason IS NULL AND c.api='STP_INST_DUE_REPORT' THEN reason:='OWNED_STP_REGISTRATION_SELECTION_REQUIRED'; END IF;
   IF reason IS NULL AND c.api='SIP_AMC_PAUSE_REPORT' AND pg_catalog.length(a.external_account_id)>15 THEN reason:='ACCOUNT_IDENTITY_UNAVAILABLE'; END IF;
   caps:=caps||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('kind',c.kind,'api',c.api,'options_type',c.options_type,
     'availability',CASE WHEN reason IS NULL THEN 'AVAILABLE' ELSE 'BLOCKED_PREREQUISITE' END,'reason',reason,
     'implemented',true,'commissioning','UNKNOWN'));
 END LOOP;
 IF p_command IS NOT NULL THEN
   BEGIN
     compiled:=nse_app.compile(p_command); reason:=nse_app.prerequisite(s,compiled->>'family');
     IF reason IS NULL AND NOT COALESCE(gate.enabled,false) THEN reason:='FEATURE_DISABLED'; END IF;
     IF reason IS NULL AND compiled->>'family'='SETTLEMENT_REDEMPTION' THEN
       PERFORM nse_app.settlement_selection(s,compiled->>'api',p_command->'options');
     END IF;
     IF reason IS NULL AND compiled->>'api'='STP_INST_DUE_REPORT' THEN reason:='OWNED_STP_REGISTRATION_SELECTION_REQUIRED'; END IF;
     IF reason IS NULL AND compiled->>'api'='SIP_AMC_PAUSE_REPORT' AND pg_catalog.length(a.external_account_id)>15 THEN reason:='ACCOUNT_IDENTITY_UNAVAILABLE'; END IF;
     eligibility:=pg_catalog.jsonb_build_object('available',reason IS NULL,'reason',reason);
   EXCEPTION WHEN OTHERS THEN eligibility:=pg_catalog.jsonb_build_object('available',false,'reason',
     CASE WHEN SQLERRM='BLOCKED_PREREQUISITE' THEN 'POSITIVE_OWNED_ORDER_EVIDENCE_REQUIRED' ELSE 'INVALID_COMMAND' END); END;
 END IF;
 ver:=a.integration_metadata->'nse_registration';
 SELECT state INTO verification_state FROM public.integration_operations WHERE integration_account_id=a.id AND workspace_id=a.workspace_id
   AND integration_key='NSE_INVEST' AND integration_environment='UAT' AND operation_type='UCC_VERIFICATION'
   AND operation_purpose='POST_REGISTRATION_VERIFICATION' ORDER BY created_at DESC,id DESC LIMIT 1;
 RETURN nse_app.reply(pg_catalog.jsonb_build_object('target_ref',p_target_ref,'environment','UAT',
   'account_state',COALESCE(a.state,'NOT_REGISTERED'),'has_external_account_id',a.external_account_id IS NOT NULL,
   'verification_status',CASE WHEN ver->>'client_master_verification_status' IN ('CONFIRMED','NOT_CONFIRMED','HTTP_FAILED') THEN ver->>'client_master_verification_status' ELSE 'UNKNOWN' END,
   'verification_checked_at',(ver->>'client_master_checked_at')::timestamptz,'verification_operation_state',verification_state,'deployment_verified',COALESCE(gate.enabled,false),
   'release_sha',gate.verified_release_sha,'capabilities',caps,'eligibility',eligibility));
EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('TEMPORARILY_UNAVAILABLE');
END $$;
CREATE OR REPLACE FUNCTION public.submit_nse_read_v1(p_target_ref uuid,p_request_id uuid,p_command jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE s jsonb; r nse_app.submission_receipts; c jsonb; op public.integration_operations; selection jsonb; new_id uuid; reason text;
BEGIN
 BEGIN s:=nse_app.scope(p_target_ref); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('NOT_AUTHORIZED'); END;
 IF p_request_id IS NULL OR p_command IS NULL OR pg_catalog.pg_column_size(p_command)>8192 THEN RETURN nse_app.failure('INVALID_COMMAND'); END IF;
 -- Actor lock also serializes request UUIDs reused across different workspaces.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nse-app-actor:'||(s->>'actor'),0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nse-app-workspace:'||(s->>'workspace'),0));
 -- Recheck after waiting for locks; hold the authority rows until acceptance.
 PERFORM 1 FROM public.workspaces WHERE id=(s->>'workspace')::uuid FOR SHARE;
 PERFORM 1 FROM public.profiles WHERE id IN ((s->>'actor')::uuid,(s->>'investor')::uuid) ORDER BY id FOR SHARE;
 PERFORM 1 FROM public.user_accounts WHERE user_id=auth.uid() FOR SHARE;
 PERFORM 1 FROM auth.users WHERE id=auth.uid() FOR SHARE;
 PERFORM 1 FROM public.workspace_memberships WHERE workspace_id=(s->>'workspace')::uuid
   AND profile_id IN ((s->>'actor')::uuid,(s->>'investor')::uuid) ORDER BY id FOR SHARE;
 PERFORM 1 FROM public.advisor_investor_assignments WHERE advisor_id=(s->>'actor')::uuid
   AND investor_id=(s->>'investor')::uuid ORDER BY id FOR SHARE;
 BEGIN s:=nse_app.scope(p_target_ref); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('NOT_AUTHORIZED'); END;
 SELECT * INTO r FROM nse_app.submission_receipts WHERE actor_profile_id=(s->>'actor')::uuid AND request_id=p_request_id;
 IF r.operation_id IS NOT NULL THEN
   IF r.target_ref<>p_target_ref OR r.command IS DISTINCT FROM p_command THEN RETURN nse_app.failure('REQUEST_CONFLICT'); END IF;
   SELECT * INTO op FROM public.integration_operations WHERE id=r.operation_id;
   RETURN nse_app.reply(pg_catalog.jsonb_build_object('acceptance','REPLAYED','request_id',p_request_id,'operation_id',op.id,'state',op.state,'poll_after_ms',2000));
 END IF;
 BEGIN c:=nse_app.compile(p_command); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('INVALID_COMMAND'); END;
 PERFORM 1 FROM nse_app.dev_access WHERE workspace_id=(s->>'workspace')::uuid AND enabled FOR SHARE;
 IF NOT FOUND THEN RETURN nse_app.failure('FEATURE_DISABLED'); END IF;
 reason:=nse_app.prerequisite(s,c->>'family');
 IF c->>'api'='STP_INST_DUE_REPORT' THEN RETURN nse_app.failure('BLOCKED_PREREQUISITE'); END IF;
 IF c->>'api'='SIP_AMC_PAUSE_REPORT' AND (SELECT pg_catalog.length(external_account_id)>15 FROM public.integration_accounts WHERE id=(s->>'account')::uuid) THEN RETURN nse_app.failure('BLOCKED_PREREQUISITE'); END IF;
 IF reason IS NOT NULL THEN RETURN nse_app.failure('BLOCKED_PREREQUISITE'); END IF;
 -- Hold account while existing preparation performs its authoritative checks.
 PERFORM 1 FROM public.integration_accounts WHERE id=(s->>'account')::uuid FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.integration_operations WHERE integration_account_id=(s->>'account')::uuid AND api_key=c->>'api'
   AND (state IN ('PREPARED','QUEUED','SUBMITTING','RECONCILIATION_REQUIRED') OR (state='SUBMISSION_FAILED' AND retry_allowed))) THEN RETURN nse_app.failure('OPERATION_IN_PROGRESS'); END IF;
 IF (SELECT count(*) FROM nse_app.submission_receipts WHERE actor_profile_id=(s->>'actor')::uuid AND accepted_at>pg_catalog.now()-interval '1 minute')>=10
   OR (SELECT count(*) FROM nse_app.submission_receipts WHERE workspace_id=(s->>'workspace')::uuid AND accepted_at>pg_catalog.now()-interval '1 minute')>=60
   OR EXISTS(SELECT 1 FROM nse_app.submission_receipts WHERE integration_account_id=(s->>'account')::uuid AND command->>'kind'=p_command->>'kind'
     AND accepted_at>pg_catalog.now()-interval '10 seconds') THEN RETURN nse_app.failure('RATE_LIMITED'); END IF;
 new_id:=pg_catalog.gen_random_uuid();
 IF c->>'family'='SETTLEMENT_REDEMPTION' THEN
   BEGIN selection:=nse_app.settlement_selection(s,c->>'api',p_command->'options'); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('BLOCKED_PREREQUISITE'); END;
 END IF;
 CASE c->>'family'
 WHEN 'ORDER_STATUS' THEN SELECT * INTO op FROM public.prepare_nse_order_status((s->>'workspace')::uuid,(s->>'account')::uuid,c->'filters',new_id);
 WHEN 'PROV_ORDERS' THEN SELECT * INTO op FROM public.prepare_nse_prov_orders((s->>'workspace')::uuid,(s->>'account')::uuid,c->'filters',new_id);
 WHEN 'CLIENT_READINESS' THEN SELECT * INTO op FROM public.prepare_nse_client_readiness((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id);
 WHEN 'ORDER_FUNDING' THEN SELECT * INTO op FROM public.prepare_nse_order_funding((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id);
 WHEN 'STP_SWP_REPORTS' THEN SELECT * INTO op FROM public.prepare_nse_stp_swp_reports((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id);
 WHEN 'SIP_XSIP_REPORTS' THEN SELECT * INTO op FROM public.prepare_nse_sip_xsip_reports((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id);
 WHEN 'SETTLEMENT_REDEMPTION' THEN SELECT * INTO op FROM public.prepare_nse_settlement_redemption((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id,selection);
 ELSE RAISE EXCEPTION 'INVALID_COMMAND'; END CASE;
 IF op.id IS DISTINCT FROM new_id OR op.safety_class<>'READ_ONLY' OR op.state<>'QUEUED' THEN RAISE EXCEPTION 'unexpected_preparation_result'; END IF;
 INSERT INTO nse_app.submission_receipts VALUES((s->>'actor')::uuid,p_request_id,p_target_ref,(s->>'workspace')::uuid,(s->>'account')::uuid,p_command,op.id,pg_catalog.now());
 INSERT INTO public.workspace_audit_logs(workspace_id,actor_id,actor_profile_id,actor_type,action,event_type,target_type,entity_type,target_id,entity_id,correlation_id,reason,new_state,payload)
 VALUES((s->>'workspace')::uuid,(s->>'actor')::uuid,(s->>'actor')::uuid,(SELECT role FROM public.profiles WHERE id=(s->>'actor')::uuid),'nse.read_accepted','nse.read_accepted',
   'integration_operation','integration_operation',op.id,op.id,p_request_id,'Authorized account read','QUEUED',pg_catalog.jsonb_build_object('kind',p_command->>'kind','channel','nse_console'));
 RETURN nse_app.reply(pg_catalog.jsonb_build_object('acceptance','ACCEPTED','request_id',p_request_id,'operation_id',op.id,'state',op.state,'poll_after_ms',2000));
 -- This exception block rolls back preparation, receipt AND audit together.
EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('TEMPORARILY_UNAVAILABLE');
END $$;
CREATE OR REPLACE FUNCTION nse_app.operation_dto(p_operation uuid,p_detail boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE o public.integration_operations; c record; summary jsonb; category text; native text; display text; pending boolean; summary_error boolean:=false;
BEGIN
 SELECT * INTO o FROM public.integration_operations WHERE id=p_operation;
 SELECT * INTO c FROM nse_app.catalog() WHERE api=o.api_key AND family=o.operation_type;
 IF c.kind IS NULL OR o.safety_class<>'READ_ONLY' OR o.integration_key<>'NSE_INVEST' OR o.integration_environment<>'UAT' OR o.contract_version<>'NNF_1.9.7' THEN RAISE EXCEPTION 'unavailable'; END IF;
 pending:=o.state IN ('PREPARED','QUEUED','SUBMITTING') OR (o.state='SUBMISSION_FAILED' AND o.retry_allowed);
 -- Only reviewed categories leave the database; no arbitrary stored strings.
 category:=CASE WHEN o.business_remark_category=ANY(ARRAY[
   'order_status_no_records','order_status_report_received','order_status_vendor_rejected','order_status_response_invalid','order_status_scope_mismatch',
   'prov_orders_no_records','prov_orders_report_received','prov_orders_vendor_rejected','prov_orders_response_invalid','prov_orders_scope_mismatch',
   'client_readiness_report_received','client_readiness_business_failed','client_readiness_response_invalid','client_readiness_row_scope_invalid','client_readiness_duplicate_rows',
   'order_funding_report_received','order_funding_no_records','order_funding_business_failed','order_funding_amc_code_invalid','order_funding_empty_success_diagnostic',
   'order_funding_response_invalid','order_funding_row_scope_invalid','order_funding_duplicate_rows',
   'settlement_redemption_report_received','settlement_redemption_no_records','settlement_redemption_business_failed','settlement_redemption_response_invalid',
   'settlement_redemption_row_scope_invalid','settlement_redemption_duplicate_rows','settlement_redemption_incomplete_selection','settlement_redemption_unknown_success_diagnostic',
   'sip_xsip_reports_report_received','sip_xsip_reports_no_records','sip_xsip_reports_response_invalid','sip_xsip_reports_unknown_diagnostic',
   'sip_xsip_reports_row_scope_invalid','sip_xsip_reports_duplicate_rows','sip_xsip_reports_incomplete_selection',
   'stp_swp_reports_report_received','stp_swp_reports_no_records','stp_swp_reports_response_invalid','stp_swp_reports_unknown_diagnostic','stp_swp_reports_row_scope_invalid','stp_swp_reports_duplicate_rows','stp_swp_reports_incomplete_selection']) THEN o.business_remark_category
   ELSE CASE WHEN o.state='SUCCESS' THEN 'report_received' WHEN pending THEN NULL ELSE 'operation_failed' END END;
 native:=CASE WHEN o.native_business_status IN ('S','F') THEN o.native_business_status ELSE NULL END;
 display:=CASE WHEN o.state IN ('PREPARED','QUEUED') THEN 'QUEUED' WHEN o.state='SUBMITTING' THEN 'RUNNING'
   WHEN pending THEN 'RETRY_PENDING' WHEN o.state='RECONCILIATION_REQUIRED' THEN 'RECONCILIATION_REQUIRED'
   WHEN o.state='SUCCESS' THEN 'SUCCESS'
   WHEN o.state='BUSINESS_FAILED' AND category=ANY(ARRAY['order_status_vendor_rejected','prov_orders_vendor_rejected','client_readiness_business_failed',
     'order_funding_business_failed','order_funding_amc_code_invalid','order_funding_no_records','settlement_redemption_business_failed']) THEN 'BUSINESS_FAILED'
   WHEN o.state IN ('BUSINESS_FAILED','VALIDATION_FAILED') THEN 'FAILED_CLOSED' ELSE 'FAILED' END;
 IF p_detail AND o.state='SUCCESS' THEN
   BEGIN
     CASE c.family
     WHEN 'ORDER_STATUS' THEN SELECT pg_catalog.to_jsonb(x) INTO summary FROM public.get_nse_order_status_observation(o.workspace_id,o.integration_account_id,o.id) x;
     WHEN 'PROV_ORDERS' THEN summary:=public.get_nse_prov_orders_summary(o.workspace_id,o.integration_account_id,o.id);
     WHEN 'CLIENT_READINESS' THEN summary:=public.get_nse_client_readiness_summary(o.workspace_id,o.integration_account_id,o.id);
     WHEN 'ORDER_FUNDING' THEN summary:=public.get_nse_order_funding_summary(o.workspace_id,o.integration_account_id,o.id);
     WHEN 'SETTLEMENT_REDEMPTION' THEN summary:=public.get_nse_settlement_redemption_summary(o.workspace_id,o.integration_account_id,o.id);
     WHEN 'STP_SWP_REPORTS' THEN summary:=public.get_nse_stp_swp_reports_summary(o.workspace_id,o.integration_account_id,o.id);
     WHEN 'SIP_XSIP_REPORTS' THEN summary:=public.get_nse_sip_xsip_reports_summary(o.workspace_id,o.integration_account_id,o.id);
     END CASE;
     IF summary IS NULL OR summary='null'::jsonb OR pg_catalog.jsonb_typeof(summary->'record_count') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'summary_unavailable'; END IF;
     summary:=pg_catalog.jsonb_build_object('record_count',summary->'record_count') || CASE WHEN c.family IN ('ORDER_STATUS','PROV_ORDERS') THEN
       pg_catalog.jsonb_build_object('valid_count',summary->'valid_count','invalid_count',summary->'invalid_count','other_count',summary->'other_count') ELSE '{}'::jsonb END;
   EXCEPTION WHEN OTHERS THEN summary:=NULL; summary_error:=true; display:='RESULT_UNAVAILABLE'; END;
 END IF;
 RETURN pg_catalog.jsonb_build_object('operation_id',o.id,'kind',c.kind,'api',c.api,'state',o.state,'display_status',display,'terminal',NOT pending,
   'backend_retry_pending',o.state='SUBMISSION_FAILED' AND o.retry_allowed,'attempt_count',o.attempt_count,
   'created_at',o.created_at,'submitted_at',o.submitted_at,'completed_at',o.completed_at,'updated_at',o.updated_at,'fetched_at',pg_catalog.now(),
   'summary',CASE WHEN p_detail THEN COALESCE(summary,'{}'::jsonb)||pg_catalog.jsonb_build_object('native_status',native,'category',CASE WHEN summary_error THEN 'summary_unavailable' ELSE category END) ELSE NULL END);
END $$;
COMMIT;
