-- Synthetic identities only. Real API roles; no fixture privilege widening.
BEGIN;
CREATE FUNCTION pg_temp.id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT md5('platform-v1-'||n)::uuid $$;
CREATE FUNCTION pg_temp.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; RAISE NOTICE 'PASS: %',label; END $$;
CREATE FUNCTION pg_temp.denied(statement text,label text,expected text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN insufficient_privilege OR raise_exception OR check_violation OR unique_violation THEN
  IF expected IS NOT NULL AND SQLERRM<>expected THEN RAISE EXCEPTION 'FAIL: %: unexpected %',label,SQLERRM; END IF;
  RAISE NOTICE 'PASS: %',label; RETURN;
 END;
 RAISE EXCEPTION 'FAIL: % unexpectedly succeeded',label;
END $$;
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM platform_authority.grants),'migration commissions nobody');
INSERT INTO auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
SELECT pg_temp.id(n),'platform-test-'||n||'@example.test',now(),'{"user_role":"platform_admin"}','{"role":"platform_admin","account_state":"advisor"}' FROM generate_series(1,11) n;
INSERT INTO public.profiles(id,user_id,role)
SELECT pg_temp.id(n),pg_temp.id(n),r FROM (VALUES(1,'advisor'),(2,'admin'),(3,'operations'),(4,'investor'),(6,'platform_admin')) v(n,r);
INSERT INTO public.workspaces(id,name,slug,owner_profile_id) VALUES(pg_temp.id(100),'MFD A','platform-test-a',pg_temp.id(2));
INSERT INTO public.workspace_memberships(id,workspace_id,profile_id,role)
SELECT pg_temp.id(100+n),pg_temp.id(100),pg_temp.id(n),r FROM (VALUES(1,'advisor'),(2,'admin'),(3,'operations'),(4,'investor')) v(n,r);
INSERT INTO public.portfolios(id,workspace_id,client_id) VALUES(pg_temp.id(200),pg_temp.id(100),pg_temp.id(4));
INSERT INTO public.investor_account_links(user_id,profile_id,verification_method) VALUES(pg_temp.id(4),pg_temp.id(4),'synthetic');
INSERT INTO public.advisor_investor_assignments(workspace_id,advisor_id,investor_id) VALUES(pg_temp.id(100),pg_temp.id(1),pg_temp.id(4));
INSERT INTO public.order_requests(id,workspace_id,investor_profile_id,scheme_code,type,amount,status,initiated_by_profile_id,initiated_by_role,initiation_channel)
VALUES(pg_temp.id(300),pg_temp.id(100),pg_temp.id(4),'PLATFORM-TEST','buy',100,'pending_review',pg_temp.id(1),'advisor','advisor_portal');
INSERT INTO public.verification_requests(id,user_id,method_code,status,workspace_id) VALUES(pg_temp.id(400),pg_temp.id(4),'folio','pending_advisor_review',pg_temp.id(100));
INSERT INTO public.mutual_funds(id,scheme_code,scheme_name,current_nav) VALUES(pg_temp.id(500),'PLATFORM-TEST','Platform fixture',10);

SET LOCAL ROLE authenticated;
DO $$ DECLARE n integer; BEGIN
 FOREACH n IN ARRAY ARRAY[1,2,3,4,5,6] LOOP
  PERFORM set_config('request.jwt.claim.sub',pg_temp.id(n)::text,true);
  PERFORM pg_temp.ok(NOT public.is_platform_admin(),'ordinary or legacy profile label grants no platform authority: '||n);
  PERFORM pg_temp.ok(NOT public.has_platform_capability('mfd_applications.review'),'metadata grants no review capability: '||n);
 END LOOP;
