BEGIN;
CREATE FUNCTION pg_temp.assert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; END $$;
SELECT 1 FROM vault.create_secret(repeat('p',40),'pan_encryption_key','synthetic test');
SELECT 1 FROM vault.create_secret(repeat('h',40),'pan_lookup_hmac_key','synthetic test');
SELECT 1 FROM vault.create_secret(repeat('b',40),'bank_account_encryption_key_v1','synthetic test');
SELECT 1 FROM vault.create_secret(repeat('l',40),'bank_account_lookup_hmac_key_v1','synthetic test');
INSERT INTO auth.users(id,email,phone,email_confirmed_at,phone_confirmed_at)
SELECT ('ab000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'onboarding-'||n||'@example.test','9190000000'||lpad(n::text,2,'0'),now(),now() FROM generate_series(1,9) n;
INSERT INTO public.profiles(id,user_id,role,full_name,account_status) VALUES
('ab100000-0000-0000-0000-000000000001','ab000000-0000-0000-0000-000000000001','advisor','Synthetic MFD','active'),
('ab100000-0000-0000-0000-000000000002','ab000000-0000-0000-0000-000000000002','advisor','Other MFD','active');
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status) VALUES
('ab200000-0000-0000-0000-000000000001','Synthetic workspace','onboarding-one','ab100000-0000-0000-0000-000000000001','active'),
('ab200000-0000-0000-0000-000000000002','Other workspace','onboarding-two','ab100000-0000-0000-0000-000000000002','active');
INSERT INTO public.workspace_memberships(id,workspace_id,profile_id,role,status) VALUES
('ab300000-0000-0000-0000-000000000001','ab200000-0000-0000-0000-000000000001','ab100000-0000-0000-0000-000000000001','admin','active'),
('ab300000-0000-0000-0000-000000000002','ab200000-0000-0000-0000-000000000002','ab100000-0000-0000-0000-000000000002','admin','active');
-- Historical approved applications are explicit owner fixtures; browser callers
-- cannot create this approval provenance (covered by the MFD approval suite).
ALTER TABLE public.mfd_applications DISABLE TRIGGER USER;
INSERT INTO public.mfd_applications(applicant_user_id,applicant_email,business_name,claimed_arn,status,version,review_started_at,review_started_by,decided_at,decided_by,decision_note,
 approved_business_name,approved_arn,profile_id,workspace_id,membership_id)
