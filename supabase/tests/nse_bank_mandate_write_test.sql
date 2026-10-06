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

SELECT 1 FROM vault.create_secret(repeat('b',40),'bank_account_encryption_key_v1','synthetic');
SELECT 1 FROM vault.create_secret(repeat('h',40),'bank_account_lookup_hmac_key_v1','synthetic');
SELECT set_config('b07.bank',(public.set_investor_bank_account('e0030000-0000-4000-8000-000000000001',
 (SELECT id FROM public.profiles WHERE user_id='e0010000-0000-4000-8000-000000000001'),'savings','12345678902','SBIN0000018',NULL,NULL,'verified',false)).id::text,true);
SELECT set_config('request.jwt.claim.sub','e0010000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_ADD','{"default_bank_flag":"N"}','b0710000-0000-4000-8000-000000000001');
SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_ADD','{"default_bank_flag":"N"}','b0710000-0000-4000-8000-000000000001');
SELECT pg_temp.expect_error($q$SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_ADD','{"default_bank_flag":"Y"}','b0710000-0000-4000-8000-000000000001')$q$,'b07_intent_conflict');
SELECT pg_temp.expect_error($q$SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_ADD','{"default_bank_flag":"N","account_no":"SUBSTITUTE"}',gen_random_uuid())$q$,'b07_terms_invalid');
DO $$ DECLARE k text;BEGIN
 FOREACH k IN ARRAY ARRAY['client_code','PAN','account_no','authority'] LOOP
  PERFORM pg_temp.expect_error(format('SELECT public.draft_nse_bank_mandate_write(%L,%L,%L,%L,%L,gen_random_uuid())',
  'e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank'),'BANK_ADD',jsonb_build_object('default_bank_flag','N',k,'SUBSTITUTE')),'b07_terms_invalid');
 END LOOP;
 PERFORM pg_temp.expect_error(format('SELECT public.draft_nse_bank_mandate_write(%L,%L,%L,%L,%L,gen_random_uuid())',
  'e0030000-0000-4000-8000-000000000002','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank'),'BANK_ADD','{"default_bank_flag":"N"}'),'b07_owner_required');
 PERFORM pg_temp.expect_error(format('SELECT public.draft_nse_bank_mandate_write(%L,%L,%L,%L,%L,gen_random_uuid())',
  'e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank'),'BANK_ADD','{"default_bank_flag":null}'),'b07_terms_invalid');
END $$;
SELECT pg_temp.assert_true(NOT (public.get_nse_bank_mandate_draft('b0710000-0000-4000-8000-000000000001')->>'approved')::boolean,'draft_not_approval');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.expect_error($q$SELECT public.prepare_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000001')$q$,'b07_approved_authority_required');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000001',1);
SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000001',1);
SELECT set_config('request.jwt.claim.sub','e0010000-0000-4000-8000-000000000002',true);
SELECT pg_temp.expect_error($q$SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000001',1)$q$,'b07_owner_required');
SELECT set_config('request.jwt.claim.sub','e0010000-0000-4000-8000-000000000001',true);
RESET ROLE;
SELECT pg_temp.expect_error($q$SELECT public.prepare_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000001')$q$,'b07_designated_uat_case_required');
SELECT pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM public.integration_operations),'no_transport_before_designation');
SELECT pg_temp.expect_error($q$UPDATE nse_bank_mandate.write_intents SET business_terms='{}'$q$,'bank_mandate_intent_immutable');
SELECT pg_temp.expect_error($q$DELETE FROM nse_bank_mandate.approvals$q$,'bank_mandate_intent_immutable');

