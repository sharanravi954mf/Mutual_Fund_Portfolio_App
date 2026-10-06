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
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE r jsonb; retry jsonb; pid uuid; n integer; BEGIN
 PERFORM pg_temp.assert(jsonb_array_length(public.list_investor_onboarding_workspaces())=1,'only owned approved workspace');
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001',0,
 '{"legal_name":"Synthetic Investor One","pan":"ZZZPZ0001Z","email":"absent@example.test","mobile":"919000009999"}');
 PERFORM pg_temp.assert(r->>'status'='DRAFT','partial draft');
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,(r->>'version')::integer); pid:=(r->>'investor_profile_id')::uuid;
 PERFORM pg_temp.assert(r->>'relationship_status'='READY' AND r->>'status'='PROFILE_INCOMPLETE','A J business identity without auth and missing prerequisites');
 PERFORM pg_temp.assert(r->>'account_link_status'='PENDING_VERIFIED_IDENTITY','A account absent');
 PERFORM pg_temp.assert(r->'missing' ? 'date_of_birth' AND r->'missing' ? 'kyc_verification','J authoritative missing prerequisites');
 PERFORM pg_temp.assert(NOT(r->'fields' ? 'pan') AND NOT(r->'fields' ? 'account_number'),'projection strips full financial identifiers');
 retry:=public.resolve_investor_onboarding((r->>'id')::uuid,1);
 PERFORM pg_temp.assert(retry->>'investor_profile_id'=pid::text,'I exact resolve replay');
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000002',0,
 '{"legal_name":"Synthetic Investor One","pan":"ZZZPZ0001Z","email":"absent@example.test","mobile":"919000009999"}');
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,1);
 PERFORM pg_temp.assert(r->>'investor_profile_id'=pid::text AND r->>'id'='ab400000-0000-0000-0000-000000000001','D canonical case reused');
 PERFORM pg_temp.assert(jsonb_array_length(public.list_investor_onboarding('ab200000-0000-0000-0000-000000000001'))=1,'I no duplicate active cases');
 -- B Explorer existed first, entered only investor information.
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000003',0,
 '{"legal_name":"Synthetic Investor Three","pan":"ZZZPZ0003Z","email":"onboarding-3@example.test","mobile":"919000000003"}');
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,1);
 PERFORM pg_temp.assert(r->>'account_link_status'='LINKED','B existing Explorer automatically linked');
 -- E email and mobile refer to different verified accounts.
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000004',0,
 '{"legal_name":"Synthetic Conflict","pan":"ZZZPZ0004Z","email":"onboarding-4@example.test","mobile":"919000000005"}');
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,1);
 PERFORM pg_temp.assert(r->>'status'='IDENTITY_RECONCILIATION_REQUIRED' AND r->>'account_link_status'<>'LINKED','E split identity fails closed');
 -- G unrelated workspace, including known PII, cannot establish authority.
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000002',gen_random_uuid(),0,'{}'); RAISE EXCEPTION 'cross workspace bypass';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000002',true);
 BEGIN PERFORM public.get_investor_onboarding('ab400000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'case enumeration'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000002',gen_random_uuid(),0,
 '{"legal_name":"Synthetic Investor One","pan":"ZZZPZ0001Z","email":"absent@example.test","mobile":"919000009999"}');
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,1);
 PERFORM pg_temp.assert(r->>'status'='RELATIONSHIP_RECONCILIATION_REQUIRED' AND r->>'investor_profile_id' IS NULL,'G PII does not grant relationship or reveal canonical id');
 -- H ordinary user cannot call privileged APIs or private matchers.
 PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000006',true);
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),0,'{}'); RAISE EXCEPTION 'ordinary bypass'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM moneybowl_onboarding.link_investor(pid); RAISE EXCEPTION 'link bypass'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.prepare_onboarded_investor_ucc('ab400000-0000-0000-0000-000000000001','SYNTHETIC'); RAISE EXCEPTION 'service bypass'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM pg_temp.assert((SELECT account_state='explorer' FROM public.bootstrap_identity()),'K unmatched signup Explorer fallback');
 PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000003',true);
 PERFORM pg_temp.assert((SELECT account_state='linked_investor' FROM public.bootstrap_identity()),'B same login Investor experience');
