-- Execute after all migrations. Synthetic data only; every fixture rolls back.
\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('d0010000-0000-4000-8000-000000000001','authenticated','authenticated','prov-orders-one@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now()),
 ('d0010000-0000-4000-8000-000000000002','authenticated','authenticated','prov-orders-two@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now());
-- Trusted synthetic provisioning; public signup creates only an Explorer account.
INSERT INTO public.profiles(user_id,role)
SELECT id,'investor' FROM auth.users WHERE id IN ('d0010000-0000-4000-8000-000000000001','d0010000-0000-4000-8000-000000000002');

-- Keep generated profile IDs distinct from auth IDs.
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('d0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,'Synthetic PROV_ORDERS',
 'prov-orders-'||right(user_id::text,1),id,'active' FROM public.profiles
 WHERE user_id IN ('d0010000-0000-4000-8000-000000000001','d0010000-0000-4000-8000-000000000002');
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role,status)
SELECT ('d0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,'investor','active'
 FROM public.profiles WHERE user_id IN ('d0010000-0000-4000-8000-000000000001','d0010000-0000-4000-8000-000000000002');
INSERT INTO public.integration_accounts(id,workspace_id,investor_profile_id,integration_key,integration_environment,external_account_id,state,current_registration_status)
SELECT ('d0060000-0000-4000-8000-'||right(user_id::text,12))::uuid,
 ('d0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,id,'NSE_INVEST','UAT','SYNTHETIC'||right(user_id::text,1),'REGISTERED','REG_SUCCESS'
 FROM public.profiles WHERE user_id IN ('d0010000-0000-4000-8000-000000000001','d0010000-0000-4000-8000-000000000002');

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
CREATE FUNCTION pg_temp.prepare() RETURNS public.integration_operations LANGUAGE sql AS $$
 SELECT public.prepare_nse_prov_orders('d0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001',
 '{"from_date":"2023-11-10","to_date":"2023-11-16","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}');
$$;
CREATE FUNCTION pg_temp.start_read(op uuid) RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event_id uuid; claim record;
BEGIN
 SELECT id INTO event_id FROM public.event_outbox WHERE entity_id=op;
 SELECT * INTO claim FROM public.claim_nse_prov_orders_event(event_id,3,120);
 RETURN public.start_nse_prov_orders(event_id,claim.claim_token,gen_random_uuid(),
   (public.get_nse_prov_orders_source(op)->'request')::text,'{"content_type":"application/json","accept":"application/json"}',now());
END $$;
CREATE FUNCTION pg_temp.finish_read(req public.integration_api_interactions, body text, http integer, outcome text, native text, category text)
RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event public.event_outbox;
BEGIN
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=req.integration_operation_id;
 RETURN public.finish_nse_prov_orders(event.id,event.claim_token,req.call_id,body,
   CASE WHEN http IS NULL THEN NULL ELSE 'application/json' END,'{}',http,native,category,outcome,
   CASE WHEN outcome='SUCCESS' THEN NULL WHEN outcome='TRANSPORT_FAILURE' THEN 'nse_request_timeout' ELSE category END,
   http IS NULL,false,now(),1,3);
END $$;

-- Every browser persona is denied at the actual API role, including platform admins.
SET LOCAL ROLE authenticated;
DO $$
DECLARE persona text;
BEGIN
 FOREACH persona IN ARRAY ARRAY['platform_admin','family_guest','inactive_member','operations','unrelated_advisor','cross_workspace'] LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','app_metadata',jsonb_build_object('role',persona))::text,true);
  BEGIN
   PERFORM public.prepare_nse_prov_orders('d0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001','{}');
   RAISE EXCEPTION 'browser_prepare_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_prov_orders_summary(NULL,NULL,NULL); RAISE EXCEPTION 'browser_observation_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT id FROM public.prepare_nse_prov_orders('d0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001',
 '{"from_date":"2023-11-10","to_date":"2023-11-16","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}',
 'd0070000-0000-4000-8000-000000000001');
RESET ROLE;

DO $$
DECLARE name text; fn regprocedure; filters jsonb := '{"from_date":"2023-11-10","to_date":"2023-11-16","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}';
 op public.integration_operations; op2 public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; claim record; source jsonb; observation jsonb; replay public.integration_api_interactions;
 body text := '{"response_status":"S","report_data_total":"2","error_remark":"","report_data":[{"client_code":"SYNTHETIC1","order_id":"100","order_status":"INVALID","request_date":"14/11/2023","order_type":"SO","settlement_type":"T3","member_unique_id":"MEMBER1","email":"PRIVATE","order_remark":"PRIVATE"},{"client_code":"SYNTHETIC1","order_id":"101","order_status":"VALID","member_unique_id":"MEMBER2"}]}';
BEGIN
 PERFORM pg_temp.assert_true(to_regclass('public.nse_prov_orders_queries') IS NULL AND to_regclass('public.nse_prov_orders_observations') IS NULL,'no_report_tables');
 PERFORM pg_temp.assert_true((SELECT relrowsecurity FROM pg_class WHERE oid='public.event_outbox'::regclass),'outbox_rls');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='event_outbox'),'private_outbox_no_policies');
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN ('prepare_nse_prov_orders','get_nse_prov_orders_source','claim_nse_prov_orders_event',
   'recover_expired_nse_prov_orders_events','start_nse_prov_orders','finish_nse_prov_orders','get_nse_prov_orders_summary') LOOP
  PERFORM pg_temp.assert_true(has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE')
    AND NOT has_function_privilege('anon',fn,'EXECUTE'),'rpc_acl');
  PERFORM pg_temp.assert_true((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_search_path');
 END LOOP;
 PERFORM pg_temp.expect_error($q$SELECT public.prepare_nse_prov_orders('d0030000-0000-4000-8000-000000000002','d0060000-0000-4000-8000-000000000001',
  '{"from_date":"2023-11-10","to_date":"2023-11-16","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}')$q$,'prov_orders_account_scope_invalid');
 FOREACH name IN ARRAY ARRAY['client_code','order_ids','member_unique_ids','PAN'] LOOP
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L::jsonb)',
   'd0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001',filters||jsonb_build_object(name,'OTHER')),'prov_orders_filters_invalid');
 END LOOP;
 PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_prov_orders_filters(%L)',filters-'from_date'),'prov_orders_filters_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_prov_orders_filters(%L)',filters||'{"to_date":"2023-11-17"}'::jsonb),'prov_orders_filters_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_prov_orders_filters(%L)',filters||'{"from_date":"2023-02-29"}'::jsonb),'prov_orders_filters_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_prov_orders_filters(%L)',filters||'{"order_status":"ALL"}'::jsonb),'prov_orders_filters_invalid');
 SELECT * INTO op FROM public.prepare_nse_prov_orders('d0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001',filters,'d0070000-0000-4000-8000-000000000001');
 PERFORM pg_temp.assert_true((SELECT count(*)=1 FROM public.event_outbox WHERE entity_id=op.id),'prepare_idempotent');
 PERFORM pg_temp.assert_true(op.operation_type='PROV_ORDERS' AND op.safety_class='READ_ONLY' AND op.reconciliation_target_operation_id IS NULL,'read_identity');
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
 PERFORM pg_temp.assert_true(event.payload=jsonb_build_object('integration_operation_id',op.id,'filters',filters,'scope_result_id',NULL,'scope_rows',NULL,'id_filter',NULL),'outbox_no_raw_request');
 SELECT * INTO claim FROM public.claim_nse_prov_orders_event(event.id,3,120);
 PERFORM pg_temp.assert_true((SELECT claim_state='no_event' FROM public.claim_nse_prov_orders_event(event.id,3,120)),'exclusive_claim');
 source:=public.get_nse_prov_orders_source(op.id)->'request';
 PERFORM pg_temp.assert_true(source->>'client_code'='SYNTHETIC1' AND source->>'date_type'='REQUEST DATE','source_account_bound');
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_prov_orders(%L,%L,%L,%L,%L,now())',event.id,claim.claim_token,gen_random_uuid(),
   (source||'{"client_code":"OTHER"}'::jsonb)::text,'{"content_type":"application/json","accept":"application/json"}'),'prov_orders_request_scope_mismatch');
 SELECT * INTO req FROM public.start_nse_prov_orders(event.id,claim.claim_token,gen_random_uuid(),source::text,'{"content_type":"application/json","accept":"application/json"}',now());
 SELECT * INTO replay FROM public.start_nse_prov_orders(event.id,claim.claim_token,req.call_id,source::text,'{"content_type":"application/json","accept":"application/json"}',now());
 PERFORM pg_temp.assert_true(req.id=replay.id,'request_replay');
 PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference))=source::text,'request_encryption');
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_prov_orders(%L,%L,%L,%L,%L,now())',event.id,claim.claim_token,req.call_id,(source||'{"order_ids":"ARBITRARY"}'::jsonb)::text,
  '{"content_type":"application/json","accept":"application/json"}'),'integration_request_idempotency_conflict');
 SELECT * INTO op2 FROM pg_temp.prepare();
 SELECT id INTO name FROM public.event_outbox WHERE entity_id=op2.id;
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_prov_orders(%L,%L,%L,%L,%L,%L,200,%L,%L,%L,NULL,false,false,now(),1,3)',
  name,claim.claim_token,req.call_id,body,'application/json','{}','S','prov_orders_report_received','SUCCESS'),'prov_orders_result_scope_mismatch');
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_prov_orders(%L,%L,%L,%L,%L,%L,200,%L,%L,%L,NULL,false,false,now(),1,3)',
  event.id,claim.claim_token,req.call_id,replace(body,'SYNTHETIC1','OTHER'),'application/json','{}','S','prov_orders_report_received','SUCCESS'),'prov_orders_result_classification_mismatch');
 SELECT * INTO result FROM pg_temp.finish_read(req,body,200,'SUCCESS','S','prov_orders_report_received');
 SELECT * INTO replay FROM public.finish_nse_prov_orders(event.id,claim.claim_token,req.call_id,body,'application/json','{}',200,'S','prov_orders_report_received','SUCCESS',NULL,false,false,now(),1,3);
 PERFORM pg_temp.assert_true(result.id=replay.id,'result_replay');
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_prov_orders(%L,%L,%L,%L,%L,%L,200,%L,%L,%L,NULL,false,false,now(),2,3)',
  event.id,claim.claim_token,req.call_id,body,'application/json','{}','S','prov_orders_report_received','SUCCESS'),'integration_result_idempotency_conflict');

 PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=body,'result_encryption');
 observation := public.get_nse_prov_orders_summary(op.workspace_id,op.integration_account_id,op.id);
 PERFORM pg_temp.assert_true(observation->>'record_count'='2' AND observation->>'valid_count'='1' AND observation->>'invalid_count'='1','private_counts');
 PERFORM pg_temp.assert_true(NOT to_jsonb(observation)::text LIKE '%PRIVATE%' AND NOT to_jsonb(observation)::text LIKE '%SYNTHETIC1%','no_pii_observation');
 PERFORM pg_temp.assert_true(public.get_nse_prov_orders_summary('d0030000-0000-4000-8000-000000000002',op.integration_account_id,op.id) IS NULL,'observation_scope');
 PERFORM pg_temp.assert_true((SELECT state='SUCCESS' AND NOT reconciliation_required FROM public.integration_operations WHERE id=op.id),'success_read_not_order');
 PERFORM pg_temp.assert_true((SELECT state='REGISTERED' AND current_registration_status='REG_SUCCESS' AND current_operation_id IS NULL FROM public.integration_accounts WHERE id=op.integration_account_id),'account_unchanged');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM public.integration_operations WHERE operation_type='UCC_VERIFICATION'),'no_ucc_target');
 PERFORM pg_temp.expect_error(format('UPDATE public.integration_api_interactions SET error_category=%L WHERE id=%L','mutate',result.id),'append_only');
 PERFORM pg_temp.expect_error(format('DELETE FROM public.integration_api_interactions WHERE id=%L',result.id),'append_only');
 PERFORM pg_temp.expect_error(format('DELETE FROM public.event_outbox WHERE entity_id=%L',op.id),'prov_orders_context_immutable');
 PERFORM pg_temp.expect_error(format('UPDATE public.event_outbox SET payload=%L WHERE entity_id=%L','{}',op.id),'prov_orders_context_immutable');
 PERFORM pg_temp.expect_error(format('UPDATE public.event_outbox SET event_type=%L WHERE entity_id=%L','other',op.id),'prov_orders_context_immutable');
 -- ID refresh derives identifiers from exact evidence rows, never user input.
 FOREACH name IN ARRAY ARRAY['order_ids','member_unique_ids'] LOOP
  SELECT * INTO op2 FROM public.prepare_nse_prov_orders(op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,ARRAY[0,1],name);
  source:=public.get_nse_prov_orders_source(op2.id)->'request';
  PERFORM pg_temp.assert_true(source->>name=CASE WHEN name='order_ids' THEN '100,101' ELSE 'MEMBER1,MEMBER2' END,'owned_ids');
 END LOOP;
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,ARRAY[0],%L)',
  'd0030000-0000-4000-8000-000000000002','d0060000-0000-4000-8000-000000000002',filters,gen_random_uuid(),result.id,'order_ids'),'prov_orders_id_scope_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,ARRAY[2],%L)',op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,'order_ids'),'prov_orders_id_scope_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,ARRAY[]::integer[],%L)',op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,'order_ids'),'prov_orders_id_scope_invalid');
 SELECT * INTO op2 FROM public.prepare_nse_prov_orders(op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,array_fill(0,ARRAY[50]),'order_ids');
 PERFORM pg_temp.assert_true(array_length(string_to_array(public.get_nse_prov_orders_source(op2.id)->'request'->>'order_ids',','),1)=50,'fifty_ids_allowed');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,array_fill(0,ARRAY[51]),%L)',op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,'order_ids'),'prov_orders_id_scope_invalid');
 -- Account identity, active membership and workspace are rechecked before submission.
 UPDATE public.workspace_memberships SET status='inactive' WHERE workspace_id=op.workspace_id;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_prov_orders_source(%L)',op.id),'prov_orders_account_scope_invalid');
 UPDATE public.workspace_memberships SET status='active' WHERE workspace_id=op.workspace_id;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id=op.workspace_id;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_prov_orders_source(%L)',op.id),'prov_orders_account_scope_invalid');
 UPDATE public.workspaces SET workspace_status='active' WHERE id=op.workspace_id;
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC1' WHERE id='d0060000-0000-4000-8000-000000000002';
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_prov_orders_source(%L)',op.id),'prov_orders_account_scope_invalid');
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC2' WHERE id='d0060000-0000-4000-8000-000000000002';
END $$;

