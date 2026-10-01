-- Execute after all migrations. Synthetic data only; every fixture rolls back.
\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('e0010000-0000-4000-8000-000000000001','authenticated','authenticated','order-funding-one@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now()),
 ('e0010000-0000-4000-8000-000000000002','authenticated','authenticated','order-funding-two@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now());
-- Current signup creates workspace-referenced profiles. Never rewrite their IDs.
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('e0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,'Synthetic ORDER_FUNDING',
 'order-funding-'||right(user_id::text,1),id,'active' FROM public.profiles
 WHERE user_id IN ('e0010000-0000-4000-8000-000000000001','e0010000-0000-4000-8000-000000000002');
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role,status)
SELECT ('e0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,'investor','active'
 FROM public.profiles WHERE user_id IN ('e0010000-0000-4000-8000-000000000001','e0010000-0000-4000-8000-000000000002');
INSERT INTO public.integration_accounts(id,workspace_id,investor_profile_id,integration_key,integration_environment,external_account_id,state,current_registration_status)
SELECT ('e0060000-0000-4000-8000-'||right(user_id::text,12))::uuid,
 ('e0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,'NSE_INVEST','UAT','SYNTHETIC'||right(user_id::text,1),'REGISTERED','REG_SUCCESS'
 FROM public.profiles WHERE user_id IN ('e0010000-0000-4000-8000-000000000001','e0010000-0000-4000-8000-000000000002');

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
SELECT ('e0040000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,
 extensions.pgp_sym_encrypt('AAAAA0000A',public.pan_encryption_key(),'cipher-algo=aes256, compress-algo=0'),
 extensions.digest('synthetic-'||id::text,'sha256'),'******000A','INVESTOR','API','VERIFIED',now()
FROM public.profiles WHERE user_id IN ('e0010000-0000-4000-8000-000000000001','e0010000-0000-4000-8000-000000000002');
UPDATE public.profiles SET canonical_pan_record_id=('e0040000-0000-4000-8000-'||right(user_id::text,12))::uuid
 WHERE user_id IN ('e0010000-0000-4000-8000-000000000001','e0010000-0000-4000-8000-000000000002');

CREATE TEMP TABLE funding_contracts(api text, filters jsonb, request jsonb, path text, row_data jsonb, needs_remark bool);
INSERT INTO funding_contracts VALUES
('ORDER_LIFECYCLE','{"from_date":"21-01-2025","to_date":"28-01-2025"}',
 '{"from_date":"21-01-2025","to_date":"28-01-2025","client_code":"SYNTHETIC1"}',
 '/nsemfdesk/api/v2/reports/order_lifecycle',
 '{"client_code":"SYNTHETIC1","product_type":"PUR","product_id":"450170000001","order_status":"VALID","payment_status":"SUCCESS","reconciliation_status":"SUCCESS","payment_account_no":"PRIVATE"}',true),
('TRANSACTION_DETAIL','{"from_date":"21-01-2025","to_date":"28-01-2025"}',
 '{"from_date":"21-01-2025","to_date":"28-01-2025","client_code":"SYNTHETIC1","date_type":"REQUEST_DATE"}',
 '/nsemfdesk/api/v2/reports/TRANSACTION_DETAIL_REPORT',
 '{"client_code":"SYNTHETIC1","primary_holder_pan":"AAAAA0000A","product_type":"NORMAL PURCHASE","product_id":"453530000107","sip_registration_no":" ","order_status":"VALID","payment_status":" ","reconciliation_status":" ","order_remark":"PRIVATE"}',true),
('FUND_ORDER','{"from_date":"10-11-2023","to_date":"10-11-2024"}',
 '{"from_date":"10-11-2023","to_date":"10-11-2024","client_code":"SYNTHETIC1"}',
 '/nsemfdesk/api/v2/reports/MEMBER_FUND_ALLOCATION/ORDER_WISE',
 '{"clientcode":"SYNTHETIC1","cfppgbankrefno":"080420241306423594511","utrno":"080420241304067310811","id":"486","totalamount":"10000","totalallocatedamount":"0","remainingamount":"10000","mappedorders":"","settledorders":"","allotmentorders":"","remitteraccountno":"PRIVATE"}',true),
('FUND_AGE','{"date":"30-04-2024"}',
 '{"date":"30-04-2024","client_code":"SYNTHETIC1","settlement_type":"all"}',
 '/nsemfdesk/api/v2/reports/MEMBER_FUND_ALLOCATION/AGE_WISE',
 '{"clientcode":"SYNTHETIC1","orderno":"440080000030","date":"30/04/2024","schemecode":"AXIOGP-GR","orderstatus":"INVALID","funds_received_status":"I","accountno":"PRIVATE"}',true);
CREATE FUNCTION pg_temp.prepare(api text) RETURNS public.integration_operations LANGUAGE sql AS $$
 SELECT public.prepare_nse_order_funding('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',api,(SELECT filters FROM funding_contracts c WHERE c.api=$1));
$$;
CREATE FUNCTION pg_temp.start_read(op uuid) RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event_id uuid; claim record;
BEGIN
 SELECT id INTO event_id FROM public.event_outbox WHERE entity_id=op;
 SELECT * INTO claim FROM public.claim_nse_order_funding_event(event_id,3,120);
 RETURN public.start_nse_order_funding(event_id,claim.claim_token,gen_random_uuid(),
   (public.get_nse_order_funding_source(op)->'request')::text,'{"content_type":"application/json","accept":"application/json"}',now());
END $$;
CREATE FUNCTION pg_temp.finish_read(req public.integration_api_interactions, body text, http integer)
RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event public.event_outbox; observation jsonb; outcome text; native text; category text;
BEGIN
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=req.integration_operation_id;
 IF http BETWEEN 200 AND 299 THEN
  observation:=public.inspect_nse_order_funding_response(req.api_key,body,extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference))::jsonb,
   public.nse_order_funding_identity(req.integration_operation_id));
  outcome:=CASE WHEN (observation->>'success')::bool THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END;native:=observation->>'native_status';category:=observation->>'category';
 ELSE outcome:=CASE WHEN http IS NULL THEN 'TRANSPORT_FAILURE' ELSE 'HTTP_FAILURE' END;
  category:=CASE WHEN http IS NULL THEN 'order_funding_transport_failed' ELSE 'order_funding_http_failure' END;
 END IF;
 RETURN public.finish_nse_order_funding(event.id,event.claim_token,req.call_id,body,
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
  BEGIN PERFORM public.prepare_nse_order_funding(NULL,NULL,'FUND_AGE'); RAISE EXCEPTION 'browser_prepare_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_order_funding_summary(NULL,NULL,NULL); RAISE EXCEPTION 'browser_summary_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_order_funding_source(NULL); RAISE EXCEPTION 'browser_source_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT id FROM public.prepare_nse_order_funding('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001','FUND_AGE','{"date":"30-04-2024"}');
RESET ROLE;

DO $$
DECLARE c record; fn regprocedure; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; src jsonb; summary jsonb; raw text; body jsonb; key text; value jsonb; replay public.integration_api_interactions; claim record;
BEGIN
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('prepare_nse_order_funding','get_nse_order_funding_source','claim_nse_order_funding_event',
 'recover_expired_nse_order_funding_events','start_nse_order_funding','finish_nse_order_funding','get_nse_order_funding_summary') LOOP
  PERFORM pg_temp.assert_true(has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'rpc_acl');
  PERFORM pg_temp.assert_true((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_search_path');
 END LOOP;
 PERFORM pg_temp.assert_true(NOT has_function_privilege('service_role','public.nse_order_funding_identity(uuid)','EXECUTE'),'identity_helper_private');
 PERFORM pg_temp.assert_true((SELECT relrowsecurity FROM pg_class WHERE oid='public.event_outbox'::regclass),'outbox_rls');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='event_outbox'),'private_outbox_policies');
 FOR c IN SELECT * FROM funding_contracts LOOP
  op:=pg_temp.prepare(c.api); src:=public.get_nse_order_funding_source(op.id);
  PERFORM pg_temp.assert_true(src->'request'=c.request AND src->>'api'=c.api AND src->>'pan'='AAAAA0000A','exact_request_'||c.api);
  SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  PERFORM pg_temp.assert_true(event.payload::text NOT LIKE '%AAAAA0000A%' AND event.payload::text NOT LIKE '%SYNTHETIC1%','encrypted_context');
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_funding(%L,%L,%L,%L)',
   'e0030000-0000-4000-8000-000000000002','e0060000-0000-4000-8000-000000000001',c.api,c.filters),'order_funding_account_scope_invalid');
  FOREACH key IN ARRAY ARRAY['PAN','pan','Pan','client_code','product_type','Product_type','product_id','order_id','systematic_reg_id','pg_bank_refno','member_code','amc_code','scheme_code','url'] LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_funding(%L,%L,%L,%L)',
    op.workspace_id,op.integration_account_id,c.api,c.filters||jsonb_build_object(key,'FOREIGN')),'order_funding_filters_invalid');
  END LOOP;
  PERFORM pg_temp.assert_true((public.prepare_nse_order_funding(op.workspace_id,op.integration_account_id,c.api,c.filters,op.id)).id=op.id,'prepare_idempotent');
  PERFORM pg_temp.expect_error(format('UPDATE public.event_outbox SET payload=payload||%L::jsonb WHERE id=%L','{"api":"UNKNOWN"}',event.id),'order_funding_context_immutable');
  PERFORM pg_temp.expect_error(format('DELETE FROM public.event_outbox WHERE id=%L',event.id),'order_funding_context_immutable');
  req:=pg_temp.start_read(op.id);
  SELECT * INTO event FROM public.event_outbox WHERE id=event.id;
  PERFORM pg_temp.assert_true(req.endpoint_path=c.path AND req.http_method='POST' AND req.phase='REQUEST','exact_endpoint_'||c.api);
  raw:=extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference));
  PERFORM pg_temp.assert_true(raw=c.request::text AND req.request_bytes=octet_length(raw) AND req.request_hash=extensions.digest(raw,'sha256'),'request_exact_evidence');
  SELECT * INTO replay FROM public.start_nse_order_funding(event.id,event.claim_token,req.call_id,raw,req.request_header_metadata,req.started_at);
  PERFORM pg_temp.assert_true(replay.id=req.id,'request_ack_replay');
  PERFORM pg_temp.expect_error(format('SELECT public.start_nse_order_funding(%L,%L,%L,%L,%L,%L)',event.id,event.claim_token,req.call_id,raw||' ',req.request_header_metadata,req.started_at),'integration_request_idempotency_conflict');
  SELECT * INTO claim FROM public.claim_nse_order_funding_event(event.id);
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
  summary:=public.get_nse_order_funding_summary(op.workspace_id,op.integration_account_id,op.id);
  PERFORM pg_temp.assert_true(summary->>'record_count'='1' AND summary->>'api'=c.api AND summary::text NOT LIKE '%PRIVATE%' AND summary::text NOT LIKE '%AAAAA0000A%','private_safe_summary');
  PERFORM pg_temp.assert_true(public.get_nse_order_funding_summary(gen_random_uuid(),op.integration_account_id,op.id) IS NULL,'summary_workspace_scope');
  PERFORM pg_temp.assert_true(public.get_nse_order_funding_summary(op.workspace_id,gen_random_uuid(),op.id) IS NULL,'summary_account_scope');
  PERFORM pg_temp.expect_error(format('UPDATE public.integration_api_interactions SET response_payload_ciphertext=NULL WHERE id=%L',result.id),'integration_api_interactions_append_only');
  PERFORM pg_temp.expect_error(format('DELETE FROM public.integration_api_interactions WHERE id=%L',req.id),'integration_api_interactions_append_only');
  FOR value IN SELECT x FROM (VALUES (body||'{"report_data_total":0}'::jsonb),(body||'{"report_data_total":null}'::jsonb),
    (body||'{"report_data_total":"1.0"}'::jsonb),(body||'{"report_data":{}}'::jsonb),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||jsonb_build_object(CASE WHEN c.api IN ('FUND_ORDER','FUND_AGE') THEN 'clientcode' ELSE 'client_code' END,'FOREIGN')))),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data,c.row_data),'report_data_total',2)),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||'{"unknown":{}}'::jsonb)))) v(x) LOOP
    PERFORM pg_temp.assert_true(NOT (public.inspect_nse_order_funding_response(c.api,value::text,c.request,src)->>'success')::bool,'bad_shape_scope_count_'||c.api);
  END LOOP;
  value:=body||'{"error_remark":"PRIVATE"}'::jsonb;
  PERFORM pg_temp.assert_true(
    (public.inspect_nse_order_funding_response(c.api,value::text,c.request,src)->>'success')::bool = false,
    'success_diagnostic_policy_'||c.api);
  PERFORM pg_temp.assert_true(public.inspect_nse_order_funding_response(c.api,value::text,c.request,src)::text NOT LIKE '%PRIVATE%','success_diagnostic_not_projected_'||c.api);
  IF c.needs_remark THEN PERFORM pg_temp.assert_true(NOT (public.inspect_nse_order_funding_response(c.api,(body-'error_remark')::text,c.request,src)->>'success')::bool,'required_remark'); END IF;
  -- Independently finish an empty report, F and malformed data for every API.
  FOREACH raw IN ARRAY ARRAY[(body||'{"report_data":[],"report_data_total":0}'::jsonb)::text,'{"response_status":"F","error_remark":"PRIVATE"}','PRIVATE'] LOOP
   op:=pg_temp.prepare(c.api);req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,raw,200);
   PERFORM pg_temp.assert_true(result.normalized_outcome=CASE WHEN raw LIKE '%"response_status": "S"%' THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END,'empty_failure_malformed_'||c.api);
  END LOOP;
 END LOOP;
