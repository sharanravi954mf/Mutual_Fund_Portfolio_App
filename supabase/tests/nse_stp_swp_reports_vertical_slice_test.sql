-- Execute after all migrations. Synthetic data only; every fixture rolls back.
\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('f0010000-0000-4000-8000-000000000001','authenticated','authenticated','stp-swp-reports-one@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now()),
 ('f0010000-0000-4000-8000-000000000002','authenticated','authenticated','stp-swp-reports-two@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now());
-- Current signup creates workspace-referenced profiles. Never rewrite their IDs.
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('f0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,'Synthetic STP_SWP_REPORTS',
 'stp-swp-reports-'||right(user_id::text,1),id,'active' FROM public.profiles
 WHERE user_id IN ('f0010000-0000-4000-8000-000000000001','f0010000-0000-4000-8000-000000000002');
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role,status)
SELECT ('f0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,'investor','active'
 FROM public.profiles WHERE user_id IN ('f0010000-0000-4000-8000-000000000001','f0010000-0000-4000-8000-000000000002');
INSERT INTO public.integration_accounts(id,workspace_id,investor_profile_id,integration_key,integration_environment,external_account_id,state,current_registration_status)
SELECT ('f0060000-0000-4000-8000-'||right(user_id::text,12))::uuid,
 ('f0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,'NSE_INVEST','UAT','SYNTHETIC'||right(user_id::text,1),'REGISTERED','REG_SUCCESS'
 FROM public.profiles WHERE user_id IN ('f0010000-0000-4000-8000-000000000001','f0010000-0000-4000-8000-000000000002');

CREATE TEMP TABLE b05_assertions(label text);
CREATE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'assertion_failed:%',label; END IF; INSERT INTO b05_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.expect_error(statement text, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN
   IF strpos(SQLERRM,expected)>0 THEN INSERT INTO b05_assertions VALUES('expected_error:'||expected); RETURN; END IF;
   RAISE EXCEPTION 'wrong_error_expected_%_got_%',expected,SQLERRM;
 END;
 RAISE EXCEPTION 'missing_error:%',expected;
END $$;

SELECT 1 FROM vault.create_secret(repeat('p',40),'pan_encryption_key','synthetic rollback-only key');
INSERT INTO public.profile_pan_records(id,profile_id,pan_ciphertext,pan_lookup_hmac,masked_pan,source,source_system,status,verified_at)
SELECT ('f0040000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,
 extensions.pgp_sym_encrypt('AAAAA0000A',public.pan_encryption_key(),'cipher-algo=aes256, compress-algo=0'),
 extensions.digest('synthetic-'||id::text,'sha256'),'******000A','INVESTOR','API','VERIFIED',now()
FROM public.profiles WHERE user_id IN ('f0010000-0000-4000-8000-000000000001','f0010000-0000-4000-8000-000000000002');
UPDATE public.profiles SET canonical_pan_record_id=('f0040000-0000-4000-8000-'||right(user_id::text,12))::uuid
 WHERE user_id IN ('f0010000-0000-4000-8000-000000000001','f0010000-0000-4000-8000-000000000002');

CREATE TEMP TABLE financial_before AS SELECT
 (SELECT count(*) FROM public.transactions) transactions,
 (SELECT count(*) FROM public.folio_references) folios,
 (SELECT count(*) FROM public.portfolios) portfolios,
 (SELECT count(*) FROM public.portfolio_folio_references) holdings,
 (SELECT count(*) FROM public.order_requests) orders,
 (SELECT count(*) FROM public.payment_events) payments;
-- Any attempt to INSERT/UPDATE/DELETE a financial table fails this whole suite.
CREATE FUNCTION pg_temp.forbid_financial_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'b05_financial_mutation_forbidden'; END $$;
CREATE TRIGGER b05_no_transactions BEFORE INSERT OR UPDATE OR DELETE ON public.transactions FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b05_no_folios BEFORE INSERT OR UPDATE OR DELETE ON public.folio_references FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b05_no_portfolios BEFORE INSERT OR UPDATE OR DELETE ON public.portfolios FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b05_no_holdings BEFORE INSERT OR UPDATE OR DELETE ON public.portfolio_folio_references FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b05_no_payments BEFORE INSERT OR UPDATE OR DELETE ON public.payment_events FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b05_no_orders BEFORE INSERT OR UPDATE OR DELETE ON public.order_requests FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TEMP TABLE stp_swp_contracts(api text, filters jsonb, request jsonb, path text, row_data jsonb, selection jsonb, id_field text, days integer);
INSERT INTO stp_swp_contracts VALUES ('STP_REG_REPORT','{}','{"client_code":"SYNTHETIC1"}','/nsemfdesk/api/v2/reports/STP_REG_REPORT','{"status": "SYNTHETIC", "member_code": "05418", "client_code": "SYNTHETIC1", "stp_registration_no": "202501011000001", "folio_no": "SYNTHETIC", "internal_ref_no": "SYNTHETIC", "from_amc_name": "SYNTHETIC", "to_amc_name": "SYNTHETIC", "from_scheme_name": "SYNTHETIC", "to_scheme_name": "SYNTHETIC", "stp_registration_date": "01 JAN 2025", "stp_start_date": "01 JAN 2025", "stp_end_date": "01 JAN 2025", "frequency_type": "MONTHLY", "trxn_mode": "SYNTHETIC", "transfer_amount": "1000", "transfer_units": "1000", "no_of_transfers": "SYNTHETIC", "first_order_todays_flag": "SYNTHETIC", "euin_declaration": "SYNTHETIC", "euin_number": "SYNTHETIC", "sub_br_code": "SYNTHETIC", "remarks": "SYNTHETIC", "sub_br_arn_code": "SYNTHETIC", "buy_sell_type": "SYNTHETIC", "from_nse_scheme_code": "SYNTHETIC", "to_nse_scheme_code": "SYNTHETIC", "email_id": "SYNTHETIC", "mobile_no": "SYNTHETIC", "member_unique_id": "SYNTHETIC_REF_1"}','null','stp_registration_no',31);
INSERT INTO stp_swp_contracts VALUES ('STP_CAN_REPORT','{}','{"client_code":"SYNTHETIC1"}','/nsemfdesk/api/v2/reports/STP_CAN_REPORT','{"member_code": "05418", "client_code": "SYNTHETIC1", "stp_registration_no": "202501011000001", "folio_no": "SYNTHETIC", "from_amc_name": "SYNTHETIC", "to_amc_name": "SYNTHETIC", "from_scheme_name": "SYNTHETIC", "to_scheme_name": "SYNTHETIC", "stp_registration_date": "01 JAN 2025", "stp_start_date": "01 JAN 2025", "stp_end_date": "01 JAN 2025", "frequency": "MONTHLY", "trxn_mode": "SYNTHETIC", "transfer_amount": "1000", "transfer_units": "1000", "no_of_transfers": "SYNTHETIC", "euin_declaration": "SYNTHETIC", "euin_number": "SYNTHETIC", "sub_br_code": "SYNTHETIC", "remarks": "SYNTHETIC", "stp_cancellation_date": "01 JAN 2025", "stp_cancelled_by": "SYNTHETIC"}','null','stp_registration_no',31);
INSERT INTO stp_swp_contracts VALUES ('SWP_REG_REPORT','{}','{"client_code":"SYNTHETIC1"}','/nsemfdesk/api/v2/reports/SWP_REG_REPORT','{"status": "SYNTHETIC", "member_code": "05418", "client_code": "SYNTHETIC1", "swp_registration_no": "202501011000001", "folio_no": "SYNTHETIC", "amc": "SYNTHETIC", "scheme_name": "SYNTHETIC", "frequency_type": "MONTHLY", "swp_registration_date": "01 JAN 2025", "swp_start_date": "01 JAN 2025", "swp_end_date": "01 JAN 2025", "withdrawl_amount": "1000", "withdrawal_units": "1000", "no_of_withdrawls": "SYNTHETIC", "euin_declaration": "SYNTHETIC", "euin_number": "SYNTHETIC", "subbrcode": "SYNTHETIC", "first_order_flag": "SYNTHETIC", "int_ref_no": "SYNTHETIC", "remark": "SYNTHETIC", "sub_broker_arn_code": "SYNTHETIC", "nse_scheme_code": "SYNTHETIC", "transaction_mode": "SYNTHETIC", "mobile_no": "SYNTHETIC", "email_id": "SYNTHETIC", "bank_account_no": "SYNTHETIC", "member_unique_id": "SYNTHETIC_REF_1"}','null','swp_registration_no',31);
INSERT INTO stp_swp_contracts VALUES ('SWP_CAN_REPORT','{}','{"client_code":"SYNTHETIC1"}','/nsemfdesk/api/v2/reports/SWP_CAN_REPORT','{"member_code": "05418", "client_code": "SYNTHETIC1", "swp_registration_no": "202501011000001", "folio_no": "SYNTHETIC", "amc": "SYNTHETIC", "scheme_name": "SYNTHETIC", "swp_registration_date": "01 JAN 2025", "swp_cancellation_date": "01 JAN 2025", "swp_start_date": "01 JAN 2025", "swp_end_date": "01 JAN 2025", "frequency_type": "MONTHLY", "withdrawl_amount": "1000", "withdrawl_units": "1000", "no_of_withdrawls": "SYNTHETIC", "euin_declaration": "SYNTHETIC", "euin_number": "SYNTHETIC", "subbrcode": "SYNTHETIC", "remark": "SYNTHETIC", "swp_cancelled_by": "SYNTHETIC", "nse_scheme_code": "SYNTHETIC"}','null','swp_registration_no',31);
INSERT INTO stp_swp_contracts VALUES ('SWP_INST_DUE_REPORT','{}','{"client_code":"SYNTHETIC1"}','/nsemfdesk/api/v2/reports/SWP_INST_DUE_REPORT','{"member_code": "05418", "client_code": "SYNTHETIC1", "client_name": "SYNTHETIC", "swp_regn_no": "202501011000001", "folio_no": "SYNTHETIC", "internal_ref_no": "SYNTHETIC", "regn_date": "01 JAN 2025", "amc_name": "SYNTHETIC", "scheme_code": "SYNTHETIC", "scheme_name": "SYNTHETIC", "frequency_type": "MONTHLY", "installment_amt": "1000", "installment_units": "1000", "due_date": "01 JAN 2025", "prev_paid_date": "01 JAN 2025", "no_of_installments_paid": "SYNTHETIC", "total_installment_amt_sold": "1000", "unit_sold": "SYNTHETIC", "entry_by": "SYNTHETIC", "dp_trans": "SYNTHETIC", "euin_declaration": "SYNTHETIC", "euin_number": "SYNTHETIC", "subbrcode": "SYNTHETIC", "first_order_flag": "SYNTHETIC", "remark": "SYNTHETIC"}','null','swp_regn_no',7);
CREATE FUNCTION pg_temp.prepare(api text) RETURNS public.integration_operations LANGUAGE sql AS $$
 SELECT public.prepare_nse_stp_swp_reports('f0030000-0000-4000-8000-000000000001','f0060000-0000-4000-8000-000000000001',api,c.filters,gen_random_uuid(),c.selection) FROM stp_swp_contracts c WHERE c.api=$1;
$$;
CREATE FUNCTION pg_temp.start_read(op uuid) RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event_id uuid; claim record;
BEGIN
 SELECT id INTO event_id FROM public.event_outbox WHERE entity_id=op;
 IF EXISTS(SELECT 1 FROM public.event_outbox WHERE id=event_id AND status='failed') THEN
  SELECT * INTO claim FROM public.claim_nse_stp_swp_reports_event(event_id,3,120);
  PERFORM pg_temp.assert_true(claim.claim_state='no_event','direct_retry_backoff');
  UPDATE public.event_outbox SET updated_at=now()-interval '31 seconds' WHERE id=event_id;
 END IF;
 SELECT * INTO claim FROM public.claim_nse_stp_swp_reports_event(event_id,3,120);
 RETURN public.start_nse_stp_swp_reports(event_id,claim.claim_token,gen_random_uuid(),
   (public.get_nse_stp_swp_reports_source(op)->'request')::text,'{"content_type":"application/json","accept":"application/json"}',now());
END $$;
CREATE FUNCTION pg_temp.finish_read(req public.integration_api_interactions, body text, http integer)
RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event public.event_outbox; observation jsonb; outcome text; native text; category text;
BEGIN
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=req.integration_operation_id;
 IF http BETWEEN 200 AND 299 THEN
  observation:=public.inspect_nse_stp_swp_reports_response(req.api_key,body,extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference))::jsonb,
   public.nse_stp_swp_reports_identity(req.integration_operation_id));
  outcome:=CASE WHEN (observation->>'success')::bool THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END;native:=observation->>'native_status';category:=observation->>'category';
 ELSE outcome:=CASE WHEN http IS NULL THEN 'TRANSPORT_FAILURE' ELSE 'HTTP_FAILURE' END;
  category:=CASE WHEN http IS NULL THEN 'stp_swp_reports_transport_failed' ELSE 'stp_swp_reports_http_failure' END;
 END IF;
 RETURN public.finish_nse_stp_swp_reports(event.id,event.claim_token,req.call_id,body,
   CASE WHEN http IS NULL THEN NULL ELSE 'application/json' END,'{}',http,native,category,outcome,
   CASE WHEN outcome='SUCCESS' THEN NULL WHEN outcome='TRANSPORT_FAILURE' THEN 'nse_request_timeout' ELSE category END,
   http IS NULL,false,now(),1,3);
END $$;

SET LOCAL ROLE authenticated;
DO $$
DECLARE persona text;
BEGIN
 FOREACH persona IN ARRAY ARRAY['platform_admin','family_guest','inactive_member','operations','unrelated_advisor','cross_workspace'] LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','app_metadata',jsonb_build_object('role',persona))::text,true);
  BEGIN PERFORM public.prepare_nse_stp_swp_reports(NULL,NULL,'STP_REG_REPORT'); RAISE EXCEPTION 'browser_prepare_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_stp_swp_reports_summary(NULL,NULL,NULL); RAISE EXCEPTION 'browser_summary_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_stp_swp_reports_source(NULL); RAISE EXCEPTION 'browser_source_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;


SET LOCAL ROLE service_role;
SELECT id FROM public.prepare_nse_stp_swp_reports('f0030000-0000-4000-8000-000000000001','f0060000-0000-4000-8000-000000000001','STP_REG_REPORT');
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM public.get_nse_stp_swp_reports_source(NULL); RAISE EXCEPTION 'anon_source_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$
DECLARE c record; fn regprocedure; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; src jsonb; summary jsonb; raw text; body jsonb; key text; value jsonb; replay public.integration_api_interactions; claim record;
BEGIN
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('prepare_nse_stp_swp_reports','get_nse_stp_swp_reports_source','claim_nse_stp_swp_reports_event',
 'recover_expired_nse_stp_swp_reports_events','start_nse_stp_swp_reports','finish_nse_stp_swp_reports','get_nse_stp_swp_reports_summary') LOOP
  PERFORM pg_temp.assert_true(has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'rpc_acl');
  PERFORM pg_temp.assert_true((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_search_path');
 END LOOP;
 PERFORM pg_temp.assert_true(NOT has_function_privilege('service_role','public.nse_stp_swp_reports_identity(uuid)','EXECUTE'),'identity_helper_private');
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('nse_stp_swp_reports_contract','nse_b05_date','validate_nse_stp_swp_reports_filters',
 'nse_stp_swp_registration_fields','nse_stp_swp_reports_request','inspect_nse_stp_swp_reports_response',
 'nse_stp_swp_reports_selection','guard_nse_stp_swp_reports_context','nse_stp_swp_reports_identity') LOOP
  PERFORM pg_temp.assert_true(NOT has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE')
   AND NOT has_function_privilege('anon',fn,'EXECUTE'),'every_b05_helper_private');
 END LOOP;
 PERFORM pg_temp.assert_true((SELECT relrowsecurity FROM pg_class WHERE oid='public.event_outbox'::regclass),'outbox_rls');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='event_outbox'),'private_outbox_policies');
 FOR c IN SELECT * FROM stp_swp_contracts LOOP
  op:=pg_temp.prepare(c.api); src:=public.get_nse_stp_swp_reports_source(op.id);
  PERFORM pg_temp.assert_true(src->'request'=c.request AND src->>'api'=c.api AND src->>'pan'='AAAAA0000A','exact_request_'||c.api);
  SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  PERFORM pg_temp.assert_true(event.payload::text NOT LIKE '%AAAAA0000A%' AND event.payload::text NOT LIKE '%SYNTHETIC1%','encrypted_context');
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_stp_swp_reports(%L,%L,%L,%L)',
   'f0030000-0000-4000-8000-000000000002','f0060000-0000-4000-8000-000000000001',c.api,c.filters),'stp_swp_reports_account_scope_invalid');
  FOREACH key IN ARRAY ARRAY['PAN','pan','Pan','client_code','product_type','Product_type','product_id','order_id','systematic_reg_id','pg_bank_refno','member_code','amc_code','scheme_code','url','stp_reg_id','swp_reg_id','parent_stp_reg_id','parent_swp_reg_id','member_unique_ids'] LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_stp_swp_reports(%L,%L,%L,%L)',
    op.workspace_id,op.integration_account_id,c.api,c.filters||jsonb_build_object(key,'FOREIGN')),'stp_swp_reports_filters_invalid');
  END LOOP;
  PERFORM pg_temp.assert_true((public.prepare_nse_stp_swp_reports(op.workspace_id,op.integration_account_id,c.api,c.filters,op.id,c.selection)).id=op.id,'prepare_idempotent');
  PERFORM pg_temp.expect_error(format('UPDATE public.event_outbox SET payload=payload||%L::jsonb WHERE id=%L','{"api":"UNKNOWN"}',event.id),'stp_swp_reports_context_immutable');
  PERFORM pg_temp.expect_error(format('DELETE FROM public.event_outbox WHERE id=%L',event.id),'stp_swp_reports_context_immutable');
  req:=pg_temp.start_read(op.id);
  SELECT * INTO event FROM public.event_outbox WHERE id=event.id;
  PERFORM pg_temp.assert_true(req.endpoint_path=c.path AND req.http_method='POST' AND req.phase='REQUEST','exact_endpoint_'||c.api);
  raw:=extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference));
  PERFORM pg_temp.assert_true(raw=c.request::text AND req.request_bytes=octet_length(raw) AND req.request_hash=extensions.digest(raw,'sha256'),'request_exact_evidence');
  SELECT * INTO replay FROM public.start_nse_stp_swp_reports(event.id,event.claim_token,req.call_id,raw,req.request_header_metadata,req.started_at);
  PERFORM pg_temp.assert_true(replay.id=req.id,'request_ack_replay');
  PERFORM pg_temp.expect_error(format('SELECT public.start_nse_stp_swp_reports(%L,%L,%L,%L,%L,%L)',event.id,event.claim_token,req.call_id,raw||' ',req.request_header_metadata,req.started_at),'integration_request_idempotency_conflict');
  SELECT * INTO claim FROM public.claim_nse_stp_swp_reports_event(event.id);
  PERFORM pg_temp.assert_true(claim.claim_state='no_event','exact_claim_once');
  body:=jsonb_build_object('response_status','S','report_data_total','1','report_data',jsonb_build_array(c.row_data));
  raw:=body::text||E'\n';
  result:=pg_temp.finish_read(req,raw,200);
  PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS' AND result.api_key=c.api,'validated_success_'||c.api);
  PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw
   AND result.response_bytes=octet_length(raw) AND result.response_hash=extensions.digest(raw,'sha256'),'result_exact_evidence');
  replay:=pg_temp.finish_read(req,raw,200);PERFORM pg_temp.assert_true(result.id=replay.id,'result_ack_replay');
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.finish_read((SELECT i FROM public.integration_api_interactions i WHERE id=%L),%L,200)',req.id,raw||' '),'integration_result_idempotency_conflict');
  summary:=public.get_nse_stp_swp_reports_summary(op.workspace_id,op.integration_account_id,op.id);
  PERFORM pg_temp.assert_true(summary->>'record_count'='1' AND summary->>'api'=c.api AND summary::text NOT LIKE '%PRIVATE%' AND summary::text NOT LIKE '%AAAAA0000A%','private_safe_summary');
  PERFORM pg_temp.assert_true(public.get_nse_stp_swp_reports_summary(gen_random_uuid(),op.integration_account_id,op.id) IS NULL,'summary_workspace_scope');
  PERFORM pg_temp.assert_true(public.get_nse_stp_swp_reports_summary(op.workspace_id,gen_random_uuid(),op.id) IS NULL,'summary_account_scope');
  PERFORM pg_temp.expect_error(format('UPDATE public.integration_api_interactions SET response_payload_ciphertext=NULL WHERE id=%L',result.id),'integration_api_interactions_append_only');
  PERFORM pg_temp.expect_error(format('DELETE FROM public.integration_api_interactions WHERE id=%L',req.id),'integration_api_interactions_append_only');
  FOR value IN SELECT x FROM (VALUES (body||'{"report_data_total":0}'::jsonb),(body||'{"report_data_total":null}'::jsonb),
    (body||'{"report_data_total":"1.0"}'::jsonb),(body||'{"report_data":{}}'::jsonb),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||jsonb_build_object('client_code','FOREIGN')))),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data,c.row_data),'report_data_total',2)),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||'{"unknown":{}}'::jsonb)))) v(x) LOOP
    PERFORM pg_temp.assert_true(NOT (public.inspect_nse_stp_swp_reports_response(c.api,value::text,c.request,src)->>'success')::bool,'bad_shape_scope_count_'||c.api);
    op:=pg_temp.prepare(c.api);req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,value::text,200);
    PERFORM pg_temp.assert_true(result.normalized_outcome='BUSINESS_FAILURE' AND extensions.pgp_sym_decrypt(result.response_payload_ciphertext,
     public.integration_payload_encryption_key(result.payload_encryption_key_reference))=value::text,'invalid_report_exact_result_'||c.api);
    PERFORM pg_temp.assert_true((SELECT NOT retry_allowed FROM public.integration_operations WHERE id=op.id)
     AND public.get_nse_stp_swp_reports_summary(op.workspace_id,op.integration_account_id,op.id) IS NULL,'invalid_report_terminal_no_summary');
  END LOOP;
  value:=body||'{"error_remark":"PRIVATE"}'::jsonb;
  PERFORM pg_temp.assert_true(
    (public.inspect_nse_stp_swp_reports_response(c.api,value::text,c.request,src)->>'success')::bool = false,
    'success_diagnostic_policy_'||c.api);
  PERFORM pg_temp.assert_true(public.inspect_nse_stp_swp_reports_response(c.api,value::text,c.request,src)::text NOT LIKE '%PRIVATE%','success_diagnostic_not_projected_'||c.api);
  -- Independently finish an empty report, F and malformed data for every API.
  FOREACH raw IN ARRAY ARRAY[(body||'{"report_data":[],"report_data_total":0}'::jsonb)::text,'{"response_status":"F","error_remark":"PRIVATE"}','PRIVATE'] LOOP
   op:=pg_temp.prepare(c.api);req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,raw,200);
   PERFORM pg_temp.assert_true(result.normalized_outcome=CASE WHEN raw LIKE '%"response_status": "S"%' THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END,'empty_failure_malformed_'||c.api);
  END LOOP;
 END LOOP;