-- Transport/HTTP budget, terminal failures, malformed payloads and empty reports.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; res public.integration_api_interactions;
 event public.event_outbox; claim record; http integer; attempt integer; body text; obs jsonb;
BEGIN
 FOREACH http IN ARRAY ARRAY[408,429,500,502,503,504,0] LOOP
  SELECT * INTO op FROM pg_temp.prepare();
  FOR attempt IN 1..3 LOOP
   SELECT * INTO req FROM pg_temp.start_read(op.id);
   SELECT * INTO res FROM pg_temp.finish_read(req,CASE WHEN http=0 THEN '' ELSE 'PRIVATE' END,NULLIF(http,0),
     CASE WHEN http=0 THEN 'TRANSPORT_FAILURE' ELSE 'HTTP_FAILURE' END,NULL,
     CASE WHEN http=0 THEN 'prov_orders_transport_failed' ELSE 'prov_orders_http_failure' END);
   SELECT * INTO op FROM public.integration_operations WHERE id=op.id;
   PERFORM pg_temp.assert_true(op.state='SUBMISSION_FAILED' AND op.retry_allowed=(attempt<3) AND NOT op.ambiguous_outcome,'bounded_retry');
  END LOOP;
  SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  PERFORM pg_temp.assert_true((SELECT claim_state='no_event' FROM public.claim_nse_prov_orders_event(event.id,3,120)),'exhausted');
  PERFORM pg_temp.assert_true((SELECT count(*)=6 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'all_attempt_evidence');
 END LOOP;
 FOREACH http IN ARRAY ARRAY[400,401,403,404,501] LOOP
  SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
  PERFORM pg_temp.finish_read(req,'PRIVATE',http,'HTTP_FAILURE',NULL,'prov_orders_http_failure');
  PERFORM pg_temp.assert_true((SELECT state='HTTP_FAILED' AND NOT retry_allowed FROM public.integration_operations WHERE id=op.id),'terminal_http');
 END LOOP;
 FOREACH body IN ARRAY ARRAY['{"response_status":"S","report_data_total":"1","report_data":[],"error_remark":"PRIVATE DIAGNOSTIC"}','not json','null','[]','{}','{"response_status":"S","report_data_total":"0","report_data":[],"error_remark":"","extra":"\u0000"}','{"response_status":"S","report_data_total":"0","report_data":{},"error_remark":""}',
  '{"response_status":"S","report_data_total":"1","report_data":[],"error_remark":""}',
  '{"response_status":"S","report_data_total":"1","report_data":[null],"error_remark":""}',
  '{"response_status":"S","report_data_total":"1","report_data":[{"client_code":"OTHER","order_id":"100","order_status":"VALID"}],"error_remark":""}',
  '{"response_status":"F","report_data_total":"0","report_data":"","error_remark":"PRIVATE"}'] LOOP
  SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
  obs:=public.inspect_nse_prov_orders_response(body,public.get_nse_prov_orders_source(op.id)->'request');
  PERFORM pg_temp.assert_true(NOT (obs->>'success')::boolean AND obs->>'record_count'='0','malformed_or_foreign_rejected');
  PERFORM pg_temp.finish_read(req,body,200,'BUSINESS_FAILURE',obs->>'native_status',obs->>'category');
  PERFORM pg_temp.assert_true(public.get_nse_prov_orders_summary(op.workspace_id,op.integration_account_id,op.id) IS NULL,'no_partial_observation');
 END LOOP;
 SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
 PERFORM pg_temp.finish_read(req,'{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":""}',200,'SUCCESS','S','prov_orders_no_records');
 PERFORM pg_temp.assert_true(public.get_nse_prov_orders_summary(op.workspace_id,op.integration_account_id,op.id)->>'record_count'='0','empty_success');
 -- Both ID selectors present: order_ids wins, even when member_unique_ids differs.
 obs:=public.inspect_nse_prov_orders_response('{"response_status":"S","report_data_total":1.00000000000000000000,"report_data":[{"client_code":"SYNTHETIC1","order_id":"100","order_status":"VALID","member_unique_id":"OTHER"}],"error_remark":""}',
 '{"client_code":"SYNTHETIC1","order_ids":"100","member_unique_ids":"IGNORED"}');
 PERFORM pg_temp.assert_true((obs->>'success')::boolean,'id_precedence_and_numeric_total');
END $$;

-- Expired leases: no evidence, later pre-REQUEST retry, and abandoned REQUEST.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; event public.event_outbox; claim record; attempt integer;
BEGIN
 SELECT * INTO op FROM pg_temp.prepare();
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
 FOR attempt IN 1..3 LOOP
  SELECT * INTO claim FROM public.claim_nse_prov_orders_event(event.id,3,120);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.prov_orders_requested'],50,0) WHERE event_outbox_id=event.id),'expired_retry_discoverable');
  PERFORM public.recover_expired_nse_prov_orders_events(event.id,3);
  PERFORM pg_temp.assert_true((SELECT state='SUBMISSION_FAILED' AND retry_allowed=(attempt<3) FROM public.integration_operations WHERE id=op.id),'pre_request_recovery');
 END LOOP;
 SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_prov_orders(%L,%L,%L,%L,NULL,%L,NULL,NULL,%L,%L,%L,true,false,now(),1,3)',
  event.id,event.claim_token,req.call_id,'','{}','prov_orders_transport_failed','TRANSPORT_FAILURE','nse_request_timeout'),'claim_not_owned');
 PERFORM public.recover_expired_nse_prov_orders_events(event.id,3);
 PERFORM public.recover_expired_nse_prov_orders_events(event.id,3);
 PERFORM pg_temp.assert_true((SELECT count(*)=1 FROM public.integration_api_interactions WHERE call_id=req.call_id AND phase='RESULT' AND normalized_outcome='TRANSPORT_FAILURE' AND NOT ambiguous_outcome),'abandoned_pair_closed_once');
 SELECT * INTO claim FROM public.claim_nse_prov_orders_event(event.id,3,120);
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_prov_orders(%L,%L,%L,%L,%L,now())',event.id,event.claim_token,gen_random_uuid(),
  (public.get_nse_prov_orders_source(op.id)->'request')::text,'{"content_type":"application/json","accept":"application/json"}'),'claim_not_owned');
 -- A retry with old evidence can itself expire before starting its new request.
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
 PERFORM public.recover_expired_nse_prov_orders_events(event.id,3);
 SELECT * INTO req FROM pg_temp.start_read(op.id);
 PERFORM pg_temp.finish_read(req,'{"response_status":"S","report_data_total":"0","report_data":[],"error_remark":""}',200,'SUCCESS','S','prov_orders_no_records');
 PERFORM pg_temp.assert_true((SELECT count(*)=4 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'retry_preserves_history');
END $$;
-- Contract-specific defaults, immutable generic context, and negative ownership.
DO $$
DECLARE filters jsonb := '{"from_date":"2023-11-10","to_date":"2023-11-16","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}';
 op public.integration_operations; req public.integration_api_interactions; res public.integration_api_interactions;
 other public.integration_operations; candidate jsonb; source jsonb; key text; field text; fn regprocedure;
 workspace uuid := 'd0030000-0000-4000-8000-000000000001';
 account uuid := 'd0060000-0000-4000-8000-000000000001';
BEGIN
 FOREACH candidate IN ARRAY ARRAY[filters,filters||'{"date_type":null}'::jsonb,filters||'{"date_type":"REQUEST DATE"}'::jsonb,filters||'{"date_type":"ORDER DATE"}'::jsonb] LOOP
  SELECT * INTO op FROM public.prepare_nse_prov_orders(workspace,account,candidate);
  source := public.get_nse_prov_orders_source(op.id)->'request';
  PERFORM pg_temp.assert_true(source= candidate-'date_type' || jsonb_build_object(
   'date_type',COALESCE(candidate->>'date_type','REQUEST DATE'),'client_code','SYNTHETIC1',
   'order_status','','settlement_type','','order_ids','','member_unique_ids',''),'exact_request');
  PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_status_filters(%L)',candidate||'{"date_type":"REQUEST DATE"}'::jsonb),'order_status_filters_invalid');
 END LOOP;
 FOREACH candidate IN ARRAY ARRAY['{"date_type":""}'::jsonb,'{"date_type":false}'::jsonb,'{"date_type":"request date"}'::jsonb,
   '{"date_type":[]}'::jsonb,'{"trans_type":null}'::jsonb,'{"order_type":"SO"}'::jsonb,'{"sub_order_type":"SIP"}'::jsonb,
   '{"settlement_type":"T3"}'::jsonb,'{"to_date":"2023-11-09"}'::jsonb,'{"from_date":"0000-01-01"}'::jsonb] LOOP
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L)',workspace,account,filters||candidate),'prov_orders_filters_invalid');
 END LOOP;
 FOREACH candidate IN ARRAY ARRAY['null'::jsonb,'[]'::jsonb,'"PRIVATE"'::jsonb] LOOP
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L)',workspace,account,candidate),'prov_orders_filters_invalid');
 END LOOP;
 -- Successful range evidence is the only ID source allowed by this facade.
 SELECT * INTO op FROM public.prepare_nse_prov_orders(workspace,account,filters);
 SELECT * INTO req FROM pg_temp.start_read(op.id);
 SELECT * INTO res FROM pg_temp.finish_read(req,'{"response_status":"S","report_data_total":"1","report_data":[{"client_code":"SYNTHETIC1","order_id":"OWNED-ORDER","member_unique_id":"OWNED-MEMBER","request_date":"14/11/2023","order_status":"VALID"}],"error_remark":""}',200,'SUCCESS','S','prov_orders_report_received');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,ARRAY[0],%L)',workspace,account,filters,gen_random_uuid(),req.id,'order_ids'),'prov_orders_id_scope_invalid');
 FOREACH key IN ARRAY ARRAY['from_date','to_date','trans_type','order_type','sub_order_type'] LOOP
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,ARRAY[0],%L)',workspace,account,filters-key,gen_random_uuid(),res.id,'order_ids'),'prov_orders_filters_invalid');
 END LOOP;
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,ARRAY[NULL]::integer[],%L)',workspace,account,filters,gen_random_uuid(),res.id,'order_ids'),'prov_orders_id_scope_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,ARRAY[-1],%L)',workspace,account,filters,gen_random_uuid(),res.id,'order_ids'),'prov_orders_id_scope_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,ARRAY[[0]],%L)',workspace,account,filters,gen_random_uuid(),res.id,'order_ids'),'prov_orders_id_scope_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,NULL,NULL)',workspace,account,filters,gen_random_uuid(),res.id),'prov_orders_id_scope_invalid');
 SELECT * INTO other FROM public.prepare_nse_prov_orders(workspace,account,filters,gen_random_uuid(),res.id,ARRAY[0],'member_unique_ids');
 PERFORM pg_temp.assert_true(public.get_nse_prov_orders_source(other.id)->'request'->>'member_unique_ids'='OWNED-MEMBER','evidence_id_projection');
 PERFORM pg_temp.assert_true((SELECT payload::text NOT LIKE '%OWNED-%' FROM public.event_outbox WHERE entity_id=other.id),'outbox_has_no_provider_ids');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L)',workspace,account,filters||'{"date_type":"ORDER DATE"}'::jsonb,op.id),'prov_orders_prepare_conflict');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_prov_orders(%L,%L,%L,%L,%L,ARRAY[0],%L)',workspace,account,filters,op.id,res.id,'order_ids'),'prov_orders_prepare_conflict');
 PERFORM pg_temp.assert_true(public.get_nse_prov_orders_summary(workspace,'d0060000-0000-4000-8000-000000000002',op.id) IS NULL,'summary_account_scope');
 -- The generic outbox cannot bypass typed context validation through a direct insert.
 PERFORM pg_temp.expect_error(format('INSERT INTO public.event_outbox(event_type,entity_id,entity_type,payload) VALUES(%L,%L,%L,%L)',
  'integration.nse.prov_orders_requested',op.id,'integration_operation',jsonb_build_object('integration_operation_id',op.id,'filters',filters,
   'scope_result_id',res.id,'scope_rows',jsonb_build_array(0),'id_filter',NULL)),'prov_orders_id_scope_invalid');
 PERFORM pg_temp.expect_error(format('INSERT INTO public.event_outbox(event_type,entity_id,entity_type,payload) SELECT event_type,entity_id,entity_type,payload FROM public.event_outbox WHERE entity_id=%L',op.id),'event_outbox_one_prov_orders_idx');

 -- A provisional report does not become an ORDER_STATUS scope source.
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_status(%L,%L,%L,%L,%L,ARRAY[0],%L)',workspace,account,filters,gen_random_uuid(),res.id,'order_ids'),'order_status_id_scope_invalid');
 -- Native error text is retained only in the encrypted result, never summaries.
 source := '{"client_code":"SYNTHETIC1","order_ids":"","member_unique_ids":""}';
 candidate := public.inspect_nse_prov_orders_response('{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":"PRIVATE"}',source);
 PERFORM pg_temp.assert_true(candidate->>'category'='prov_orders_no_records' AND candidate->>'success'='true' AND candidate::text NOT LIKE '%PRIVATE%','provisional_historical_success_remark');
 PERFORM pg_temp.assert_true(public.inspect_nse_order_status_response('{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":"PRIVATE"}',source)->>'success'='true','order_status_success_remark_unchanged');
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN ('validate_nse_prov_orders_filters','inspect_nse_prov_orders_response','guard_nse_prov_orders_context') LOOP
  PERFORM pg_temp.assert_true(NOT has_function_privilege('service_role',fn,'EXECUTE')
    AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'private_helpers');
 END LOOP;
