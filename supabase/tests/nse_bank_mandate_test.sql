-- Execute after all migrations. Synthetic data only; every fixture rolls back.
\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('e0010000-0000-4000-8000-000000000001','authenticated','authenticated','client-readiness-one@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now()),
 ('e0010000-0000-4000-8000-000000000002','authenticated','authenticated','client-readiness-two@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now());
-- Trusted synthetic provisioning; public signup creates only an Explorer account.
INSERT INTO public.profiles(user_id,role)
SELECT id,'investor' FROM auth.users WHERE id IN ('e0010000-0000-4000-8000-000000000001','e0010000-0000-4000-8000-000000000002');

-- Explicit owned-investor links are required by current workspace containment.
INSERT INTO public.investor_account_links(user_id,profile_id,verification_method,verified_at)
SELECT user_id,id,'synthetic_fixture',now() FROM public.profiles
 WHERE user_id IN ('e0010000-0000-4000-8000-000000000001','e0010000-0000-4000-8000-000000000002');
-- Keep generated profile IDs distinct from auth IDs.
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('e0030000-0000-4000-8000-'||right(user_id::text,12))::uuid,'Synthetic MANDATE_STATUS',
 'client-readiness-'||right(user_id::text,1),id,'active' FROM public.profiles
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

CREATE TEMP TABLE readiness_contracts(api text, filters jsonb, request jsonb, path text, row_data jsonb, needs_remark bool);
INSERT INTO readiness_contracts VALUES
('MANDATE_STATUS','{}','{"client_code":"SYNTHETIC1"}','/nsemfdesk/api/v2/reports/MANDATE_STATUS',
 '{"mandateId":"12345","clientCode":"SYNTHETIC1","memberCode":"TEST","memberMandateId":"","bankAccountNumber":"PRIVATE","status":"APPROVED"}',true);
CREATE FUNCTION pg_temp.prepare(api text) RETURNS public.integration_operations LANGUAGE sql AS $$
 SELECT public.prepare_nse_mandate_status('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',api,(SELECT filters FROM readiness_contracts c WHERE c.api=$1));
$$;
CREATE FUNCTION pg_temp.start_read(op uuid) RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event_id uuid; claim record;
BEGIN
 SELECT id INTO event_id FROM public.event_outbox WHERE entity_id=op;
 SELECT * INTO claim FROM public.claim_nse_mandate_status_event(event_id,3,120);
 RETURN public.start_nse_mandate_status(event_id,claim.claim_token,gen_random_uuid(),
   (public.get_nse_mandate_status_source(op)->'request')::text,'{"content_type":"application/json","accept":"application/json"}',now());
END $$;
CREATE FUNCTION pg_temp.finish_read(req public.integration_api_interactions, body text, http integer)
RETURNS public.integration_api_interactions LANGUAGE plpgsql AS $$
DECLARE event public.event_outbox; observation jsonb; outcome text; native text; category text;
BEGIN
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=req.integration_operation_id;
 IF http BETWEEN 200 AND 299 THEN
  observation:=public.inspect_nse_mandate_status_response(req.api_key,body,extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference))::jsonb,
   public.nse_mandate_status_identity(req.integration_operation_id));
  outcome:=CASE WHEN (observation->>'success')::bool THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END;native:=observation->>'native_status';category:=observation->>'category';
 ELSE outcome:=CASE WHEN http IS NULL THEN 'TRANSPORT_FAILURE' ELSE 'HTTP_FAILURE' END;
  category:=CASE WHEN http IS NULL THEN 'mandate_status_transport_failed' ELSE 'mandate_status_http_failure' END;
 END IF;
 RETURN public.finish_nse_mandate_status(event.id,event.claim_token,req.call_id,body,
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
  BEGIN PERFORM public.prepare_nse_mandate_status(NULL,NULL,'MANDATE_STATUS'); RAISE EXCEPTION 'browser_prepare_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_mandate_status_summary(NULL,NULL,NULL); RAISE EXCEPTION 'browser_summary_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_mandate_status_source(NULL); RAISE EXCEPTION 'browser_source_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT id FROM public.prepare_nse_mandate_status('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001','MANDATE_STATUS');
RESET ROLE;

DO $$
DECLARE c record; fn regprocedure; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; src jsonb; summary jsonb; raw text; body jsonb; key text; value jsonb; replay public.integration_api_interactions; claim record;
BEGIN
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('prepare_nse_mandate_status','get_nse_mandate_status_source','claim_nse_mandate_status_event',
 'recover_expired_nse_mandate_status_events','start_nse_mandate_status','finish_nse_mandate_status','get_nse_mandate_status_summary') LOOP
  PERFORM pg_temp.assert_true(has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'rpc_acl');
  PERFORM pg_temp.assert_true((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_search_path');
 END LOOP;
 PERFORM pg_temp.assert_true(NOT has_function_privilege('service_role','public.nse_mandate_status_identity(uuid)','EXECUTE'),'identity_helper_private');
 PERFORM pg_temp.assert_true((SELECT relrowsecurity FROM pg_class WHERE oid='public.event_outbox'::regclass),'outbox_rls');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='event_outbox'),'private_outbox_policies');
 FOR c IN SELECT * FROM readiness_contracts LOOP
  op:=pg_temp.prepare(c.api); src:=public.get_nse_mandate_status_source(op.id);
  PERFORM pg_temp.assert_true(src->'request'=c.request AND src->>'api'=c.api AND src->>'pan'='AAAAA0000A','exact_request_'||c.api);
  SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  PERFORM pg_temp.assert_true(event.payload::text NOT LIKE '%AAAAA0000A%' AND event.payload::text NOT LIKE '%SYNTHETIC1%','encrypted_context');
  PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_mandate_status(%L,%L,%L,%L)',
   'e0030000-0000-4000-8000-000000000002','e0060000-0000-4000-8000-000000000001',c.api,c.filters),'mandate_status_account_scope_invalid');
  FOREACH key IN ARRAY ARRAY['PAN','pan_no','pan_pkern_no','client_code','product_type','Product_type','product_id','order_ids','url'] LOOP
   PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_mandate_status(%L,%L,%L,%L)',
    op.workspace_id,op.integration_account_id,c.api,c.filters||jsonb_build_object(key,'FOREIGN')),'mandate_status_filters_invalid');
  END LOOP;
  PERFORM pg_temp.assert_true((public.prepare_nse_mandate_status(op.workspace_id,op.integration_account_id,c.api,c.filters,op.id)).id=op.id,'prepare_idempotent');
  PERFORM pg_temp.expect_error(format('UPDATE public.event_outbox SET payload=payload||%L::jsonb WHERE id=%L','{"api":"UNKNOWN"}',event.id),'mandate_status_context_immutable');
  PERFORM pg_temp.expect_error(format('DELETE FROM public.event_outbox WHERE id=%L',event.id),'mandate_status_context_immutable');
  req:=pg_temp.start_read(op.id);
  SELECT * INTO event FROM public.event_outbox WHERE id=event.id;
  PERFORM pg_temp.assert_true(req.endpoint_path=c.path AND req.http_method='POST' AND req.phase='REQUEST','exact_endpoint_'||c.api);
  raw:=extensions.pgp_sym_decrypt(req.request_payload_ciphertext,public.integration_payload_encryption_key(req.payload_encryption_key_reference));
  PERFORM pg_temp.assert_true(raw=c.request::text AND req.request_bytes=octet_length(raw) AND req.request_hash=extensions.digest(raw,'sha256'),'request_exact_evidence');
  SELECT * INTO replay FROM public.start_nse_mandate_status(event.id,event.claim_token,req.call_id,raw,req.request_header_metadata,req.started_at);
  PERFORM pg_temp.assert_true(replay.id=req.id,'request_ack_replay');
  PERFORM pg_temp.expect_error(format('SELECT public.start_nse_mandate_status(%L,%L,%L,%L,%L,%L)',event.id,event.claim_token,req.call_id,raw||' ',req.request_header_metadata,req.started_at),'integration_request_idempotency_conflict');
  SELECT * INTO claim FROM public.claim_nse_mandate_status_event(event.id);
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
  summary:=public.get_nse_mandate_status_summary(op.workspace_id,op.integration_account_id,op.id);
  PERFORM pg_temp.assert_true(summary->>'record_count'='1' AND summary->>'api'=c.api AND summary::text NOT LIKE '%PRIVATE%' AND summary::text NOT LIKE '%AAAAA0000A%','private_safe_summary');
  PERFORM pg_temp.assert_true(public.get_nse_mandate_status_summary(gen_random_uuid(),op.integration_account_id,op.id) IS NULL,'summary_workspace_scope');
  PERFORM pg_temp.assert_true(public.get_nse_mandate_status_summary(op.workspace_id,gen_random_uuid(),op.id) IS NULL,'summary_account_scope');
  PERFORM pg_temp.expect_error(format('UPDATE public.integration_api_interactions SET response_payload_ciphertext=NULL WHERE id=%L',result.id),'integration_api_interactions_append_only');
  PERFORM pg_temp.expect_error(format('DELETE FROM public.integration_api_interactions WHERE id=%L',req.id),'integration_api_interactions_append_only');
  FOR value IN SELECT x FROM (VALUES (body||'{"report_data_total":0}'::jsonb),(body||'{"report_data_total":null}'::jsonb),
    (body||'{"report_data_total":"1.0"}'::jsonb),(body||'{"report_data":{}}'::jsonb),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||jsonb_build_object('clientCode','FOREIGN')))),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data,c.row_data),'report_data_total',2)),
    (body||jsonb_build_object('report_data',jsonb_build_array(c.row_data||'{"unknown":{}}'::jsonb)))) v(x) LOOP
    PERFORM pg_temp.assert_true(NOT (public.inspect_nse_mandate_status_response(c.api,value::text,c.request,src)->>'success')::bool,'bad_shape_scope_count_'||c.api);
  END LOOP;
  value:=body||'{"error_remark":"PRIVATE"}'::jsonb;
  PERFORM pg_temp.assert_true(
    (public.inspect_nse_mandate_status_response(c.api,value::text,c.request,src)->>'success')::bool = (c.api='ELOG_REPORT'),
    'success_diagnostic_policy_'||c.api);
  PERFORM pg_temp.assert_true(public.inspect_nse_mandate_status_response(c.api,value::text,c.request,src)::text NOT LIKE '%PRIVATE%','success_diagnostic_not_projected_'||c.api);
  IF c.needs_remark THEN PERFORM pg_temp.assert_true(NOT (public.inspect_nse_mandate_status_response(c.api,(body-'error_remark')::text,c.request,src)->>'success')::bool,'required_remark'); END IF;
  -- Independently finish an empty report, F and malformed data for every API.
  FOREACH raw IN ARRAY ARRAY[(body||'{"report_data":[],"report_data_total":0}'::jsonb)::text,'{"response_status":"F","error_remark":"PRIVATE"}','PRIVATE'] LOOP
   op:=pg_temp.prepare(c.api);req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,raw,200);
   PERFORM pg_temp.assert_true(result.normalized_outcome='BUSINESS_FAILURE','empty_failure_malformed_'||c.api);
  END LOOP;
 END LOOP;