END $$;
RESET ROLE;
-- C/L investor first, then verified Auth signup. The initial neutral account
-- shell has never completed Explorer onboarding or created an Explorer profile.
INSERT INTO auth.users(id,email,phone,email_confirmed_at,phone_confirmed_at)
VALUES('ab000000-0000-0000-0000-000000000010','absent@example.test','919000009999',now(),now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000010',true);
SELECT pg_temp.assert((SELECT account_state='linked_investor' FROM public.bootstrap_identity()),'C L first completed bootstrap Investor');
RESET ROLE;
SELECT pg_temp.assert((SELECT count(*)=1 FROM public.profiles WHERE user_id='ab000000-0000-0000-0000-000000000010'),'C no duplicate investor');
SELECT pg_temp.assert((SELECT count(*)=1 FROM public.advisor_investor_assignments WHERE investor_id=(SELECT investor_profile_id FROM moneybowl_onboarding.cases WHERE id='ab400000-0000-0000-0000-000000000001')),'I no duplicate assignment');
-- F account has another trusted business profile; no overwrite or detachment.
INSERT INTO public.profiles(user_id,role,full_name,account_status) VALUES('ab000000-0000-0000-0000-000000000007','investor','Prior identity','active');
INSERT INTO public.investor_account_links(user_id,profile_id,verification_method,verified_at)
SELECT user_id,id,'legacy_migration',now() FROM public.profiles WHERE user_id='ab000000-0000-0000-0000-000000000007';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE r jsonb; BEGIN
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),0,'{"legal_name":"Incompatible identity","pan":"ZZZPZ0007Z","email":"onboarding-7@example.test","mobile":"919000000007"}');
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,1);
 PERFORM pg_temp.assert(r->>'status'='IDENTITY_RECONCILIATION_REQUIRED','F account already linked elsewhere');
END $$;
RESET ROLE;

SELECT pg_temp.assert((SELECT p.full_name='Prior identity' FROM public.investor_account_links l JOIN public.profiles p ON p.id=l.profile_id WHERE l.user_id='ab000000-0000-0000-0000-000000000007' AND l.link_status='active'),'F prior link preserved');
-- A single confirmed contact is not enough for new MFD-asserted identity.
UPDATE auth.users SET phone_confirmed_at=NULL WHERE id='ab000000-0000-0000-0000-000000000008';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE r jsonb; old_version integer; BEGIN
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000008',0,
 '{"legal_name":"Synthetic Pending Evidence","pan":"ZZZPZ0008Z","email":"onboarding-8@example.test","mobile":"919000000008","kyc_status":"completed","nomination_choice":"opt_in"}');
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,1);
 PERFORM pg_temp.assert(r->>'account_link_status'<>'LINKED','typed contacts do not verify Auth');
 PERFORM pg_temp.assert(r->'missing' ? 'nominee_details' AND r->'missing' ? 'nomination_provider_support','nomination not defaulted');
 PERFORM pg_temp.assert(r->'missing' ? 'kyc_verification','MFD completed claim is not KYC verification');
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',(r->>'id')::uuid,(r->>'version')::integer,'{"email":"changed@example.test"}');
 RAISE EXCEPTION 'identity changed'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'resolved_identity_immutable' THEN RAISE; END IF; END;
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),0,'{"user_id":"ab000000-0000-0000-0000-000000000008"}');
 RAISE EXCEPTION 'caller picked account'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'invalid_onboarding_field' THEN RAISE; END IF; END;
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),0,'{"nomination_choice":"invented"}');
 RAISE EXCEPTION 'invented choice'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'invalid_onboarding_choice' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000008',true);
 PERFORM pg_temp.assert((SELECT account_state='link_pending' FROM public.bootstrap_identity()),'signup holds for verified evidence');
 PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000004',true);
 PERFORM pg_temp.assert((SELECT resolution='identity_reconciliation_required' FROM public.bootstrap_identity()),'E signup ambiguity explicit');