END $$;
SELECT set_config('request.jwt.claim.sub',pg_temp.id(6)::text,true);
SELECT pg_temp.ok((SELECT account_state='explorer' FROM public.bootstrap_identity()),'legacy platform profile no longer maps to advisor');
SELECT set_config('request.jwt.claim.sub',pg_temp.id(5)::text,true);
SELECT pg_temp.ok((SELECT account_state='explorer' FROM public.bootstrap_identity()),'public signup still neutral Explorer');
SELECT pg_temp.denied('select platform_authority.grant_authority(pg_temp.id(5),''platform_admin'',pg_temp.id(50),''self grant test'')','browser self grant denied');
SELECT pg_temp.denied('insert into platform_authority.grants(user_id,grant_key,granted_by,evidence,grant_request_id) values(pg_temp.id(5),''platform_admin'',''fake'',''self grant test'',pg_temp.id(50))','browser raw insert denied');
SELECT pg_temp.denied('select * from platform_authority.grants','grant table private');
SELECT pg_temp.ok(to_regprocedure('public.get_my_platform_context(uuid)') IS NULL,'projection has no caller-selected account overload');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.denied('select platform_authority.bootstrap_first_admin(pg_temp.id(7),pg_temp.id(701),pg_temp.id(702),''operator verification record'')','service key cannot commission privilege');
RESET ROLE;