END $$;

DO $$
DECLARE c record; key text; value jsonb; filters jsonb;
BEGIN
 FOR c IN SELECT * FROM funding_contracts LOOP
  FOR key IN SELECT jsonb_object_keys(c.filters) LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_funding_filters(%L,%L)',c.api,c.filters-key),'order_funding_filters_invalid');
   FOREACH value IN ARRAY ARRAY['null'::jsonb,'""','"31-02-2025"','"01-01-0000"','"2025-01-28"','"1-01-2025"'] LOOP
    PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_funding_filters(%L,%L)',c.api,c.filters||jsonb_build_object(key,value)),'order_funding_filters_invalid');
   END LOOP;
  END LOOP;
  IF c.api<>'FUND_AGE' THEN
   PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_funding_filters(%L,%L)',c.api,c.filters||'{"to_date":"01-01-2023"}'),'order_funding_filters_invalid');
   PERFORM public.validate_nse_order_funding_filters(c.api,'{"from_date":"28-02-2024","to_date":"01-03-2024"}');
  END IF;
  IF c.api IN ('ORDER_LIFECYCLE','TRANSACTION_DETAIL') THEN
   PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_funding_filters(%L,%L)',c.api,c.filters||'{"to_date":"29-01-2025"}'),'order_funding_filters_invalid');
  END IF;
 END LOOP;
 FOREACH key IN ARRAY ARRAY['REQUEST_DATE','ORDER_DATE','LAST_ACTIVITY_DATE'] LOOP
  PERFORM public.validate_nse_order_funding_filters('TRANSACTION_DETAIL',jsonb_build_object('from_date','21-01-2025','to_date','24-01-2025','date_type',key));
 END LOOP;
 FOREACH value IN ARRAY ARRAY['"LAST ACTIVITY DATE"'::jsonb,'"last_activity_date"','"REQUEST DATE"','null','""'] LOOP
  PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_funding_filters(%L,%L)','TRANSACTION_DETAIL',jsonb_build_object('from_date','21-01-2025','to_date','24-01-2025','date_type',value)),'order_funding_filters_invalid');
 END LOOP;
 PERFORM pg_temp.expect_error($q$SELECT public.validate_nse_order_funding_filters('TRANSACTION_DETAIL','{"from_date":"21-01-2025","to_date":"25-01-2025","date_type":"LAST_ACTIVITY_DATE"}')$q$,'order_funding_filters_invalid');
 PERFORM pg_temp.expect_error($q$SELECT public.validate_nse_order_funding_filters('UNKNOWN','{}')$q$,'order_funding_filters_invalid');
 -- Controlled DEV UAT 2026-10-01: exact lifecycle empty-success diagnostic.
 PERFORM pg_temp.assert_true(public.inspect_nse_order_funding_response('ORDER_LIFECYCLE',
  '{"response_status":"S","report_data_total":"0","report_data":[],"error_remark":"No record(s) found."}',
  '{"from_date":"30-09-2026","to_date":"30-09-2026","client_code":"SYNTHETIC1"}',
  '{"client_code":"SYNTHETIC1","selectors":{}}') =
  '{"native_status":"S","category":"order_funding_no_records","success":true,"record_count":0}'::jsonb,'live_lifecycle_no_records');
 PERFORM pg_temp.assert_true(NOT (public.inspect_nse_order_funding_response('ORDER_LIFECYCLE',
  '{"response_status":"S","report_data_total":"0","report_data":[],"error_remark":"No record found."}',
  '{"from_date":"30-09-2026","to_date":"30-09-2026","client_code":"SYNTHETIC1"}',
  '{"client_code":"SYNTHETIC1","selectors":{}}')->>'success')::bool,'lifecycle_unknown_success_diagnostic_rejected');
 PERFORM pg_temp.assert_true(public.inspect_nse_order_funding_response('TRANSACTION_DETAIL',
  '{"response_status":"S","report_data_total":"0","report_data":[],"error_remark":"No record(s) found."}',
  '{"from_date":"30-09-2026","to_date":"30-09-2026","client_code":"SYNTHETIC1","date_type":"REQUEST_DATE"}',
  '{"client_code":"SYNTHETIC1","selectors":{}}') =
  '{"native_status":"S","category":"order_funding_no_records","success":true,"record_count":0}'::jsonb,'live_transaction_detail_no_records');
 PERFORM pg_temp.assert_true(NOT (public.inspect_nse_order_funding_response('TRANSACTION_DETAIL',
  '{"response_status":"S","report_data_total":"0","report_data":[],"error_remark":"No record found."}',
  '{"from_date":"30-09-2026","to_date":"30-09-2026","client_code":"SYNTHETIC1","date_type":"REQUEST_DATE"}',
  '{"client_code":"SYNTHETIC1","selectors":{}}')->>'success')::bool,'transaction_detail_unknown_success_diagnostic_rejected');
 -- Narrow #34 compatibility: no diagnostic projection and no positive-row rule.
 PERFORM pg_temp.assert_true(public.inspect_nse_order_funding_response('FUND_AGE','{"response_status":"S","report_data_total":"0","report_data":[],"error_remark":"PRIVATE"}',
  '{"date":"30-04-2024","client_code":"SYNTHETIC1","settlement_type":"all"}','{"client_code":"SYNTHETIC1"}') =
  '{"native_status":"S","category":"order_funding_empty_success_diagnostic","success":true,"record_count":0}'::jsonb,'historical_empty_diagnostic');