SAVEPOINT revoked_authority;
SET LOCAL ROLE authenticated;
SELECT public.revoke_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000001');
RESET ROLE;
SELECT pg_temp.expect_error($q$SELECT public.prepare_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000001')$q$,'b07_approved_authority_required');
ROLLBACK TO SAVEPOINT revoked_authority;

-- Owner-only synthetic ledger setup; this is not provider UAT evidence.
CREATE FUNCTION pg_temp.baseline(api text,body text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE op uuid:=gen_random_uuid(); call uuid:=gen_random_uuid(); rid uuid;
BEGIN
 INSERT INTO public.integration_operations(id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state)
 VALUES(op,'e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001','NSE_INVEST','UAT','RECONCILIATION','READ_ONLY','B07_SYNTHETIC_BASELINE',api,'NNF_1.9.7','SUCCESS');
 INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,started_at,request_payload_ciphertext,request_header_metadata,request_content_type,request_bytes,request_hash,normalized_outcome)
 SELECT workspace_id,id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,'/synthetic','POST',call,'REQUEST',1,correlation_id,'integration_payload_encryption_key_v1',1,now(),extensions.pgp_sym_encrypt('{"client_code":"SYNTHETIC1"}',public.integration_payload_encryption_key('integration_payload_encryption_key_v1')),'{}','application/json',28,extensions.digest('{"client_code":"SYNTHETIC1"}','sha256'),'REQUEST_RECORDED' FROM public.integration_operations WHERE id=op;
 INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,started_at,response_payload_ciphertext,response_header_metadata,response_bytes,response_hash,http_status,http_success,completed_at,elapsed_ms,normalized_outcome)
 SELECT workspace_id,id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,'/synthetic','POST',call,'RESULT',1,correlation_id,'integration_payload_encryption_key_v1',1,now(),extensions.pgp_sym_encrypt(body,public.integration_payload_encryption_key('integration_payload_encryption_key_v1')),'{}',octet_length(body),extensions.digest(body,'sha256'),200,true,now(),0,'SUCCESS' FROM public.integration_operations WHERE id=op RETURNING id INTO rid;
 RETURN rid;
END $$;
INSERT INTO nse_bank_mandate.uat_cases(bank_account_id,integration_account_id,designation_reference,designation_sha256,baseline_client_result_id,baseline_mandate_result_id,expires_at)
VALUES(current_setting('b07.bank')::uuid,'e0060000-0000-4000-8000-000000000001',gen_random_uuid(),extensions.digest('synthetic designation','sha256'),
 pg_temp.baseline('CLIENT_MASTER_REPORT','{"response_status":"S","error_remark":"","report_data_total":1,"report_data":[{"client_code":"SYNTHETIC1"}]}'),
 pg_temp.baseline('MANDATE_STATUS','{"response_status":"S","error_remark":"","report_data_total":0,"report_data":[]}'),now()+interval '1 hour');


-- A private database-operator designation may authorize a synthetic UAT fixture
-- without fabricating an end-user Auth identity. Runtime roles cannot call it.
SAVEPOINT operator_uat_authority;
DO $$
DECLARE
  c nse_bank_mandate.uat_cases;
  op uuid := 'b0720000-0000-4000-8000-000000000001';
BEGIN
  SELECT * INTO c FROM nse_bank_mandate.uat_cases
   WHERE bank_account_id=current_setting('b07.bank')::uuid
     AND integration_account_id='e0060000-0000-4000-8000-000000000001';

  PERFORM pg_temp.assert_true(
    NOT has_function_privilege(
      'authenticated',
      'nse_bank_mandate.create_operator_uat_intent(uuid,uuid,uuid,text,jsonb,uuid,uuid,bytea)',
      'EXECUTE')
    AND NOT has_function_privilege(
      'service_role',
      'nse_bank_mandate.create_operator_uat_intent(uuid,uuid,uuid,text,jsonb,uuid,uuid,bytea)',
      'EXECUTE'),
    'operator_uat_helper_private');

  PERFORM nse_bank_mandate.create_operator_uat_intent(
    'e0030000-0000-4000-8000-000000000001',
    'e0060000-0000-4000-8000-000000000001',
    current_setting('b07.bank')::uuid,
    'BANK_ADD',
    '{"default_bank_flag":"N"}',
    op,
    c.designation_reference,
    c.designation_sha256);

  PERFORM pg_temp.assert_true(
    (SELECT authority_mode='UAT_OPERATOR'
      AND actor_user_id IS NULL
      AND operator_designation_reference=c.designation_reference
      AND operator_designation_sha256=c.designation_sha256
     FROM nse_bank_mandate.write_intents
     WHERE id=op),
    'operator_uat_intent_frozen');

  PERFORM pg_temp.assert_true(
    NOT EXISTS(SELECT 1 FROM nse_bank_mandate.approvals WHERE intent_id=op),
    'operator_uat_no_fake_investor_approval');

  PERFORM pg_temp.assert_true(
    public.prepare_nse_bank_mandate_write(op)=op,
    'operator_uat_prepare_allowed');

  PERFORM pg_temp.assert_true(
    EXISTS(SELECT 1 FROM public.integration_operations
      WHERE id=op AND operation_type='BANK_MANDATE_WRITE' AND state='QUEUED')
    AND EXISTS(SELECT 1 FROM public.event_outbox
      WHERE entity_id=op
        AND event_type='integration.nse.bank_add_requested'
        AND status='pending'),
    'operator_uat_real_runtime_path');