SELECT pg_temp.denied('select platform_authority.bootstrap_first_admin(pg_temp.id(7),pg_temp.id(701),pg_temp.id(701),''operator verification record'')','conflicting bootstrap requests fail atomically','platform_request_conflict');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM platform_authority.grants) AND NOT EXISTS(SELECT 1 FROM platform_authority.events),'failed bootstrap leaves no partial authority or audit');
SELECT platform_authority.bootstrap_first_admin(pg_temp.id(7),pg_temp.id(701),pg_temp.id(702),'operator verification record');
SELECT platform_authority.bootstrap_first_admin(pg_temp.id(7),pg_temp.id(701),pg_temp.id(702),'operator verification record');
SELECT pg_temp.ok((SELECT count(*)=2 FROM platform_authority.grants WHERE user_id=pg_temp.id(7)),'bootstrap idempotent grants');
SELECT pg_temp.ok((SELECT count(*)=2 FROM platform_authority.events WHERE user_id=pg_temp.id(7)),'bootstrap idempotent audit');
SELECT pg_temp.denied('select platform_authority.bootstrap_first_admin(pg_temp.id(8),pg_temp.id(801),pg_temp.id(802),''operator verification record'')','second first-admin attempt denied','platform_bootstrap_already_commissioned');
SELECT pg_temp.denied('update platform_authority.grants set evidence=''tampered provenance'' where grant_request_id=pg_temp.id(701)','grant provenance immutable','platform_grant_provenance_immutable');
SELECT pg_temp.denied('delete from platform_authority.events','audit history immutable','platform_audit_immutable');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM public.profiles WHERE user_id=pg_temp.id(7)),'platform-only operator has no profile, ARN or EUIN');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM public.investor_account_links WHERE user_id=pg_temp.id(7)),'platform-only operator has no investor identity');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',pg_temp.id(7)::text,true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.id(7),'role','authenticated','aal','aal1')::text,true);
SELECT pg_temp.ok(public.is_platform_admin(),'active grant enables platform context without workspace');
SELECT pg_temp.ok(public.has_platform_capability('mfd_applications.review'),'explicit review capability discoverable');
SELECT pg_temp.ok(NOT public.has_platform_capability('platform.catalog.manage'),'admin implies no ungranted catalogue capability');
SELECT pg_temp.ok((public.get_my_platform_context()->'capabilities') ? 'mfd_applications.review','safe own projection exposes bounded capability');
SELECT pg_temp.ok((SELECT account_state='explorer' AND resolution='platform_context' FROM public.bootstrap_identity()),'platform bootstrap uses neutral state');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.portfolios),'platform grant provides no MFD portfolio reads');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.transactions),'platform grant provides no MFD transaction reads');
SELECT pg_temp.ok(NOT public.is_workspace_admin(pg_temp.id(100)),'platform admin is not workspace admin');
SELECT pg_temp.ok(NOT public.can_select_order_request(pg_temp.id(100),pg_temp.id(4)),'platform grant provides no order authority');
SELECT pg_temp.denied('select public.qualify_order(pg_temp.id(300),''approved'')','platform-only operator cannot qualify order');
SELECT pg_temp.ok(public.get_nse_read_context_v1(pg_temp.id(104))#>>'{error,code}'='NOT_AUTHORIZED','platform grant provides no NSE authority');
SELECT pg_temp.ok(NOT public.can_review_verification(pg_temp.id(400)),'platform grant provides no tenant folio review');
SELECT pg_temp.denied('select public.begin_folio_review(pg_temp.id(400),1)','platform folio decision denied');
SELECT pg_temp.denied('select public.authorize_cams_kfintech_workspace(pg_temp.id(100))','platform grant provides no ingestion authority');
SELECT pg_temp.denied('select * from public.ingested_documents','platform grant provides no document access');
SELECT pg_temp.denied('update platform_authority.grants set revoked_at=now()','browser raw revoke denied');
SELECT pg_temp.denied('select platform_authority.revoke_authority(pg_temp.id(701),pg_temp.id(750),''browser revocation'')','browser revoke function denied');
SELECT pg_temp.ok(NOT public.platform_admin_step_up_verified(),'AAL1 denies step-up');
SELECT pg_temp.denied('select public.platform_update_fund_nav(pg_temp.id(500),11,current_date)','ungranted sensitive operation denied','platform_capability_required');
SELECT pg_temp.denied('select public.begin_platform_admin_override_attempt(pg_temp.id(100),''family_delegations'',pg_temp.id(900),''family_delegation.read'',''support request'',pg_temp.id(910))','admin alone cannot start tenant support override','platform_capability_required');
RESET ROLE;

SELECT platform_authority.grant_authority(pg_temp.id(7),'platform.catalog.manage',pg_temp.id(703),'catalogue maintenance authority');
SET LOCAL ROLE authenticated;
SELECT pg_temp.denied('select public.platform_update_fund_nav(pg_temp.id(500),11,current_date)','granted sensitive operation still denies AAL1','platform_admin_step_up_required');
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.id(7),'role','authenticated','aal','aal2','session_id',pg_temp.id(710))::text,true);
SELECT pg_temp.ok(NOT public.platform_admin_step_up_verified(),'AAL2 claim alone without session/factor is insufficient');
RESET ROLE;
-- Synthetic GoTrue state tests the enforcement contract; this enrolls nobody.
INSERT INTO auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) VALUES(pg_temp.id(711),pg_temp.id(7),'totp','verified',now(),now());
INSERT INTO auth.sessions(id,user_id,factor_id,aal) VALUES(pg_temp.id(710),pg_temp.id(7),pg_temp.id(711),'aal2');
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.platform_admin_step_up_verified(),'AAL2 with live own session and verified factor accepted');
SELECT public.platform_update_fund_nav(pg_temp.id(500),11,current_date);
SELECT pg_temp.ok((SELECT current_nav=11 FROM public.mutual_funds WHERE id=pg_temp.id(500)),'explicit capability plus MFA permits catalogue update');
RESET ROLE;
SELECT pg_temp.ok(EXISTS(SELECT 1 FROM platform_authority.events WHERE action='catalog.nav_updated' AND actor_user_id=pg_temp.id(7)),'sensitive mutation audited with auth actor');
-- Existing narrow support overrides use an explicit grant and auth-user audit,
-- including profile-free operators; a recorded attempt never outlives authority.
SELECT platform_authority.grant_authority(pg_temp.id(7),'platform.family_support',pg_temp.id(704),'separate approved support access');
INSERT INTO public.family_delegations(id,workspace_id,owner_profile_id,delegate_profile_id,consent_status,is_active,expires_at)
VALUES(pg_temp.id(900),pg_temp.id(100),pg_temp.id(4),pg_temp.id(1),'accepted',false,now()+interval '1 day');
SET LOCAL ROLE authenticated;
SELECT public.begin_platform_admin_override_attempt(pg_temp.id(100),'family_delegations',pg_temp.id(900),'family_delegation.restore_access','specific approved support case',pg_temp.id(910));
SELECT public.begin_platform_admin_override_attempt(pg_temp.id(100),'family_delegations',pg_temp.id(900),'family_delegation.read','specific approved support case',pg_temp.id(911));
RESET ROLE;
SELECT pg_temp.ok(EXISTS(SELECT 1 FROM public.workspace_audit_logs WHERE correlation_id=pg_temp.id(910) AND actor_user_id=pg_temp.id(7) AND actor_profile_id IS NULL),'support audit requires no fake business profile');
SET LOCAL ROLE service_role;
SELECT pg_temp.ok((public.platform_admin_restore_family_delegation_access(pg_temp.id(910),pg_temp.id(100),pg_temp.id(900),pg_temp.id(4),pg_temp.id(1))).is_active,'explicit MFA-gated support restores only bound delegation');
SELECT public.finish_platform_admin_override_attempt(pg_temp.id(910),'override.succeeded');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.platform_admin_read_family_delegation_support_projection(pg_temp.id(911),pg_temp.id(100),pg_temp.id(900),pg_temp.id(4),pg_temp.id(1))),'separately authorized support projection retains exact target');
RESET ROLE;
SELECT platform_authority.revoke_authority((SELECT id FROM platform_authority.grants WHERE grant_request_id=pg_temp.id(704)),pg_temp.id(754),'specific support authority retired');
SET LOCAL ROLE service_role;
SELECT pg_temp.denied('select public.platform_admin_read_family_delegation_support_projection(pg_temp.id(911),pg_temp.id(100),pg_temp.id(900),pg_temp.id(4),pg_temp.id(1))','recorded support attempt cannot bypass current revocation','platform_support_authority_expired');
RESET ROLE;
UPDATE auth.mfa_factors SET status='unverified' WHERE id=pg_temp.id(711);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(NOT public.platform_admin_step_up_verified(),'removed verified factor invalidates retained AAL2');
RESET ROLE;
UPDATE auth.mfa_factors SET status='verified' WHERE id=pg_temp.id(711);
UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id=pg_temp.id(710);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(NOT public.platform_admin_step_up_verified(),'expired session invalidates retained AAL2');
RESET ROLE;
UPDATE auth.sessions SET not_after=NULL WHERE id=pg_temp.id(710);