END $$;

-- Binary RESULT evidence uses the existing ciphertext/hash/length columns.
DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; event public.event_outbox;
 result public.integration_api_interactions; replay public.integration_api_interactions; raw bytea; body text; encoded text;
BEGIN
 FOREACH raw IN ARRAY ARRAY[decode('efbbbf7b7d','hex'),decode('ff80','hex'),decode('007b7d','hex')] LOOP
  op:=pg_temp.prepare('MANDATE_STATUS');req:=pg_temp.start_read(op.id);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  body:=CASE WHEN raw=decode('efbbbf7b7d','hex') THEN convert_from(raw,'UTF8') ELSE '' END; encoded:=encode(raw,'base64');
  result:=public.finish_nse_mandate_status(event.id,event.claim_token,req.call_id,body,'application/json','{}',200,NULL,
    'mandate_status_response_invalid','BUSINESS_FAILURE','mandate_status_response_invalid',false,false,now(),1,3,encoded);
  PERFORM pg_temp.assert_true(extensions.pgp_sym_decrypt_bytea(result.response_payload_ciphertext,public.integration_payload_encryption_key(result.payload_encryption_key_reference))=raw
    AND result.response_bytes=octet_length(raw) AND result.response_hash=extensions.digest(raw,'sha256'),'exact_binary_result');
  replay:=public.finish_nse_mandate_status(event.id,event.claim_token,req.call_id,body,'application/json','{}',200,NULL,
    'mandate_status_response_invalid','BUSINESS_FAILURE','mandate_status_response_invalid',false,false,now(),1,3,encoded);
  PERFORM pg_temp.assert_true(result.id=replay.id,'binary_result_ack_replay');
 END LOOP;