END $$;

-- Explicit date tests use a deterministic India day; UCC takes precedence and
-- dates are omitted by default. No member-wide date fallback can be constructed.
DO $$
DECLARE c record; bad jsonb; key text; src jsonb; body jsonb; op public.integration_operations;
BEGIN
 FOR c IN SELECT * FROM stp_swp_contracts LOOP
  PERFORM public.validate_nse_stp_swp_reports_filters(c.api,'{}','2026-10-01');
  PERFORM public.validate_nse_stp_swp_reports_filters(c.api,jsonb_build_object('from_date','01-10-2026','to_date',CASE WHEN c.days=7 THEN '08-10-2026' ELSE '01-11-2026' END),'2026-10-01');
  FOR bad IN SELECT x FROM (VALUES ('null'::jsonb),('[]'::jsonb),('{"from_date":null,"to_date":"02-10-2026"}'::jsonb),
    ('{"from_date":"01-10-2026"}'::jsonb),('{"to_date":"02-10-2026"}'::jsonb),
    ('{"from_date":"01-10-2026","to_date":"01-10-2026"}'::jsonb),('{"from_date":"02-10-2026","to_date":"01-10-2026"}'::jsonb),
    ('{"from_date":"31-02-2025","to_date":"01-03-2025"}'::jsonb),('{"from_date":"2026-10-01","to_date":"02-10-2026"}'::jsonb),
    ('{"from_date":"01-01-0000","to_date":"02-01-0000"}'::jsonb),
    (jsonb_build_object('from_date','01-10-2026','to_date',CASE WHEN c.days=7 THEN '09-10-2026' ELSE '02-11-2026' END))) v(x) LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_stp_swp_reports_filters(%L,%L,%L)',c.api,bad,'2026-10-01'),'stp_swp_reports_filters_invalid');
  END LOOP;
  IF c.days=7 THEN
   PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_stp_swp_reports_filters(%L,%L,%L)',c.api,'{"from_date":"30-09-2026","to_date":"01-10-2026"}','2026-10-01'),'stp_swp_reports_filters_invalid');
  ELSE PERFORM public.validate_nse_stp_swp_reports_filters(c.api,'{"from_date":"30-09-2026","to_date":"01-10-2026"}','2026-10-01'); END IF;
  op:=pg_temp.prepare(c.api);src:=public.get_nse_stp_swp_reports_source(op.id);
  FOR key IN SELECT jsonb_object_keys(c.row_data) LOOP
   FOREACH bad IN ARRAY ARRAY[c.row_data-key,c.row_data||jsonb_build_object(key,NULL),c.row_data||jsonb_build_object(key,1)] LOOP
    body:=jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array(bad));
    PERFORM pg_temp.assert_true(NOT(public.inspect_nse_stp_swp_reports_response(c.api,body::text,c.request,src)->>'success')::bool,'endpoint_schema_'||c.api||'_'||key);
   END LOOP;
  END LOOP;
  FOREACH bad IN ARRAY ARRAY[c.row_data||'{"unknown":""}',c.row_data||'{"client_code":"FOREIGN"}',c.row_data||'{"member_code":"9999"}'] LOOP
   body:=jsonb_build_object('response_status','S','report_data_total',2,'report_data',jsonb_build_array(c.row_data,bad));
   PERFORM pg_temp.assert_true(NOT(public.inspect_nse_stp_swp_reports_response(c.api,body::text,c.request,src)->>'success')::bool,'mixed_unknown_rows');
  END LOOP;
  FOREACH bad IN ARRAY ARRAY['{"error_remark":""}'::jsonb,'{"error_remark":"No record(s) found."}','{"unknown":""}'] LOOP
   body:=jsonb_build_object('response_status','S','report_data_total',0,'report_data','[]'::jsonb)||bad;
   PERFORM pg_temp.assert_true(NOT(public.inspect_nse_stp_swp_reports_response(c.api,body::text,c.request,src)->>'success')::bool,'no_borrowed_diagnostic_policy');
  END LOOP;
 END LOOP;
