-- Authenticated application facade. Provider preparation/evidence ACLs stay intact.
BEGIN;
CREATE SCHEMA nse_app;
REVOKE ALL ON SCHEMA nse_app FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE nse_app.dev_access (
  workspace_id uuid PRIMARY KEY REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  environment text NOT NULL DEFAULT 'UAT' CHECK (environment = 'UAT'),
  enabled boolean NOT NULL DEFAULT false,
  verified_release_sha text CHECK (verified_release_sha ~ '^[0-9a-f]{40}$'),
  verified_at timestamptz,
  CHECK (NOT enabled OR (verified_release_sha IS NOT NULL AND verified_at IS NOT NULL))
);
CREATE TABLE nse_app.submission_receipts (
  actor_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  request_id uuid NOT NULL,
  target_ref uuid NOT NULL REFERENCES public.workspace_memberships(id) ON DELETE RESTRICT,
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  integration_account_id uuid NOT NULL REFERENCES public.integration_accounts(id) ON DELETE RESTRICT,
  command jsonb NOT NULL CHECK (jsonb_typeof(command) = 'object'),
  operation_id uuid NOT NULL UNIQUE REFERENCES public.integration_operations(id) ON DELETE RESTRICT,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (actor_profile_id, request_id)
);
ALTER TABLE nse_app.dev_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE nse_app.submission_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA nse_app FROM PUBLIC, anon, authenticated, service_role;
CREATE INDEX nse_receipts_actor_time ON nse_app.submission_receipts(actor_profile_id, accepted_at DESC);
CREATE INDEX nse_receipts_workspace_time ON nse_app.submission_receipts(workspace_id, accepted_at DESC);
CREATE INDEX nse_receipts_account_kind_time ON nse_app.submission_receipts(integration_account_id, (command->>'kind'), accepted_at DESC);
CREATE INDEX nse_operations_app_history ON public.integration_operations(integration_account_id, created_at DESC, id DESC)
  WHERE integration_key = 'NSE_INVEST' AND integration_environment = 'UAT' AND safety_class = 'READ_ONLY';
CREATE TRIGGER nse_receipt_immutable BEFORE UPDATE OR DELETE ON nse_app.submission_receipts
  FOR EACH ROW EXECUTE FUNCTION public.reject_integration_api_interaction_mutation();

CREATE FUNCTION nse_app.audit_gate() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.workspace_audit_logs(workspace_id, action, event_type, target_type, entity_type, target_id, entity_id, actor_type, reason, previous_state, new_state, payload)
  VALUES(COALESCE(NEW.workspace_id, OLD.workspace_id), 'nse.application_gate_changed', 'nse.application_gate_changed',
    'workspace','workspace',COALESCE(NEW.workspace_id, OLD.workspace_id),COALESCE(NEW.workspace_id, OLD.workspace_id),
    'system','DEV deployment gate changed',CASE WHEN TG_OP='INSERT' THEN NULL ELSE OLD.enabled::text END,
    CASE WHEN TG_OP='DELETE' THEN 'false' ELSE NEW.enabled::text END,
    pg_catalog.jsonb_build_object('enabled',CASE WHEN TG_OP='DELETE' THEN false ELSE NEW.enabled END,
      'release_sha',CASE WHEN TG_OP='DELETE' THEN NULL ELSE NEW.verified_release_sha END));
  RETURN COALESCE(NEW,OLD);
END $$;
CREATE TRIGGER nse_gate_audit AFTER INSERT OR UPDATE OR DELETE ON nse_app.dev_access FOR EACH ROW EXECUTE FUNCTION nse_app.audit_gate();

-- Static application catalog; values cannot select arbitrary functions or routes.
CREATE FUNCTION nse_app.catalog() RETURNS TABLE(kind text, api text, family text, options_type text)
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
 ('read_xsip_topup_report','XSIP_TOPUP_REPORT','SIP_XSIP_REPORTS','optional_dates');