SELECT ('ab000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'onboarding-'||n||'@example.test','Synthetic MFD','ARN-12345','approved',3,now(),('ab000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,now(),('ab000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'Synthetic approval',
 'Synthetic MFD','ARN-12345',('ab100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,('ab200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,('ab300000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid FROM generate_series(1,2) n;
ALTER TABLE public.mfd_applications ENABLE TRIGGER USER;
SELECT 1 FROM vault.create_secret(repeat('e',40),'integration_payload_encryption_key_v1','synthetic test');
INSERT INTO moneybowl_onboarding.ekyc_amcs(code,label,source_reference) VALUES('TEST','Synthetic AMC','local fixture only');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE r jsonb; q jsonb; BEGIN
 r:=public.start_onboarding_kyc('ab200000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001','ZZZPZ0001Z');
 PERFORM pg_temp.assert(r->>'status'='KYC_CHECK_REQUIRED' AND r->>'investor_profile_id' IS NULL,'A PAN-only without a fabricated profile');
 q:=public.start_onboarding_kyc('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),'ZZZPZ0001Z');
 PERFORM pg_temp.assert(q->>'id'=r->>'id','PAN restart converges');
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',(r->>'id')::uuid,1,'{"pan":"ZZZPZ0002Z"}'); RAISE EXCEPTION 'PAN substituted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'onboarding_identity_frozen' THEN RAISE; END IF; END;
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',(r->>'id')::uuid,1,'{"kyc_status":"completed"}'); RAISE EXCEPTION 'KYC fabricated';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'onboarding_identity_frozen' THEN RAISE; END IF; END;
 BEGIN PERFORM public.resolve_investor_onboarding((r->>'id')::uuid,1); RAISE EXCEPTION 'pre-KYC resolve';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'authoritative_kyc_required' THEN RAISE; END IF; END;
 r:=public.request_onboarding_kyc((r->>'id')::uuid,'ab600000-0000-0000-0000-000000000001','CHECK');
 PERFORM pg_temp.assert(r->>'status'='KYC_CHECKING','E check queued');
 PERFORM public.request_onboarding_kyc((r->>'id')::uuid,'ab600000-0000-0000-0000-000000000001','CHECK');
 PERFORM public.request_onboarding_kyc((r->>'id')::uuid,gen_random_uuid(),'CHECK');
 PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000002',true);
 BEGIN PERFORM public.get_onboarding_kyc((r->>'id')::uuid); RAISE EXCEPTION 'D unrelated read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_onboarding_ekyc_link((r->>'id')::uuid); RAISE EXCEPTION 'Q unrelated link'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.request_onboarding_kyc((r->>'id')::uuid,gen_random_uuid(),'CHECK'); RAISE EXCEPTION 'D unrelated write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.assert((SELECT count(*)=1 FROM moneybowl_onboarding.kyc_operations),'N one operation');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM public.integration_accounts),'no fake integration accounts');
CREATE FUNCTION pg_temp.perform_call(case_id uuid,body text,http integer DEFAULT 200,transmission text DEFAULT 'SENT_WITH_RESULT') RETURNS text LANGUAGE plpgsql AS $$
DECLARE e uuid; claim jsonb; result text; BEGIN
 SELECT ev.id INTO e FROM public.event_outbox ev JOIN moneybowl_onboarding.kyc_operations o ON o.id=ev.entity_id WHERE o.case_id=perform_call.case_id AND o.state IN ('QUEUED','RETRY');
 claim:=public.claim_onboarding_kyc(e);
 PERFORM pg_temp.assert(claim IS NOT NULL,'worker claim');
 PERFORM public.start_onboarding_kyc_call((claim->>'operation_id')::uuid,(claim->>'claim_token')::uuid,(claim->>'call_id')::uuid);
 result:=public.finish_onboarding_kyc_call((claim->>'operation_id')::uuid,(claim->>'claim_token')::uuid,(claim->>'call_id')::uuid,encode(convert_to(body,'UTF8'),'base64'),http,transmission);
 PERFORM pg_temp.assert(result=public.finish_onboarding_kyc_call((claim->>'operation_id')::uuid,(claim->>'claim_token')::uuid,(claim->>'call_id')::uuid,encode(convert_to(body,'UTF8'),'base64'),http,transmission),'finish exact retry');
 RETURN result;
END $$;
DO $$ DECLARE req jsonb; BEGIN
 SELECT extensions.pgp_sym_decrypt(request_ciphertext,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'))::jsonb INTO req FROM moneybowl_onboarding.kyc_operations;
 PERFORM pg_temp.assert(req='{"pan_no":"ZZZPZ0001Z"}'::jsonb,'E exact protected PAN-only body');
 PERFORM pg_temp.assert(pg_temp.perform_call('ab400000-0000-0000-0000-000000000001','{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":"No record(s) found."}')='KYC_NOT_AVAILABLE','F characterized empty');
END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE i integer; BEGIN
 FOR i IN 1..4 LOOP
 BEGIN
 PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000001',gen_random_uuid(),'EKYC',CASE WHEN i=1 THEN NULL ELSE 'fixture@example.test' END,CASE WHEN i=2 THEN NULL ELSE '9000000000' END,CASE WHEN i=3 THEN NULL WHEN i=4 THEN 'UNAPPROVED' ELSE 'TEST' END);
 RAISE EXCEPTION 'J missing prerequisite accepted'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ekyc_details_required' THEN RAISE; END IF; END;
 END LOOP;
 PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000001','ab600000-0000-0000-0000-000000000002','EKYC','fixture@example.test','9000000000','TEST');
 PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000001','ab600000-0000-0000-0000-000000000002','EKYC','fixture@example.test','9000000000','TEST');
END $$;
RESET ROLE;
DO $$ DECLARE req jsonb; link text:='https://nseinvestuat.nseindia.com/nsemfdesk/ekycVerifyByUser/'||'synthetic'; result text; BEGIN
 SELECT extensions.pgp_sym_decrypt(request_ciphertext,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'))::jsonb INTO req FROM moneybowl_onboarding.kyc_operations WHERE api='EKYCREG';
 PERFORM pg_temp.assert(req=jsonb_build_object('amcCode','TEST','panNo','ZZZPZ0001Z','invEmail','fixture@example.test','mobileNo','9000000000'),'K exact fresh eKYC fields');
 result:=pg_temp.perform_call('ab400000-0000-0000-0000-000000000001',jsonb_build_object('message','EKYC FRESH REGISTRATION REQUEST RECEIVED','link',link)::text);
 PERFORM pg_temp.assert(result='EKYC_IN_PROGRESS','L successful initiation');
 PERFORM pg_temp.assert(NOT EXISTS(SELECT 1 FROM moneybowl_onboarding.events WHERE evidence::text LIKE '%ekycVerifyByUser%'),'L link not audited');
 PERFORM pg_temp.assert(NOT EXISTS(SELECT 1 FROM public.event_outbox WHERE payload::text LIKE '%ekycVerifyByUser%'),'L link not outbox payload');
 PERFORM pg_temp.assert((SELECT count(*)=2 FROM public.integration_api_interactions WHERE onboarding_operation_id IN (SELECT id FROM moneybowl_onboarding.kyc_operations WHERE api='EKYCREG')),'L encrypted request and result');
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 PERFORM pg_temp.assert(public.get_onboarding_ekyc_link('ab400000-0000-0000-0000-000000000001') IS NOT NULL,'Q owner may open');
 PERFORM pg_temp.assert(public.list_investor_onboarding('ab200000-0000-0000-0000-000000000001')::text NOT LIKE '%ekycVerifyByUser%','L no link in list');
 PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000001',gen_random_uuid(),'REFRESH');
END $$;
RESET ROLE;
DO $$ BEGIN
 PERFORM pg_temp.assert(pg_temp.perform_call('ab400000-0000-0000-0000-000000000001','{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":"No record(s) found."}')='EKYC_IN_PROGRESS','absence after link preserves progress');
END $$;
-- Strict envelope/schema/scope/status semantics; all fixtures are synthetic.
DO $$ DECLARE j jsonb; bad text; BEGIN
 j:='{"response_status":"S","report_data_total":1,"report_data":[{"client_code":"","client_pan":"ZZZPZ0001Z","holding_type":"","holder_name":"Synthetic","holder_dob":"","kyc_status":"UNCHARACTERIZED","status_remark":""}]}';
 PERFORM pg_temp.assert(moneybowl_onboarding.kyc_classify(j::text,'ZZZPZ0001Z')='KYC_PROVIDER_REVIEW_REQUIRED','H unknown never compliant');
 PERFORM pg_temp.assert(moneybowl_onboarding.kyc_classify(j::text,'ZZZPZ0002Z')='PROVIDER_RECONCILIATION_REQUIRED','G foreign PAN');
 PERFORM pg_temp.assert(moneybowl_onboarding.kyc_classify(jsonb_set(j,'{report_data_total}','2')::text,'ZZZPZ0001Z')='PROVIDER_RECONCILIATION_REQUIRED','G inconsistent count');
 j:=jsonb_set(jsonb_set(j,'{report_data}',(j->'report_data')||(j->'report_data')),'{report_data_total}','2');
 PERFORM pg_temp.assert(moneybowl_onboarding.kyc_classify(j::text,'ZZZPZ0001Z')='PROVIDER_RECONCILIATION_REQUIRED','G duplicate rows');
 FOREACH bad IN ARRAY ARRAY['{}','not json','{"response_status":"S","report_data_total":0,"report_data":[]}', '{"response_status":"F","report_data_total":0,"report_data":[],"error_remark":"No record(s) found."}'] LOOP
 PERFORM pg_temp.assert(moneybowl_onboarding.kyc_classify(bad,'ZZZPZ0001Z')='PROVIDER_RECONCILIATION_REQUIRED','G unsupported empty or malformed'); END LOOP;
 FOREACH bad IN ARRAY ARRAY['http://nseinvestuat.nseindia.com/nsemfdesk/ekycVerifyByUser/synthetic','https://evil.example/nsemfdesk/ekycVerifyByUser/synthetic','https://nseinvestuat.nseindia.com/wrong/synthetic','https://user@nseinvestuat.nseindia.com/nsemfdesk/ekycVerifyByUser/synthetic','https://nseinvestuat.nseindia.com/nsemfdesk/ekycVerifyByUser/synthetic?x=y'] LOOP
 PERFORM pg_temp.assert(moneybowl_onboarding.ekyc_link(jsonb_build_object('message','EKYC FRESH REGISTRATION REQUEST RECEIVED','link',bad)::text) IS NULL,'M untrusted link'); END LOOP;
END $$;
-- Identity reuse and conflicting/duplicate PAN records use the same V1 fixtures.
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; v1 uuid:='ab400000-0000-0000-0000-000000000010'; BEGIN
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',v1,0,'{"pan":"ZZZPZ0010Z","legal_name":"Synthetic Existing"}');
 r:=public.resolve_investor_onboarding(v1,1);
 r:=public.start_onboarding_kyc('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),'ZZZPZ0010Z');
 PERFORM pg_temp.assert(r->>'id'=v1::text AND r->>'investor_profile_id' IS NOT NULL,'C reuse V1 canonical case');
 PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000002',true);
 r:=public.start_onboarding_kyc('ab200000-0000-0000-0000-000000000002',gen_random_uuid(),'ZZZPZ0010Z');
 PERFORM pg_temp.assert(r->>'status'='RELATIONSHIP_RECONCILIATION_REQUIRED' AND r->>'investor_profile_id' IS NULL,'D relationship not stolen or leaked');
END $$;
RESET ROLE;
INSERT INTO public.profiles(id,role,full_name,account_status) VALUES('ab100000-0000-0000-0000-000000000020','investor','Synthetic Duplicate','active');
INSERT INTO public.profile_pan_records(profile_id,pan_ciphertext,pan_lookup_hmac,masked_pan,source,source_system,status)
SELECT 'ab100000-0000-0000-0000-000000000020',pan_ciphertext,pan_lookup_hmac,masked_pan,source,source_system,status FROM public.profile_pan_records WHERE pan_lookup_hmac=extensions.hmac('ZZZPZ0010Z',public.pan_lookup_hmac_key(),'sha256');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
-- A distinct PAN with two identities must enter reconciliation.
RESET ROLE;
UPDATE public.profile_pan_records SET pan_lookup_hmac=extensions.hmac('ZZZPZ0020Z',public.pan_lookup_hmac_key(),'sha256') WHERE pan_lookup_hmac=extensions.hmac('ZZZPZ0010Z',public.pan_lookup_hmac_key(),'sha256');
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.start_onboarding_kyc('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),'ZZZPZ0020Z');
 PERFORM pg_temp.assert(r->>'status'='IDENTITY_RECONCILIATION_REQUIRED','B duplicate PAN');
END $$;
RESET ROLE;
-- Bounded retry and no resend after uncertain mutation; result handling stays local.
DO $$ DECLARE c uuid; i integer; e uuid; claim jsonb; BEGIN
 FOR i IN 1..3 LOOP
 PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
 c:=gen_random_uuid();
 PERFORM public.start_onboarding_kyc('ab200000-0000-0000-0000-000000000001',c,'ZZZPZ010'||i||'Z');
 PERFORM public.request_onboarding_kyc(c,gen_random_uuid(),'CHECK');
 PERFORM pg_temp.perform_call(c,'{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":"No record(s) found."}');
 PERFORM public.request_onboarding_kyc(c,gen_random_uuid(),'EKYC','fixture@example.test','9000000000','TEST');
 IF i=1 THEN
 PERFORM pg_temp.assert(pg_temp.perform_call(c,'',NULL,'PROVEN_NOT_SENT')='EKYC_INITIATION_PENDING','O bounded safe retry');
 PERFORM pg_temp.assert(pg_temp.perform_call(c,'',NULL,'PROVEN_NOT_SENT')='EKYC_INITIATION_PENDING','O second safe retry');
 PERFORM pg_temp.assert(pg_temp.perform_call(c,'',NULL,'PROVEN_NOT_SENT')='PROVIDER_RECONCILIATION_REQUIRED','O exhausted');
 ELSIF i=2 THEN
 PERFORM pg_temp.assert(pg_temp.perform_call(c,'',NULL,'MAYBE_SENT')='PROVIDER_RECONCILIATION_REQUIRED','P ambiguous no retry');
 ELSE
 SELECT ev.id INTO e FROM public.event_outbox ev JOIN moneybowl_onboarding.kyc_operations o ON o.id=ev.entity_id WHERE o.case_id=c AND o.api='EKYCREG';
 claim:=public.claim_onboarding_kyc(e);
 PERFORM public.start_onboarding_kyc_call((claim->>'operation_id')::uuid,(claim->>'claim_token')::uuid,(claim->>'call_id')::uuid);
 UPDATE moneybowl_onboarding.kyc_operations SET lease_until=now()-interval '1 second' WHERE id=(claim->>'operation_id')::uuid;
 PERFORM pg_temp.assert(public.claim_onboarding_kyc(e) IS NULL,'P expired mutation no resend');
 END IF;
 PERFORM public.request_onboarding_kyc(c,gen_random_uuid(),'EKYC','fixture@example.test','9000000000','TEST');
 PERFORM pg_temp.assert((SELECT count(*)=1 FROM moneybowl_onboarding.kyc_operations WHERE case_id=c AND api='EKYCREG'),'N P one lifetime fresh registration');
 END LOOP;
END $$;
DO $$ DECLARE t regclass; BEGIN
 FOREACH t IN ARRAY ARRAY['moneybowl_onboarding.kyc_cases'::regclass,'moneybowl_onboarding.kyc_operations'::regclass,'moneybowl_onboarding.ekyc_amcs'::regclass] LOOP
 PERFORM pg_temp.assert((SELECT relrowsecurity FROM pg_class WHERE oid=t),'RLS enabled');
 PERFORM pg_temp.assert(NOT has_table_privilege('authenticated',t,'SELECT,INSERT,UPDATE,DELETE'),'private tables denied'); END LOOP;
 PERFORM pg_temp.assert(NOT has_function_privilege('authenticated','public.finish_onboarding_kyc_call(uuid,uuid,uuid,text,integer,text)','EXECUTE'),'service result boundary');
END $$;
-- Q: a safe V1-linked investor receives only their own secure action.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE r jsonb; BEGIN
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000090',0,
 '{"legal_name":"Synthetic Linked Investor","pan":"ZZZPZ0090Z","email":"onboarding-3@example.test","mobile":"919000000003"}');
 PERFORM public.resolve_investor_onboarding((r->>'id')::uuid,1);
 PERFORM public.start_onboarding_kyc('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),'ZZZPZ0090Z');
 PERFORM public.request_onboarding_kyc((r->>'id')::uuid,gen_random_uuid(),'CHECK');
END $$;
RESET ROLE;
DO $$ BEGIN
 PERFORM pg_temp.perform_call('ab400000-0000-0000-0000-000000000090','{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":"No record(s) found."}');
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000090',gen_random_uuid(),'EKYC',NULL,NULL,'TEST'); END $$;
RESET ROLE;
DO $$ BEGIN
 PERFORM pg_temp.perform_call('ab400000-0000-0000-0000-000000000090',jsonb_build_object('message','EKYC FRESH REGISTRATION REQUEST RECEIVED',
 'link','https://nseinvestuat.nseindia.com/nsemfdesk/ekycVerifyByUser/'||'synthetic')::text);
END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000003',true);
DO $$ BEGIN
 PERFORM pg_temp.assert(public.get_onboarding_ekyc_link('ab400000-0000-0000-0000-000000000090') IS NOT NULL,'Q linked investor');
 BEGIN PERFORM public.get_onboarding_ekyc_link('ab400000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'Q other investor'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE public.advisor_investor_assignments SET status='ended',ended_at=now() WHERE investor_id=(SELECT investor_profile_id FROM moneybowl_onboarding.cases WHERE id='ab400000-0000-0000-0000-000000000090');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ BEGIN
 BEGIN PERFORM public.get_onboarding_ekyc_link('ab400000-0000-0000-0000-000000000090'); RAISE EXCEPTION 'Q revoked MFD'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
-- Legacy incomplete drafts resume at PAN rather than an unusable Check action.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE c uuid:='ab400000-0000-0000-0000-000000000099'; r jsonb; BEGIN
 PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',c,0,'{}');
 PERFORM pg_temp.assert(public.get_onboarding_kyc(c)->>'status'='DRAFT','legacy draft asks for PAN');
 r:=public.start_onboarding_kyc('ab200000-0000-0000-0000-000000000001',c,'ZZZPZ0999Z');
 PERFORM pg_temp.assert(r->>'id'=c::text AND r->>'status'='KYC_CHECK_REQUIRED','legacy draft keeps identity and gains PAN');
END $$;
RESET ROLE;
DO $$ BEGIN
 PERFORM pg_temp.assert(NOT EXISTS(SELECT 1 FROM moneybowl_onboarding.events WHERE evidence::text LIKE '%ZZZPZ%' OR evidence::text LIKE '%@example.test%' OR evidence::text LIKE '%ekycVerifyByUser%'),'audit contains no synthetic sensitive facts');
END $$;
-- A canonical identity arising after draft preparation does not confer relationship authority.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ BEGIN
 PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000099',gen_random_uuid(),'CHECK');
END $$;
RESET ROLE;
INSERT INTO public.profile_pan_records(profile_id,pan_ciphertext,pan_lookup_hmac,masked_pan,source,source_system,status)
VALUES('ab100000-0000-0000-0000-000000000020',extensions.pgp_sym_encrypt('ZZZPZ0999Z',public.pan_encryption_key()),extensions.hmac('ZZZPZ0999Z',public.pan_lookup_hmac_key(),'sha256'),public.mask_pan('ZZZPZ0999Z'),'ADVISOR','MANUAL','OBSERVED');
DO $$ DECLARE e uuid; BEGIN
 SELECT ev.id INTO e FROM public.event_outbox ev JOIN moneybowl_onboarding.kyc_operations o ON o.id=ev.entity_id JOIN moneybowl_onboarding.kyc_cases k ON k.case_id=o.case_id
 WHERE k.pan_hmac=extensions.hmac('ZZZPZ0999Z',public.pan_lookup_hmac_key(),'sha256');
 PERFORM pg_temp.assert(public.claim_onboarding_kyc(e) IS NULL,'canonical change fences dispatch');
END $$;
-- The worker API grants are exercised under the actual service role, without table grants.
SET LOCAL ROLE service_role;
DO $$ BEGIN
 PERFORM pg_temp.assert(public.claim_onboarding_kyc(gen_random_uuid()) IS NULL,'service facade callable');
 BEGIN PERFORM public.start_onboarding_kyc_call(gen_random_uuid(),gen_random_uuid(),gen_random_uuid());
 RAISE EXCEPTION 'unknown claim accepted'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'onboarding_claim_invalid' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
ROLLBACK;