END $$;
RESET ROLE;
UPDATE auth.users SET phone_confirmed_at=now() WHERE id='ab000000-0000-0000-0000-000000000008';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000008',true);
SELECT pg_temp.assert((SELECT account_state='linked_investor' FROM public.bootstrap_identity()),'later verified contact links same account');
RESET ROLE;
-- Persist bank and registration in the same resolve transaction; retries do
-- not duplicate or accidentally upgrade captured evidence to verification.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE r jsonb; BEGIN
 r:=public.get_investor_onboarding('ab400000-0000-0000-0000-000000000001');
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',(r->>'id')::uuid,(r->>'version')::integer,
 '{"date_of_birth":"1990-01-01","legal_first_name":"Synthetic","gender":"female","residency_status":"resident_individual",
 "occupation":"service","holding_mode":"single","kyc_method":"kra","communication_preference":"electronic","onboarding_mode":"paper",
 "mobile_owner_relationship":"self","email_owner_relationship":"self","nomination_choice":"opt_out","account_number":"000000000001",
 "bank_name":"Synthetic Bank","account_type":"savings","ifsc_code":"ZZZZ0000001",
 "address_line_1":"Synthetic Address","city":"Synthetic City","region":"Synthetic Region","postal_code":"000000","country":"India"}');
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',(r->>'id')::uuid,(r->>'version')::integer,'{"micr_code":"000000001"}');
 PERFORM pg_temp.assert(NOT (r->'missing' ? 'micr_code'),'resume completes missing unverified bank input');
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,(r->>'version')::integer);
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,(r->>'version')::integer);
 PERFORM pg_temp.assert(r->'missing' ? 'bank_verification' AND r->'missing' ? 'kyc_verification','capture never verifies financial identity');
END $$;
RESET ROLE;
SELECT pg_temp.assert((SELECT count(*)=1 FROM public.investor_bank_accounts WHERE workspace_id='ab200000-0000-0000-0000-000000000001'),'bank retry idempotent');
SELECT pg_temp.assert((SELECT micr_code='000000001' AND verification_status='unverified' FROM public.investor_bank_accounts WHERE workspace_id='ab200000-0000-0000-0000-000000000001'),'unverified bank completion retained without verification escalation');
SELECT pg_temp.assert((SELECT count(*)=1 FROM public.investor_registration_profiles WHERE workspace_id='ab200000-0000-0000-0000-000000000001'),'registration profile reused');
SELECT pg_temp.assert((SELECT count(*)=1 FROM public.investor_addresses WHERE workspace_id='ab200000-0000-0000-0000-000000000001'),'address retry idempotent');
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.prepare_onboarded_investor_ucc('ab400000-0000-0000-0000-000000000001','SYNTHETIC');
 RAISE EXCEPTION 'missing prerequisites bypassed'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'onboarding_prerequisites_incomplete' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
-- The existing trusted verification pipeline supplies evidence, not the MFD.
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.get_investor_onboarding('ab400000-0000-0000-0000-000000000001');
 PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',(r->>'id')::uuid,(r->>'version')::integer,
 '{"tax_status":"01","occupation_code":"01","kyc_status":"completed","declarations":"synthetic consent evidence",
 "mobile_declaration_flag":"SE","email_declaration_flag":"SE","div_pay_mode":"02","nse_state":"WB","nse_country":"IND"}');
