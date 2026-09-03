-- NSEInvest CLIENTCOMMON183 vertical-slice database regression. Local only.
BEGIN;

SELECT 1 FROM vault.create_secret(repeat('p', 40), 'integration_payload_encryption_key_v1', 'synthetic local test key');
SELECT 1 FROM vault.create_secret(repeat('b', 40), 'bank_account_encryption_key_v1', 'synthetic local test key');
SELECT 1 FROM vault.create_secret(repeat('h', 40), 'bank_account_lookup_hmac_key_v1', 'synthetic local test key');

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 ('c0010000-0000-4000-8000-000000000001','authenticated','authenticated','ucc-one@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now()),
 ('c0010000-0000-4000-8000-000000000002','authenticated','authenticated','ucc-two@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now()),
 ('c0010000-0000-4000-8000-000000000003','authenticated','authenticated','ucc-three@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now()),
 ('c0010000-0000-4000-8000-000000000004','authenticated','authenticated','ucc-four@moneybowl.invalid','{"user_role":"investor"}','{}',now(),now());
UPDATE public.profiles SET
 id = ('c0020000-0000-4000-8000-' || right(user_id::text, 12))::uuid,
 role='investor', full_name='MONEYBOWL SYNTHETIC',
 phone_number='000000000' || right(user_id::text, 1)
WHERE user_id::text LIKE 'c0010000-0000-4000-8000-00000000000%';
INSERT INTO public.workspaces (id,name,slug,owner_profile_id,workspace_status) VALUES
 ('c0030000-0000-4000-8000-000000000001','Synthetic UCC Test Workspace','synthetic-ucc-test','c0020000-0000-4000-8000-000000000001','active');
DELETE FROM public.workspace_memberships WHERE profile_id::text LIKE 'c0020000-0000-4000-8000-00000000000%';
INSERT INTO public.workspace_memberships (workspace_id,profile_id,role,status)
SELECT 'c0030000-0000-4000-8000-000000000001',
 ('c0020000-0000-4000-8000-00000000000' || suffix)::uuid,'investor','active'
FROM unnest(ARRAY['1','2','3','4']) suffix;

INSERT INTO public.profile_pan_records (id,profile_id,pan_ciphertext,pan_lookup_hmac,masked_pan,source,source_system,status,verified_at) VALUES
 ('c0040000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000001',
 extensions.pgp_sym_encrypt('ZZZPZ0000Z',public.pan_encryption_key(),'cipher-algo=aes256, compress-algo=0'),
 extensions.hmac('ZZZPZ0000Z',public.pan_lookup_hmac_key(),'sha256'),'******0000','INVESTOR','MANUAL','VERIFIED',now());
UPDATE public.profiles SET canonical_pan_record_id='c0040000-0000-4000-8000-000000000001'
WHERE id='c0020000-0000-4000-8000-000000000001';

-- Canonical schema supports more than the first integration slice.
INSERT INTO public.investor_registration_profiles (workspace_id,investor_profile_id,legal_name,legal_first_name,legal_last_name,investor_kind,date_of_birth,incorporation_date,gender,residency_status,occupation,holding_mode,pan_exempt,kyc_method,kyc_verified_at,communication_preference,mobile_owner_relationship,email_owner_relationship,onboarding_mode,nomination_opted_in) VALUES
 ('c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000001','MONEYBOWL SYNTHETIC','MONEYBOWL','SYNTHETIC','individual','1990-01-01',NULL,'other','resident_individual','other','single',false,'kra',now(),'electronic','self','self','paper',false),
 ('c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000002','SYNTHETIC MINOR','SYNTHETIC','MINOR','individual','2015-01-01',NULL,'other','resident_individual','student','single',false,'kra',NULL,'electronic','guardian','guardian','paper',false),
 ('c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000003','SYNTHETIC ENTITY',NULL,NULL,'non_individual',NULL,'2000-01-01',NULL,'resident_entity','business','single',false,'kra',NULL,'electronic','authorized_person','authorized_person','paper',false);
INSERT INTO public.investor_addresses (workspace_id,investor_profile_id,address_type,address_line_1,city,region,postal_code,country,is_current) VALUES
 ('c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000001','domestic','SYNTHETIC UAT ADDRESS','UATCITY','KARNATAKA','000000','INDIA',true);
SELECT 1 FROM public.set_investor_bank_account('c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000001','savings','TESTACCOUNT01','TEST0000000',NULL,'MONEYBOWL SYNTHETIC','verified',true);

DO $$
DECLARE
 v_operation public.integration_operations; v_account public.integration_accounts; v_event public.event_outbox; v_claim record;
 v_operation2 public.integration_operations; v_account2 public.integration_accounts; v_event2 public.event_outbox; v_claim2 record;
 v_operation3 public.integration_operations; v_account3 public.integration_accounts; v_event3 public.event_outbox; v_claim3 record;
 v_operation4 public.integration_operations; v_account4 public.integration_accounts; v_event4 public.event_outbox; v_claim4 record;
 v_request public.integration_api_interactions; v_result public.integration_api_interactions; v_count bigint; v_table text;
 v_verification public.integration_operations; v_verification_event public.event_outbox; v_verification_claim record;
 v_started timestamptz := '2026-09-01T12:00:00Z'; v_completed timestamptz := '2026-09-01T12:00:01Z';
 v_request_text text := '{"reg_details":[{"client_code":"MBUAT0001"}]}';
 v_request_headers jsonb := '{"content_type":"application/json","user_agent":"MoneyBowl-UAT-Test","accept":"application/json"}';
 v_response_headers jsonb := '{"content_type":"application/json","x_request_id":"synthetic-request"}';
BEGIN
 FOREACH v_table IN ARRAY ARRAY['investor_registration_profiles','investor_addresses','investor_bank_accounts','integration_accounts','integration_operations','integration_api_interactions'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=v_table AND c.relrowsecurity) THEN RAISE EXCEPTION 'rls_not_enabled:%',v_table; END IF;
  IF has_table_privilege('authenticated','public.'||v_table,'SELECT') OR has_table_privilege('authenticated','public.'||v_table,'INSERT') OR has_table_privilege('authenticated','public.'||v_table,'UPDATE') OR has_table_privilege('authenticated','public.'||v_table,'DELETE') THEN RAISE EXCEPTION 'browser_table_privilege:%',v_table; END IF;
 END LOOP;
 IF has_function_privilege('authenticated','public.prepare_nse_ucc_registration(uuid,uuid,jsonb)','EXECUTE') OR NOT has_function_privilege('service_role','public.prepare_nse_ucc_registration(uuid,uuid,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'rpc_privilege_invalid'; END IF;
 IF NOT public.integration_payload_has_forbidden_key('{"nested":{"Authorization":"forbidden"}}') THEN RAISE EXCEPTION 'credential_guard_failed'; END IF;
 IF public.integration_header_metadata_is_safe('{"authorization":"forbidden"}','REQUEST') OR NOT public.integration_header_metadata_is_safe(v_request_headers,'REQUEST') THEN RAISE EXCEPTION 'header_allowlist_failed'; END IF;
 BEGIN
  PERFORM public.claim_nse_ucc_registration_event(NULL,2,120);
  RAISE EXCEPTION 'null_event_claim_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'event_outbox_id_required')=0 THEN RAISE; END IF; END;

 BEGIN
  PERFORM public.prepare_nse_ucc_registration('c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000001','{"external_account_candidate":"MBUAT0001","ucc_mode":"physical","pan":"forbidden","nse_codes":{}}');
  RAISE EXCEPTION 'metadata_allowlist_not_enforced';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'invalid_integration_metadata')=0 THEN RAISE; END IF; END;

 SELECT * INTO v_operation FROM public.prepare_nse_ucc_registration('c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000001',
 '{"external_account_candidate":"MBUAT0001","ucc_mode":"physical","nse_codes":{"tax_status":"01","occupation_code":"08","state":"KA","country":"INDIA","mobile_declaration_flag":"SE","email_declaration_flag":"SE","div_pay_mode":"04"}}');
 SELECT * INTO v_account FROM public.integration_accounts WHERE id=v_operation.integration_account_id;
 IF v_operation.integration_key<>'NSE_INVEST' OR v_operation.integration_environment<>'UAT' OR v_operation.category<>'CLIENT' OR v_operation.safety_class<>'WRITE_CLIENT' OR v_operation.operation_type<>'UCC_REGISTRATION' OR v_operation.api_key<>'CLIENTCOMMON183' OR v_operation.contract_version<>'NNF_1.9.7' THEN RAISE EXCEPTION 'classification_invalid'; END IF;
 IF v_account.integration_metadata ? 'pan' OR v_account.integration_metadata ? 'bank' THEN RAISE EXCEPTION 'account_duplicates_pii'; END IF;
 SELECT * INTO v_event FROM public.event_outbox WHERE entity_id=v_operation.id;
 IF v_event.event_type<>'integration.nse.ucc_registration_requested' OR v_event.entity_type<>'integration_operation' OR v_event.payload ? 'pan' THEN RAISE EXCEPTION 'outbox_invalid'; END IF;
 IF public.get_nse_ucc_registration_source(v_operation.id)->>'external_account_candidate'<>'MBUAT0001' OR public.get_nse_ucc_registration_source(v_operation.id)->>'investor_kind'<>'individual' OR NOT (public.get_nse_ucc_registration_source(v_operation.id)->>'kyc_verified')::bool THEN RAISE EXCEPTION 'source_projection_invalid'; END IF;

 SELECT * INTO v_claim FROM public.claim_nse_ucc_registration_event(v_event.id,2,120);
 SELECT * INTO v_request FROM public.start_nse_ucc_submission(v_event.id,v_claim.claim_token,'c0050000-0000-4000-8000-000000000001',v_request_text,'application/json',v_request_headers,v_started);
 -- Identical replay is idempotent; conflicting replay is rejected.
 IF (public.start_nse_ucc_submission(v_event.id,v_claim.claim_token,'c0050000-0000-4000-8000-000000000001',v_request_text,'application/json',v_request_headers,v_started)).id<>v_request.id THEN RAISE EXCEPTION 'request_idempotency_failed'; END IF;
 BEGIN
  PERFORM public.start_nse_ucc_submission(v_event.id,v_claim.claim_token,'c0050000-0000-4000-8000-000000000001','{"reg_details":[{"client_code":"CONFLICT"}]}','application/json',v_request_headers,v_started);
  RAISE EXCEPTION 'request_conflict_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_request_idempotency_conflict')=0 THEN RAISE; END IF; END;
 IF v_request.payload_encryption_key_reference<>'integration_payload_encryption_key_v1' OR v_request.payload_encryption_key_version<>1 OR extensions.pgp_sym_decrypt(v_request.request_payload_ciphertext,public.integration_payload_encryption_key(v_request.payload_encryption_key_reference))<>v_request_text THEN RAISE EXCEPTION 'request_encryption_invalid'; END IF;
 SELECT * INTO v_result FROM public.finish_nse_ucc_submission(v_event.id,v_claim.claim_token,v_request.call_id,'',NULL,'{}',NULL,v_completed,10,NULL,NULL,'PRE_TRANSMISSION_FAILURE','synthetic_not_sent',false,true,NULL,NULL,2);
 IF (public.finish_nse_ucc_submission(v_event.id,v_claim.claim_token,v_request.call_id,'',NULL,'{}',NULL,v_completed,10,NULL,NULL,'PRE_TRANSMISSION_FAILURE','synthetic_not_sent',false,true,NULL,NULL,2)).id<>v_result.id THEN RAISE EXCEPTION 'result_idempotency_failed'; END IF;
 BEGIN
  PERFORM public.finish_nse_ucc_submission(v_event.id,v_claim.claim_token,v_request.call_id,'',NULL,'{}',NULL,v_completed,10,NULL,NULL,'PRE_TRANSMISSION_FAILURE','conflict',false,true,NULL,NULL,2);
  RAISE EXCEPTION 'result_conflict_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_result_idempotency_conflict')=0 THEN RAISE; END IF; END;
 SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id;
 IF v_operation.state<>'SUBMISSION_FAILED' OR NOT v_operation.retry_allowed THEN RAISE EXCEPTION 'first_not_sent_retry_invalid'; END IF;

 SELECT * INTO v_claim FROM public.claim_nse_ucc_registration_event(v_event.id,2,120);
 SELECT * INTO v_request FROM public.start_nse_ucc_submission(v_event.id,v_claim.claim_token,'c0050000-0000-4000-8000-000000000002','{"reg_details":[{"client_code":"MBUAT0001","attempt":"2"}]}','application/json',v_request_headers,v_started+interval '1 minute');
 SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id; SELECT * INTO v_account FROM public.integration_accounts WHERE id=v_account.id;
 IF v_operation.completed_at IS NOT NULL OR v_operation.native_business_status IS NOT NULL OR v_operation.retry_allowed OR v_account.state<>'REGISTRATION_PENDING' THEN RAISE EXCEPTION 'retry_cleanup_invalid'; END IF;
 PERFORM public.finish_nse_ucc_submission(v_event.id,v_claim.claim_token,v_request.call_id,'',NULL,'{}',NULL,v_completed+interval '1 minute',10,NULL,NULL,'PRE_TRANSMISSION_FAILURE','synthetic_not_sent',false,true,NULL,NULL,2);
 SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id; SELECT * INTO v_event FROM public.event_outbox WHERE id=v_event.id;
 IF v_operation.state<>'SUBMISSION_FAILED' OR v_operation.retry_allowed OR v_event.status<>'failed' THEN RAISE EXCEPTION 'retry_exhaustion_invalid'; END IF;
 IF (SELECT claim_state FROM public.claim_nse_ucc_registration_event(v_event.id,2,120))<>'no_event' THEN RAISE EXCEPTION 'exhausted_event_reclaimed'; END IF;
 SELECT count(*) INTO v_count FROM public.integration_api_interactions WHERE integration_operation_id=v_operation.id; IF v_count<>4 THEN RAISE EXCEPTION 'history_overwritten'; END IF;
 BEGIN UPDATE public.integration_api_interactions SET error_category='mutation' WHERE id=v_request.id; RAISE EXCEPTION 'interaction_update_allowed'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_api_interactions_append_only')=0 THEN RAISE; END IF; END;
 BEGIN DELETE FROM public.integration_api_interactions WHERE id=v_request.id; RAISE EXCEPTION 'interaction_delete_allowed'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_api_interactions_append_only')=0 THEN RAISE; END IF; END;

 -- Success and defensive client-code correlation.
 INSERT INTO public.integration_accounts (id,workspace_id,investor_profile_id,integration_key,integration_environment,state,integration_metadata) VALUES ('c0060000-0000-4000-8000-000000000002','c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000002','NSE_INVEST','UAT','REGISTRATION_PENDING','{}') RETURNING * INTO v_account2;
 INSERT INTO public.integration_operations (id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state) VALUES ('c0070000-0000-4000-8000-000000000002',v_account2.workspace_id,v_account2.id,'NSE_INVEST','UAT','CLIENT','WRITE_CLIENT','UCC_REGISTRATION','CLIENTCOMMON183','NNF_1.9.7','QUEUED') RETURNING * INTO v_operation2;
 INSERT INTO public.event_outbox(event_type,payload,status,entity_id,entity_type) VALUES('integration.nse.ucc_registration_requested','{}','pending',v_operation2.id,'integration_operation') RETURNING * INTO v_event2;
 SELECT * INTO v_claim2 FROM public.claim_nse_ucc_registration_event(v_event2.id,2,120);
 SELECT * INTO v_request FROM public.start_nse_ucc_submission(v_event2.id,v_claim2.claim_token,'c0050000-0000-4000-8000-000000000012','{"reg_details":[{"client_code":"MBUAT0002","primary_holder_pan":"ZZZPZ0000Z"}]}','application/json',v_request_headers,v_started);
 IF (extensions.pgp_sym_decrypt(v_request.request_payload_ciphertext,public.integration_payload_encryption_key(v_request.payload_encryption_key_reference))::jsonb->'reg_details'->0->>'primary_holder_pan')<>'ZZZPZ0000Z'
    OR (extensions.pgp_sym_decrypt(v_request.request_payload_ciphertext,public.integration_payload_encryption_key(v_request.payload_encryption_key_reference))::jsonb->'reg_details'->0 ? 'pan') THEN
  RAISE EXCEPTION 'registration_request_contract_shape_invalid';
 END IF;
 PERFORM public.finish_nse_ucc_submission(v_event2.id,v_claim2.claim_token,'c0050000-0000-4000-8000-000000000012','{"reg_details":[{"client_code":"MBUAT0002","reg_id":"SYNTHETIC","reg_status":"REG_SUCCESS","reg_remark":""}]}','application/json',v_response_headers,200,v_completed,20,'REG_SUCCESS','none','SUCCESS',NULL,false,false,'MBUAT0002','SYNTHETIC',2);
 SELECT * INTO v_operation2 FROM public.integration_operations WHERE id=v_operation2.id; SELECT * INTO v_account2 FROM public.integration_accounts WHERE id=v_account2.id;
 IF v_operation2.state<>'SUCCESS' OR v_account2.state<>'REGISTERED' OR v_account2.external_account_id<>'MBUAT0002' THEN RAISE EXCEPTION 'success_distribution_invalid'; END IF;
 IF v_account2.current_registration_status<>'REG_SUCCESS'
    OR NOT (v_account2.integration_metadata->'nse_registration' ? 'registration_result_interaction_id')
    OR (v_account2.integration_metadata->'nse_registration' ? 'verified_from_interaction_id') THEN
  RAISE EXCEPTION 'native_registration_status_invalid';
 END IF;

 -- A successful registration is independently verified without changing NSE-native status.
 SELECT * INTO v_verification FROM public.prepare_nse_ucc_verification(v_operation2.id,'POST_REGISTRATION_VERIFICATION');
 IF public.get_nse_ucc_verification_source(v_verification.id)->>'pan'<>'ZZZPZ0000Z' THEN
  RAISE EXCEPTION 'verification_source_primary_holder_pan_invalid';
 END IF;
 SELECT * INTO v_verification_event FROM public.event_outbox WHERE entity_id=v_verification.id;
 SELECT * INTO v_verification_claim FROM public.claim_nse_ucc_verification_event(v_verification_event.id,3,120);
 SELECT * INTO v_request FROM public.start_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000031',
  '{"client_code":"MBUAT0002","PAN":"","from_date":"","to_date":""}',v_request_headers,v_started);
 IF (extensions.pgp_sym_decrypt(v_request.request_payload_ciphertext,public.integration_payload_encryption_key(v_request.payload_encryption_key_reference))::jsonb->>'PAN')<>'' THEN
  RAISE EXCEPTION 'verification_pan_transmitted';
 END IF;
 BEGIN
  PERFORM public.finish_nse_ucc_verification(
   v_verification_event.id,v_verification_claim.claim_token,v_request.call_id,
   '{"response_status":"S","report_data":[{"client_code":"MBUAT0002","primary_holder_pan":"WRONG0000X"}]}',
   'application/json',v_response_headers,200,'S','ucc_match_confirmed','SUCCESS',NULL,false,false,v_completed,9,3);
  RAISE EXCEPTION 'verification_wrong_pan_accepted';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'verification_success_invariant_failed')=0 THEN RAISE; END IF; END;
 PERFORM public.finish_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,v_request.call_id,
  '{"response_status":"S","report_data":[{"client_code":"MBUAT0002","primary_holder_pan":"ZZZPZ0000Z"}]}',
  'application/json',v_response_headers,200,'S','ucc_match_confirmed','SUCCESS',NULL,false,false,v_completed,9,3);
 IF NOT public.nse_ucc_verification_evidence_matches(v_operation2.id,v_verification.id) THEN
  RAISE EXCEPTION 'production_shaped_verification_evidence_did_not_match';
 END IF;
 PERFORM public.distribute_nse_ucc_verification_result(v_operation2.id,v_verification.id);
 SELECT * INTO v_operation2 FROM public.integration_operations WHERE id=v_operation2.id;
 SELECT * INTO v_account2 FROM public.integration_accounts WHERE id=v_account2.id;
 IF v_operation2.state<>'SUCCESS' OR v_account2.current_registration_status<>'REG_SUCCESS'
    OR v_account2.integration_metadata->'nse_registration'->>'client_master_verification_status'<>'CONFIRMED'
    OR v_account2.integration_metadata->'nse_registration'->>'client_master_verified_at' IS NULL THEN
  RAISE EXCEPTION 'post_registration_verification_invalid';
 END IF;

 -- An immediate no-match is evidence, but it must not undo a successful registration.
 SELECT count(*) INTO v_count FROM public.event_outbox WHERE event_type='integration.nse.ucc_registration_requested';
 SELECT * INTO v_verification FROM public.prepare_nse_ucc_verification(v_operation2.id,'POST_REGISTRATION_VERIFICATION');
 SELECT * INTO v_verification_event FROM public.event_outbox WHERE entity_id=v_verification.id;
 SELECT * INTO v_verification_claim FROM public.claim_nse_ucc_verification_event(v_verification_event.id,3,120);
 SELECT * INTO v_request FROM public.start_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000032',
  '{"client_code":"MBUAT0002","PAN":"","from_date":"","to_date":""}',v_request_headers,v_started);
 PERFORM public.finish_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,v_request.call_id,
  '{"response_status":"S","report_data":[]}','application/json',v_response_headers,200,'S',
  'ucc_not_found','BUSINESS_FAILURE',NULL,false,false,v_completed,9,3);
 PERFORM public.distribute_nse_ucc_verification_result(v_operation2.id,v_verification.id);
 SELECT * INTO v_operation2 FROM public.integration_operations WHERE id=v_operation2.id;
 SELECT * INTO v_account2 FROM public.integration_accounts WHERE id=v_account2.id;
 IF v_operation2.state<>'SUCCESS' OR v_account2.state<>'REGISTERED'
    OR v_account2.current_registration_status<>'REG_SUCCESS'
    OR v_account2.integration_metadata->'nse_registration'->>'client_master_verification_status'<>'NOT_CONFIRMED'
    OR (SELECT count(*) FROM public.event_outbox WHERE event_type='integration.nse.ucc_registration_requested')<>v_count THEN
  RAISE EXCEPTION 'post_registration_no_match_changed_registration';
 END IF;

 INSERT INTO public.integration_operations (id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state) VALUES ('c0070000-0000-4000-8000-000000000003',v_account2.workspace_id,v_account2.id,'NSE_INVEST','UAT','CLIENT','WRITE_CLIENT','UCC_REGISTRATION','CLIENTCOMMON183','NNF_1.9.7','QUEUED') RETURNING * INTO v_operation2;
 INSERT INTO public.event_outbox(event_type,payload,status,entity_id,entity_type) VALUES('integration.nse.ucc_registration_requested','{}','pending',v_operation2.id,'integration_operation') RETURNING * INTO v_event2; SELECT * INTO v_claim2 FROM public.claim_nse_ucc_registration_event(v_event2.id,2,120);
 PERFORM public.start_nse_ucc_submission(v_event2.id,v_claim2.claim_token,'c0050000-0000-4000-8000-000000000013','{"reg_details":[{"client_code":"MBUAT0002"}]}','application/json',v_request_headers,v_started);
 PERFORM public.finish_nse_ucc_submission(v_event2.id,v_claim2.claim_token,'c0050000-0000-4000-8000-000000000013','{"reg_details":[{"client_code":"OTHER0001","reg_id":"SYNTHETIC","reg_status":"REG_SUCCESS","reg_remark":""}]}','application/json',v_response_headers,200,v_completed,20,'REG_SUCCESS','none','SUCCESS',NULL,false,false,'OTHER0001','SYNTHETIC',2);
 SELECT * INTO v_operation2 FROM public.integration_operations WHERE id=v_operation2.id; SELECT * INTO v_account2 FROM public.integration_accounts WHERE id=v_account2.id;
 IF v_operation2.state<>'RECONCILIATION_REQUIRED' OR NOT v_operation2.ambiguous_outcome OR v_account2.external_account_id<>'MBUAT0002' THEN RAISE EXCEPTION 'client_code_mismatch_invalid'; END IF;

 -- Pre-request expiry is proven NOT_SENT; after REQUEST evidence expiry is ambiguous.
 INSERT INTO public.integration_accounts (id,workspace_id,investor_profile_id,integration_key,integration_environment,state,integration_metadata) VALUES ('c0060000-0000-4000-8000-000000000003','c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000003','NSE_INVEST','UAT','REGISTRATION_PENDING','{}') RETURNING * INTO v_account3;
 INSERT INTO public.integration_operations (id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state) VALUES ('c0070000-0000-4000-8000-000000000004',v_account3.workspace_id,v_account3.id,'NSE_INVEST','UAT','CLIENT','WRITE_CLIENT','UCC_REGISTRATION','CLIENTCOMMON183','NNF_1.9.7','QUEUED') RETURNING * INTO v_operation3;
 INSERT INTO public.event_outbox(event_type,payload,status,entity_id,entity_type) VALUES('integration.nse.ucc_registration_requested','{}','pending',v_operation3.id,'integration_operation') RETURNING * INTO v_event3; SELECT * INTO v_claim3 FROM public.claim_nse_ucc_registration_event(v_event3.id,2,120);
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=v_event3.id; PERFORM public.recover_expired_nse_ucc_events(2);
 SELECT * INTO v_operation3 FROM public.integration_operations WHERE id=v_operation3.id; IF v_operation3.state<>'SUBMISSION_FAILED' OR NOT v_operation3.retry_allowed THEN RAISE EXCEPTION 'pre_request_recovery_invalid'; END IF;
 SELECT * INTO v_claim3 FROM public.claim_nse_ucc_registration_event(v_event3.id,2,120); PERFORM public.start_nse_ucc_submission(v_event3.id,v_claim3.claim_token,'c0050000-0000-4000-8000-000000000014','{"reg_details":[{"client_code":"MBUAT0003"}]}','application/json',v_request_headers,v_started);
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=v_event3.id; PERFORM public.recover_expired_nse_ucc_events(2);
 SELECT * INTO v_operation3 FROM public.integration_operations WHERE id=v_operation3.id; SELECT * INTO v_event3 FROM public.event_outbox WHERE id=v_event3.id;
 IF v_operation3.state<>'RECONCILIATION_REQUIRED' OR NOT v_operation3.reconciliation_required OR v_event3.status<>'completed' OR (SELECT count(*) FROM public.integration_api_interactions WHERE call_id='c0050000-0000-4000-8000-000000000014')<>2 THEN RAISE EXCEPTION 'post_request_recovery_invalid'; END IF;

 -- SQL invariants reject impossible success/non-definitive HTTP results, then accept 400.
 INSERT INTO public.integration_accounts (id,workspace_id,investor_profile_id,integration_key,integration_environment,state,integration_metadata) VALUES ('c0060000-0000-4000-8000-000000000004','c0030000-0000-4000-8000-000000000001','c0020000-0000-4000-8000-000000000004','NSE_INVEST','UAT','REGISTRATION_PENDING','{}') RETURNING * INTO v_account4;
 INSERT INTO public.integration_operations (id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state) VALUES ('c0070000-0000-4000-8000-000000000005',v_account4.workspace_id,v_account4.id,'NSE_INVEST','UAT','CLIENT','WRITE_CLIENT','UCC_REGISTRATION','CLIENTCOMMON183','NNF_1.9.7','QUEUED') RETURNING * INTO v_operation4;
 INSERT INTO public.event_outbox(event_type,payload,status,entity_id,entity_type) VALUES('integration.nse.ucc_registration_requested','{}','pending',v_operation4.id,'integration_operation') RETURNING * INTO v_event4; SELECT * INTO v_claim4 FROM public.claim_nse_ucc_registration_event(v_event4.id,2,120);
 PERFORM public.start_nse_ucc_submission(v_event4.id,v_claim4.claim_token,'c0050000-0000-4000-8000-000000000015','{"reg_details":[{"client_code":"MBUAT0004"}]}','application/json',v_request_headers,v_started);
 BEGIN
  PERFORM public.finish_nse_ucc_submission(v_event4.id,v_claim4.claim_token,'c0050000-0000-4000-8000-000000000015','{}','application/json',v_response_headers,200,v_completed,1,'REG_FAILED','none','SUCCESS',NULL,false,false,'MBUAT0004',NULL,2);
  RAISE EXCEPTION 'impossible_success_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'invalid_success_result')=0 THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.finish_nse_ucc_submission(v_event4.id,v_claim4.claim_token,'c0050000-0000-4000-8000-000000000015','{}','application/json',v_response_headers,500,v_completed,1,NULL,NULL,'HTTP_FAILURE','nse_http_error',false,false,NULL,NULL,2);
  RAISE EXCEPTION 'http_500_definitive_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'http_failure_not_definitive')=0 THEN RAISE; END IF; END;
 PERFORM public.finish_nse_ucc_submission(v_event4.id,v_claim4.claim_token,'c0050000-0000-4000-8000-000000000015','{}','application/json',v_response_headers,400,v_completed,1,NULL,NULL,'HTTP_FAILURE','nse_http_definitive_failure',false,false,NULL,NULL,2);
 SELECT * INTO v_operation4 FROM public.integration_operations WHERE id=v_operation4.id; IF v_operation4.state<>'HTTP_FAILED' OR v_operation4.retry_allowed OR v_operation4.ambiguous_outcome THEN RAISE EXCEPTION 'http_400_invariant_invalid'; END IF;

 -- The second definitive auth failure is also terminal; 5xx must use ambiguity.
 INSERT INTO public.integration_operations (id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state) VALUES ('c0070000-0000-4000-8000-000000000006',v_account4.workspace_id,v_account4.id,'NSE_INVEST','UAT','CLIENT','WRITE_CLIENT','UCC_REGISTRATION','CLIENTCOMMON183','NNF_1.9.7','QUEUED') RETURNING * INTO v_operation4;
 INSERT INTO public.event_outbox(event_type,payload,status,entity_id,entity_type) VALUES('integration.nse.ucc_registration_requested','{}','pending',v_operation4.id,'integration_operation') RETURNING * INTO v_event4; SELECT * INTO v_claim4 FROM public.claim_nse_ucc_registration_event(v_event4.id,2,120); PERFORM public.start_nse_ucc_submission(v_event4.id,v_claim4.claim_token,'c0050000-0000-4000-8000-000000000016','{"reg_details":[{"client_code":"MBUAT0004"}]}','application/json',v_request_headers,v_started);
 PERFORM public.finish_nse_ucc_submission(v_event4.id,v_claim4.claim_token,'c0050000-0000-4000-8000-000000000016','{}','application/json',v_response_headers,403,v_completed,1,NULL,NULL,'HTTP_FAILURE','nse_authentication_failure',false,false,NULL,NULL,2);
 SELECT * INTO v_operation4 FROM public.integration_operations WHERE id=v_operation4.id; IF v_operation4.state<>'HTTP_FAILED' THEN RAISE EXCEPTION 'http_403_invariant_invalid'; END IF;
 INSERT INTO public.integration_operations (id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state) VALUES ('c0070000-0000-4000-8000-000000000007',v_account4.workspace_id,v_account4.id,'NSE_INVEST','UAT','CLIENT','WRITE_CLIENT','UCC_REGISTRATION','CLIENTCOMMON183','NNF_1.9.7','QUEUED') RETURNING * INTO v_operation4;
 INSERT INTO public.event_outbox(event_type,payload,status,entity_id,entity_type) VALUES('integration.nse.ucc_registration_requested','{}','pending',v_operation4.id,'integration_operation') RETURNING * INTO v_event4; SELECT * INTO v_claim4 FROM public.claim_nse_ucc_registration_event(v_event4.id,2,120); PERFORM public.start_nse_ucc_submission(v_event4.id,v_claim4.claim_token,'c0050000-0000-4000-8000-000000000017','{"reg_details":[{"client_code":"MBUAT0004","primary_holder_pan":"ZZZPZ0000Z"}]}','application/json',v_request_headers,v_started);
 PERFORM public.finish_nse_ucc_submission(v_event4.id,v_claim4.claim_token,'c0050000-0000-4000-8000-000000000017','{}','application/json',v_response_headers,500,v_completed,1,NULL,NULL,'AMBIGUOUS','nse_http_ambiguous_failure',false,false,NULL,NULL,2);
 SELECT * INTO v_operation4 FROM public.integration_operations WHERE id=v_operation4.id; IF v_operation4.state<>'RECONCILIATION_REQUIRED' OR NOT v_operation4.reconciliation_required OR v_operation4.retry_allowed THEN RAISE EXCEPTION 'http_500_ambiguity_invalid'; END IF;
 -- A no-match read leaves an ambiguous write unresolved and never resubmits it.
 SELECT count(*) INTO v_count FROM public.event_outbox WHERE event_type='integration.nse.ucc_registration_requested';
 SELECT * INTO v_verification FROM public.prepare_nse_ucc_verification(v_operation4.id,'AMBIGUOUS_WRITE_RECONCILIATION');
 SELECT * INTO v_verification_event FROM public.event_outbox WHERE entity_id=v_verification.id;
 SELECT * INTO v_verification_claim FROM public.claim_nse_ucc_verification_event(v_verification_event.id,3,120);
 SELECT * INTO v_request FROM public.start_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000033',
  '{"client_code":"MBUAT0004","PAN":"","from_date":"","to_date":""}',v_request_headers,v_started);
 PERFORM public.finish_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,v_request.call_id,
  '{"response_status":"S","report_data":[{"client_code":"MBUAT0004","primary_holder_pan":"WRONG0000X"}]}','application/json',v_response_headers,200,'S',
  'ucc_not_found','BUSINESS_FAILURE',NULL,false,false,v_completed,9,3);
 PERFORM public.distribute_nse_ucc_verification_result(v_operation4.id,v_verification.id);
 SELECT * INTO v_operation4 FROM public.integration_operations WHERE id=v_operation4.id;
 IF v_operation4.state<>'RECONCILIATION_REQUIRED' OR NOT v_operation4.reconciliation_required
    OR (SELECT count(*) FROM public.event_outbox WHERE event_type='integration.nse.ucc_registration_requested')<>v_count THEN
  RAISE EXCEPTION 'ambiguous_no_match_resubmitted_or_resolved';
 END IF;

 -- Candidate collision is protected at the database boundary, including concurrent inserts.
 BEGIN
  UPDATE public.integration_accounts
  SET integration_metadata='{"external_account_candidate":"MBUAT0001"}'
  WHERE id=v_account4.id;
  RAISE EXCEPTION 'candidate_collision_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_accounts_nse_uat_candidate_idx')=0 THEN RAISE; END IF; END;

 -- Generic reconciliation may be required without ambiguity.
 INSERT INTO public.integration_operations(workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state,ambiguous_outcome,reconciliation_required)
 VALUES(v_account4.workspace_id,v_account4.id,'NSE_INVEST','UAT','RECONCILIATION','READ_ONLY','STATE_REVIEW','LOCAL_STATE_REVIEW','INTERNAL_1','RECONCILIATION_REQUIRED',false,true)
 RETURNING * INTO v_verification;
 INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,request_payload_ciphertext,request_header_metadata,request_content_type,request_bytes,request_hash,started_at,normalized_outcome)
 VALUES(v_verification.workspace_id,v_verification.id,v_verification.integration_key,v_verification.integration_environment,v_verification.category,v_verification.safety_class,v_verification.operation_type,v_verification.api_key,v_verification.contract_version,'/local/state_review','POST','c0050000-0000-4000-8000-000000000030','REQUEST',1,v_verification.correlation_id,'integration_payload_encryption_key_v1',1,extensions.pgp_sym_encrypt('{}',public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'),v_request_headers,'application/json',2,extensions.digest('{}'::bytea,'sha256'),v_started,'REQUEST_RECORDED');
 INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,started_at,response_payload_ciphertext,response_header_metadata,response_content_type,response_bytes,response_hash,http_status,http_success,completed_at,elapsed_ms,normalized_outcome,ambiguous_outcome,reconciliation_required)
 VALUES(v_verification.workspace_id,v_verification.id,v_verification.integration_key,v_verification.integration_environment,v_verification.category,v_verification.safety_class,v_verification.operation_type,v_verification.api_key,v_verification.contract_version,'/local/state_review','POST','c0050000-0000-4000-8000-000000000030','RESULT',1,v_verification.correlation_id,'integration_payload_encryption_key_v1',1,v_started,extensions.pgp_sym_encrypt('{}',public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'),v_response_headers,'application/json',2,extensions.digest('{}'::bytea,'sha256'),200,true,v_completed,1,'BUSINESS_FAILURE',false,true);

 -- A separate ambiguous UCC write is resolved only by exact encrypted Client Master evidence.
 INSERT INTO public.integration_operations(id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state)
 VALUES('c0070000-0000-4000-8000-000000000020',v_account.workspace_id,v_account.id,'NSE_INVEST','UAT','CLIENT','WRITE_CLIENT','UCC_REGISTRATION','CLIENTCOMMON183','NNF_1.9.7','QUEUED') RETURNING * INTO v_operation;
 INSERT INTO public.event_outbox(event_type,payload,status,entity_id,entity_type) VALUES('integration.nse.ucc_registration_requested','{}','pending',v_operation.id,'integration_operation') RETURNING * INTO v_event;
 SELECT * INTO v_claim FROM public.claim_nse_ucc_registration_event(v_event.id,2,120);
 PERFORM public.start_nse_ucc_submission(v_event.id,v_claim.claim_token,'c0050000-0000-4000-8000-000000000020','{"reg_details":[{"client_code":"MBUAT0001","primary_holder_pan":"ZZZPZ0000Z"}]}','application/json',v_request_headers,v_started);
 PERFORM public.finish_nse_ucc_submission(v_event.id,v_claim.claim_token,'c0050000-0000-4000-8000-000000000020','{}','application/json',v_response_headers,503,v_completed,5,NULL,NULL,'AMBIGUOUS','nse_http_ambiguous_failure',false,false,NULL,NULL,2);
 SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id;
 IF v_operation.state<>'RECONCILIATION_REQUIRED' THEN RAISE EXCEPTION 'reconciliation_fixture_invalid'; END IF;
 BEGIN
  UPDATE public.integration_operations SET state='SUCCESS',reconciliation_required=false,ambiguous_outcome=false WHERE id=v_operation.id;
  RAISE EXCEPTION 'direct_reconciliation_edit_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'invalid_integration_operation_transition')=0 THEN RAISE; END IF; END;
 SELECT * INTO v_verification FROM public.prepare_nse_ucc_verification(v_operation.id,'AMBIGUOUS_WRITE_RECONCILIATION');
 IF v_verification.category<>'RECONCILIATION' OR v_verification.safety_class<>'READ_ONLY'
    OR v_verification.operation_purpose<>'AMBIGUOUS_WRITE_RECONCILIATION'
    OR v_verification.api_key<>'CLIENT_MASTER_REPORT' OR v_verification.reconciliation_target_operation_id<>v_operation.id THEN
  RAISE EXCEPTION 'verification_classification_invalid';
 END IF;
 SELECT * INTO v_verification_event FROM public.event_outbox WHERE entity_id=v_verification.id;
 SELECT * INTO v_verification_claim FROM public.claim_nse_ucc_verification_event(v_verification_event.id,3,120);
 SELECT * INTO v_request FROM public.start_nse_ucc_verification(v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000021','{"client_code":"MBUAT0001","PAN":"","from_date":"","to_date":""}',v_request_headers,v_started);
 IF (public.start_nse_ucc_verification(v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000021','{"client_code":"MBUAT0001","PAN":"","from_date":"","to_date":""}',v_request_headers,v_started)).id<>v_request.id THEN RAISE EXCEPTION 'verification_request_idempotency_failed'; END IF;
 BEGIN
  PERFORM public.start_nse_ucc_verification(v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000021','{"client_code":"OTHER0001","PAN":"","from_date":"","to_date":""}',v_request_headers,v_started);
  RAISE EXCEPTION 'verification_request_conflict_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_request_idempotency_conflict')=0 THEN RAISE; END IF; END;
 SELECT * INTO v_result FROM public.finish_nse_ucc_verification(v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000021','{"response_status":"S","report_data":[{"client_code":"MBUAT0001","primary_holder_pan":"ZZZPZ0000Z"}]}','application/json',v_response_headers,200,'S','ucc_match_confirmed','SUCCESS',NULL,false,false,v_completed,9,3);
 IF (public.finish_nse_ucc_verification(v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000021','{"response_status":"S","report_data":[{"client_code":"MBUAT0001","primary_holder_pan":"ZZZPZ0000Z"}]}','application/json',v_response_headers,200,'S','ucc_match_confirmed','SUCCESS',NULL,false,false,v_completed,9,3)).id<>v_result.id THEN RAISE EXCEPTION 'verification_result_idempotency_failed'; END IF;
 BEGIN
  PERFORM public.finish_nse_ucc_verification(v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000021','{"response_status":"S","report_data":[]}','application/json',v_response_headers,200,'S','ucc_match_confirmed','SUCCESS',NULL,false,false,v_completed,9,3);
  RAISE EXCEPTION 'verification_result_conflict_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_result_idempotency_conflict')=0 THEN RAISE; END IF; END;
 PERFORM public.distribute_nse_ucc_verification_result(v_operation.id,v_verification.id);
 SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id;
 SELECT * INTO v_account FROM public.integration_accounts WHERE id=v_account.id;
 IF v_operation.state<>'SUCCESS' OR v_operation.reconciliation_required OR v_operation.ambiguous_outcome OR v_operation.reconciliation_resolution_operation_id<>v_verification.id OR v_account.state<>'REGISTERED' OR v_account.external_account_id<>'MBUAT0001' THEN RAISE EXCEPTION 'read_reconciliation_resolution_invalid'; END IF;
 IF (SELECT count(*) FROM public.integration_api_interactions WHERE integration_operation_id=v_verification.id)<>2 THEN RAISE EXCEPTION 'verification_evidence_pair_missing'; END IF;

 -- Client Master read crash recovery: before REQUEST is proven not sent.
 SELECT * INTO v_verification FROM public.prepare_nse_ucc_verification(
  'c0070000-0000-4000-8000-000000000002','POST_REGISTRATION_VERIFICATION');
 SELECT * INTO v_verification_event FROM public.event_outbox WHERE entity_id=v_verification.id;
 SELECT * INTO v_verification_claim FROM public.claim_nse_ucc_verification_event(v_verification_event.id,3,120);
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=v_verification_event.id;
 IF public.recover_expired_nse_ucc_verification_events(v_verification_event.id,3)<>'safe_read_retry_available' THEN
  RAISE EXCEPTION 'verification_pre_request_recovery_not_available';
 END IF;
 SELECT * INTO v_verification FROM public.integration_operations WHERE id=v_verification.id;
 IF v_verification.state<>'SUBMISSION_FAILED' OR NOT v_verification.retry_allowed
    OR EXISTS (SELECT 1 FROM public.integration_api_interactions WHERE integration_operation_id=v_verification.id) THEN
  RAISE EXCEPTION 'verification_pre_request_recovery_invalid';
 END IF;
 SELECT * INTO v_verification_claim FROM public.claim_nse_ucc_verification_event(v_verification_event.id,3,120);
 IF v_verification_claim.attempt<>2 OR v_verification_claim.claim_state<>'safe_retry_claimed' THEN
  RAISE EXCEPTION 'verification_pre_request_retry_claim_invalid';
 END IF;
 SELECT * INTO v_request FROM public.start_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000040',
  '{"client_code":"MBUAT0002","PAN":"","from_date":"","to_date":""}',v_request_headers,v_started);
 PERFORM public.finish_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,v_request.call_id,
  '{"response_status":"S","report_data":[]}','application/json',v_response_headers,200,'S',
  'ucc_not_found','BUSINESS_FAILURE',NULL,false,false,v_completed,9,3);
 PERFORM public.distribute_nse_ucc_verification_result(
  'c0070000-0000-4000-8000-000000000002',v_verification.id);

 -- After REQUEST, preserve the abandoned attempt with TRANSPORT_FAILURE, then use a new call_id.
 SELECT * INTO v_verification FROM public.prepare_nse_ucc_verification(
  'c0070000-0000-4000-8000-000000000002','POST_REGISTRATION_VERIFICATION');
 SELECT * INTO v_verification_event FROM public.event_outbox WHERE entity_id=v_verification.id;
 SELECT * INTO v_verification_claim FROM public.claim_nse_ucc_verification_event(v_verification_event.id,3,120);
 SELECT * INTO v_request FROM public.start_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000041',
  '{"client_code":"MBUAT0002","PAN":"","from_date":"","to_date":""}',v_request_headers,v_started);
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=v_verification_event.id;
 IF public.recover_expired_nse_ucc_verification_events(v_verification_event.id,3)<>'safe_read_retry_available' THEN
  RAISE EXCEPTION 'verification_post_request_recovery_not_available';
 END IF;
 IF (SELECT count(*) FROM public.integration_api_interactions WHERE call_id=v_request.call_id)<>2
    OR (SELECT normalized_outcome FROM public.integration_api_interactions WHERE call_id=v_request.call_id AND phase='RESULT')<>'TRANSPORT_FAILURE' THEN
  RAISE EXCEPTION 'verification_abandoned_attempt_not_closed';
 END IF;
 SELECT * INTO v_verification_claim FROM public.claim_nse_ucc_verification_event(v_verification_event.id,3,120);
 SELECT * INTO v_request FROM public.start_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,'c0050000-0000-4000-8000-000000000042',
  '{"client_code":"MBUAT0002","PAN":"","from_date":"","to_date":""}',v_request_headers,v_started+interval '1 minute');
 IF v_request.attempt_number<>2
    OR (SELECT count(DISTINCT call_id) FROM public.integration_api_interactions WHERE integration_operation_id=v_verification.id AND phase='REQUEST')<>2 THEN
  RAISE EXCEPTION 'verification_read_retry_history_invalid';
 END IF;
 PERFORM public.finish_nse_ucc_verification(
  v_verification_event.id,v_verification_claim.claim_token,v_request.call_id,
  '{"response_status":"S","report_data":[]}','application/json',v_response_headers,200,'S',
  'ucc_not_found','BUSINESS_FAILURE',NULL,false,false,v_completed+interval '1 minute',9,3);
 PERFORM public.distribute_nse_ucc_verification_result(
  'c0070000-0000-4000-8000-000000000002',v_verification.id);

 -- Scope trigger rejects an interaction linked to a different workspace/context.
 BEGIN
  INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,request_payload_ciphertext,request_header_metadata,request_content_type,request_bytes,request_hash,started_at,normalized_outcome)
  VALUES(v_operation.workspace_id,v_operation.id,'OTHER_INTEGRATION','UAT','CLIENT','WRITE_CLIENT','UCC_REGISTRATION','CLIENTCOMMON183','NNF_1.9.7','/x','POST',gen_random_uuid(),'REQUEST',1,v_operation.correlation_id,'integration_payload_encryption_key_v1',1,'x'::bytea,v_request_headers,'application/json',1,'x'::bytea,now(),'REQUEST_RECORDED');
  RAISE EXCEPTION 'interaction_scope_mismatch_allowed';
 EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_interaction_scope_mismatch')=0 THEN RAISE; END IF; END;
END $$;

ROLLBACK;