END $$;

-- C029/C030: current member_unique_ids, sourced only from owned B05 registration
-- reports of the same family; preserve stable registration business correlation.
DO $$
DECLARE c record; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 source_result public.integration_api_interactions; selected jsonb; bad jsonb; src jsonb; body jsonb; rows jsonb; key text; id uuid;
 filters jsonb:='{"from_date":"01-01-2025","to_date":"01-02-2025"}';
BEGIN
 FOR c IN SELECT * FROM stp_swp_contracts WHERE api IN ('STP_REG_REPORT','SWP_REG_REPORT') LOOP
  op:=pg_temp.prepare(c.api);req:=pg_temp.start_read(op.id);
  body:=jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array(c.row_data));
  source_result:=pg_temp.finish_read(req,body::text,200);
  selected:=jsonb_build_object('result_id',source_result.id,'row_indices',jsonb_build_array(0),'selector','member');
  FOREACH bad IN ARRAY ARRAY['{}'::jsonb,selected||'{"row_indices":[]}',selected||'{"row_indices":[0,0]}',selected||'{"row_indices":[-1]}',
    selected||'{"row_indices":[1]}',selected||'{"row_indices":[0.5]}',selected||'{"row_indices":["0"]}',selected||'{"row_indices":[2147483648]}',
    selected||'{"result_id":"bad"}',selected||'{"selector":null}',selected||'{"selector":"registration"}',selected||'{"member_unique_ids":"FOREIGN"}',
    selected||jsonb_build_object('result_id',req.id),selected||jsonb_build_object('row_indices',to_jsonb(array_fill(0,ARRAY[51])))] LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_stp_swp_reports(%L,%L,%L,%L,%L,%L)',op.workspace_id,op.integration_account_id,c.api,filters,gen_random_uuid(),bad),'stp_swp_reports_selection_invalid');
  END LOOP;
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_stp_swp_reports(%L,%L,%L,%L,%L,%L)',
   'f0030000-0000-4000-8000-000000000002','f0060000-0000-4000-8000-000000000002',c.api,filters,gen_random_uuid(),selected),'stp_swp_reports_selection_invalid');
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_stp_swp_reports(%L,%L,%L,%L,%L,%L)',op.workspace_id,op.integration_account_id,
   CASE WHEN c.api='STP_REG_REPORT' THEN 'SWP_REG_REPORT' ELSE 'STP_REG_REPORT' END,filters,gen_random_uuid(),selected),'stp_swp_reports_selection_invalid');
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_stp_swp_reports(%L,%L,%L,%L,%L,%L)',op.workspace_id,op.integration_account_id,'STP_CAN_REPORT',filters,gen_random_uuid(),selected),'stp_swp_reports_selection_invalid');
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_stp_swp_reports(%L,%L,%L,%L,%L,%L)',op.workspace_id,op.integration_account_id,c.api,'{}',gen_random_uuid(),selected),'stp_swp_reports_selection_invalid');
  op:=public.prepare_nse_stp_swp_reports(op.workspace_id,op.integration_account_id,c.api,filters,gen_random_uuid(),selected);
  src:=public.get_nse_stp_swp_reports_source(op.id);
  PERFORM pg_temp.assert_true(src->'request'=filters||jsonb_build_object('member_unique_ids',c.row_data->>'member_unique_id'),'exact_current_member_selector');
  PERFORM pg_temp.assert_true(NOT(src->'request' ?| ARRAY['client_code','stp_reg_id','swp_reg_id']),'only_effective_member_selector');
  FOR key IN SELECT jsonb_object_keys(src->'selectors'->'rows'->0) LOOP
   PERFORM pg_temp.assert_true(NOT(public.inspect_nse_stp_swp_reports_response(c.api,
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||jsonb_build_object(key,'FOREIGN'))))::text,src->'request',src)->>'success')::bool,'member_business_correlation_'||key);
  END LOOP;
  req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,body::text,200);
  PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS','member_observation');
  PERFORM pg_temp.expect_error(format('SELECT public.nse_stp_swp_reports_selection(%L,%L,%L,%L)',op.workspace_id,op.integration_account_id,c.api,
   selected||jsonb_build_object('result_id',result.id)),'stp_swp_reports_selection_invalid');
  -- Blank references and non-unique member lineage may be observed, never selected.
  FOREACH rows IN ARRAY ARRAY[jsonb_build_array(c.row_data||'{"member_unique_id":""}'),
    jsonb_build_array(c.row_data,c.row_data||jsonb_build_object(c.id_field,'202501011000002')),
    jsonb_build_array(c.row_data,c.row_data||jsonb_build_object(c.id_field,'202501011000002','client_code','FOREIGN'))] LOOP
   op:=pg_temp.prepare(c.api);req:=pg_temp.start_read(op.id);
   result:=pg_temp.finish_read(req,jsonb_build_object('response_status','S','report_data_total',jsonb_array_length(rows),'report_data',rows)::text,200);
   PERFORM pg_temp.expect_error(format('SELECT public.nse_stp_swp_reports_selection(%L,%L,%L,%L)',op.workspace_id,op.integration_account_id,c.api,
    selected||jsonb_build_object('result_id',result.id)),'stp_swp_reports_selection_invalid');
  END LOOP;
  -- Two selected registrations must be distinct and cover the positive response.
  rows:=jsonb_build_array(c.row_data,c.row_data||jsonb_build_object(c.id_field,'202501011000002','member_unique_id','SECOND'));
  op:=pg_temp.prepare(c.api);req:=pg_temp.start_read(op.id);
  result:=pg_temp.finish_read(req,jsonb_build_object('response_status','S','report_data_total',2,'report_data',rows)::text,200);
  selected:=selected||jsonb_build_object('result_id',result.id,'row_indices',jsonb_build_array(0,1));
  op:=public.prepare_nse_stp_swp_reports(op.workspace_id,op.integration_account_id,c.api,filters,gen_random_uuid(),selected);
  src:=public.get_nse_stp_swp_reports_source(op.id);
  PERFORM pg_temp.assert_true(public.inspect_nse_stp_swp_reports_response(c.api,body::text,src->'request',src)->>'category'='stp_swp_reports_incomplete_selection','partial_member_selection');
  req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,jsonb_build_object('response_status','S','report_data_total',2,'report_data',rows)::text,200);
  PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS','two_owned_members');
 END LOOP;
