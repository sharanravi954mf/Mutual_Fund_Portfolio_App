-- Execute after all migrations. Synthetic data only; every fixture rolls back.
\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('f0010000-0000-4000-8000-000000000001','authenticated','authenticated','settlement-redemption-one@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now()),
 ('f0010000-0000-4000-8000-000000000002','authenticated','authenticated','settlement-redemption-two@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now());
-- Trusted synthetic provisioning; public signup creates only an Explorer account.
INSERT INTO public.profiles(user_id,role)
SELECT id,'investor' FROM auth.users WHERE id IN ('f0010000-0000-4000-8000-000000000001','f0010000-0000-4000-8000-000000000002');

-- Keep generated profile IDs distinct from auth IDs.
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('f0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,'Synthetic SETTLEMENT_REDEMPTION',
 'settlement-redemption-'||right(user_id::text,1),id,'active' FROM public.profiles
 WHERE user_id IN ('f0010000-0000-4000-8000-000000000001','f0010000-0000-4000-8000-000000000002');
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role,status)
SELECT ('f0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,'investor','active'
 FROM public.profiles WHERE user_id IN ('f0010000-0000-4000-8000-000000000001','f0010000-0000-4000-8000-000000000002');
INSERT INTO public.integration_accounts(id,workspace_id,investor_profile_id,integration_key,integration_environment,external_account_id,state,current_registration_status)
SELECT ('f0060000-0000-4000-8000-'||right(user_id::text,12))::uuid,
 ('f0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,'NSE_INVEST','UAT','SYNTHETIC'||right(user_id::text,1),'REGISTERED','REG_SUCCESS'
 FROM public.profiles WHERE user_id IN ('f0010000-0000-4000-8000-000000000001','f0010000-0000-4000-8000-000000000002');

CREATE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'assertion_failed:%',label; END IF; END $$;
CREATE FUNCTION pg_temp.expect_error(statement text, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN
   IF strpos(SQLERRM,expected)>0 THEN RETURN; END IF;
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
BEGIN RAISE EXCEPTION 'b03_financial_mutation_forbidden'; END $$;
CREATE TRIGGER b03_no_transactions BEFORE INSERT OR UPDATE OR DELETE ON public.transactions FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b03_no_folios BEFORE INSERT OR UPDATE OR DELETE ON public.folio_references FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b03_no_portfolios BEFORE INSERT OR UPDATE OR DELETE ON public.portfolios FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b03_no_holdings BEFORE INSERT OR UPDATE OR DELETE ON public.portfolio_folio_references FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b03_no_payments BEFORE INSERT OR UPDATE OR DELETE ON public.payment_events FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TRIGGER b03_no_orders BEFORE INSERT OR UPDATE OR DELETE ON public.order_requests FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_financial_mutation();
CREATE TEMP TABLE settlement_contracts(api text,filters jsonb,request jsonb,path text,row_data jsonb,needs_remark bool,owned jsonb,selection jsonb);
INSERT INTO settlement_contracts VALUES ('REDEMPTION_PAYOUT','{"from_date": "27-05-2025", "to_date": "28-05-2025", "report_type": "Order Date"}','{"from_date": "27-05-2025", "to_date": "28-05-2025", "report_type": "Order Date", "order_id": "451480000468"}','/nsemfdesk/api/v2/reports/REDEMPTION_PAYOUT','{"order_id": "451480000468", "member_code": "05418", "client_code": "SYNTHETIC1", "member_unique_id": "SYNTHETICREF", "scheme_code": "TEST-GR", "isin": "INF000000001", "transaction_type": "R", "order_date": "27 MAY 2025", "settlement_id": "2025105", "settlement_type": "T2", "rta_transaction_no": "RTA001", "funds_payout_status": "NATIVE_UNCHARACTERIZED", "allotted_amount": "1000.00", "first_applicant_pan": "AAAAA0000A", "rta_scheme_code": "TEST", "funds_payout_date": "28 MAY 2025", "funds_transfer_date": " "}',true,'{"order_id": "451480000468", "member_unique_id": "SYNTHETICREF", "member_id": "05418", "scheme_code": "TEST-GR", "isin": "INF000000001", "transaction_type": "R", "order_date": "27/05/2025", "settlement_id": "2025105", "settlement_type": "T2", "folio_no": "SYNTHETIC/FOLIO"}',NULL);
INSERT INTO settlement_contracts VALUES ('REDEMPTION_PAYOUT_NON_DEMAT','{"from_date": "27-05-2025", "to_date": "28-05-2025", "report_type": "Order Date"}','{"from_date": "27-05-2025", "to_date": "28-05-2025", "report_type": "Order Date", "order_id": "451480000468"}','/nsemfdesk/api/v2/reports/REDEMPTION_PAYOUT_NON_DEMAT','{"order_id": "451480000468", "member_code": "05418", "client_code": "SYNTHETIC1", "member_unique_id": "SYNTHETICREF", "scheme_code": "TEST-GR", "isin": "INF000000001", "transaction_type": "R", "order_date": "27 MAY 2025", "settlement_id": "2025105", "settlement_type": "T2", "rta_transaction_no": "RTA001", "funds_payout_status": "NATIVE_UNCHARACTERIZED", "allotted_amount": "1000.00", "first_applicant_pan": "AAAAA0000A", "product_code": "TEST", "folio_number": "SYNTHETIC/FOLIO", "payout_desc": "PRIVATE", "mailed_date": "05/28/2025 12:00:00 AM", "funds_payout_date": "05/28/2025 12:00:00 AM", "despatch_status": " ", "instrm_no": " ", "instrm_bank": "PRIVATE", "payee_acno": "PRIVATE"}',true,'{"order_id": "451480000468", "member_unique_id": "SYNTHETICREF", "member_id": "05418", "scheme_code": "TEST-GR", "isin": "INF000000001", "transaction_type": "R", "order_date": "27/05/2025", "settlement_id": "2025105", "settlement_type": "T2", "folio_no": "SYNTHETIC/FOLIO"}',NULL);
INSERT INTO settlement_contracts VALUES ('REDEMPTION_STATEMENT','{"from_date": "27-05-2025", "to_date": "28-05-2025"}','{"from_date": "27-05-2025", "to_date": "28-05-2025", "order_ids": "451480000468"}','/nsemfdesk/api/v2/reports/REDEMPTION_STATEMENT','{"orderno": "451480000468", "member_unique_id": "SYNTHETICREF", "clientcode": "SYNTHETIC1", "schemecode": "TEST-GR", "isin": "INF000000001", "orderdate": "27-05-2025", "reportdate": "28-05-2025", "settlementid": "2025105", "settlementype": "T2", "rtatransactionno": "RTA001", "ordertype": "NRM", "ordersubtype": "NRM", "validflag": "NATIVE_UNCHARACTERIZED", "allottednav": "10", "allottedqty": "100", "dptrans": "N", "membercode": "05418", "allottedamt": "1000"}',true,'{"order_id": "451480000468", "member_unique_id": "SYNTHETICREF", "member_id": "05418", "scheme_code": "TEST-GR", "isin": "INF000000001", "transaction_type": "R", "order_date": "27/05/2025", "settlement_id": "2025105", "settlement_type": "T2", "folio_no": "SYNTHETIC/FOLIO"}',NULL);
INSERT INTO settlement_contracts VALUES ('ALLOTMENT_STATEMENT','{"from_date": "27-05-2025", "to_date": "28-05-2025", "date_type": "ORD_DATE"}','{"from_date": "27-05-2025", "to_date": "28-05-2025", "date_type": "ORD_DATE", "order_ids": "451480000468"}','/nsemfdesk/api/v2/reports/ALLOTMENT_STATEMENT','{"orderno": "451480000468", "member_unique_id": "SYNTHETICREF", "clientcode": "SYNTHETIC1", "schemecode": "TEST-GR", "isin": "INF000000001", "orderdate": "2025-05-27", "reportdate": "2025-05-28", "settlementid": "2025105", "settlementype": "T2", "rtatransactionno": "RTA001", "ordertype": "NRM", "ordersubtype": "NRM", "validflag": "NATIVE_UNCHARACTERIZED", "allottednav": "10", "allottedqty": "100", "dptrans": "N", "memberid": "05418", "allotmentamt": "1000", "pgbankrefno": "PRIVATE"}',true,'{"order_id": "451480000468", "member_unique_id": "SYNTHETICREF", "member_id": "05418", "scheme_code": "TEST-GR", "isin": "INF000000001", "transaction_type": "P", "order_date": "27/05/2025", "settlement_id": "2025105", "settlement_type": "T2", "folio_no": "SYNTHETIC/FOLIO"}',NULL);
CREATE FUNCTION pg_temp.source_result(rows jsonb, account_suffix text DEFAULT '1', endpoint text DEFAULT 'order_status') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE op public.integration_operations; event public.event_outbox; claim record; src jsonb; req public.integration_api_interactions; result public.integration_api_interactions; observation jsonb; raw text;
BEGIN
 EXECUTE format('SELECT * FROM public.prepare_nse_%s($1,$2,$3)',endpoint) INTO op USING
  ('f0030000-0000-4000-8000-00000000000'||account_suffix)::uuid,('f0060000-0000-4000-8000-00000000000'||account_suffix)::uuid,
  '{"from_date":"2025-05-27","to_date":"2025-05-28","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}'::jsonb;
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
 EXECUTE format('SELECT * FROM public.claim_nse_%s_event($1)',endpoint) INTO claim USING event.id;
 EXECUTE format('SELECT public.get_nse_%s_source($1)',endpoint) INTO src USING op.id;
 EXECUTE format('SELECT * FROM public.start_nse_%s($1,$2,$3,$4,$5,now())',endpoint) INTO req USING event.id,claim.claim_token,gen_random_uuid(),(src->'request')::text,'{"content_type":"application/json","accept":"application/json"}'::jsonb;
 raw:=jsonb_build_object('response_status','S','report_data_total',jsonb_array_length(rows),'report_data',rows,'error_remark','')::text;
 EXECUTE format('SELECT public.inspect_nse_%s_response($1,$2)',endpoint) INTO observation USING raw,src->'request';
 EXECUTE format('SELECT * FROM public.finish_nse_%s($1,$2,$3,$4,$5,$6,200,$7,$8,$9,$10,false,false,now(),1,3)',endpoint) INTO result USING
 event.id,claim.claim_token,req.call_id,raw,'application/json','{}'::jsonb,observation->>'native_status',observation->>'category',
 CASE WHEN (observation->>'success')::bool THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END,
 CASE WHEN (observation->>'success')::bool THEN NULL ELSE observation->>'category' END;
 RETURN result.id;
END $$;
UPDATE settlement_contracts SET selection=jsonb_build_object('result_id',pg_temp.source_result(jsonb_build_array(owned||'{"client_code":"SYNTHETIC1","order_status":"VALID","order_type":"NRM","order_sub_type":"NRM"}'::jsonb)),'row_indices',jsonb_build_array(0));
CREATE FUNCTION pg_temp.prepare(api text) RETURNS public.integration_operations LANGUAGE sql AS $$
 SELECT public.prepare_nse_settlement_redemption('f0030000-0000-4000-8000-000000000001','f0060000-0000-4000-8000-000000000001',api,c.filters,gen_random_uuid(),c.selection) FROM settlement_contracts c WHERE c.api=$1;
$$;
CREATE FUNCTION pg_temp.start_read(op uuid) RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event_id uuid; claim record;
BEGIN
 SELECT id INTO event_id FROM public.event_outbox WHERE entity_id=op;
 IF EXISTS(SELECT 1 FROM public.event_outbox WHERE id=event_id AND status='failed') THEN
  SELECT * INTO claim FROM public.claim_nse_settlement_redemption_event(event_id,3,120);
  PERFORM pg_temp.assert_true(claim.claim_state='no_event','direct_retry_backoff');
  UPDATE public.event_outbox SET updated_at=now()-interval '31 seconds' WHERE id=event_id;
 END IF;
 SELECT * INTO claim FROM public.claim_nse_settlement_redemption_event(event_id,3,120);
 RETURN public.start_nse_settlement_redemption(event_id,claim.claim_token,gen_random_uuid(),
   (public.get_nse_settlement_redemption_source(op)->'request')::text,'{"content_type":"application/json","accept":"application/json"}',now());
END $$;
CREATE FUNCTION pg_temp.finish_read(req public.integration_api_interactions, body text, http integer)
RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event public.event_outbox; observation jsonb; outcome text; native text; category text;
BEGIN
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=req.integration_operation_id;
 IF http BETWEEN 200 AND 299 THEN
  observation:=public.inspect_nse_settlement_redemption_response(req.api_key,body,extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference))::jsonb,
   public.nse_settlement_redemption_identity(req.integration_operation_id));
  outcome:=CASE WHEN (observation->>'success')::bool THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END;native:=observation->>'native_status';category:=observation->>'category';
 ELSE outcome:=CASE WHEN http IS NULL THEN 'TRANSPORT_FAILURE' ELSE 'HTTP_FAILURE' END;
  category:=CASE WHEN http IS NULL THEN 'settlement_redemption_transport_failed' ELSE 'settlement_redemption_http_failure' END;
 END IF;
 RETURN public.finish_nse_settlement_redemption(event.id,event.claim_token,req.call_id,body,
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
  BEGIN PERFORM public.prepare_nse_settlement_redemption(NULL,NULL,'REDEMPTION_PAYOUT'); RAISE EXCEPTION 'browser_prepare_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_settlement_redemption_summary(NULL,NULL,NULL); RAISE EXCEPTION 'browser_summary_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_settlement_redemption_source(NULL); RAISE EXCEPTION 'browser_source_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;


SELECT set_config('test.b03_selection',(SELECT selection::text FROM settlement_contracts WHERE api='REDEMPTION_PAYOUT'),true);
SET LOCAL ROLE service_role;
SELECT id FROM public.prepare_nse_settlement_redemption('f0030000-0000-4000-8000-000000000001','f0060000-0000-4000-8000-000000000001',
 'REDEMPTION_PAYOUT','{"from_date":"27-05-2025","to_date":"28-05-2025","report_type":"Order Date"}',gen_random_uuid(),current_setting('test.b03_selection')::jsonb);
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM public.get_nse_settlement_redemption_source(NULL); RAISE EXCEPTION 'anon_source_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$
DECLARE c record; fn regprocedure; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; src jsonb; summary jsonb; raw text; body jsonb; key text; value jsonb; replay public.integration_api_interactions; claim record;
BEGIN
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('prepare_nse_settlement_redemption','get_nse_settlement_redemption_source','claim_nse_settlement_redemption_event',
 'recover_expired_nse_settlement_redemption_events','start_nse_settlement_redemption','finish_nse_settlement_redemption','get_nse_settlement_redemption_summary') LOOP
  PERFORM pg_temp.assert_true(has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'rpc_acl');
  PERFORM pg_temp.assert_true((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_search_path');
 END LOOP;
 PERFORM pg_temp.assert_true(NOT has_function_privilege('service_role','public.nse_settlement_redemption_identity(uuid)','EXECUTE'),'identity_helper_private');
 PERFORM pg_temp.assert_true((SELECT relrowsecurity FROM pg_class WHERE oid='public.event_outbox'::regclass),'outbox_rls');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='event_outbox'),'private_outbox_policies');
 FOR c IN SELECT * FROM settlement_contracts LOOP
  op:=pg_temp.prepare(c.api); src:=public.get_nse_settlement_redemption_source(op.id);
  PERFORM pg_temp.assert_true(src->'request'=c.request AND src->>'api'=c.api AND src->>'pan'='AAAAA0000A','exact_request_'||c.api);
  SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  PERFORM pg_temp.assert_true(event.payload::text NOT LIKE '%AAAAA0000A%' AND event.payload::text NOT LIKE '%SYNTHETIC1%','encrypted_context');
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_settlement_redemption(%L,%L,%L,%L)',
   'f0030000-0000-4000-8000-000000000002','f0060000-0000-4000-8000-000000000001',c.api,c.filters),'settlement_redemption_account_scope_invalid');
  FOREACH key IN ARRAY ARRAY['PAN','pan','Pan','client_code','product_type','Product_type','product_id','order_id','systematic_reg_id','pg_bank_refno','member_code','amc_code','scheme_code','url'] LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_settlement_redemption(%L,%L,%L,%L)',
    op.workspace_id,op.integration_account_id,c.api,c.filters||jsonb_build_object(key,'FOREIGN')),'settlement_redemption_filters_invalid');
  END LOOP;
  PERFORM pg_temp.assert_true((public.prepare_nse_settlement_redemption(op.workspace_id,op.integration_account_id,c.api,c.filters,op.id,c.selection)).id=op.id,'prepare_idempotent');
  PERFORM pg_temp.expect_error(format('UPDATE public.event_outbox SET payload=payload||%L::jsonb WHERE id=%L','{"api":"UNKNOWN"}',event.id),'settlement_redemption_context_immutable');
  PERFORM pg_temp.expect_error(format('DELETE FROM public.event_outbox WHERE id=%L',event.id),'settlement_redemption_context_immutable');
  req:=pg_temp.start_read(op.id);
  SELECT * INTO event FROM public.event_outbox WHERE id=event.id;
  PERFORM pg_temp.assert_true(req.endpoint_path=c.path AND req.http_method='POST' AND req.phase='REQUEST','exact_endpoint_'||c.api);
  raw:=extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference));
  PERFORM pg_temp.assert_true(raw=c.request::text AND req.request_bytes=octet_length(raw) AND req.request_hash=extensions.digest(raw,'sha256'),'request_exact_evidence');
  SELECT * INTO replay FROM public.start_nse_settlement_redemption(event.id,event.claim_token,req.call_id,raw,req.request_header_metadata,req.started_at);
  PERFORM pg_temp.assert_true(replay.id=req.id,'request_ack_replay');
  PERFORM pg_temp.expect_error(format('SELECT public.start_nse_settlement_redemption(%L,%L,%L,%L,%L,%L)',event.id,event.claim_token,req.call_id,raw||' ',req.request_header_metadata,req.started_at),'integration_request_idempotency_conflict');
  SELECT * INTO claim FROM public.claim_nse_settlement_redemption_event(event.id);
  PERFORM pg_temp.assert_true(claim.claim_state='no_event','exact_claim_once');
  body:=jsonb_build_object('response_status','S','report_data_total','1','report_data',jsonb_build_array(c.row_data));
  IF c.needs_remark THEN body:=body||'{"error_remark":""}'::jsonb; END IF;
  raw:=body::text||E'\n';
  result:=pg_temp.finish_read(req,raw,200);
  PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS' AND result.api_key=c.api,'validated_success_'||c.api);
  PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw
   AND result.response_bytes=octet_length(raw) AND result.response_hash=extensions.digest(raw,'sha256'),'result_exact_evidence');
  replay:=pg_temp.finish_read(req,raw,200);PERFORM pg_temp.assert_true(result.id=replay.id,'result_ack_replay');
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.finish_read((SELECT i FROM public.integration_api_interactions i WHERE id=%L),%L,200)',req.id,raw||' '),'integration_result_idempotency_conflict');
  summary:=public.get_nse_settlement_redemption_summary(op.workspace_id,op.integration_account_id,op.id);
  PERFORM pg_temp.assert_true(summary->>'record_count'='1' AND summary->>'api'=c.api AND summary::text NOT LIKE '%PRIVATE%' AND summary::text NOT LIKE '%AAAAA0000A%','private_safe_summary');
  PERFORM pg_temp.assert_true(public.get_nse_settlement_redemption_summary(gen_random_uuid(),op.integration_account_id,op.id) IS NULL,'summary_workspace_scope');
  PERFORM pg_temp.assert_true(public.get_nse_settlement_redemption_summary(op.workspace_id,gen_random_uuid(),op.id) IS NULL,'summary_account_scope');
  PERFORM pg_temp.expect_error(format('UPDATE public.integration_api_interactions SET response_payload_ciphertext=NULL WHERE id=%L',result.id),'integration_api_interactions_append_only');
  PERFORM pg_temp.expect_error(format('DELETE FROM public.integration_api_interactions WHERE id=%L',req.id),'integration_api_interactions_append_only');
  FOR value IN SELECT x FROM (VALUES (body||'{"report_data_total":0}'::jsonb),(body||'{"report_data_total":null}'::jsonb),
    (body||'{"report_data_total":"1.0"}'::jsonb),(body||'{"report_data":{}}'::jsonb),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||jsonb_build_object(CASE WHEN c.api IN ('REDEMPTION_PAYOUT','REDEMPTION_PAYOUT_NON_DEMAT') THEN 'client_code' ELSE 'clientcode' END,'FOREIGN')))),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data,c.row_data),'report_data_total',2)),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||'{"unknown":{}}'::jsonb)))) v(x) LOOP
    PERFORM pg_temp.assert_true(NOT (public.inspect_nse_settlement_redemption_response(c.api,value::text,c.request,src)->>'success')::bool,'bad_shape_scope_count_'||c.api);
  END LOOP;
  value:=body||'{"error_remark":"PRIVATE"}'::jsonb;
  PERFORM pg_temp.assert_true(
    (public.inspect_nse_settlement_redemption_response(c.api,value::text,c.request,src)->>'success')::bool = false,
    'success_diagnostic_policy_'||c.api);
  PERFORM pg_temp.assert_true(public.inspect_nse_settlement_redemption_response(c.api,value::text,c.request,src)::text NOT LIKE '%PRIVATE%','success_diagnostic_not_projected_'||c.api);
  IF c.needs_remark THEN PERFORM pg_temp.assert_true(NOT (public.inspect_nse_settlement_redemption_response(c.api,(body-'error_remark')::text,c.request,src)->>'success')::bool,'required_remark'); END IF;
  -- Independently finish an empty report, F and malformed data for every API.
  FOREACH raw IN ARRAY ARRAY[(body||'{"report_data":[],"report_data_total":0}'::jsonb)::text,'{"response_status":"F","error_remark":"PRIVATE"}','PRIVATE'] LOOP
   op:=pg_temp.prepare(c.api);req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,raw,200);
   PERFORM pg_temp.assert_true(result.normalized_outcome=CASE WHEN raw LIKE '%"response_status": "S"%' THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END,'empty_failure_malformed_'||c.api);
  END LOOP;
 END LOOP;
