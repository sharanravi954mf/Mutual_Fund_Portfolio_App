-- Execute after all migrations. Synthetic data only; every fixture rolls back.
\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('d0010000-0000-4000-8000-000000000001','authenticated','authenticated','order-status-one@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now()),
 ('d0010000-0000-4000-8000-000000000002','authenticated','authenticated','order-status-two@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now());
-- Current signup creates workspace-referenced profiles. Never rewrite their IDs.
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('d0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,'Synthetic ORDER_STATUS',
 'order-status-'||right(user_id::text,1),id,'active' FROM public.profiles
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
 SELECT public.prepare_nse_order_status('d0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001',
 '{"from_date":"2023-11-10","to_date":"2023-11-16","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}');
$$;
CREATE FUNCTION pg_temp.start_read(op uuid) RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event_id uuid; claim record;
BEGIN
 SELECT id INTO event_id FROM public.event_outbox WHERE entity_id=op;
 SELECT * INTO claim FROM public.claim_nse_order_status_event(event_id,3,120);
 RETURN public.start_nse_order_status(event_id,claim.claim_token,gen_random_uuid(),
   (public.get_nse_order_status_source(op)->'request')::text,'{"content_type":"application/json","accept":"application/json"}',now());
END $$;
CREATE FUNCTION pg_temp.finish_read(req public.integration_api_interactions, body text, http integer, outcome text, native text, category text)
RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event public.event_outbox;
BEGIN
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=req.integration_operation_id;
 RETURN public.finish_nse_order_status(event.id,event.claim_token,req.call_id,body,
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
   PERFORM public.prepare_nse_order_status('d0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001','{}');
   RAISE EXCEPTION 'browser_prepare_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM 1 FROM public.nse_order_status_observations; RAISE EXCEPTION 'browser_observation_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT id FROM public.prepare_nse_order_status('d0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001',
 '{"from_date":"2023-11-10","to_date":"2023-11-16","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}',
 'd0070000-0000-4000-8000-000000000001');
RESET ROLE;

DO $$
DECLARE name text; fn regprocedure; filters jsonb := '{"from_date":"2023-11-10","to_date":"2023-11-16","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}';
 op public.integration_operations; op2 public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; claim record; source jsonb; observation public.nse_order_status_observations; replay public.integration_api_interactions;
 body text := '{"response_status":"S","report_data_total":"2","error_remark":"","report_data":[{"client_code":"SYNTHETIC1","order_id":"100","order_status":"INVALID","member_unique_id":"MEMBER1","email":"PRIVATE","order_remark":"PRIVATE"},{"client_code":"SYNTHETIC1","order_id":"101","order_status":"VALID","member_unique_id":"MEMBER2"}]}';
BEGIN
 FOREACH name IN ARRAY ARRAY['nse_order_status_queries','nse_order_status_observations'] LOOP
  PERFORM pg_temp.assert_true((SELECT relrowsecurity FROM pg_class WHERE oid=('public.'||name)::regclass),'rls');
  PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=name),'private_no_policies');
  PERFORM pg_temp.assert_true(NOT has_table_privilege('authenticated','public.'||name,'SELECT,INSERT,UPDATE,DELETE'),'browser_no_tables');
  PERFORM pg_temp.assert_true(NOT has_table_privilege('service_role','public.'||name,'SELECT,INSERT,UPDATE,DELETE'),'service_uses_rpcs');
 END LOOP;
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN ('prepare_nse_order_status','get_nse_order_status_source','claim_nse_order_status_event',
   'recover_expired_nse_order_status_events','start_nse_order_status','finish_nse_order_status','get_nse_order_status_observation') LOOP
  PERFORM pg_temp.assert_true(has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE')
    AND NOT has_function_privilege('anon',fn,'EXECUTE'),'rpc_acl');
  PERFORM pg_temp.assert_true((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_search_path');
 END LOOP;
 PERFORM pg_temp.expect_error($q$SELECT public.prepare_nse_order_status('d0030000-0000-4000-8000-000000000002','d0060000-0000-4000-8000-000000000001',
  '{"from_date":"2023-11-10","to_date":"2023-11-16","trans_type":"ALL","order_type":"ALL","sub_order_type":"ALL"}')$q$,'order_status_account_scope_invalid');
 FOREACH name IN ARRAY ARRAY['client_code','order_ids','member_unique_ids','date_type','PAN'] LOOP
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_status(%L,%L,%L::jsonb)',
   'd0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001',filters||jsonb_build_object(name,'OTHER')),'order_status_filters_invalid');
 END LOOP;
 PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_status_filters(%L)',filters-'from_date'),'order_status_filters_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_status_filters(%L)',filters||'{"to_date":"2023-11-17"}'::jsonb),'order_status_dates_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_status_filters(%L)',filters||'{"from_date":"2023-02-29"}'::jsonb),'order_status_dates_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.validate_nse_order_status_filters(%L)',filters||'{"order_status":"ALL"}'::jsonb),'order_status_filters_invalid');
 SELECT * INTO op FROM public.prepare_nse_order_status('d0030000-0000-4000-8000-000000000001','d0060000-0000-4000-8000-000000000001',filters,'d0070000-0000-4000-8000-000000000001');
 PERFORM pg_temp.assert_true((SELECT count(*)=1 FROM public.event_outbox WHERE entity_id=op.id),'prepare_idempotent');
 PERFORM pg_temp.assert_true(op.operation_type='ORDER_STATUS' AND op.safety_class='READ_ONLY' AND op.reconciliation_target_operation_id IS NULL,'read_identity');
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
 PERFORM pg_temp.assert_true(event.payload=jsonb_build_object('integration_operation_id',op.id),'outbox_no_raw_request');
 SELECT * INTO claim FROM public.claim_nse_order_status_event(event.id,3,120);
 PERFORM pg_temp.assert_true((SELECT claim_state='no_event' FROM public.claim_nse_order_status_event(event.id,3,120)),'exclusive_claim');
 source:=public.get_nse_order_status_source(op.id)->'request';
 PERFORM pg_temp.assert_true(source->>'client_code'='SYNTHETIC1' AND NOT source ? 'date_type','source_account_bound');
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_order_status(%L,%L,%L,%L,%L,now())',event.id,claim.claim_token,gen_random_uuid(),
   (source||'{"client_code":"OTHER"}'::jsonb)::text,'{"content_type":"application/json","accept":"application/json"}'),'order_status_request_scope_mismatch');
 SELECT * INTO req FROM public.start_nse_order_status(event.id,claim.claim_token,gen_random_uuid(),source::text,'{"content_type":"application/json","accept":"application/json"}',now());
 SELECT * INTO replay FROM public.start_nse_order_status(event.id,claim.claim_token,req.call_id,source::text,'{"content_type":"application/json","accept":"application/json"}',now());
 PERFORM pg_temp.assert_true(req.id=replay.id,'request_replay');
 PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference))=source::text,'request_encryption');
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_order_status(%L,%L,%L,%L,%L,now())',event.id,claim.claim_token,req.call_id,(source||'{"order_ids":"ARBITRARY"}'::jsonb)::text,
  '{"content_type":"application/json","accept":"application/json"}'),'integration_request_idempotency_conflict');
 SELECT * INTO op2 FROM pg_temp.prepare();
 SELECT id INTO name FROM public.event_outbox WHERE entity_id=op2.id;
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_order_status(%L,%L,%L,%L,%L,%L,200,%L,%L,%L,NULL,false,false,now(),1,3)',
  name,claim.claim_token,req.call_id,body,'application/json','{}','S','order_status_report_received','SUCCESS'),'order_status_result_scope_mismatch');
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_order_status(%L,%L,%L,%L,%L,%L,200,%L,%L,%L,NULL,false,false,now(),1,3)',
  event.id,claim.claim_token,req.call_id,replace(body,'SYNTHETIC1','OTHER'),'application/json','{}','S','order_status_report_received','SUCCESS'),'order_status_result_classification_mismatch');
 SELECT * INTO result FROM pg_temp.finish_read(req,body,200,'SUCCESS','S','order_status_report_received');
 SELECT * INTO replay FROM public.finish_nse_order_status(event.id,claim.claim_token,req.call_id,body,'application/json','{}',200,'S','order_status_report_received','SUCCESS',NULL,false,false,now(),1,3);
 PERFORM pg_temp.assert_true(result.id=replay.id,'result_replay');
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_order_status(%L,%L,%L,%L,%L,%L,200,%L,%L,%L,NULL,false,false,now(),2,3)',
  event.id,claim.claim_token,req.call_id,body,'application/json','{}','S','order_status_report_received','SUCCESS'),'integration_result_idempotency_conflict');

 PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=body,'result_encryption');
 SELECT * INTO observation FROM public.get_nse_order_status_observation(op.workspace_id,op.integration_account_id,op.id);
 PERFORM pg_temp.assert_true(observation.record_count=2 AND observation.valid_count=1 AND observation.invalid_count=1,'private_counts');
 PERFORM pg_temp.assert_true(NOT to_jsonb(observation)::text LIKE '%PRIVATE%' AND NOT to_jsonb(observation)::text LIKE '%SYNTHETIC1%','no_pii_observation');
 PERFORM pg_temp.assert_true((public.get_nse_order_status_observation('d0030000-0000-4000-8000-000000000002',op.integration_account_id,op.id)).operation_id IS NULL,'observation_scope');
 PERFORM pg_temp.assert_true((SELECT state='SUCCESS' AND NOT reconciliation_required FROM public.integration_operations WHERE id=op.id),'success_read_not_order');
 PERFORM pg_temp.assert_true((SELECT state='REGISTERED' AND current_registration_status='REG_SUCCESS' AND current_operation_id IS NULL FROM public.integration_accounts WHERE id=op.integration_account_id),'account_unchanged');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM public.integration_operations WHERE operation_type='UCC_VERIFICATION'),'no_ucc_target');
 PERFORM pg_temp.expect_error(format('UPDATE public.integration_api_interactions SET error_category=%L WHERE id=%L','mutate',result.id),'append_only');
 PERFORM pg_temp.expect_error(format('DELETE FROM public.nse_order_status_observations WHERE operation_id=%L',op.id),'append_only');
 -- ID refresh derives identifiers from exact evidence rows, never user input.
 FOREACH name IN ARRAY ARRAY['order_ids','member_unique_ids'] LOOP
  SELECT * INTO op2 FROM public.prepare_nse_order_status(op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,ARRAY[0,1],name);
  source:=public.get_nse_order_status_source(op2.id)->'request';
  PERFORM pg_temp.assert_true(source->>name=CASE WHEN name='order_ids' THEN '100,101' ELSE 'MEMBER1,MEMBER2' END,'owned_ids');
 END LOOP;
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_status(%L,%L,%L,%L,%L,ARRAY[0],%L)',
  'd0030000-0000-4000-8000-000000000002','d0060000-0000-4000-8000-000000000002',filters,gen_random_uuid(),result.id,'order_ids'),'order_status_id_scope_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_status(%L,%L,%L,%L,%L,ARRAY[2],%L)',op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,'order_ids'),'order_status_id_scope_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_status(%L,%L,%L,%L,%L,ARRAY[]::integer[],%L)',op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,'order_ids'),'order_status_id_scope_invalid');
 SELECT * INTO op2 FROM public.prepare_nse_order_status(op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,array_fill(0,ARRAY[50]),'order_ids');
 PERFORM pg_temp.assert_true(array_length(string_to_array(public.get_nse_order_status_source(op2.id)->'request'->>'order_ids',','),1)=50,'fifty_ids_allowed');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_order_status(%L,%L,%L,%L,%L,array_fill(0,ARRAY[51]),%L)',op.workspace_id,op.integration_account_id,filters,gen_random_uuid(),result.id,'order_ids'),'order_status_id_scope_invalid');
 -- Account identity, active membership and workspace are rechecked before submission.
 UPDATE public.workspace_memberships SET status='inactive' WHERE workspace_id=op.workspace_id;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_order_status_source(%L)',op.id),'order_status_account_scope_invalid');
 UPDATE public.workspace_memberships SET status='active' WHERE workspace_id=op.workspace_id;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id=op.workspace_id;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_order_status_source(%L)',op.id),'order_status_account_scope_invalid');
 UPDATE public.workspaces SET workspace_status='active' WHERE id=op.workspace_id;
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC1' WHERE id='d0060000-0000-4000-8000-000000000002';
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_order_status_source(%L)',op.id),'order_status_account_scope_invalid');
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
     CASE WHEN http=0 THEN 'order_status_transport_failed' ELSE 'order_status_http_failure' END);
   SELECT * INTO op FROM public.integration_operations WHERE id=op.id;
   PERFORM pg_temp.assert_true(op.state='SUBMISSION_FAILED' AND op.retry_allowed=(attempt<3) AND NOT op.ambiguous_outcome,'bounded_retry');
  END LOOP;
  SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  PERFORM pg_temp.assert_true((SELECT claim_state='no_event' FROM public.claim_nse_order_status_event(event.id,3,120)),'exhausted');
  PERFORM pg_temp.assert_true((SELECT count(*)=6 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'all_attempt_evidence');
 END LOOP;
 FOREACH http IN ARRAY ARRAY[400,401,403,404,501] LOOP
  SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
  PERFORM pg_temp.finish_read(req,'PRIVATE',http,'HTTP_FAILURE',NULL,'order_status_http_failure');
  PERFORM pg_temp.assert_true((SELECT state='HTTP_FAILED' AND NOT retry_allowed FROM public.integration_operations WHERE id=op.id),'terminal_http');
 END LOOP;
 FOREACH body IN ARRAY ARRAY['not json','null','[]','{}','{"response_status":"S","report_data_total":"0","report_data":[],"error_remark":"","extra":"\u0000"}','{"response_status":"S","report_data_total":"0","report_data":{},"error_remark":""}',
  '{"response_status":"S","report_data_total":"1","report_data":[],"error_remark":""}',
  '{"response_status":"S","report_data_total":"1","report_data":[null],"error_remark":""}',
  '{"response_status":"S","report_data_total":"1","report_data":[{"client_code":"OTHER","order_id":"100","order_status":"VALID"}],"error_remark":""}',
  '{"response_status":"F","report_data_total":"0","report_data":"","error_remark":"PRIVATE"}'] LOOP
  SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
  obs:=public.inspect_nse_order_status_response(body,public.get_nse_order_status_source(op.id)->'request');
  PERFORM pg_temp.assert_true(NOT (obs->>'success')::boolean AND obs->>'record_count'='0','malformed_or_foreign_rejected');
  PERFORM pg_temp.finish_read(req,body,200,'BUSINESS_FAILURE',obs->>'native_status',obs->>'category');
  PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM public.nse_order_status_observations WHERE operation_id=op.id),'no_partial_observation');
 END LOOP;
 SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
 PERFORM pg_temp.finish_read(req,'{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":""}',200,'SUCCESS','S','order_status_no_records');
 PERFORM pg_temp.assert_true((SELECT record_count=0 FROM public.nse_order_status_observations WHERE operation_id=op.id),'empty_success');
 -- Both ID selectors present: order_ids wins, even when member_unique_ids differs.
 obs:=public.inspect_nse_order_status_response('{"response_status":"S","report_data_total":1.00000000000000000000,"report_data":[{"client_code":"SYNTHETIC1","order_id":"100","order_status":"VALID","member_unique_id":"OTHER"}],"error_remark":""}',
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
  SELECT * INTO claim FROM public.claim_nse_order_status_event(event.id,3,120);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.order_status_requested'],50,0) WHERE event_outbox_id=event.id),'expired_retry_discoverable');
  PERFORM public.recover_expired_nse_order_status_events(event.id,3);
  PERFORM pg_temp.assert_true((SELECT state='SUBMISSION_FAILED' AND retry_allowed=(attempt<3) FROM public.integration_operations WHERE id=op.id),'pre_request_recovery');
 END LOOP;
 SELECT * INTO op FROM pg_temp.prepare(); SELECT * INTO req FROM pg_temp.start_read(op.id);
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_order_status(%L,%L,%L,%L,NULL,%L,NULL,NULL,%L,%L,%L,true,false,now(),1,3)',
  event.id,event.claim_token,req.call_id,'','{}','order_status_transport_failed','TRANSPORT_FAILURE','nse_request_timeout'),'claim_not_owned');
 PERFORM public.recover_expired_nse_order_status_events(event.id,3);
 PERFORM public.recover_expired_nse_order_status_events(event.id,3);
 PERFORM pg_temp.assert_true((SELECT count(*)=1 FROM public.integration_api_interactions WHERE call_id=req.call_id AND phase='RESULT' AND normalized_outcome='TRANSPORT_FAILURE' AND NOT ambiguous_outcome),'abandoned_pair_closed_once');
 SELECT * INTO claim FROM public.claim_nse_order_status_event(event.id,3,120);
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_order_status(%L,%L,%L,%L,%L,now())',event.id,event.claim_token,gen_random_uuid(),
  (public.get_nse_order_status_source(op.id)->'request')::text,'{"content_type":"application/json","accept":"application/json"}'),'claim_not_owned');
 -- A retry with old evidence can itself expire before starting its new request.
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
 PERFORM public.recover_expired_nse_order_status_events(event.id,3);
 SELECT * INTO req FROM pg_temp.start_read(op.id);
 PERFORM pg_temp.finish_read(req,'{"response_status":"S","report_data_total":"0","report_data":[],"error_remark":""}',200,'SUCCESS','S','order_status_no_records');
 PERFORM pg_temp.assert_true((SELECT count(*)=4 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'retry_preserves_history');
END $$;
ROLLBACK;