-- DB revocation changes authorization with exactly the same retained claims.
SELECT platform_authority.revoke_authority((SELECT id FROM platform_authority.grants WHERE grant_request_id=pg_temp.id(702)),pg_temp.id(752),'review authority retired');
SELECT platform_authority.revoke_authority((SELECT id FROM platform_authority.grants WHERE grant_request_id=pg_temp.id(702)),pg_temp.id(752),'review authority retired');
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.is_platform_admin() AND NOT public.has_platform_capability('mfd_applications.review'),'capability revocation immediate without JWT refresh');
SELECT pg_temp.ok(NOT (public.get_my_platform_context()->'capabilities') ? 'mfd_applications.review','projection reflects capability revocation');
RESET ROLE;
DO $$ DECLARE state text; BEGIN
 FOREACH state IN ARRAY ARRAY['UPDATE auth.users SET banned_until=now()+interval ''1 hour'' WHERE id=pg_temp.id(7)',
 'UPDATE auth.users SET deleted_at=now() WHERE id=pg_temp.id(7)',
 'UPDATE auth.users SET is_anonymous=true WHERE id=pg_temp.id(7)'] LOOP
  EXECUTE state; EXECUTE 'set local role authenticated';
  PERFORM pg_temp.ok(NOT public.is_platform_admin(),'account lifecycle overrides grant: '||state);
  EXECUTE 'reset role'; UPDATE auth.users SET banned_until=NULL,deleted_at=NULL,is_anonymous=false WHERE id=pg_temp.id(7);
 END LOOP;