END $$;
-- Cross-runtime disagreement cannot discard a completed provider response.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; event public.event_outbox;
 result public.integration_api_interactions; replay public.integration_api_interactions; raw text;
BEGIN
 FOREACH raw IN ARRAY ARRAY['{"response_status":"F"}',
   '{"response_status":"S","report_data_total":1e-400,"report_data":[]}'] LOOP
  op:=pg_temp.prepare('STP_REG_REPORT');req:=pg_temp.start_read(op.id);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  result:=public.finish_nse_stp_swp_reports(event.id,event.claim_token,req.call_id,raw,'application/json','{}',200,'S',
   'stp_swp_reports_report_received','SUCCESS',NULL,false,false,now(),1);
  PERFORM pg_temp.assert_true(result.normalized_outcome='BUSINESS_FAILURE' AND result.native_remark_category='stp_swp_reports_interpretation_mismatch'
   AND extensions.pgp_sym_decrypt(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw,'mismatched_interpretation_retains_exact_evidence');
  PERFORM pg_temp.assert_true((SELECT state='BUSINESS_FAILED' AND NOT retry_allowed FROM public.integration_operations WHERE id=op.id),'mismatch_terminal');
  PERFORM pg_temp.assert_true(public.get_nse_stp_swp_reports_summary(op.workspace_id,op.integration_account_id,op.id) IS NULL,'mismatch_no_trusted_summary');
  replay:=public.finish_nse_stp_swp_reports(event.id,event.claim_token,req.call_id,raw,'application/json','{}',200,'S',
   'stp_swp_reports_report_received','SUCCESS',NULL,false,false,now(),1);
  PERFORM pg_temp.assert_true(replay.id=result.id,'mismatch_ack_replay');
 END LOOP;
END $$;

-- Binary RESULT evidence uses the existing ciphertext/hash/length columns.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; event public.event_outbox;
 result public.integration_api_interactions; replay public.integration_api_interactions; raw bytea; body text; encoded text;
BEGIN
 FOREACH raw IN ARRAY ARRAY[decode('efbbbf7b7d','hex'),decode('ff80','hex'),decode('007b7d','hex')] LOOP
  op:=pg_temp.prepare('STP_REG_REPORT');req:=pg_temp.start_read(op.id);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  body:=CASE WHEN raw=decode('efbbbf7b7d','hex') THEN convert_from(raw,'UTF8') ELSE '' END; encoded:=encode(raw,'base64');
  result:=public.finish_nse_stp_swp_reports(event.id,event.claim_token,req.call_id,body,'application/json','{}',200,NULL,
    'stp_swp_reports_response_invalid','BUSINESS_FAILURE','stp_swp_reports_response_invalid',false,false,now(),1,3,encoded);
  PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt_bytea(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw
    AND result.response_bytes=octet_length(raw) AND result.response_hash=extensions.digest(raw,'sha256'),'exact_binary_result');
  replay:=public.finish_nse_stp_swp_reports(event.id,event.claim_token,req.call_id,body,'application/json','{}',200,NULL,
    'stp_swp_reports_response_invalid','BUSINESS_FAILURE','stp_swp_reports_response_invalid',false,false,now(),1,3,encoded);
  PERFORM pg_temp.assert_true(result.id=replay.id,'binary_result_ack_replay');
 END LOOP;
END $$;

-- All endpoints use the same bounded lifecycle, independent of native statuses.
DO $$
DECLARE c record; status integer; attempt integer; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; claim record; before_state text; raw text;
BEGIN
 FOR c IN SELECT * FROM stp_swp_contracts LOOP
  FOREACH status IN ARRAY ARRAY[408,429,500,502,503,504,0,400,401,403,404,501] LOOP
   op:=pg_temp.prepare(c.api);
   FOR attempt IN 1..CASE WHEN status IN (408,429,500,502,503,504,0) THEN 3 ELSE 1 END LOOP
    req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,CASE WHEN status=0 THEN '' ELSE 'PRIVATE' END,NULLIF(status,0));
    PERFORM pg_temp.assert_true(result.attempt_number=attempt AND result.normalized_outcome=CASE WHEN status=0 THEN 'TRANSPORT_FAILURE' ELSE 'HTTP_FAILURE' END,'retry_classification_'||c.api);
    SELECT * INTO op FROM public.integration_operations WHERE id=op.id;
    PERFORM pg_temp.assert_true(op.retry_allowed=(status IN (408,429,500,502,503,504,0) AND attempt<3),'bounded_retry_budget');
   END LOOP;
   SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
   SELECT * INTO claim FROM public.claim_nse_stp_swp_reports_event(event.id);
   PERFORM pg_temp.assert_true(claim.claim_state='no_event','terminal_no_claim');
   PERFORM pg_temp.assert_true((SELECT count(*)=op.attempt_count*2 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'all_attempt_pairs_retained');
  END LOOP;
  -- Expired claim before transport, then expired claim after immutable REQUEST.
  op:=pg_temp.prepare(c.api);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  SELECT * INTO claim FROM public.claim_nse_stp_swp_reports_event(event.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM public.recover_expired_nse_stp_swp_reports_events(event.id);
  UPDATE public.event_outbox SET updated_at=now()-interval '31 seconds' WHERE id=event.id;
  SELECT * INTO claim FROM public.claim_nse_stp_swp_reports_event(event.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.stp_swp_reports_requested'],50,0) WHERE event_outbox_id=event.id),'retry_pre_request_discovery');
  PERFORM public.recover_expired_nse_stp_swp_reports_events(event.id);
  req:=pg_temp.start_read(op.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM public.recover_expired_nse_stp_swp_reports_events(event.id);
  PERFORM pg_temp.assert_true((SELECT count(*)=2 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'abandoned_request_closed');
  PERFORM pg_temp.assert_true((SELECT NOT retry_allowed AND attempt_count=3 FROM public.integration_operations WHERE id=op.id),'expired_budget_exhausted');
  PERFORM pg_temp.assert_true((SELECT normalized_outcome='TRANSPORT_FAILURE' AND response_bytes=0 AND error_category='stp_swp_reports_read_lease_expired' FROM public.integration_api_interactions WHERE call_id=req.call_id AND phase='RESULT'),'truthful_expired_evidence');
 END LOOP;
END $$;
DO $$
DECLARE c record; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions; profile uuid; body jsonb;
BEGIN
 SELECT * INTO c FROM stp_swp_contracts WHERE api='STP_REG_REPORT'; op:=pg_temp.prepare(c.api);
 -- Account/identity validity before REQUEST; immutable snapshot after transport.
 SELECT id INTO profile FROM public.profiles WHERE user_id='f0010000-0000-4000-8000-000000000001';
 UPDATE public.workspace_memberships SET status='inactive' WHERE workspace_id=op.workspace_id AND profile_id=profile;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_stp_swp_reports_source(%L)',op.id),'stp_swp_reports_account_scope_invalid');
 UPDATE public.workspace_memberships SET status='active' WHERE workspace_id=op.workspace_id AND profile_id=profile;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id=op.workspace_id;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_stp_swp_reports_source(%L)',op.id),'stp_swp_reports_account_scope_invalid');
 UPDATE public.workspaces SET workspace_status='active' WHERE id=op.workspace_id;
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC1' WHERE id='f0060000-0000-4000-8000-000000000002';
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_stp_swp_reports_source(%L)',op.id),'stp_swp_reports_account_scope_invalid');
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC2' WHERE id='f0060000-0000-4000-8000-000000000002';
 req:=pg_temp.start_read(op.id);
 UPDATE public.integration_accounts SET external_account_id='CHANGED' WHERE id=op.integration_account_id;
 body:=jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array(c.row_data));
 result:=pg_temp.finish_read(req,body::text,200);
 PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS' AND public.get_nse_stp_swp_reports_summary(op.workspace_id,op.integration_account_id,op.id)->>'record_count'='1','immutable_post_transport_identity');
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_stp_swp_reports_source(%L)',op.id),'stp_swp_reports_identity_changed');
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC1' WHERE id=op.integration_account_id;
END $$;
-- Only transient network/timeouts (and reviewed HTTP statuses) allow transport retry.
DO $$
DECLARE code text; op public.integration_operations; req public.integration_api_interactions; event public.event_outbox; result public.integration_api_interactions;
BEGIN
 FOREACH code IN ARRAY ARRAY['nse_response_too_large','nse_response_invalid','nse_request_invalid'] LOOP
  op:=pg_temp.prepare('STP_REG_REPORT');req:=pg_temp.start_read(op.id);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  result:=public.finish_nse_stp_swp_reports(event.id,event.claim_token,req.call_id,'',NULL,'{}',NULL,NULL,'stp_swp_reports_transport_failed','TRANSPORT_FAILURE',code,false,false,now(),1);
  PERFORM pg_temp.assert_true((SELECT NOT retry_allowed FROM public.integration_operations WHERE id=op.id),'nontransient_transport_terminal');
 END LOOP;
END $$;

-- Independent STP due lineage: no client/member fields in the native response.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 src jsonb; selected jsonb; bad jsonb; row_data jsonb:='{"stp_registration_no": "202501011000001", "client_name": "SYNTHETIC", "folio_no": "SYNTHETIC", "internal_ref_no": "SYNTHETIC", "stp_registration_date": "01 JAN 2025", "amc_name": "SYNTHETIC", "from_scheme_name": "SYNTHETIC", "to_scheme_name": "SYNTHETIC", "frequency_type": "MONTHLY", "dp_trans": "SYNTHETIC", "transfer_amount": "1000", "transfer_units": "1000", "due_date": "01 JAN 2025", "prev_transfer_date": "01 JAN 2025", "no_of_transfer_completed": "SYNTHETIC", "first_order_todays_flag": "SYNTHETIC", "euin_declaration": "SYNTHETIC", "euin_number": "SYNTHETIC", "sub_br_code": "SYNTHETIC", "remarks": "SYNTHETIC", "entry_by": "SYNTHETIC"}'::jsonb; body jsonb; id uuid; key text;
BEGIN
 PERFORM pg_temp.expect_error($q$SELECT public.prepare_nse_stp_swp_reports('f0030000-0000-4000-8000-000000000001','f0060000-0000-4000-8000-000000000001','STP_INST_DUE_REPORT')$q$,'stp_swp_reports_owned_registration_required');
 op:=pg_temp.prepare('STP_REG_REPORT'); req:=pg_temp.start_read(op.id);
 result:=pg_temp.finish_read(req,jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array('{"status": "SYNTHETIC", "member_code": "05418", "client_code": "SYNTHETIC1", "stp_registration_no": "202501011000001", "folio_no": "SYNTHETIC", "internal_ref_no": "SYNTHETIC", "from_amc_name": "SYNTHETIC", "to_amc_name": "SYNTHETIC", "from_scheme_name": "SYNTHETIC", "to_scheme_name": "SYNTHETIC", "stp_registration_date": "01 JAN 2025", "stp_start_date": "01 JAN 2025", "stp_end_date": "01 JAN 2025", "frequency_type": "MONTHLY", "trxn_mode": "SYNTHETIC", "transfer_amount": "1000", "transfer_units": "1000", "no_of_transfers": "SYNTHETIC", "first_order_todays_flag": "SYNTHETIC", "euin_declaration": "SYNTHETIC", "euin_number": "SYNTHETIC", "sub_br_code": "SYNTHETIC", "remarks": "SYNTHETIC", "sub_br_arn_code": "SYNTHETIC", "buy_sell_type": "SYNTHETIC", "from_nse_scheme_code": "SYNTHETIC", "to_nse_scheme_code": "SYNTHETIC", "email_id": "SYNTHETIC", "mobile_no": "SYNTHETIC", "member_unique_id": "SYNTHETIC_REF_1"}'::jsonb))::text,200);
 selected:=jsonb_build_object('result_id',result.id,'row_indices',jsonb_build_array(0),'selector','registration');
 FOREACH bad IN ARRAY ARRAY[selected||'{"row_indices":[]}',selected||'{"row_indices":[0,0]}',selected||'{"row_indices":[1]}',selected||'{"row_indices":[-1]}',selected||'{"row_indices":["0"]}',selected||'{"selector":"member"}',selected||jsonb_build_object('result_id',req.id)] LOOP
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_stp_swp_reports(%L,%L,%L,%L,%L,%L)',op.workspace_id,op.integration_account_id,'STP_INST_DUE_REPORT','{}',gen_random_uuid(),bad),'stp_swp_reports_selection_invalid');
 END LOOP;
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_stp_swp_reports(%L,%L,%L,%L,%L,%L)','f0030000-0000-4000-8000-000000000002','f0060000-0000-4000-8000-000000000002','STP_INST_DUE_REPORT','{}',gen_random_uuid(),selected),'stp_swp_reports_selection_invalid');
 op:=public.prepare_nse_stp_swp_reports(op.workspace_id,op.integration_account_id,'STP_INST_DUE_REPORT','{}',gen_random_uuid(),selected);
 src:=public.get_nse_stp_swp_reports_source(op.id);
 PERFORM pg_temp.assert_true(src->'request'='{"stp_reg_id":"202501011000001"}'::jsonb,'due_exact_owned_id_request');
 body:=jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array(row_data));
 FOR key IN SELECT jsonb_object_keys(row_data) LOOP
  FOREACH bad IN ARRAY ARRAY[row_data-key,row_data||jsonb_build_object(key,NULL),row_data||jsonb_build_object(key,1)] LOOP
   PERFORM pg_temp.assert_true(NOT(public.inspect_nse_stp_swp_reports_response('STP_INST_DUE_REPORT',(body||jsonb_build_object('report_data',jsonb_build_array(bad)))::text,src->'request',src)->>'success')::bool,'due_field_'||key);
  END LOOP;
 END LOOP;
 FOR key IN SELECT jsonb_object_keys(src->'selectors'->'rows'->0) LOOP
  PERFORM pg_temp.assert_true(NOT(public.inspect_nse_stp_swp_reports_response('STP_INST_DUE_REPORT',(body||jsonb_build_object('report_data',jsonb_build_array(row_data||jsonb_build_object(key,'FOREIGN'))))::text,src->'request',src)->>'success')::bool,'due_owned_business_'||key);
 END LOOP;
 req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,body::text,200);
 PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS' AND public.get_nse_stp_swp_reports_summary(op.workspace_id,op.integration_account_id,op.id)->>'record_count'='1','due_positive_observation');
 op:=public.prepare_nse_stp_swp_reports(op.workspace_id,op.integration_account_id,'STP_INST_DUE_REPORT','{}',gen_random_uuid(),selected);
 req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,'{"response_status":"S","report_data_total":0,"report_data":[]}',200);
 PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS','due_empty_observation');