END $$;
ROLLBACK TO SAVEPOINT operator_uat_authority;

SAVEPOINT changed_account_owner;
UPDATE public.integration_accounts SET investor_profile_id=(SELECT id FROM public.profiles WHERE user_id='e0010000-0000-4000-8000-000000000002') WHERE id='e0060000-0000-4000-8000-000000000001';
SELECT pg_temp.expect_error($q$SELECT public.prepare_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000001')$q$,'b07_approved_authority_required');
ROLLBACK TO SAVEPOINT changed_account_owner;

CREATE FUNCTION pg_temp.begin_write(op uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE e uuid; c jsonb; src jsonb; call uuid:=gen_random_uuid(); req uuid;
BEGIN
 SELECT id INTO e FROM public.event_outbox WHERE entity_id=op;
 c:=public.claim_nse_bank_mandate_write(e);src:=public.get_nse_bank_mandate_write_source(op);
 req:=public.start_nse_bank_mandate_write(e,(c->>'claim_token')::uuid,call,(src->'request')::text,'{"content_type":"application/json","accept":"application/json"}',now());
 PERFORM pg_temp.assert_true(public.start_nse_bank_mandate_write(e,(c->>'claim_token')::uuid,call,(src->'request')::text,'{"content_type":"application/json","accept":"application/json"}',now())=req,'request_replay');
 PERFORM pg_temp.assert_true((SELECT extensions.pgp_sym_decrypt(request_payload_ciphertext,public.integration_payload_encryption_key(payload_encryption_key_reference))=(src->'request')::text FROM public.integration_api_interactions WHERE id=req),'exact_encrypted_request');
 PERFORM pg_temp.assert_true(public.claim_nse_bank_mandate_write(e) IS NULL,'exclusive_claim');
 RETURN c||jsonb_build_object('call',call);
END $$;
CREATE FUNCTION pg_temp.complete(c jsonb,body text,delivery text DEFAULT 'SENT_WITH_RESULT') RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.finish_nse_bank_mandate_write((c->>'event_id')::uuid,(c->>'claim_token')::uuid,(c->>'call')::uuid,replace(encode(convert_to(body,'UTF8'),'base64'),E'\n',''),CASE delivery WHEN 'SENT_WITH_RESULT' THEN 200 ELSE NULL END,'{}',delivery,now())
$$;
-- A positive read resolves ambiguous ADD, but cannot authorize deleting it.
SAVEPOINT ambiguous_add;
DO $$ DECLARE op uuid:='b0710000-0000-4000-8000-000000000001';c jsonb;v uuid:=gen_random_uuid();BEGIN
 PERFORM public.prepare_nse_bank_mandate_write(op);c:=pg_temp.begin_write(op);
 PERFORM pg_temp.complete(c,'','MAYBE_SENT');
 PERFORM public.prepare_nse_bank_mandate_verification(op,v);c:=pg_temp.begin_write(v);
 PERFORM pg_temp.complete(c,'{"response_status":"S","error_remark":"","report_data_total":1,"report_data":[{"client_code":"SYNTHETIC1","account_no_1":"12345678902","account_type_1":"SB","ifsc_code_1":"SBIN0000018","micr_no_1":"","default_bank_flag_1":"NO"}]}');
 PERFORM public.reconcile_nse_bank_mandate_write(v);
 PERFORM pg_temp.assert_true((SELECT state='SUCCESS' FROM public.integration_operations WHERE id=op),'ambiguous_add_reconciled');
END $$;
SET LOCAL ROLE authenticated;
SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_DEL','{"default_bank_flag":"N"}','b0710000-0000-4000-8000-000000000008');
SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000008',1);
RESET ROLE;
SELECT pg_temp.expect_error($q$SELECT public.prepare_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000008')$q$,'b07_fresh_created_relationship_required');
ROLLBACK TO SAVEPOINT ambiguous_add;

-- Provider HTTP 400/403 are definitive write rejections, matching the existing
-- UCC write policy. They must not strand the operation as MAYBE_SENT.
SAVEPOINT definitive_http;
DO $$ DECLARE op uuid:='b0710000-0000-4000-8000-000000000001'; c jsonb; raw text:='{"error":"synthetic validation rejection"}';BEGIN
 PERFORM public.prepare_nse_bank_mandate_write(op);c:=pg_temp.begin_write(op);
 PERFORM public.finish_nse_bank_mandate_write((c->>'event_id')::uuid,(c->>'claim_token')::uuid,(c->>'call')::uuid,
  replace(encode(convert_to(raw,'UTF8'),'base64'),E'\n',''),400,'{}','SENT_WITH_RESULT',now());
 PERFORM pg_temp.assert_true((SELECT state='HTTP_FAILED' AND NOT retry_allowed AND NOT ambiguous_outcome AND NOT reconciliation_required FROM public.integration_operations WHERE id=op),'write_http_400_definitive');
END $$;
ROLLBACK TO SAVEPOINT definitive_http;

DO $$ DECLARE op uuid:='b0710000-0000-4000-8000-000000000001'; c jsonb; r jsonb; result jsonb; verification uuid:=gen_random_uuid(); body text;
BEGIN
 PERFORM pg_temp.assert_true(public.prepare_nse_bank_mandate_write(op)=op AND public.prepare_nse_bank_mandate_write(op)=op,'stable_operation');
 c:=pg_temp.begin_write(op);
 result:=pg_temp.complete(c,'','PROVEN_NOT_SENT');
 PERFORM pg_temp.assert_true((SELECT retry_allowed AND state='SUBMISSION_FAILED' FROM public.integration_operations WHERE id=op),'only_not_sent_retry');
 c:=pg_temp.begin_write(op);
 PERFORM pg_temp.expect_error(format('SELECT public.finish_nse_bank_mandate_write(%L,%L,%L,%L,200,%L,%L,now())',c->>'event_id',gen_random_uuid(),c->>'call','','{}','SENT_WITH_RESULT'),'claim_not_owned');
 r:=nse_bank_mandate.request(op)->'bank_dtl'->0;
 body:=jsonb_build_object('bank_dtl',jsonb_build_array((r-'default_bank_flag')||'{"status":"SUCCESS","error_remark":""}'))::text;
 result:=pg_temp.complete(c,body);
 PERFORM pg_temp.assert_true(pg_temp.complete(c,body)=result,'result_ack_replay');
 PERFORM pg_temp.assert_true((SELECT convert_from(extensions.pgp_sym_decrypt_bytea(response_payload_ciphertext,public.integration_payload_encryption_key(payload_encryption_key_reference)),'UTF8')=body FROM public.integration_api_interactions WHERE id=(result->>'result_id')::uuid),'exact_encrypted_result');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM nse_bank_mandate.bank_relationships),'no_projection_before_read');
 PERFORM public.prepare_nse_bank_mandate_verification(op,verification);c:=pg_temp.begin_write(verification);
 body:='{"response_status":"S","error_remark":"","report_data_total":1,"report_data":[{"client_code":"SYNTHETIC1","account_no_1":"12345678902","account_type_1":"SB","ifsc_code_1":"SBIN0000018","micr_no_1":"","default_bank_flag_1":"NO"}]}';
 PERFORM pg_temp.complete(c,body);PERFORM public.reconcile_nse_bank_mandate_write(verification);
 PERFORM pg_temp.assert_true((SELECT count(*)=1 AND bool_and(NOT is_default) FROM nse_bank_mandate.bank_relationships),'verified_provider_relationship');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,body)='MATCH','positive');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,replace(body,'SYNTHETIC1','FOREIGN'))='MISMATCH','foreign');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,replace(body,'SBIN0000018','SBIN0000019'))='MISMATCH','mismatch');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,'{"response_status":"S","error_remark":"","report_data_total":0,"report_data":[]}')='ZERO','zero');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,'{"response_status":"S","error_remark":"","report_data_total":2,"report_data":[{},{}]}')='MULTIPLE','multiple');