END $$;
INSERT INTO public.profiles(id,user_id,role,account_status) VALUES(pg_temp.id(7),pg_temp.id(7),'user','suspended');
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(NOT public.is_platform_admin(),'optional suspended account profile denies platform authority');
RESET ROLE;
UPDATE public.profiles SET account_status='active',role='advisor' WHERE id=pg_temp.id(7);
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role) VALUES(pg_temp.id(100),pg_temp.id(7),'admin');
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(NOT public.is_workspace_admin(pg_temp.id(100)) AND (SELECT count(*)=0 FROM public.portfolios),'platform operator cannot reuse obsolete advisor membership');
SELECT pg_temp.ok((SELECT account_state='explorer' FROM public.bootstrap_identity()),'obsolete advisor state cannot override platform context');
RESET ROLE;
UPDATE public.workspace_memberships SET status='inactive',ended_at=now() WHERE profile_id=pg_temp.id(7);
UPDATE public.profiles SET role='user' WHERE id=pg_temp.id(7);
SELECT platform_authority.revoke_authority((SELECT id FROM platform_authority.grants WHERE grant_request_id=pg_temp.id(701)),pg_temp.id(751),'platform operator retired');
SELECT pg_temp.denied('select platform_authority.bootstrap_first_admin(pg_temp.id(7),pg_temp.id(701),pg_temp.id(702),''operator verification record'')','replayed bootstrap cannot resurrect revoked authority','platform_grant_revoked');
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(NOT public.is_platform_admin() AND NOT public.has_platform_capability('platform.catalog.manage'),'admin revocation immediately removes all effective capabilities');
SELECT pg_temp.ok(public.get_my_platform_context()->>'is_platform_admin'='false','same JWT projection reflects role revocation');
SELECT pg_temp.denied('select public.platform_update_fund_nav(pg_temp.id(500),12,current_date)','revoked admin cannot mutate with retained AAL2','platform_capability_required');
SELECT pg_temp.ok((SELECT account_state='explorer' FROM public.bootstrap_identity()),'retired operator returns to neutral account');
SELECT set_config('request.jwt.claim.sub',pg_temp.id(5)::text,true);
SELECT pg_temp.ok(public.get_my_platform_context()->'capabilities'='[]'::jsonb,'caller sees only own projection');
SELECT set_config('request.jwt.claim.sub',pg_temp.id(2)::text,true);
INSERT INTO public.workspace_invitations(workspace_id,email,role,invited_by,token_hash,expires_at)
VALUES(pg_temp.id(100),'platform-test-11@example.test','advisor',pg_temp.id(2),encode(extensions.digest('platform-invite','sha256'),'hex'),now()+interval '1 hour');
SELECT set_config('request.jwt.claim.sub',pg_temp.id(11)::text,true);
SELECT pg_temp.ok(public.accept_workspace_invitation('platform-invite'),'normal advisor invitation still works');
SELECT pg_temp.ok(NOT public.is_platform_admin() AND NOT public.has_platform_capability('mfd_applications.review'),'advisor invitation grants no platform authority');
RESET ROLE;
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='platform_authority' AND (has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE') OR has_function_privilege('anon',p.oid,'EXECUTE'))),'private authority functions inaccessible to all Data API roles');
SELECT pg_temp.ok(NOT has_function_privilege('anon','public.get_my_platform_context()','EXECUTE'),'anonymous projection denied');
SELECT pg_temp.ok((SELECT count(*)=3 FROM platform_authority.events WHERE user_id=pg_temp.id(7) AND action='revoked'),'replayed revocation creates no duplicate audit');
ROLLBACK;