END $$;

-- Historical request 20: HTTP 200, success_like, nonempty_diagnostic, string
-- count, empty report_data. Literal values were deliberately not retained in
-- live_uat evidence; all values below are synthetic. Nonempty rows additionally
-- exercise the diagnostic policy with account and identifier checks intact.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; res public.integration_api_interactions;
 body text; rows jsonb; envelope jsonb; patch jsonb; source jsonb; obs jsonb; category text;
BEGIN
 FOREACH rows IN ARRAY ARRAY['[]'::jsonb,
  '[{"client_code":"SYNTHETIC1","order_id":"100","member_unique_id":"MEMBER1","order_status":"INVALID","email":"PRIVATE"}]'::jsonb] LOOP
  body := jsonb_build_object('response_status','S','report_data_total',jsonb_array_length(rows)::text,
    'report_data',rows,'error_remark','SYNTHETIC PRIVATE UAT DIAGNOSTIC')::text;
  category := CASE WHEN jsonb_array_length(rows)=0 THEN 'prov_orders_no_records' ELSE 'prov_orders_report_received' END;
  SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
  SELECT * INTO res FROM pg_temp.finish_read(req,body,200,'SUCCESS','S',category);
  PERFORM pg_temp.assert_true(res.native_status_value='S' AND res.normalized_outcome='SUCCESS'
    AND res.native_remark_category=category AND res.error_category IS NULL,'historical_success_accepted');
  PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt(res.response_payload_ciphertext,
    public.integration_payload_encryption_key(res.payload_encryption_key_reference))=body,'historical_diagnostic_encrypted');
  PERFORM pg_temp.assert_true((to_jsonb(res)-'response_payload_ciphertext')::text NOT LIKE '%PRIVATE%','no_plaintext_result_diagnostic');
  obs := public.get_nse_prov_orders_summary(op.workspace_id,op.integration_account_id,op.id);
  PERFORM pg_temp.assert_true(obs->>'success'='true' AND obs->>'category'=category
    AND (obs->>'record_count')::integer=jsonb_array_length(rows)
    AND (obs->>'invalid_count')::integer=jsonb_array_length(rows)
    AND obs->>'valid_count'='0' AND obs->>'other_count'='0'
    AND obs::text NOT LIKE '%PRIVATE%' AND NOT obs ? 'error_remark','historical_safe_summary');
  SELECT * INTO op FROM public.integration_operations WHERE id=op.id;
  PERFORM pg_temp.assert_true(op.state='SUCCESS' AND NOT op.retry_allowed AND NOT op.ambiguous_outcome
    AND NOT op.reconciliation_required AND to_jsonb(op)::text NOT LIKE '%PRIVATE%','historical_safe_operation');
  PERFORM pg_temp.assert_true((SELECT status='completed' AND error_message IS NULL AND to_jsonb(e)::text NOT LIKE '%PRIVATE%'
    FROM public.event_outbox e WHERE entity_id=op.id),'historical_safe_outbox');
  PERFORM pg_temp.assert_true((SELECT count(*)=2 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'historical_one_call_pair');
 END LOOP;
 source := '{"client_code":"SYNTHETIC1","order_ids":"","member_unique_ids":""}';
 envelope := body::jsonb;
 FOREACH patch IN ARRAY ARRAY['{"response_status":"F"}'::jsonb,'{"response_status":"UNKNOWN"}'::jsonb,
   '{"report_data":{}}'::jsonb,'{"report_data":""}'::jsonb,'{"report_data":[null]}'::jsonb,
   '{"report_data_total":"0"}'::jsonb,'{"report_data_total":"2"}'::jsonb,'{"report_data_total":"1.0"}'::jsonb,
   '{"report_data_total":-1}'::jsonb,'{"error_remark":null}'::jsonb,'{"error_remark":123}'::jsonb,
   '{"report_data":[{"client_code":"OTHER","order_id":"100","order_status":"VALID"}]}'::jsonb] LOOP
  body := (envelope||patch)::text;
  obs := public.inspect_nse_prov_orders_response(body,source);
  PERFORM pg_temp.assert_true(obs->>'success'='false' AND obs->>'record_count'='0' AND obs::text NOT LIKE '%PRIVATE%','diagnostic_cannot_bypass_validation');
  SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
  PERFORM pg_temp.finish_read(req,body,200,'BUSINESS_FAILURE',obs->>'native_status',obs->>'category');
  PERFORM pg_temp.assert_true(public.get_nse_prov_orders_summary(op.workspace_id,op.integration_account_id,op.id) IS NULL,'invalid_diagnostic_report_not_projected');
 END LOOP;
 PERFORM pg_temp.assert_true(public.inspect_nse_prov_orders_response((envelope-'error_remark')::text,source)->>'success'='false','remark_field_still_required');
 FOREACH patch IN ARRAY ARRAY['{"order_ids":"OTHER"}'::jsonb,'{"member_unique_ids":"OTHER"}'::jsonb] LOOP
  obs := public.inspect_nse_prov_orders_response(envelope::text,source||patch);
  PERFORM pg_temp.assert_true(obs->>'success'='false' AND obs->>'category'='prov_orders_scope_mismatch','diagnostic_preserves_id_scope');
 END LOOP;
END $$;

ROLLBACK;