END $$;

-- Verification is READ_BOUNDED: uncertain read transport is evidence, not a
-- mutation ambiguity, and remains safely retryable within the attempt cap.
SAVEPOINT verification_transport;
DO $$ DECLARE v uuid:=gen_random_uuid();c jsonb; next_claim jsonb;BEGIN
 PERFORM public.prepare_nse_bank_mandate_verification('b0710000-0000-4000-8000-000000000001',v);c:=pg_temp.begin_write(v);
 PERFORM pg_temp.complete(c,'','PROVEN_NOT_SENT');
 PERFORM pg_temp.assert_true((SELECT state='SUBMISSION_FAILED' AND retry_allowed FROM public.integration_operations WHERE id=v),'read_not_sent_persisted');
 c:=pg_temp.begin_write(v);PERFORM pg_temp.complete(c,'','MAYBE_SENT');
 PERFORM pg_temp.assert_true((SELECT count(*)=4 FROM public.integration_api_interactions WHERE integration_operation_id=v),'read_failure_exact_evidence');
 PERFORM pg_temp.assert_true((SELECT state='SUBMISSION_FAILED' AND retry_allowed AND NOT ambiguous_outcome AND NOT reconciliation_required FROM public.integration_operations WHERE id=v),'read_maybe_sent_retryable');
 next_claim:=public.claim_nse_bank_mandate_write((c->>'event_id')::uuid);
 PERFORM pg_temp.assert_true(next_claim IS NOT NULL AND (next_claim->>'attempt')::int=3,'read_maybe_sent_safe_retry');