END $$;

-- Selector lineage fixtures are produced through the existing real local RPCs.
-- They never install arbitrary provider IDs in B02's caller-facing arguments.
DO $$
DECLARE kind text; op public.integration_operations; target public.integration_operations; event public.event_outbox; claim record;
 req public.integration_api_interactions; result public.integration_api_interactions; target_req public.integration_api_interactions;
 source jsonb; body text; filters jsonb; selection jsonb; src jsonb; bad jsonb; v_api text; row_data jsonb;
 workspace uuid := 'e0030000-0000-4000-8000-000000000001'; account uuid := 'e0060000-0000-4000-8000-000000000001';
BEGIN
 FOREACH kind IN ARRAY ARRAY['client_readiness','order_status','prov_orders'] LOOP
  IF kind='client_readiness' THEN
   op:=public.prepare_nse_client_readiness(workspace,account,'TWO_FA','{"from_date":"21-01-2025","to_date":"28-01-2025"}');
   body:='{"response_status":"S","report_data_total":"2","error_remark":"","report_data":[{"client_code":"SYNTHETIC1","product_type":"PUR","product_id":"450170000001","primary_holder_authentication_status":"SUCCESS"},{"client_code":"SYNTHETIC1","product_type":"SIP","product_id":"202412061000007","primary_holder_authentication_status":"SUCCESS"}]}';
   v_api:='ORDER_LIFECYCLE';
  ELSE
   filters:='{"from_date":"2025-01-21","to_date":"2025-01-27","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}';
   EXECUTE format('SELECT * FROM public.prepare_nse_%I($1,$2,$3)',kind) INTO op USING workspace,account,filters;
   body:='{"response_status":"S","report_data_total":"1","error_remark":"","report_data":[{"client_code":"SYNTHETIC1","order_id":"453530000107","order_status":"VALID"}]}';
   v_api:='TRANSACTION_DETAIL';
  END IF;
  SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  EXECUTE format('SELECT * FROM public.claim_nse_%s_event($1)',kind) INTO claim USING event.id;
  EXECUTE format('SELECT public.get_nse_%s_source($1)',kind) INTO source USING op.id;
  EXECUTE format('SELECT * FROM public.start_nse_%s($1,$2,$3,$4,$5,now())',kind) INTO req
   USING event.id,claim.claim_token,gen_random_uuid(),(source->'request')::text,'{"content_type":"application/json","accept":"application/json"}'::jsonb;
  EXECUTE format('SELECT * FROM public.finish_nse_%s($1,$2,$3,$4,$5,$6,200,$7,$8,$9,NULL,false,false,now(),1,3)',kind) INTO result
   USING event.id,claim.claim_token,req.call_id,body,'application/json','{}'::jsonb,'S',kind||'_report_received','SUCCESS';
  selection:=jsonb_build_object('result_id',result.id,'row_indices',jsonb_build_array(0));
  SELECT c.filters,c.row_data INTO filters,row_data FROM funding_contracts c WHERE c.api=v_api;
  target:=public.prepare_nse_order_funding(workspace,account,v_api,filters,gen_random_uuid(),selection);
  src:=public.get_nse_order_funding_source(target.id);
  IF v_api='ORDER_LIFECYCLE' THEN
   PERFORM pg_temp.assert_true(src->'selectors'='{"Product_type":"PUR","product_id":"450170000001"}'::jsonb,'two_fa_product_lineage');
   PERFORM pg_temp.assert_true(src->'request'->>'Product_type'='PUR' AND NOT(src->'request' ? 'product_type'),'exact_product_casing');
   PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_funding(%L,%L,%L,%L,%L,%L)',workspace,account,v_api,filters,gen_random_uuid(),selection||'{"row_indices":[0,1]}'),'order_funding_selection_invalid');
  ELSE
   PERFORM pg_temp.assert_true(src->'selectors'='{"order_id":"453530000107"}'::jsonb,'owned_order_lineage_'||kind);
   PERFORM pg_temp.assert_true(src->'request'->>'order_id'='453530000107' AND NOT(src->'request' ? 'systematic_reg_id'),'effective_order_selector');
  END IF;
  PERFORM pg_temp.assert_true((SELECT payload::text NOT LIKE '%450170000001%' AND payload::text NOT LIKE '%453530000107%' FROM public.event_outbox WHERE entity_id=target.id),'selectors_encrypted');
  PERFORM pg_temp.assert_true((public.prepare_nse_order_funding(workspace,account,v_api,filters,target.id,selection)).id=target.id,'selection_prepare_idempotent');
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_funding(%L,%L,%L,%L,%L)',workspace,account,v_api,filters,target.id),'order_funding_prepare_conflict');
  target_req:=pg_temp.start_read(target.id);
  PERFORM pg_temp.assert_true((pg_temp.finish_read(target_req,jsonb_build_object('response_status','S','report_data_total',1,'error_remark','','report_data',jsonb_build_array(row_data))::text,200)).normalized_outcome='SUCCESS','owned_selector_response');
  PERFORM pg_temp.assert_true(NOT (public.inspect_nse_order_funding_response(v_api,jsonb_build_object('response_status','S','report_data_total',1,'error_remark','','report_data',jsonb_build_array(row_data||'{"product_id":"FOREIGN"}'))::text,src->'request',src)->>'success')::bool,'foreign_product_under_owned_ucc');
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_funding(%L,%L,%L,%L,%L,%L)','e0030000-0000-4000-8000-000000000002','e0060000-0000-4000-8000-000000000002',v_api,filters,gen_random_uuid(),selection),'order_funding_selection_invalid');
  FOREACH bad IN ARRAY ARRAY['null'::jsonb,'[]','[-1]','[0,0]','[100]','["0"]','[0.5]','[2147483648]'] LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_funding(%L,%L,%L,%L,%L,%L)',workspace,account,v_api,filters,gen_random_uuid(),selection||jsonb_build_object('row_indices',bad)),'order_funding_selection_invalid');
  END LOOP;
  FOREACH bad IN ARRAY ARRAY[selection||jsonb_build_object('result_id',req.id),selection||'{"extra":"bad"}',selection||'{"result_id":"arbitrary"}'] LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_funding(%L,%L,%L,%L,%L,%L)',workspace,account,v_api,filters,gen_random_uuid(),bad),'order_funding_selection_invalid');
  END LOOP;
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_funding(%L,%L,%L,%L,%L,%L)',workspace,account,'FUND_ORDER','{"from_date":"21-01-2025","to_date":"28-01-2025"}',gen_random_uuid(),selection),'order_funding_selection_invalid');
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
  op:=pg_temp.prepare('FUND_ORDER');req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,raw,200);
  PERFORM pg_temp.assert_true(result.native_status_value IS NULL AND result.native_remark_category='order_funding_response_invalid'
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
  op:=pg_temp.prepare('FUND_ORDER');req:=pg_temp.start_read(op.id);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  result:=public.finish_nse_order_funding(event.id,event.claim_token,req.call_id,raw,'application/json','{}',200,'S',
   'order_funding_report_received','SUCCESS',NULL,false,false,now(),1);
  PERFORM pg_temp.assert_true(result.normalized_outcome='BUSINESS_FAILURE' AND result.native_remark_category='order_funding_interpretation_mismatch'
   AND extensions.pgp_sym_decrypt(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw,'mismatched_interpretation_retains_exact_evidence');
  PERFORM pg_temp.assert_true((SELECT state='BUSINESS_FAILED' AND NOT retry_allowed FROM public.integration_operations WHERE id=op.id),'mismatch_terminal');
  PERFORM pg_temp.assert_true(public.get_nse_order_funding_summary(op.workspace_id,op.integration_account_id,op.id) IS NULL,'mismatch_no_trusted_summary');
  replay:=public.finish_nse_order_funding(event.id,event.claim_token,req.call_id,raw,'application/json','{}',200,'S',
   'order_funding_report_received','SUCCESS',NULL,false,false,now(),1);
  PERFORM pg_temp.assert_true(replay.id=result.id,'mismatch_ack_replay');
 END LOOP;
END $$;

-- Binary RESULT evidence uses the existing ciphertext/hash/length columns.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; event public.event_outbox;
 result public.integration_api_interactions; replay public.integration_api_interactions; raw bytea; body text; encoded text;
BEGIN
 FOREACH raw IN ARRAY ARRAY[decode('efbbbf7b7d','hex'),decode('ff80','hex'),decode('007b7d','hex')] LOOP
  op:=pg_temp.prepare('FUND_ORDER');req:=pg_temp.start_read(op.id);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  body:=CASE WHEN raw=decode('efbbbf7b7d','hex') THEN convert_from(raw,'UTF8') ELSE '' END; encoded:=encode(raw,'base64');
  result:=public.finish_nse_order_funding(event.id,event.claim_token,req.call_id,body,'application/json','{}',200,NULL,
    'order_funding_response_invalid','BUSINESS_FAILURE','order_funding_response_invalid',false,false,now(),1,3,encoded);
  PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt_bytea(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw
    AND result.response_bytes=octet_length(raw) AND result.response_hash=extensions.digest(raw,'sha256'),'exact_binary_result');
  replay:=public.finish_nse_order_funding(event.id,event.claim_token,req.call_id,body,'application/json','{}',200,NULL,
    'order_funding_response_invalid','BUSINESS_FAILURE','order_funding_response_invalid',false,false,now(),1,3,encoded);
  PERFORM pg_temp.assert_true(result.id=replay.id,'binary_result_ack_replay');
 END LOOP;
END $$;

-- All endpoints use the same bounded lifecycle, independent of native statuses.
DO $$
DECLARE c record; status integer; attempt integer; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; claim record; before_state text; raw text;
BEGIN
 FOR c IN SELECT * FROM funding_contracts LOOP
  FOREACH status IN ARRAY ARRAY[408,429,500,502,503,504,0,400,401,403,404,501] LOOP
   op:=pg_temp.prepare(c.api);
   FOR attempt IN 1..CASE WHEN status IN (408,429,500,502,503,504,0) THEN 3 ELSE 1 END LOOP
    req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,CASE WHEN status=0 THEN '' ELSE 'PRIVATE' END,NULLIF(status,0));
    PERFORM pg_temp.assert_true(result.attempt_number=attempt AND result.normalized_outcome=CASE WHEN status=0 THEN 'TRANSPORT_FAILURE' ELSE 'HTTP_FAILURE' END,'retry_classification_'||c.api);
    SELECT * INTO op FROM public.integration_operations WHERE id=op.id;
    PERFORM pg_temp.assert_true(op.retry_allowed=(status IN (408,429,500,502,503,504,0) AND attempt<3),'bounded_retry_budget');
   END LOOP;
   SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
   SELECT * INTO claim FROM public.claim_nse_order_funding_event(event.id);
   PERFORM pg_temp.assert_true(claim.claim_state='no_event','terminal_no_claim');
   PERFORM pg_temp.assert_true((SELECT count(*)=op.attempt_count*2 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'all_attempt_pairs_retained');
  END LOOP;
  -- Expired claim before transport, then expired claim after immutable REQUEST.
  op:=pg_temp.prepare(c.api);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  SELECT * INTO claim FROM public.claim_nse_order_funding_event(event.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM public.recover_expired_nse_order_funding_events(event.id);
  SELECT * INTO claim FROM public.claim_nse_order_funding_event(event.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.order_funding_requested'],50,0) WHERE event_outbox_id=event.id),'retry_pre_request_discovery');
  PERFORM public.recover_expired_nse_order_funding_events(event.id);
  req:=pg_temp.start_read(op.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM public.recover_expired_nse_order_funding_events(event.id);
  PERFORM pg_temp.assert_true((SELECT count(*)=2 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'abandoned_request_closed');
  PERFORM pg_temp.assert_true((SELECT NOT retry_allowed AND attempt_count=3 FROM public.integration_operations WHERE id=op.id),'expired_budget_exhausted');
  PERFORM pg_temp.assert_true((SELECT normalized_outcome='TRANSPORT_FAILURE' AND response_bytes=0 AND error_category='order_funding_read_lease_expired' FROM public.integration_api_interactions WHERE call_id=req.call_id AND phase='RESULT'),'truthful_expired_evidence');
 END LOOP;
END $$;

DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; event public.event_outbox; claim record; profile uuid; raw text; result public.integration_api_interactions; summary jsonb;
BEGIN
 op:=pg_temp.prepare('FUND_AGE');
 SELECT id INTO profile FROM public.profiles WHERE user_id='e0010000-0000-4000-8000-000000000001';
 UPDATE public.workspace_memberships SET status='inactive' WHERE workspace_id=op.workspace_id AND profile_id=profile;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_order_funding_source(%L)',op.id),'order_funding_account_scope_invalid');
 UPDATE public.workspace_memberships SET status='active' WHERE workspace_id=op.workspace_id AND profile_id=profile;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id=op.workspace_id;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_order_funding_source(%L)',op.id),'order_funding_account_scope_invalid');
 UPDATE public.workspaces SET workspace_status='active' WHERE id=op.workspace_id;
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC1' WHERE id='e0060000-0000-4000-8000-000000000002';
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_order_funding_source(%L)',op.id),'order_funding_account_scope_invalid');
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC2' WHERE id='e0060000-0000-4000-8000-000000000002';
 UPDATE public.profiles SET canonical_pan_record_id=NULL WHERE user_id='e0010000-0000-4000-8000-000000000002';
 UPDATE public.profiles SET canonical_pan_record_id='e0040000-0000-4000-8000-000000000002' WHERE id=profile;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_order_funding_source(%L)',op.id),'order_funding_account_scope_invalid');
 UPDATE public.profiles SET canonical_pan_record_id='e0040000-0000-4000-8000-000000000001' WHERE id=profile;
 UPDATE public.profiles SET canonical_pan_record_id='e0040000-0000-4000-8000-000000000002' WHERE user_id='e0010000-0000-4000-8000-000000000002';
 UPDATE public.profile_pan_records SET status='SUPERSEDED' WHERE id='e0040000-0000-4000-8000-000000000001';
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_order_funding_source(%L)',op.id),'order_funding_account_scope_invalid');
 UPDATE public.profile_pan_records SET status='VERIFIED' WHERE id='e0040000-0000-4000-8000-000000000001';
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
 SELECT * INTO claim FROM public.claim_nse_order_funding_event(event.id);
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_order_funding(%L,%L,%L,%L,%L,now())',event.id,claim.claim_token,gen_random_uuid(),'{"date":"30-04-2024","client_code":"FOREIGN","settlement_type":"all"}','{"content_type":"application/json","accept":"application/json"}'),'order_funding_request_scope_mismatch');
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_order_funding(%L,%L,%L,%L,%L,now())',event.id,gen_random_uuid(),gen_random_uuid(),'{"date":"30-04-2024","client_code":"SYNTHETIC1","settlement_type":"all"}','{"content_type":"application/json","accept":"application/json"}'),'claim_not_owned');
 req:=public.start_nse_order_funding(event.id,claim.claim_token,gen_random_uuid(),'{"date":"30-04-2024","client_code":"SYNTHETIC1","settlement_type":"all"}','{"content_type":"application/json","accept":"application/json"}',now());
 -- Source changes after send cannot erase/rebind an in-flight response or history.
 UPDATE public.integration_accounts SET external_account_id='CHANGED' WHERE id=op.integration_account_id;
 UPDATE public.profile_pan_records SET pan_ciphertext=extensions.pgp_sym_encrypt('BBBBB1111B',public.pan_encryption_key()) WHERE id='e0040000-0000-4000-8000-000000000001';
 raw:=jsonb_build_object('response_status','S','error_remark','','report_data_total',1,'report_data',jsonb_build_array((SELECT row_data FROM funding_contracts WHERE api='FUND_AGE')))::text;
 result:=pg_temp.finish_read(req,raw,200);
 summary:=public.get_nse_order_funding_summary(op.workspace_id,op.integration_account_id,op.id);
 PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS' AND summary->>'record_count'='1','immutable_identity_snapshot');
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_order_funding_source(%L)',op.id),'order_funding_identity_changed');
END $$;
ROLLBACK;