END $$;

-- AMC Pause is a distinct contract: slash dates, response_data_total, PAUSE only.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 src jsonb; bad jsonb; body jsonb; row_data jsonb:='{"client_code": "SYNTHETIC1", "sip_registration_no": "202501011000001", "scheme_code": "SYNTHETIC", "scheme_name": "SYNTHETIC", "amount": "1000", "sip_start_date": "01 JAN 2025", "sip_end_date": "01 JAN 2025", "no_of_instalments_paused": "SYNTHETIC", "date_of_activation": "01 JAN 2025", "pause_from_date": "01 JAN 2025", "pause_to_date": "01 JAN 2025", "request_id": "552", "entry_by": "SYNTHETIC", "modified_date": "01 JAN 2025", "modified_instalments": "SYNTHETIC"}'::jsonb; key text; raw text;
BEGIN
 PERFORM public.validate_nse_stp_swp_reports_filters('SIP_AMC_PAUSE_REPORT','{"from_date":"01/01/2025","to_date":"08/01/2025"}','2026-10-02');
 FOREACH bad IN ARRAY ARRAY['{"from_date":"01-01-2025","to_date":"02-01-2025"}'::jsonb,'{"from_date":"01/01/2025","to_date":"09/01/2025"}','{"from_date":"31/02/2025","to_date":"01/03/2025"}','{"modification_type":"UNPAUSE"}','{"request_id":"552"}','{"registration_no":"202501011000001"}'] LOOP
  PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_stp_swp_reports_filters(%L,%L)','SIP_AMC_PAUSE_REPORT',bad),'stp_swp_reports_filters_invalid');
 END LOOP;
 op:=public.prepare_nse_stp_swp_reports('f0030000-0000-4000-8000-000000000001','f0060000-0000-4000-8000-000000000001','SIP_AMC_PAUSE_REPORT');
 src:=public.get_nse_stp_swp_reports_source(op.id);
 PERFORM pg_temp.assert_true(src->'request'='{"client_code":"SYNTHETIC1","modification_type":"PAUSE"}'::jsonb,'amc_exact_request');
 body:=jsonb_build_object('response_status','S','response_data_total',2,'report_data',jsonb_build_array(row_data,row_data||'{"request_id":"557"}'),'error_remark','');
 req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,body::text,200);
 PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS' AND public.get_nse_stp_swp_reports_summary(op.workspace_id,op.integration_account_id,op.id)->>'record_count'='2','amc_request_id_not_registration_id');
 FOR key IN SELECT jsonb_object_keys(row_data) LOOP
  FOREACH bad IN ARRAY ARRAY[row_data-key,row_data||jsonb_build_object(key,NULL),row_data||jsonb_build_object(key,1)] LOOP
   PERFORM pg_temp.assert_true(NOT(public.inspect_nse_stp_swp_reports_response('SIP_AMC_PAUSE_REPORT',(body||jsonb_build_object('response_data_total',1,'report_data',jsonb_build_array(bad)))::text,src->'request',src)->>'success')::bool,'amc_field_'||key);
  END LOOP;
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[body-'error_remark',body-'response_data_total'||'{"report_data_total":2}',body||'{"error_remark":"No record(s) found."}',body||'{"error_remark":null}',body||'{"response_status":"F"}',body||'{"response_data_total":1}',body||jsonb_build_object('report_data',jsonb_build_array(row_data,row_data)),body||jsonb_build_object('report_data',jsonb_build_array(row_data,row_data||'{"client_code":"FOREIGN"}'))] LOOP
  op:=public.prepare_nse_stp_swp_reports(op.workspace_id,op.integration_account_id,'SIP_AMC_PAUSE_REPORT'); req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,bad::text,200);
  PERFORM pg_temp.assert_true(result.normalized_outcome='BUSINESS_FAILURE' AND (SELECT NOT retry_allowed FROM public.integration_operations WHERE id=op.id),'amc_invalid_terminal');
 END LOOP;
 op:=public.prepare_nse_stp_swp_reports(op.workspace_id,op.integration_account_id,'SIP_AMC_PAUSE_REPORT');req:=pg_temp.start_read(op.id);
 result:=pg_temp.finish_read(req,'{"response_status":"S","response_data_total":"0","report_data":[],"error_remark":""}',200);
 PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS','amc_empty');
END $$;
-- Financial business relations cannot be changed by any B05 RPC.
DO $$
DECLARE fn record;
BEGIN
 FOR fn IN SELECT prosrc FROM pg_proc WHERE proname LIKE '%nse_stp_swp_reports%' LOOP
  PERFORM pg_temp.assert_true(fn.prosrc !~* '(insert into|update|delete from) public\.(transactions|folios|portfolios|scheme_holdings|order_requests)','no_business_mutation');
 END LOOP;
END $$;
SELECT pg_temp.assert_true((SELECT transactions=(SELECT count(*) FROM public.transactions) AND folios=(SELECT count(*) FROM public.folio_references)
 AND portfolios=(SELECT count(*) FROM public.portfolios) AND holdings=(SELECT count(*) FROM public.portfolio_folio_references)
 AND orders=(SELECT count(*) FROM public.order_requests) AND payments=(SELECT count(*) FROM public.payment_events) FROM financial_before),'financial_tables_unchanged');
SELECT count(*) AS b05_assertions_passed FROM b05_assertions;
ROLLBACK;