END $$;
ROLLBACK TO SAVEPOINT verification_transport;

-- A newer contradictory provider read overrides an older positive relationship.
SAVEPOINT changed_provider_default;
SET LOCAL ROLE authenticated;
SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_DEL','{"default_bank_flag":"N"}','b0710000-0000-4000-8000-000000000007');
SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000007',1);
RESET ROLE;
DO $$ DECLARE v uuid:=gen_random_uuid();c jsonb;body text;BEGIN
 PERFORM public.prepare_nse_bank_mandate_verification('b0710000-0000-4000-8000-000000000001',v);c:=pg_temp.begin_write(v);
 body:='{"response_status":"S","error_remark":"","report_data_total":1,"report_data":[{"client_code":"SYNTHETIC1","account_no_1":"12345678902","account_type_1":"SB","ifsc_code_1":"SBIN0000018","micr_no_1":"","default_bank_flag_1":"YES"}]}';
 PERFORM public.finish_nse_bank_mandate_write((c->>'event_id')::uuid,(c->>'claim_token')::uuid,(c->>'call')::uuid,replace(encode(convert_to(body,'UTF8'),'base64'),E'\n',''),200,'{}','SENT_WITH_RESULT',clock_timestamp());
 PERFORM pg_temp.expect_error($q$SELECT public.prepare_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000007')$q$,'b07_fresh_created_relationship_required');
END $$;
ROLLBACK TO SAVEPOINT changed_provider_default;

-- Independent mandate branch; rollback its authority/dependency before DEL.
SAVEPOINT mandate_branch;
SET LOCAL ROLE authenticated;
SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'MANDATE',
 jsonb_build_object('amount','100.00','mandate_type','X','processing','PROVIDER','start_date',to_char(current_date,'DD/MM/YYYY'),'end_date',to_char(current_date+365,'DD/MM/YYYY')),'b0710000-0000-4000-8000-000000000003');
SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000003',1);
RESET ROLE;
DO $$ DECLARE op uuid:='b0710000-0000-4000-8000-000000000003'; c jsonb; r jsonb; body text; v uuid:=gen_random_uuid();row jsonb;
BEGIN
 PERFORM public.prepare_nse_bank_mandate_write(op);c:=pg_temp.begin_write(op);r:=nse_bank_mandate.request(op)->'reg_data'->0;
 PERFORM pg_temp.assert_true(NOT(r ? 'micr_no') AND NOT(r ? 'micr_code') AND NOT(r ? 'registration_date'),'optional_omission_subset');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,false,jsonb_build_object('reg_data',jsonb_build_array(r||'{"reg_status":"REG_SUCCESS","reg_id":"123","reg_remark":""}'))::text)='SUCCESS','native_mandate_success');
 PERFORM pg_temp.complete(c,'','MAYBE_SENT');
 PERFORM pg_temp.assert_true(public.claim_nse_bank_mandate_write((c->>'event_id')::uuid) IS NULL,'mandate_maybe_sent_no_resend');
 PERFORM public.prepare_nse_bank_mandate_verification(op,v);c:=pg_temp.begin_write(v);
 row:=jsonb_build_object('mandateId','123','clientCode',r->>'client_code','memberMandateId',r->>'member_mandate_no','bankAccountNumber',r->>'account_no','amount','100','mandateType','X','startDate',r->>'start_date','endDate',r->>'end_date','status','PENDING');
 body:=jsonb_build_object('response_status','S','error_remark','','report_data_total',1,'report_data',jsonb_build_array(row))::text;
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,body)='MATCH','frozen_visible_terms_match');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,replace(body,'PENDING','APPROVED'))='MATCH','status_not_authority');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,replace(body,r->>'member_mandate_no','FOREIGN'))='MISMATCH','foreign_reference');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,replace(body,'"amount": "100"','"amount": "101"'))='MISMATCH','mandate_amount_mismatch');
 PERFORM pg_temp.complete(c,body);PERFORM public.reconcile_nse_bank_mandate_write(v);
 PERFORM pg_temp.assert_true((SELECT state='SUCCESS' AND NOT reconciliation_required AND reconciliation_resolution_operation_id=v FROM public.integration_operations WHERE id=op),'positive_read_resolves_ambiguous_write');