END $$;

DO $$
DECLARE c record; key text; bad jsonb; selection jsonb; id uuid; row_data jsonb; result public.integration_api_interactions; op public.integration_operations; req public.integration_api_interactions; src jsonb;
BEGIN
 FOR c IN SELECT * FROM settlement_contracts LOOP
  FOREACH selection IN ARRAY ARRAY['null'::jsonb,'{}',c.selection||'{"row_indices":[]}',c.selection||'{"row_indices":[0,0]}',c.selection||'{"row_indices":[-1]}',c.selection||'{"row_indices":[1]}',c.selection||'{"row_indices":[0.5]}',c.selection||'{"row_indices":["0"]}',c.selection||'{"row_indices":[2147483648]}',c.selection||'{"result_id":"bad"}',c.selection||'{"selector":null}',c.selection||'{"selector":"ALL"}',c.selection||'{"order_id":"FOREIGN"}'] LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_settlement_redemption(%L,%L,%L,%L,%L,%L)',
    'f0030000-0000-4000-8000-000000000001','f0060000-0000-4000-8000-000000000001',c.api,c.filters,gen_random_uuid(),selection),'settlement_redemption_selection_invalid');
  END LOOP;
  SELECT i.* INTO result FROM public.integration_api_interactions i WHERE i.id=(c.selection->>'result_id')::uuid;
  SELECT i.* INTO req FROM public.integration_api_interactions i WHERE i.call_id=result.call_id AND phase='REQUEST';
  PERFORM pg_temp.expect_error(format('SELECT public.nse_settlement_redemption_selection(%L,%L,%L,%L)',result.workspace_id,
   'f0060000-0000-4000-8000-000000000001',c.api,c.selection||jsonb_build_object('result_id',req.id)),'settlement_redemption_selection_invalid');
  PERFORM pg_temp.expect_error(format('SELECT public.nse_settlement_redemption_selection(%L,%L,%L,%L)',
   'f0030000-0000-4000-8000-000000000002','f0060000-0000-4000-8000-000000000002',c.api,c.selection),'settlement_redemption_selection_invalid');
  row_data:=c.owned||'{"client_code":"SYNTHETIC1","order_status":"VALID","order_type":"NRM","order_sub_type":"NRM"}'::jsonb;
  FOR bad IN SELECT x FROM (VALUES (jsonb_build_array(row_data,row_data)),(jsonb_build_array(row_data,row_data||'{"client_code":"FOREIGN","order_id":"999"}')),
   (jsonb_build_array(row_data-'member_unique_id')),(jsonb_build_array(row_data||'{"order_sub_type":"SWH"}')),
   (jsonb_build_array(row_data||'{"transaction_type":"OTHER"}')),(jsonb_build_array(row_data||'{"order_date":"31/02/2025"}')),
   (jsonb_build_array(row_data||'{"member_unique_id":""}')),(jsonb_build_array(row_data||'{"order_id":"FOREIGN"}')),
   (jsonb_build_array(row_data,row_data||'{"order_id":"999"}'))) v(x) LOOP
   id:=pg_temp.source_result(bad);
   PERFORM pg_temp.expect_error(format('SELECT public.nse_settlement_redemption_selection(%L,%L,%L,%L)',result.workspace_id,
    'f0060000-0000-4000-8000-000000000001',c.api,jsonb_build_object('result_id',id,'row_indices',jsonb_build_array(0))),'settlement_redemption_selection_invalid');
  END LOOP;
  id:=pg_temp.source_result(jsonb_build_array(row_data),'1','prov_orders');
  PERFORM pg_temp.expect_error(format('SELECT public.nse_settlement_redemption_selection(%L,%L,%L,%L)',result.workspace_id,
   'f0060000-0000-4000-8000-000000000001',c.api,jsonb_build_object('result_id',id,'row_indices',jsonb_build_array(0))),'settlement_redemption_selection_invalid');
  op:=public.prepare_nse_settlement_redemption(result.workspace_id,'f0060000-0000-4000-8000-000000000001',c.api,c.filters,gen_random_uuid(),c.selection||'{"selector":"member"}');
  src:=public.get_nse_settlement_redemption_source(op.id);
  PERFORM pg_temp.assert_true(src->'request'->>'member_unique_ids'=c.owned->>'member_unique_id' AND NOT(src->'request' ?| ARRAY['order_id','order_ids']),'member_selector_only');
  req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array(c.row_data),'error_remark','')::text,200);
  PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS','member_selected_positive');
  FOR key IN SELECT jsonb_object_keys(c.filters) LOOP
   IF key='date_type' THEN CONTINUE; END IF;
   PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_settlement_redemption_filters(%L,%L)',c.api,c.filters-key),'settlement_redemption_filters_invalid');
   FOREACH bad IN ARRAY ARRAY['null'::jsonb,'""','"31-02-2025"','"01-01-0000"','"2025-01-28"'] LOOP
    PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_settlement_redemption_filters(%L,%L)',c.api,c.filters||jsonb_build_object(key,bad)),'settlement_redemption_filters_invalid');
   END LOOP;
  END LOOP;
  PERFORM public.validate_nse_settlement_redemption_filters(c.api,c.filters||'{"from_date":"27-05-2025","to_date":"26-06-2025"}');
  PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_settlement_redemption_filters(%L,%L)',c.api,c.filters||'{"to_date":"27-06-2025"}'),'settlement_redemption_filters_invalid');
  FOREACH bad IN ARRAY ARRAY['{"response_status":"F","report_data_total":0,"report_data":"","error_remark":"PRIVATE"}'::jsonb,
   '{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":"No record(s) found."}',
   '{"response_status":"F","report_data_total":0,"report_data":[],"error_remark":"No record(s) found."}'] LOOP
   PERFORM pg_temp.assert_true(NOT(public.inspect_nse_settlement_redemption_response(c.api,bad::text,src->'request',src)->>'success')::bool,'diagnostic_fails_closed');
  END LOOP;
 END LOOP;