END $$;
RESET ROLE;
UPDATE public.investor_registration_profiles SET kyc_verified_at=now() WHERE workspace_id='ab200000-0000-0000-0000-000000000001';
UPDATE public.investor_bank_accounts SET verification_status='verified',verified_at=now() WHERE workspace_id='ab200000-0000-0000-0000-000000000001';
UPDATE public.profile_pan_records SET status='VERIFIED',verified_at=now() WHERE profile_id=(SELECT investor_profile_id FROM moneybowl_onboarding.cases WHERE id='ab400000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.get_investor_onboarding('ab400000-0000-0000-0000-000000000001');
 PERFORM pg_temp.assert(jsonb_array_length(r->'missing')=0 AND r->>'kyc_state'='VERIFIED','readiness derives from trusted evidence');
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',(r->>'id')::uuid,(r->>'version')::integer,'{"legal_first_name":"Changed"}');
 RAISE EXCEPTION 'verified registration overwritten'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'verified_registration_requires_review' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$ DECLARE op uuid; again uuid; BEGIN
 op:=public.prepare_onboarded_investor_ucc('ab400000-0000-0000-0000-000000000001','SYNTHETIC');
 again:=public.prepare_onboarded_investor_ucc('ab400000-0000-0000-0000-000000000001','SYNTHETIC');
 PERFORM pg_temp.assert(op=again,'external attempt idempotency');
 PERFORM pg_temp.assert(public.get_nse_ucc_registration_source(op)->>'operation_id'=op::text,'existing CLIENTCOMMON183 source consumes canonical onboarding');
END $$;
RESET ROLE;
SELECT pg_temp.assert((SELECT count(*)=1 FROM public.integration_operations WHERE workspace_id='ab200000-0000-0000-0000-000000000001'),'one external attempt');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert(public.get_investor_onboarding('ab400000-0000-0000-0000-000000000001')->>'status'='NSE_REGISTRATION_PENDING','lifecycle references actual NSE state');
RESET ROLE;
-- Unexpected historical duplicate business identities fail closed; migration
-- never deletes or silently merges them to manufacture a unique result.
INSERT INTO public.profiles(id,role,full_name,account_status) VALUES
 ('ab600000-0000-0000-0000-000000000001','investor','Duplicate Synthetic','active'),
 ('ab600000-0000-0000-0000-000000000002','investor','Duplicate Synthetic','active');
INSERT INTO public.profile_pan_records(profile_id,pan_ciphertext,pan_lookup_hmac,masked_pan,source,source_system,status)
 SELECT id,extensions.pgp_sym_encrypt('ZZZPZ0012Z',public.pan_encryption_key()),
 extensions.hmac('ZZZPZ0012Z',public.pan_lookup_hmac_key(),'sha256'),'******012Z','LEGACY','LEGACY','OBSERVED'
 FROM public.profiles WHERE id::text LIKE 'ab600000%';
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),0,'{"legal_name":"Duplicate Synthetic","pan":"ZZZPZ0012Z"}');
 r:=public.resolve_investor_onboarding((r->>'id')::uuid,1);
 PERFORM pg_temp.assert(r->>'status'='IDENTITY_RECONCILIATION_REQUIRED' AND r->>'investor_profile_id' IS NULL,'multiple canonical investors not guessed');
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',(r->>'id')::uuid,(r->>'version')::integer,'{"reconciliation_reason":""}');
 RAISE EXCEPTION 'client cleared conflict'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'invalid_onboarding_field' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
-- Assignment revocation removes read access to the saved investor inputs.
UPDATE public.advisor_investor_assignments SET status='ended',ended_at=now()
 WHERE investor_id=(SELECT investor_profile_id FROM moneybowl_onboarding.cases WHERE id='ab400000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.get_investor_onboarding('ab400000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'revoked assignment read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
-- Live revocation and non-MFD workspace roles must fail even with the same JWT.
UPDATE public.workspace_memberships SET ended_at=now() WHERE id='ab300000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.list_investor_onboarding('ab200000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'ended member allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE public.workspace_memberships SET ended_at=NULL,role='operations' WHERE id='ab300000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.get_investor_onboarding('ab400000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'operations allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 BEGIN UPDATE moneybowl_onboarding.events SET evidence='{}'; RAISE EXCEPTION 'audit mutable';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'onboarding_audit_immutable' THEN RAISE; END IF; END;
END $$;
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM moneybowl_onboarding.events WHERE evidence::text ~ 'ZZZPZ|"000000000001"|example.test'),'audit contains identifiers and verification provenance only');
SELECT pg_temp.assert(NOT has_schema_privilege('authenticated','moneybowl_onboarding','USAGE'),'private security boundary');
SELECT pg_temp.assert(NOT has_function_privilege('anon','public.save_investor_onboarding(uuid,uuid,integer,jsonb)','EXECUTE'),'anonymous denied');
SELECT pg_temp.assert(NOT has_function_privilege('authenticated','public.prepare_onboarded_investor_ucc(uuid,text)','EXECUTE'),'service hook protected');
SELECT pg_temp.assert(NOT has_function_privilege('authenticated','moneybowl_onboarding.legacy_bootstrap()','EXECUTE'),'legacy bootstrap not alternate browser route');
ROLLBACK;