END $$;
SET LOCAL ROLE authenticated;
SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_DEL','{"default_bank_flag":"N"}','b0710000-0000-4000-8000-000000000004');
SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000004',1);
RESET ROLE;
SELECT pg_temp.expect_error($q$SELECT public.prepare_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000004')$q$,'b07_bank_dependencies_present');
ROLLBACK TO SAVEPOINT mandate_branch;

-- Expired lease after persisted REQUEST creates missing-result evidence and stops.
SAVEPOINT expired_branch;
SET LOCAL ROLE authenticated;
SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_DEL','{"default_bank_flag":"N"}','b0710000-0000-4000-8000-000000000005');
SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000005',1);
RESET ROLE;
DO $$ DECLARE op uuid:='b0710000-0000-4000-8000-000000000005'; c jsonb;
BEGIN
 UPDATE public.investor_bank_accounts SET is_default=true WHERE id=current_setting('b07.bank')::uuid;
 PERFORM pg_temp.expect_error(format('SELECT public.prepare_nse_bank_mandate_write(%L)',op),'b07_default_delete_protected');
 UPDATE public.investor_bank_accounts SET is_default=false WHERE id=current_setting('b07.bank')::uuid;
 PERFORM public.prepare_nse_bank_mandate_write(op);c:=pg_temp.begin_write(op);
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=(c->>'event_id')::uuid;
 PERFORM pg_temp.assert_true(public.claim_nse_bank_mandate_write((c->>'event_id')::uuid) IS NULL,'expired_after_request_not_claimed');
 PERFORM pg_temp.assert_true((SELECT count(*)=2 FROM public.integration_api_interactions WHERE integration_operation_id=op),'expired_missing_result_closed');
 PERFORM pg_temp.assert_true((SELECT state='RECONCILIATION_REQUIRED' AND NOT retry_allowed FROM public.integration_operations WHERE id=op),'expired_requires_reconciliation');
END $$;
ROLLBACK TO SAVEPOINT expired_branch;

SAVEPOINT delete_success;
SET LOCAL ROLE authenticated;
SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_DEL','{"default_bank_flag":"N"}','b0710000-0000-4000-8000-000000000006');
SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000006',1);
RESET ROLE;
DO $$ DECLARE op uuid:='b0710000-0000-4000-8000-000000000006';c jsonb;r jsonb;BEGIN
 PERFORM public.prepare_nse_bank_mandate_write(op);c:=pg_temp.begin_write(op);r:=nse_bank_mandate.request(op)->'bank_dtl'->0;
 PERFORM pg_temp.complete(c,jsonb_build_object('bank_dtl',jsonb_build_array((r-'default_bank_flag')||'{"status":"SUCCESS","error_remark":""}'))::text);
 PERFORM pg_temp.assert_true((SELECT count(*)=1 FROM nse_bank_mandate.bank_deletion_receipts WHERE operation_id=op),'positive_delete_receipt');
 PERFORM pg_temp.assert_true((SELECT is_active FROM public.investor_bank_accounts WHERE id=current_setting('b07.bank')::uuid),'canonical_bank_unchanged');
END $$;
ROLLBACK TO SAVEPOINT delete_success;

SET LOCAL ROLE authenticated;
SELECT public.draft_nse_bank_mandate_write('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001',current_setting('b07.bank')::uuid,'BANK_DEL','{"default_bank_flag":"N"}','b0710000-0000-4000-8000-000000000002');
SELECT public.approve_nse_bank_mandate_write('b0710000-0000-4000-8000-000000000002',1);
RESET ROLE;
DO $$ DECLARE op uuid:='b0710000-0000-4000-8000-000000000002'; c jsonb; body text;
BEGIN
 PERFORM public.prepare_nse_bank_mandate_write(op);c:=pg_temp.begin_write(op);
 PERFORM pg_temp.complete(c,'','MAYBE_SENT');
 PERFORM pg_temp.assert_true((SELECT state='RECONCILIATION_REQUIRED' AND NOT retry_allowed FROM public.integration_operations WHERE id=op),'maybe_sent_no_retry');
 PERFORM pg_temp.assert_true(public.claim_nse_bank_mandate_write((c->>'event_id')::uuid) IS NULL,'ambiguous_cannot_claim');
 PERFORM pg_temp.assert_true(nse_bank_mandate.classify(op,true,'{"response_status":"S","error_remark":"","report_data_total":0,"report_data":[]}')='ZERO','absence_not_delete_proof');
END $$;
-- Every API role is denied the private authority/designation/projection tables.
DO $$ DECLARE role_name text;t text;BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
 FOREACH t IN ARRAY ARRAY['write_intents','approvals','revocations','uat_cases','bank_relationships','bank_deletion_receipts','reconciliations'] LOOP
 PERFORM pg_temp.assert_true(NOT has_table_privilege(role_name,'nse_bank_mandate.'||t,'SELECT,INSERT,UPDATE,DELETE'),'private_tables');
 END LOOP;END LOOP;
END $$;
ROLLBACK;