END $$;
-- Classifier portability: preserve malformed JSON evidence with the same safe
-- category in SQL and TypeScript, including escaped NUL and numeric overflow.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions; raw text;
BEGIN
 FOREACH raw IN ARRAY ARRAY['{"response_status":"S","report_data_total":0,"report_data":[],"extra":1e999}',
   '{"response_status":"S","report_data_total":0,"report_data":[],"extra":"\u0000"}',
   '{"response_status":"S","report_data_total":0,"report_data":[],"extra":"\ud800"}'] LOOP
  op:=pg_temp.prepare('REDEMPTION_PAYOUT');req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,raw,200);
  PERFORM pg_temp.assert_true(result.native_status_value IS NULL AND result.native_remark_category='settlement_redemption_response_invalid'
    AND extensions.pgp_sym_decrypt(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw,'portable_invalid_json_evidence');
 END LOOP;
END $$;

-- Cross-runtime disagreement cannot discard a completed provider response.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; event public.event_outbox;
 result public.integration_api_interactions; replay public.integration_api_interactions; raw text;
BEGIN
 FOREACH raw IN ARRAY ARRAY['{"response_status":"F"}',
   '{"response_status":"S","report_data_total":1e-400,"report_data":[],"error_remark":""}'] LOOP
  op:=pg_temp.prepare('REDEMPTION_PAYOUT');req:=pg_temp.start_read(op.id);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  result:=public.finish_nse_settlement_redemption(event.id,event.claim_token,req.call_id,raw,'application/json','{}',200,'S',
   'settlement_redemption_report_received','SUCCESS',NULL,false,false,now(),1);
  PERFORM pg_temp.assert_true(result.normalized_outcome='BUSINESS_FAILURE' AND result.native_remark_category='settlement_redemption_interpretation_mismatch'
   AND extensions.pgp_sym_decrypt(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw,'mismatched_interpretation_retains_exact_evidence');
  PERFORM pg_temp.assert_true((SELECT state='BUSINESS_FAILED' AND NOT retry_allowed FROM public.integration_operations WHERE id=op.id),'mismatch_terminal');
  PERFORM pg_temp.assert_true(public.get_nse_settlement_redemption_summary(op.workspace_id,op.integration_account_id,op.id) IS NULL,'mismatch_no_trusted_summary');
  replay:=public.finish_nse_settlement_redemption(event.id,event.claim_token,req.call_id,raw,'application/json','{}',200,'S',
   'settlement_redemption_report_received','SUCCESS',NULL,false,false,now(),1);
  PERFORM pg_temp.assert_true(replay.id=result.id,'mismatch_ack_replay');
 END LOOP;
END $$;

-- Binary RESULT evidence uses the existing ciphertext/hash/length columns.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; event public.event_outbox;
 result public.integration_api_interactions; replay public.integration_api_interactions; raw bytea; body text; encoded text;
BEGIN
 FOREACH raw IN ARRAY ARRAY[decode('efbbbf7b7d','hex'),decode('ff80','hex'),decode('007b7d','hex')] LOOP
  op:=pg_temp.prepare('REDEMPTION_PAYOUT');req:=pg_temp.start_read(op.id);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  body:=CASE WHEN raw=decode('efbbbf7b7d','hex') THEN convert_from(raw,'UTF8') ELSE '' END; encoded:=encode(raw,'base64');
  result:=public.finish_nse_settlement_redemption(event.id,event.claim_token,req.call_id,body,'application/json','{}',200,NULL,
    'settlement_redemption_response_invalid','BUSINESS_FAILURE','settlement_redemption_response_invalid',false,false,now(),1,3,encoded);
  PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt_bytea(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw
    AND result.response_bytes=octet_length(raw) AND result.response_hash=extensions.digest(raw,'sha256'),'exact_binary_result');
  replay:=public.finish_nse_settlement_redemption(event.id,event.claim_token,req.call_id,body,'application/json','{}',200,NULL,
    'settlement_redemption_response_invalid','BUSINESS_FAILURE','settlement_redemption_response_invalid',false,false,now(),1,3,encoded);
  PERFORM pg_temp.assert_true(result.id=replay.id,'binary_result_ack_replay');
 END LOOP;
END $$;

-- All endpoints use the same bounded lifecycle, independent of native statuses.
DO $$
DECLARE c record; status integer; attempt integer; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; claim record; before_state text; raw text;
BEGIN
 FOR c IN SELECT * FROM settlement_contracts LOOP
  FOREACH status IN ARRAY ARRAY[408,429,500,502,503,504,0,400,401,403,404,501] LOOP
   op:=pg_temp.prepare(c.api);
   FOR attempt IN 1..CASE WHEN status IN (408,429,500,502,503,504,0) THEN 3 ELSE 1 END LOOP
    req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,CASE WHEN status=0 THEN '' ELSE 'PRIVATE' END,NULLIF(status,0));
    PERFORM pg_temp.assert_true(result.attempt_number=attempt AND result.normalized_outcome=CASE WHEN status=0 THEN 'TRANSPORT_FAILURE' ELSE 'HTTP_FAILURE' END,'retry_classification_'||c.api);
    SELECT * INTO op FROM public.integration_operations WHERE id=op.id;
    PERFORM pg_temp.assert_true(op.retry_allowed=(status IN (408,429,500,502,503,504,0) AND attempt<3),'bounded_retry_budget');
   END LOOP;
   SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
   SELECT * INTO claim FROM public.claim_nse_settlement_redemption_event(event.id);
   PERFORM pg_temp.assert_true(claim.claim_state='no_event','terminal_no_claim');
   PERFORM pg_temp.assert_true((SELECT count(*)=op.attempt_count*2 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'all_attempt_pairs_retained');
  END LOOP;
  -- Expired claim before transport, then expired claim after immutable REQUEST.
  op:=pg_temp.prepare(c.api);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  SELECT * INTO claim FROM public.claim_nse_settlement_redemption_event(event.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM public.recover_expired_nse_settlement_redemption_events(event.id);
  UPDATE public.event_outbox SET updated_at=now()-interval '31 seconds' WHERE id=event.id;
  SELECT * INTO claim FROM public.claim_nse_settlement_redemption_event(event.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.settlement_redemption_requested'],50,0) WHERE event_outbox_id=event.id),'retry_pre_request_discovery');
  PERFORM public.recover_expired_nse_settlement_redemption_events(event.id);
  req:=pg_temp.start_read(op.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM public.recover_expired_nse_settlement_redemption_events(event.id);
  PERFORM pg_temp.assert_true((SELECT count(*)=2 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'abandoned_request_closed');
  PERFORM pg_temp.assert_true((SELECT NOT retry_allowed AND attempt_count=3 FROM public.integration_operations WHERE id=op.id),'expired_budget_exhausted');
  PERFORM pg_temp.assert_true((SELECT normalized_outcome='TRANSPORT_FAILURE' AND response_bytes=0 AND error_category='settlement_redemption_read_lease_expired' FROM public.integration_api_interactions WHERE call_id=req.call_id AND phase='RESULT'),'truthful_expired_evidence');
 END LOOP;
END $$;
-- Endpoint-specific correlation and ambiguity failures retain no partial summary.
DO $$
DECLARE c record; src jsonb; row_data jsonb; changed jsonb; body jsonb; key text; idkey text; rtakey text; rows jsonb;
 op public.integration_operations; req public.integration_api_interactions; event public.event_outbox; result public.integration_api_interactions; profile uuid;
BEGIN
 FOR c IN SELECT * FROM settlement_contracts LOOP
  op:=pg_temp.prepare(c.api);src:=public.get_nse_settlement_redemption_source(op.id);
  idkey:=CASE WHEN c.api LIKE 'REDEMPTION_PAYOUT%' THEN 'order_id' ELSE 'orderno' END;
  rtakey:=CASE WHEN c.api LIKE 'REDEMPTION_PAYOUT%' THEN 'rta_transaction_no' ELSE 'rtatransactionno' END;
  FOR key IN SELECT jsonb_object_keys(c.row_data) LOOP
   body:=jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array(c.row_data-key),'error_remark','');
   PERFORM pg_temp.assert_true(NOT(public.inspect_nse_settlement_redemption_response(c.api,body::text,src->'request',src)->>'success')::bool,'missing_structural_field_'||key);
  END LOOP;
  FOREACH key IN ARRAY ARRAY[idkey,'member_unique_id','isin',CASE WHEN c.api LIKE 'REDEMPTION_PAYOUT%' THEN 'scheme_code' ELSE 'schemecode' END,
   CASE c.api WHEN 'ALLOTMENT_STATEMENT' THEN 'memberid' WHEN 'REDEMPTION_STATEMENT' THEN 'membercode' ELSE 'member_code' END,
   CASE WHEN c.api LIKE 'REDEMPTION_PAYOUT%' THEN 'settlement_id' ELSE 'settlementid' END] LOOP
   body:=jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array(c.row_data||jsonb_build_object(key,'FOREIGN')),'error_remark','');
   PERFORM pg_temp.assert_true(public.inspect_nse_settlement_redemption_response(c.api,body::text,src->'request',src)->>'category'='settlement_redemption_row_scope_invalid','foreign_identity_'||key);
  END LOOP;
  changed:=c.owned||'{"order_id":"451480000469","member_unique_id":"SECOND"}';
  src:=jsonb_set(src,'{selectors,rows}',jsonb_build_array(c.owned,changed));
  src:=jsonb_set(src,'{request}',public.nse_settlement_redemption_request(c.api,c.filters,src));
  body:=jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array(c.row_data),'error_remark','');
  PERFORM pg_temp.assert_true(public.inspect_nse_settlement_redemption_response(c.api,body::text,src->'request',src)->>'category'='settlement_redemption_incomplete_selection','missing_selected_order');
  changed:=c.row_data||jsonb_build_object(idkey,'451480000469','member_unique_id','SECOND');
  body:=body||jsonb_build_object('report_data_total',2,'report_data',jsonb_build_array(c.row_data,changed));
  PERFORM pg_temp.assert_true(public.inspect_nse_settlement_redemption_response(c.api,body::text,src->'request',src)->>'category'='settlement_redemption_duplicate_rows','duplicate_registrar_lineage');
  body:=body||jsonb_build_object('report_data',jsonb_build_array(c.row_data,changed||jsonb_build_object(rtakey,'RTA002')));
  PERFORM pg_temp.assert_true((public.inspect_nse_settlement_redemption_response(c.api,body::text,src->'request',src)->>'success')::bool,'two_distinct_normal_orders');
  IF c.api IN ('REDEMPTION_STATEMENT','ALLOTMENT_STATEMENT') THEN
   body:=body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||'{"ordersubtype":"SWH"}',changed||jsonb_build_object(rtakey,'RTA002')));
   PERFORM pg_temp.assert_true(NOT(public.inspect_nse_settlement_redemption_response(c.api,body::text,src->'request',src)->>'success')::bool,'switch_leg_not_inferred');
  END IF;
 END LOOP;
 PERFORM public.validate_nse_settlement_redemption_filters('ALLOTMENT_STATEMENT','{"from_date":"27-05-2025","to_date":"28-05-2025","date_type":"ALT_DATE"}');
 PERFORM pg_temp.expect_error($q$SELECT public.validate_nse_settlement_redemption_filters('ALLOTMENT_STATEMENT','{"from_date":"27-05-2025","to_date":"28-05-2025","date_type":"ORDER DATE"}')$q$,'settlement_redemption_filters_invalid');
 SELECT * INTO c FROM settlement_contracts WHERE api='ALLOTMENT_STATEMENT';
 op:=public.prepare_nse_settlement_redemption('f0030000-0000-4000-8000-000000000001','f0060000-0000-4000-8000-000000000001',c.api,c.filters-'date_type',gen_random_uuid(),c.selection);
 PERFORM pg_temp.assert_true(public.get_nse_settlement_redemption_source(op.id)->'request'->>'date_type'='ORD_DATE','explicit_default_order_date');
 -- Account/identity validity before REQUEST; immutable snapshot after transport.
 SELECT id INTO profile FROM public.profiles WHERE user_id='f0010000-0000-4000-8000-000000000001';
 UPDATE public.workspace_memberships SET status='inactive' WHERE workspace_id=op.workspace_id AND profile_id=profile;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_settlement_redemption_source(%L)',op.id),'settlement_redemption_account_scope_invalid');
 UPDATE public.workspace_memberships SET status='active' WHERE workspace_id=op.workspace_id AND profile_id=profile;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id=op.workspace_id;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_settlement_redemption_source(%L)',op.id),'settlement_redemption_account_scope_invalid');
 UPDATE public.workspaces SET workspace_status='active' WHERE id=op.workspace_id;
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC1' WHERE id='f0060000-0000-4000-8000-000000000002';
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_settlement_redemption_source(%L)',op.id),'settlement_redemption_account_scope_invalid');
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC2' WHERE id='f0060000-0000-4000-8000-000000000002';
 req:=pg_temp.start_read(op.id);
 UPDATE public.integration_accounts SET external_account_id='CHANGED' WHERE id=op.integration_account_id;
 body:=jsonb_build_object('response_status','S','report_data_total',1,'report_data',jsonb_build_array(c.row_data),'error_remark','');
 result:=pg_temp.finish_read(req,body::text,200);
 PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS' AND public.get_nse_settlement_redemption_summary(op.workspace_id,op.integration_account_id,op.id)->>'record_count'='1','immutable_post_transport_identity');
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_settlement_redemption_source(%L)',op.id),'settlement_redemption_identity_changed');
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC1' WHERE id=op.integration_account_id;
END $$;
-- Only transient network/timeouts (and reviewed HTTP statuses) allow transport retry.
DO $$
DECLARE code text; op public.integration_operations; req public.integration_api_interactions; event public.event_outbox; result public.integration_api_interactions;
BEGIN
 FOREACH code IN ARRAY ARRAY['nse_response_too_large','nse_response_invalid','nse_request_invalid'] LOOP
  op:=pg_temp.prepare('REDEMPTION_PAYOUT');req:=pg_temp.start_read(op.id);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  result:=public.finish_nse_settlement_redemption(event.id,event.claim_token,req.call_id,'',NULL,'{}',NULL,NULL,'settlement_redemption_transport_failed','TRANSPORT_FAILURE',code,false,false,now(),1);
  PERFORM pg_temp.assert_true((SELECT NOT retry_allowed FROM public.integration_operations WHERE id=op.id),'nontransient_transport_terminal');
 END LOOP;
END $$;

-- Financial business relations cannot be changed by any B03 RPC.
DO $$
DECLARE fn record;
BEGIN
 FOR fn IN SELECT prosrc FROM pg_proc WHERE proname LIKE '%nse_settlement_redemption%' LOOP
  PERFORM pg_temp.assert_true(fn.prosrc !~* '(insert into|update|delete from) public\.(transactions|folios|portfolios|scheme_holdings|order_requests)','no_business_mutation');
 END LOOP;
END $$;
SELECT pg_temp.assert_true((SELECT transactions=(SELECT count(*) FROM public.transactions) AND folios=(SELECT count(*) FROM public.folio_references)
 AND portfolios=(SELECT count(*) FROM public.portfolios) AND holdings=(SELECT count(*) FROM public.portfolio_folio_references)
 AND orders=(SELECT count(*) FROM public.order_requests) AND payments=(SELECT count(*) FROM public.payment_events) FROM financial_before),'financial_tables_unchanged');
ROLLBACK;