$$;
CREATE FUNCTION nse_app.reply(p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  PERFORM pg_catalog.set_config('response.headers','[{"Cache-Control":"no-store"}]',true);
  RETURN pg_catalog.jsonb_build_object('schema_version',1,'data',p_data);
END $$;
CREATE FUNCTION nse_app.failure(p_code text) RETURNS jsonb LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  PERFORM pg_catalog.set_config('response.headers','[{"Cache-Control":"no-store"}]',true);
  RETURN pg_catalog.jsonb_build_object('schema_version',1,'error',pg_catalog.jsonb_build_object('code',p_code));
END $$;
CREATE FUNCTION nse_app.actor() RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR (SELECT count(*) FROM public.profiles WHERE user_id=auth.uid())<>1 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  v_id:=public.current_user_profile_id();
  IF NOT EXISTS(SELECT 1 FROM public.profiles p JOIN public.user_accounts a ON a.user_id=p.user_id
    JOIN auth.users u ON u.id=p.user_id WHERE p.id=v_id AND p.account_status='active'
    AND p.role IN ('advisor','admin') AND a.account_state='advisor'
    AND NOT u.is_anonymous AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=pg_catalog.now())) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  RETURN v_id;
END $$;
CREATE FUNCTION nse_app.can_target(p_actor uuid,p_target uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT EXISTS(SELECT 1 FROM public.workspace_memberships i
 JOIN public.workspaces w ON w.id=i.workspace_id AND w.workspace_status='active'
 JOIN public.profiles investor ON investor.id=i.profile_id AND investor.account_status='active'
 JOIN public.workspace_memberships m ON m.workspace_id=w.id AND m.profile_id=p_actor
   AND m.status='active' AND m.ended_at IS NULL
 WHERE i.id=p_target AND i.role='investor' AND i.status='active' AND i.ended_at IS NULL
 AND ((m.role='admin' AND w.owner_profile_id=p_actor) OR (m.role='advisor' AND EXISTS(
   SELECT 1 FROM public.advisor_investor_assignments a WHERE a.advisor_id=p_actor
   AND a.investor_id=i.profile_id AND a.status='active' AND a.ended_at IS NULL))));
$$;
CREATE FUNCTION nse_app.scope(p_target uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=nse_app.actor(); v_scope jsonb;
BEGIN
  IF p_target IS NULL OR NOT nse_app.can_target(v_actor,p_target) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT pg_catalog.jsonb_build_object('actor',v_actor,'target',i.id,'workspace',i.workspace_id,
    'investor',i.profile_id,'account',a.id) INTO v_scope
  FROM public.workspace_memberships i LEFT JOIN public.integration_accounts a
    ON a.workspace_id=i.workspace_id AND a.investor_profile_id=i.profile_id
    AND a.integration_key='NSE_INVEST' AND a.integration_environment='UAT' WHERE i.id=p_target;
  RETURN v_scope;
END $$;
CREATE FUNCTION nse_app.prerequisite(p_scope jsonb,p_family text) RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE a public.integration_accounts;
BEGIN
 SELECT * INTO a FROM public.integration_accounts WHERE id=(p_scope->>'account')::uuid;
 IF a.id IS NULL OR a.state<>'REGISTERED' THEN RETURN 'REGISTERED_ACCOUNT_REQUIRED'; END IF;
 IF a.external_account_id IS NULL OR a.external_account_id !~ '^[A-Za-z0-9_-]{1,20}$' OR EXISTS(
   SELECT 1 FROM public.integration_accounts other WHERE other.id<>a.id AND other.integration_key='NSE_INVEST'
     AND other.integration_environment='UAT' AND other.external_account_id=a.external_account_id) THEN RETURN 'ACCOUNT_IDENTITY_UNAVAILABLE'; END IF;
 IF p_family NOT IN ('ORDER_STATUS','PROV_ORDERS') AND NOT EXISTS(
   SELECT 1 FROM public.profiles p JOIN public.profile_pan_records pan ON pan.id=p.canonical_pan_record_id
   AND pan.profile_id=p.id AND pan.status='VERIFIED' WHERE p.id=a.investor_profile_id) THEN RETURN 'VERIFIED_IDENTITY_REQUIRED'; END IF;
 RETURN NULL;
END $$;
CREATE FUNCTION nse_app.iso_date(p_value jsonb) RETURNS date LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE v date; t text:=p_value#>>'{}';
BEGIN
 IF pg_catalog.jsonb_typeof(p_value) IS DISTINCT FROM 'string' OR t !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' OR t LIKE '0000-%' THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
 v:=t::date;
 IF pg_catalog.to_char(v,'YYYY-MM-DD')<>t THEN RAISE EXCEPTION 'INVALID_COMMAND'; END IF;
 RETURN v;
EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'INVALID_COMMAND';
END $$;

-- Compile ONLY non-sensitive application options into existing closed filters.
CREATE FUNCTION nse_app.compile(p_command jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = '' AS $$
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
   f:=pg_catalog.jsonb_build_object('from_date',pg_catalog.to_char(d1,CASE WHEN c.family IN ('ORDER_STATUS','PROV_ORDERS') THEN 'YYYY-MM-DD' ELSE 'DD-MM-YYYY' END),
     'to_date',pg_catalog.to_char(d2,CASE WHEN c.family IN ('ORDER_STATUS','PROV_ORDERS') THEN 'YYYY-MM-DD' ELSE 'DD-MM-YYYY' END));
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

CREATE FUNCTION nse_app.settlement_selection(p_scope jsonb,p_api text,p_options jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result uuid; v_selection jsonb;
BEGIN
 SELECT last_interaction_id INTO v_result FROM public.integration_operations
 WHERE id=(p_options->>'source_operation_id')::uuid AND workspace_id=(p_scope->>'workspace')::uuid
 AND integration_account_id=(p_scope->>'account')::uuid AND operation_type='ORDER_STATUS' AND state='SUCCESS';
 IF v_result IS NULL THEN RAISE EXCEPTION 'BLOCKED_PREREQUISITE'; END IF;
 v_selection:=pg_catalog.jsonb_build_object('result_id',v_result,'row_indices',p_options->'row_indices','selector','order');
 PERFORM public.nse_settlement_redemption_selection((p_scope->>'workspace')::uuid,(p_scope->>'account')::uuid,p_api,v_selection);
 RETURN v_selection;
EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'BLOCKED_PREREQUISITE';
END $$;

CREATE FUNCTION public.list_nse_read_targets_v1(p_after uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE a uuid; items jsonb;
BEGIN
 a:=nse_app.actor();
 SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('target_ref',q.id,'client_label',q.full_name,'workspace_label',q.name) ORDER BY q.id),'[]'::jsonb)
 INTO items FROM (SELECT i.id,p.full_name,w.name FROM public.workspace_memberships i
 JOIN public.profiles p ON p.id=i.profile_id JOIN public.workspaces w ON w.id=i.workspace_id
 WHERE (p_after IS NULL OR i.id>p_after) AND nse_app.can_target(a,i.id) ORDER BY i.id LIMIT 50) q;
 RETURN nse_app.reply(pg_catalog.jsonb_build_object('items',items,'next_cursor',CASE WHEN pg_catalog.jsonb_array_length(items)=50 THEN items->49->>'target_ref' ELSE NULL END));
EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('NOT_AUTHORIZED');
END $$;

CREATE FUNCTION public.get_nse_read_context_v1(p_target_ref uuid,p_command jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
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

CREATE FUNCTION public.list_nse_settlement_candidates_v1(p_target_ref uuid,p_kind text,p_source_operation_id uuid,p_after integer DEFAULT -1)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE s jsonb; c record; total integer; idx integer; items jsonb:='[]'::jsonb; valid boolean;
BEGIN
 BEGIN s:=nse_app.scope(p_target_ref); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('NOT_AUTHORIZED'); END;
 SELECT * INTO c FROM nse_app.catalog() WHERE kind=p_kind AND family='SETTLEMENT_REDEMPTION';
 IF c.kind IS NULL OR p_after IS NULL OR p_after NOT BETWEEN -1 AND 9999 THEN RETURN nse_app.failure('INVALID_COMMAND'); END IF;
 SELECT obs.record_count INTO total FROM public.nse_order_status_observations obs JOIN public.integration_operations o ON o.id=obs.operation_id
 WHERE o.id=p_source_operation_id AND o.integration_account_id=(s->>'account')::uuid AND o.workspace_id=(s->>'workspace')::uuid
 AND o.state='SUCCESS' AND o.last_interaction_id=obs.result_interaction_id;
 IF total IS NULL THEN RETURN nse_app.failure('TARGET_UNAVAILABLE'); END IF;
 FOR idx IN SELECT generate_series(p_after+1,LEAST(p_after+20,total-1)) LOOP
   valid:=true;
   BEGIN PERFORM nse_app.settlement_selection(s,c.api,pg_catalog.jsonb_build_object('source_operation_id',p_source_operation_id,'row_indices',pg_catalog.jsonb_build_array(idx)));
   EXCEPTION WHEN OTHERS THEN valid:=false; END;
   items:=items||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('row_index',idx,'eligible',valid,
     'label','Report row '||(idx+1)::text,'reason',CASE WHEN valid THEN NULL ELSE 'ORDER_EVIDENCE_NOT_ELIGIBLE' END));
 END LOOP;
 RETURN nse_app.reply(pg_catalog.jsonb_build_object('items',items,'next_cursor',CASE WHEN p_after+20<total-1 THEN p_after+20 ELSE NULL END));
EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('TEMPORARILY_UNAVAILABLE');
END $$;

CREATE FUNCTION public.submit_nse_read_v1(p_target_ref uuid,p_request_id uuid,p_command jsonb) RETURNS jsonb
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

CREATE FUNCTION nse_app.operation_dto(p_operation uuid,p_detail boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
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
   'sip_xsip_reports_row_scope_invalid','sip_xsip_reports_duplicate_rows','sip_xsip_reports_incomplete_selection']) THEN o.business_remark_category
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

CREATE FUNCTION public.list_nse_read_operations_v1(p_target_ref uuid,p_before_time timestamptz DEFAULT NULL,p_before_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE s jsonb; items jsonb; last_item jsonb;
BEGIN
 BEGIN s:=nse_app.scope(p_target_ref); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('NOT_AUTHORIZED'); END;
 IF (p_before_time IS NULL)<>(p_before_id IS NULL) THEN RETURN nse_app.failure('INVALID_COMMAND'); END IF;
 SELECT COALESCE(pg_catalog.jsonb_agg(nse_app.operation_dto(q.id,false)||pg_catalog.jsonb_build_object('target_ref',p_target_ref) ORDER BY q.created_at DESC,q.id DESC),'[]'::jsonb) INTO items FROM (
   SELECT o.id,o.created_at FROM public.integration_operations o JOIN nse_app.catalog() c ON c.api=o.api_key AND c.family=o.operation_type
   WHERE o.integration_account_id=(s->>'account')::uuid AND o.workspace_id=(s->>'workspace')::uuid AND o.safety_class='READ_ONLY' AND o.integration_environment='UAT' AND o.integration_key='NSE_INVEST' AND o.contract_version='NNF_1.9.7'
     AND (p_before_time IS NULL OR (o.created_at,o.id)<(p_before_time,p_before_id)) ORDER BY o.created_at DESC,o.id DESC LIMIT 20) q;
 last_item:=items->19;
 RETURN nse_app.reply(pg_catalog.jsonb_build_object('items',items,'next_cursor',CASE WHEN last_item IS NULL THEN NULL ELSE
   pg_catalog.jsonb_build_object('before_time',last_item->'created_at','before_id',last_item->'operation_id') END));
EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('TEMPORARILY_UNAVAILABLE');
END $$;
CREATE FUNCTION public.get_nse_read_operation_v1(p_operation_id uuid DEFAULT NULL,p_request_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid; op uuid:=p_operation_id; target uuid;
BEGIN
 actor:=nse_app.actor();
 IF (p_operation_id IS NULL)=(p_request_id IS NULL) THEN RETURN nse_app.failure('INVALID_COMMAND'); END IF;
 IF p_request_id IS NOT NULL THEN SELECT operation_id INTO op FROM nse_app.submission_receipts WHERE actor_profile_id=actor AND request_id=p_request_id; END IF;
 SELECT i.id INTO target FROM public.integration_operations o JOIN public.integration_accounts a ON a.id=o.integration_account_id
   JOIN public.workspace_memberships i ON i.workspace_id=a.workspace_id AND i.profile_id=a.investor_profile_id
 WHERE o.id=op AND o.workspace_id=a.workspace_id AND i.role='investor' AND i.ended_at IS NULL AND nse_app.can_target(actor,i.id);
 IF target IS NULL THEN RETURN nse_app.failure('TARGET_UNAVAILABLE'); END IF;
 RETURN nse_app.reply(nse_app.operation_dto(op,true)||pg_catalog.jsonb_build_object('target_ref',target));
EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('TARGET_UNAVAILABLE');
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA nse_app FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.list_nse_read_targets_v1(uuid),public.get_nse_read_context_v1(uuid,jsonb),
 public.list_nse_settlement_candidates_v1(uuid,text,uuid,integer),public.submit_nse_read_v1(uuid,uuid,jsonb),
 public.list_nse_read_operations_v1(uuid,timestamptz,uuid),public.get_nse_read_operation_v1(uuid,uuid)
 FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_nse_read_targets_v1(uuid),public.get_nse_read_context_v1(uuid,jsonb),
 public.list_nse_settlement_candidates_v1(uuid,text,uuid,integer),public.submit_nse_read_v1(uuid,uuid,jsonb),
 public.list_nse_read_operations_v1(uuid,timestamptz,uuid),public.get_nse_read_operation_v1(uuid,uuid)
 TO authenticated;
COMMIT;