END $$;

-- All endpoints use the same bounded lifecycle, independent of native statuses.
DO $$
DECLARE c record; status integer; attempt integer; op public.integration_operations; req public.integration_api_interactions; result public.integration_api_interactions;
 event public.event_outbox; claim record; before_state text; raw text;
BEGIN
 FOR c IN SELECT * FROM readiness_contracts LOOP
  FOREACH status IN ARRAY ARRAY[408,429,500,502,503,504,0,400,401,403,404,501] LOOP
   op:=pg_temp.prepare(c.api);
   FOR attempt IN 1..CASE WHEN status IN (408,429,500,502,503,504,0) THEN 3 ELSE 1 END LOOP
    req:=pg_temp.start_read(op.id);result:=pg_temp.finish_read(req,CASE WHEN status=0 THEN '' ELSE 'PRIVATE' END,NULLIF(status,0));
    PERFORM pg_temp.assert_true(result.attempt_number=attempt AND result.normalized_outcome=CASE WHEN status=0 THEN 'TRANSPORT_FAILURE' ELSE 'HTTP_FAILURE' END,'retry_classification_'||c.api);
    SELECT * INTO op FROM public.integration_operations WHERE id=op.id;
    PERFORM pg_temp.assert_true(op.retry_allowed=(status IN (408,429,500,502,503,504,0) AND attempt<3),'bounded_retry_budget');
   END LOOP;
   SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
   SELECT * INTO claim FROM public.claim_nse_mandate_status_event(event.id);
   PERFORM pg_temp.assert_true(claim.claim_state='no_event','terminal_no_claim');
   PERFORM pg_temp.assert_true((SELECT count(*)=op.attempt_count*2 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'all_attempt_pairs_retained');
  END LOOP;
  -- Expired claim before transport, then expired claim after immutable REQUEST.
  op:=pg_temp.prepare(c.api);SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
  SELECT * INTO claim FROM public.claim_nse_mandate_status_event(event.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM public.recover_expired_nse_mandate_status_events(event.id);
  SELECT * INTO claim FROM public.claim_nse_mandate_status_event(event.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.mandate_status_requested'],50,0) WHERE event_outbox_id=event.id),'retry_pre_request_discovery');
  PERFORM public.recover_expired_nse_mandate_status_events(event.id);
  req:=pg_temp.start_read(op.id);
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=event.id;
  PERFORM public.recover_expired_nse_mandate_status_events(event.id);
  PERFORM pg_temp.assert_true((SELECT count(*)=2 FROM public.integration_api_interactions WHERE integration_operation_id=op.id),'abandoned_request_closed');
  PERFORM pg_temp.assert_true((SELECT NOT retry_allowed AND attempt_count=3 FROM public.integration_operations WHERE id=op.id),'expired_budget_exhausted');
  PERFORM pg_temp.assert_true((SELECT normalized_outcome='TRANSPORT_FAILURE' AND response_bytes=0 AND error_category='mandate_status_read_lease_expired' FROM public.integration_api_interactions WHERE call_id=req.call_id AND phase='RESULT'),'truthful_expired_evidence');
 END LOOP;
END $$;

DO $$
DECLARE op public.integration_operations; req public.integration_api_interactions; event public.event_outbox; claim record; profile uuid; raw text; result public.integration_api_interactions; summary jsonb;
BEGIN
 op:=pg_temp.prepare('MANDATE_STATUS');
 SELECT id INTO profile FROM public.profiles WHERE user_id='e0010000-0000-4000-8000-000000000001';
 UPDATE public.workspace_memberships SET status='inactive' WHERE workspace_id=op.workspace_id AND profile_id=profile;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_mandate_status_source(%L)',op.id),'mandate_status_account_scope_invalid');
 UPDATE public.workspace_memberships SET status='active' WHERE workspace_id=op.workspace_id AND profile_id=profile;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id=op.workspace_id;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_mandate_status_source(%L)',op.id),'mandate_status_account_scope_invalid');
 UPDATE public.workspaces SET workspace_status='active' WHERE id=op.workspace_id;
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC1' WHERE id='e0060000-0000-4000-8000-000000000002';
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_mandate_status_source(%L)',op.id),'mandate_status_account_scope_invalid');
 UPDATE public.integration_accounts SET external_account_id='SYNTHETIC2' WHERE id='e0060000-0000-4000-8000-000000000002';
 UPDATE public.profiles SET canonical_pan_record_id=NULL WHERE user_id='e0010000-0000-4000-8000-000000000002';
 UPDATE public.profiles SET canonical_pan_record_id='e0040000-0000-4000-8000-000000000002' WHERE id=profile;
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_mandate_status_source(%L)',op.id),'mandate_status_account_scope_invalid');
 UPDATE public.profiles SET canonical_pan_record_id='e0040000-0000-4000-8000-000000000001' WHERE id=profile;
 UPDATE public.profiles SET canonical_pan_record_id='e0040000-0000-4000-8000-000000000002' WHERE user_id='e0010000-0000-4000-8000-000000000002';
 UPDATE public.profile_pan_records SET status='SUPERSEDED' WHERE id='e0040000-0000-4000-8000-000000000001';
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_mandate_status_source(%L)',op.id),'mandate_status_account_scope_invalid');
 UPDATE public.profile_pan_records SET status='VERIFIED' WHERE id='e0040000-0000-4000-8000-000000000001';
 SELECT * INTO event FROM public.event_outbox WHERE entity_id=op.id;
 SELECT * INTO claim FROM public.claim_nse_mandate_status_event(event.id);
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_mandate_status(%L,%L,%L,%L,%L,now())',event.id,claim.claim_token,gen_random_uuid(),'{"client_code":"FOREIGN"}','{"content_type":"application/json","accept":"application/json"}'),'mandate_status_request_scope_mismatch');
 PERFORM pg_temp.expect_error(format('SELECT public.start_nse_mandate_status(%L,%L,%L,%L,%L,now())',event.id,gen_random_uuid(),gen_random_uuid(),'{"client_code":"SYNTHETIC1"}','{"content_type":"application/json","accept":"application/json"}'),'claim_not_owned');
 req:=public.start_nse_mandate_status(event.id,claim.claim_token,gen_random_uuid(),'{"client_code":"SYNTHETIC1"}','{"content_type":"application/json","accept":"application/json"}',now());
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_mandate_status(%L,%L,%L,%L,%L,%L,200,%L,%L,%L,NULL,false,false,now(),1)',event.id,claim.claim_token,req.call_id,'{"response_status":"F"}','application/json','{}','S','mandate_status_unique_match_received','SUCCESS'),'mandate_status_result_classification_mismatch');
 -- Source changes after send cannot erase/rebind an in-flight response or history.
 UPDATE public.integration_accounts SET external_account_id='CHANGED' WHERE id=op.integration_account_id;
 UPDATE public.profile_pan_records SET pan_ciphertext=extensions.pgp_sym_encrypt('BBBBB1111B',public.pan_encryption_key()) WHERE id='e0040000-0000-4000-8000-000000000001';
 raw:=jsonb_build_object('error_remark','','response_status','S','report_data_total',1,'report_data',jsonb_build_array((SELECT row_data FROM readiness_contracts WHERE api='MANDATE_STATUS')))::text;
 result:=pg_temp.finish_read(req,raw,200);
 summary:=public.get_nse_mandate_status_summary(op.workspace_id,op.integration_account_id,op.id);
 PERFORM pg_temp.assert_true(result.normalized_outcome='SUCCESS' AND summary->>'record_count'='1','immutable_identity_snapshot');
 PERFORM pg_temp.expect_error(format('SELECT public.get_nse_mandate_status_source(%L)',op.id),'mandate_status_identity_changed');
END $$;
-- Owner review proposals: synthetic encrypted bank source, no NSE write path.
-- Reject ANY enqueue/evidence insert, even if a future regression chooses an ID
-- unrelated to the proposal. These sentinels run under the real API role below.
CREATE FUNCTION pg_temp.reject_b07_transport() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'blocked_b07_must_not_queue:%',TG_TABLE_NAME; END $$;
CREATE TRIGGER b07_no_operation BEFORE INSERT ON public.integration_operations
 FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_b07_transport();
CREATE TRIGGER b07_no_event BEFORE INSERT ON public.event_outbox
 FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_b07_transport();
CREATE TRIGGER b07_no_evidence BEFORE INSERT ON public.integration_api_interactions
 FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_b07_transport();
SELECT 1 FROM vault.create_secret(repeat('b',40),'bank_account_encryption_key_v1','synthetic');
SELECT 1 FROM vault.create_secret(repeat('h',40),'bank_account_lookup_hmac_key_v1','synthetic');
-- Restore identity changed by the in-flight evidence test above.
UPDATE public.integration_accounts SET external_account_id='SYNTHETIC1' WHERE id='e0060000-0000-4000-8000-000000000001';
SELECT set_config('b07.default',(public.set_investor_bank_account('e0030000-0000-4000-8000-000000000001',
 (SELECT id FROM public.profiles WHERE user_id='e0010000-0000-4000-8000-000000000001'),'savings','12345678901','SBIN0000018',NULL,NULL,'verified',true)).id::text,true);
SELECT set_config('b07.other',(public.set_investor_bank_account('e0030000-0000-4000-8000-000000000001',
 (SELECT id FROM public.profiles WHERE user_id='e0010000-0000-4000-8000-000000000001'),'savings','12345678902','SBIN0000018',NULL,NULL,'verified',false)).id::text,true);
SELECT set_config('request.jwt.claim.sub','e0010000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'MANDATE','b0700000-0000-4000-8000-000000000001');
SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'BANK_ADD','b0700000-0000-4000-8000-000000000002');
SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'BANK_DEL','b0700000-0000-4000-8000-000000000003');
SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'BANK_ADD','b0700000-0000-4000-8000-000000000002');
SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'BANK_DEL','b0700000-0000-4000-8000-000000000003');
SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'MANDATE','b0700000-0000-4000-8000-000000000001');
SELECT pg_temp.expect_error($q$SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.default')::uuid,'BANK_DEL',gen_random_uuid())$q$,'bank_delete_default_protected');
SELECT pg_temp.expect_error($q$SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'BANK_ADD',gen_random_uuid())$q$,'bank_mandate_duplicate_intent');
SELECT pg_temp.expect_error($q$SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.default')::uuid,'MANDATE','b0700000-0000-4000-8000-000000000001')$q$,'bank_mandate_intent_conflict');
SELECT pg_temp.expect_error($q$SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000002','e0060000-0000-4000-8000-000000000002',current_setting('b07.other')::uuid,'MANDATE',gen_random_uuid())$q$,'not_authorized');
SELECT set_config('request.jwt.claim.sub','e0010000-0000-4000-8000-000000000002',true);
SELECT pg_temp.expect_error($q$SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'MANDATE',gen_random_uuid())$q$,'not_authorized');
SELECT pg_temp.expect_error($q$SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000002','e0060000-0000-4000-8000-000000000002',current_setting('b07.other')::uuid,'MANDATE',gen_random_uuid())$q$,'bank_mandate_verified_owned_bank_required');
RESET ROLE;
DROP TRIGGER b07_no_operation ON public.integration_operations;
DROP TRIGGER b07_no_event ON public.event_outbox;
DROP TRIGGER b07_no_evidence ON public.integration_api_interactions;
DO $$
DECLARE op public.integration_operations; src jsonb; i nse_bank_mandate.intents; observation jsonb; role_name text;
BEGIN
 SELECT * INTO i FROM nse_bank_mandate.intents WHERE id='b0700000-0000-4000-8000-000000000001';
 PERFORM pg_temp.assert_true((SELECT count(*)=3 AND bool_and(state='BLOCKED') FROM nse_bank_mandate.intents),'mutations_fail_closed');
 PERFORM pg_temp.assert_true((SELECT bool_and(block_reason=CASE action
   WHEN 'MANDATE' THEN 'mandate_contract_and_consent_unresolved'
   WHEN 'BANK_ADD' THEN 'bank_add_consent_and_provider_relationship_unproven'
   WHEN 'BANK_DEL' THEN 'bank_delete_dependencies_unproven' END)
   FROM nse_bank_mandate.intents),'each_write_retains_specific_blocker');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM public.event_outbox WHERE entity_id IN(SELECT id FROM nse_bank_mandate.intents)),'no_write_events');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM public.integration_operations WHERE safety_class<>'READ_ONLY' AND id IN(SELECT id FROM nse_bank_mandate.intents)),'no_write_operations');
 PERFORM pg_temp.assert_true((extensions.pgp_sym_decrypt(i.source_ciphertext,public.integration_payload_encryption_key(i.source_key_reference))::jsonb)->>'account_no'='12345678902','encrypted_owned_snapshot');
 PERFORM pg_temp.expect_error(format('UPDATE nse_bank_mandate.intents SET state=%L WHERE id=%L','BLOCKED',i.id),'bank_mandate_intent_immutable');
 PERFORM pg_temp.expect_error(format('DELETE FROM nse_bank_mandate.intents WHERE id=%L',i.id),'bank_mandate_intent_immutable');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM pg_temp.assert_true(NOT has_table_privilege(role_name,'nse_bank_mandate.intents','SELECT,INSERT,UPDATE,DELETE'),'private_intent_acl');
 END LOOP;
 PERFORM pg_temp.assert_true((SELECT relrowsecurity FROM pg_class WHERE oid='nse_bank_mandate.intents'::regclass),'intent_rls');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='nse_bank_mandate'),'no_browser_policies');
 op:=public.prepare_nse_mandate_status(i.workspace_id,i.integration_account_id,'MANDATE_STATUS',jsonb_build_object('intent_id',i.id));
 src:=public.get_nse_mandate_status_source(op.id);
 PERFORM pg_temp.assert_true(src->'request'=jsonb_build_object('memberMandateIds',i.member_mandate_no),'C031_exact_owned_member_filter');
 observation:=public.inspect_nse_mandate_status_response('MANDATE_STATUS',jsonb_build_object('response_status','S','report_data_total',1,'error_remark','','report_data',jsonb_build_array(jsonb_build_object('mandateId','123','clientCode','SYNTHETIC1','memberCode','TEST','memberMandateId',i.member_mandate_no,'bankAccountNumber','12345678902','status','APPROVED')))::text,src->'request',src);
 PERFORM pg_temp.assert_true((observation->>'success')::bool,'unique_positive_member_match');
 PERFORM pg_temp.assert_true(NOT (public.inspect_nse_mandate_status_response('MANDATE_STATUS',jsonb_build_object('response_status','S','report_data_total',1,'error_remark','','report_data',jsonb_build_array(jsonb_build_object('mandateId','123','clientCode','SYNTHETIC1','memberCode','TEST','memberMandateId',i.member_mandate_no,'bankAccountNumber','FOREIGN','status','APPROVED')))::text,src->'request',src)->>'success')::bool,'foreign_bank_not_positive_match');
 PERFORM pg_temp.assert_true((SELECT state='BLOCKED' FROM nse_bank_mandate.intents WHERE id=i.id),'status_not_legal_authority');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_mandate_status(%L,%L,%L,%L)',
 'e0030000-0000-4000-8000-000000000002','e0060000-0000-4000-8000-000000000002','MANDATE_STATUS',jsonb_build_object('intent_id',i.id)),'mandate_status_intent_scope_invalid');
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_mandate_status(%L,%L,%L,%L)',i.workspace_id,i.integration_account_id,'MANDATE_STATUS',jsonb_build_object('memberMandateIds',i.member_mandate_no)),'mandate_status_filters_invalid');
END $$;


-- Current investor membership is checked, irrespective of forged elevated claims.
SELECT set_config('request.jwt.claim.sub','e0010000-0000-4000-8000-000000000001',true);
UPDATE public.workspace_memberships SET status='inactive' WHERE workspace_id='e0030000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_error($q$SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'MANDATE',gen_random_uuid())$q$,'not_authorized');
RESET ROLE;
UPDATE public.workspace_memberships SET status='active',role='operations' WHERE workspace_id='e0030000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_error($q$SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.other')::uuid,'MANDATE',gen_random_uuid())$q$,'not_authorized');
RESET ROLE;
SELECT pg_temp.assert_true((SELECT count(*)=3 FROM public.workspace_audit_logs WHERE action='nse.bank_mandate.review_requested'),'one_audit_per_distinct_review');
SELECT pg_temp.expect_error($q$DELETE FROM public.workspace_audit_logs WHERE action='nse.bank_mandate.review_requested'$q$,'immutable');
ROLLBACK;
