-- Synthetic fixtures; only the disposable full-schema harness executes this suite.
BEGIN;
CREATE FUNCTION pg_temp.mid(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT md5('mfd-v1-'||n)::uuid $$;
CREATE FUNCTION pg_temp.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; RAISE NOTICE 'PASS: %',label; END $$;
CREATE FUNCTION pg_temp.denied(statement text,label text,expected text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN insufficient_privilege OR raise_exception OR check_violation OR unique_violation OR foreign_key_violation THEN
  IF expected IS NOT NULL AND SQLERRM<>expected THEN RAISE EXCEPTION 'FAIL: %: unexpected %',label,SQLERRM; END IF;
  RAISE NOTICE 'PASS: %',label; RETURN;
 END;
 RAISE EXCEPTION 'FAIL: % unexpectedly succeeded',label;
END $$;
CREATE FUNCTION pg_temp.login(n integer,aal text DEFAULT 'aal1',session_n integer DEFAULT 0) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.mid(n),'role','authenticated','aal',aal,'session_id',pg_temp.mid(session_n))::text,true)::void
$$;
INSERT INTO auth.users(id,email,email_confirmed_at)
SELECT pg_temp.mid(n),'mfd-'||n||'@example.test',now() FROM generate_series(1,35) n;
-- 1 reviewer; 2 second reviewer; 3 admin-only; 4 capability-only; 5 tenant admin.
SELECT platform_authority.grant_authority(pg_temp.mid(1),'platform_admin',pg_temp.mid(101),'synthetic platform reviewer');
SELECT platform_authority.grant_authority(pg_temp.mid(1),'mfd_applications.review',pg_temp.mid(102),'synthetic application reviewer');
SELECT platform_authority.grant_authority(pg_temp.mid(2),'platform_admin',pg_temp.mid(103),'synthetic second reviewer');
SELECT platform_authority.grant_authority(pg_temp.mid(2),'mfd_applications.review',pg_temp.mid(104),'synthetic second reviewer');
SELECT platform_authority.grant_authority(pg_temp.mid(3),'platform_admin',pg_temp.mid(105),'synthetic admin only');
SELECT platform_authority.grant_authority(pg_temp.mid(4),'platform_admin',pg_temp.mid(106),'synthetic removed base');
SELECT platform_authority.grant_authority(pg_temp.mid(4),'mfd_applications.review',pg_temp.mid(107),'synthetic orphan capability');
SELECT platform_authority.revoke_authority((SELECT id FROM platform_authority.grants WHERE grant_request_id=pg_temp.mid(106)),pg_temp.mid(108),'synthetic revoke base');
INSERT INTO auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at)
SELECT pg_temp.mid(200+n),pg_temp.mid(n),'totp','verified',now(),now() FROM generate_series(1,4) n;
INSERT INTO auth.sessions(id,user_id,factor_id,aal)
SELECT pg_temp.mid(300+n),pg_temp.mid(n),pg_temp.mid(200+n),'aal2' FROM generate_series(1,4) n;
INSERT INTO public.profiles(id,user_id,role) VALUES(pg_temp.mid(405),pg_temp.mid(5),'advisor');
INSERT INTO public.workspaces(id,name,slug,owner_profile_id) VALUES(pg_temp.mid(505),'Existing tenant','mfd-existing-tenant',pg_temp.mid(405));
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role) VALUES(pg_temp.mid(505),pg_temp.mid(405),'admin');
UPDATE auth.users SET email_confirmed_at=NULL WHERE id=pg_temp.mid(11);
UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=pg_temp.mid(12);
UPDATE auth.users SET deleted_at=now() WHERE id=pg_temp.mid(13);
UPDATE auth.users SET is_anonymous=true WHERE id=pg_temp.mid(14);
UPDATE public.user_accounts SET account_state='link_pending' WHERE user_id=pg_temp.mid(15);
INSERT INTO public.profiles(user_id,role,account_status) VALUES(pg_temp.mid(16),'investor','active'),(pg_temp.mid(17),'user','suspended');

SET LOCAL ROLE authenticated;
SELECT pg_temp.login(10);
SELECT pg_temp.ok((public.get_my_mfd_application_context()->>'can_apply')::boolean,'clean Explorer eligible');
SELECT public.submit_mfd_application(pg_temp.mid(1000),'  Example MFD  ','  arbitrary ARN / claim  ','  applicant note  ');
SELECT pg_temp.ok((SELECT applicant_user_id=pg_temp.mid(10) AND business_name='Example MFD' AND claimed_arn='arbitrary ARN / claim' AND version=1 FROM public.mfd_applications),'server identity and trimmed unvalidated claims');
SELECT pg_temp.ok(public.submit_mfd_application(pg_temp.mid(1000),'Example MFD','arbitrary ARN / claim','applicant note')=public.submit_mfd_application(pg_temp.mid(1000),'Example MFD','arbitrary ARN / claim','applicant note'),'submission receipt replay');
SELECT pg_temp.denied($q$SELECT public.submit_mfd_application(pg_temp.mid(1000),'Changed','arbitrary ARN / claim','applicant note')$q$,'modified submission request conflicts','mfd_request_conflict');
SELECT pg_temp.denied($q$SELECT public.submit_mfd_application(pg_temp.mid(1001),'Another','ARN',NULL)$q$,'one open application','mfd_application_open');
SELECT pg_temp.denied($q$UPDATE public.mfd_applications SET status='approved'$q$,'applicant cannot approve or edit');
SELECT pg_temp.denied($q$INSERT INTO public.mfd_applications(applicant_user_id,applicant_email,business_name,claimed_arn,profile_id) VALUES(pg_temp.mid(10),'fake','fake','fake',pg_temp.mid(405))$q$,'direct submission and result IDs denied');
SELECT pg_temp.denied($q$DELETE FROM public.mfd_application_events$q$,'direct event delete denied');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.mfd_application_events),'applicant own submitted event');
SELECT pg_temp.login(18);
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.mfd_applications) AND (SELECT count(*)=0 FROM public.mfd_application_events),'another applicant cannot read application/events');
DO $$ DECLARE n integer; BEGIN
 FOREACH n IN ARRAY ARRAY[1,5,11,12,13,14,15,16,17] LOOP
  PERFORM pg_temp.login(n);
  PERFORM pg_temp.denied(format('SELECT public.submit_mfd_application(%L,''Business'',''ARN'',NULL)',pg_temp.mid(1100+n)),'ineligible applicant '||n,'mfd_applicant_ineligible');
 END LOOP;
END $$;
SELECT pg_temp.login(10);
SELECT pg_temp.denied($q$SELECT public.submit_mfd_application(pg_temp.mid(1110),'','ARN',NULL)$q$,'blank business name denied','mfd_invalid_input');
SELECT pg_temp.denied($q$SELECT public.submit_mfd_application(pg_temp.mid(1110),'B',repeat('a',101),NULL)$q$,'oversize ARN denied','mfd_invalid_input');
RESET ROLE;
-- Claims remain immutable even to a table owner; RPC role ACL is not the only defence.
SELECT pg_temp.denied($q$UPDATE public.mfd_applications SET claimed_arn='changed'$q$,'claim trigger immutable','mfd_claims_immutable');
SELECT pg_temp.denied($q$UPDATE public.mfd_application_events SET details='{}'$q$,'event update immutable','mfd_history_immutable');
SELECT pg_temp.denied($q$DELETE FROM public.mfd_application_events$q$,'event delete immutable','mfd_history_immutable');
SELECT pg_temp.denied($q$DELETE FROM public.mfd_applications$q$,'application history preserved','mfd_history_immutable');
-- Persist UUID in a temp helper, not browser-authorized access to private data.
CREATE FUNCTION pg_temp.app(n integer) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$ SELECT id FROM public.mfd_applications WHERE applicant_user_id=pg_temp.mid(n) ORDER BY submitted_at DESC,id LIMIT 1 $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.login(5);
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.mfd_applications),'tenant admin has no review reads');
SELECT pg_temp.denied($q$SELECT public.start_mfd_application_review(pg_temp.app(10),1,pg_temp.mid(1200))$q$,'tenant admin cannot review','platform_capability_required');
SELECT pg_temp.login(1);
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.mfd_applications),'review capability reads queue at AAL1');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.workspaces),'review capability gives no tenant reads');
SELECT public.start_mfd_application_review(pg_temp.app(10),1,pg_temp.mid(1201));
SELECT public.start_mfd_application_review(pg_temp.app(10),1,pg_temp.mid(1201));
SELECT pg_temp.login(2);
SELECT public.start_mfd_application_review(pg_temp.app(10),1,pg_temp.mid(1202));
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.mfd_application_events WHERE event_type='review_started'),'start review records one event across reviewers/retries');
DO $$ DECLARE n integer; BEGIN
 FOREACH n IN ARRAY ARRAY[3,4,5,10] LOOP
  PERFORM pg_temp.login(n,'aal2',300+n);
  PERFORM pg_temp.denied('SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),''manual review reference'')','unauthorized approve '||n,'platform_capability_required');
 END LOOP;
END $$;
SELECT pg_temp.login(1);
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference')$q$,'AAL1 approval denied','platform_admin_step_up_required');
SELECT pg_temp.denied($q$SELECT public.reject_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'reason')$q$,'AAL1 rejection denied','platform_admin_step_up_required');
SELECT pg_temp.login(1,'aal2',302);
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference')$q$,'another operator session denied','platform_admin_step_up_required');
SELECT pg_temp.denied($q$SELECT public.reject_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'reason')$q$,'another operator session rejection denied','platform_admin_step_up_required');
SELECT pg_temp.login(1,'aal2',999);
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference')$q$,'fake AAL2 denied','platform_admin_step_up_required');
RESET ROLE;
UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id=pg_temp.mid(301);
SET LOCAL ROLE authenticated;
SELECT pg_temp.login(1,'aal2',301);
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference')$q$,'expired session denied','platform_admin_step_up_required');
RESET ROLE;
UPDATE auth.sessions SET not_after=NULL WHERE id=pg_temp.mid(301);
UPDATE auth.mfa_factors SET status='unverified' WHERE id=pg_temp.mid(201);
SET LOCAL ROLE authenticated;
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference')$q$,'removed factor denied','platform_admin_step_up_required');
RESET ROLE;
UPDATE auth.mfa_factors SET status='verified' WHERE id=pg_temp.mid(201);
SET LOCAL ROLE authenticated;
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'  ')$q$,'evidence required','mfd_decision_note_required');
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),1,pg_temp.mid(1300),'reviewed')$q$,'stale version denied','mfd_application_changed');
RESET ROLE;
CREATE TEMP TABLE mfd_counts AS SELECT
 (SELECT count(*) FROM public.advisor_profiles) ap,(SELECT count(*) FROM public.advisor_euin_assignments) euin,
 (SELECT count(*) FROM public.investor_account_links) links,(SELECT count(*) FROM public.advisor_investor_assignments) assignments,
 (SELECT count(*) FROM public.portfolios) portfolios,(SELECT count(*) FROM public.order_requests) orders,
 (SELECT count(*) FROM public.integration_accounts) nse,(SELECT count(*) FROM public.integration_operations) nse_ops,
 (SELECT count(*) FROM nse_reference.connections) connections,(SELECT count(*) FROM platform_authority.grants) grants,
 (SELECT count(*) FROM platform_authority.events) platform_events,(SELECT count(*) FROM public.workspace_billing) billing,
 (SELECT count(*) FROM public.folio_grants) folio,(SELECT count(*) FROM public.verification_request_assignments) reviews,
 (SELECT count(*) FROM public.distributor_details) distributor,(SELECT count(*) FROM public.event_outbox) outbox;
-- Fault injection at the final audit proves all earlier authority and events roll back.
CREATE FUNCTION pg_temp.fail_mfd_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='mfd.application_provisioned' THEN RAISE EXCEPTION 'synthetic_audit_failure'; END IF; RETURN NEW; END $$;
CREATE TRIGGER mfd_test_failure BEFORE INSERT ON public.workspace_audit_logs FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_mfd_audit();
SET LOCAL ROLE authenticated;
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference')$q$,'late failure rolls back','synthetic_audit_failure');
RESET ROLE;
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM public.profiles WHERE user_id=pg_temp.mid(10)) AND NOT EXISTS(SELECT 1 FROM public.workspaces WHERE slug='mfd-'||pg_temp.app(10)::text) AND NOT EXISTS(SELECT 1 FROM public.mfd_application_events WHERE event_type='approved') AND NOT EXISTS(SELECT 1 FROM mfd_application_private.requests WHERE request_id=pg_temp.mid(1300)),'failed approval leaves no authority/event/receipt');
DROP TRIGGER mfd_test_failure ON public.workspace_audit_logs;
SET LOCAL ROLE authenticated;
SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference');
SELECT pg_temp.ok(public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference')->>'status'='approved','approval replay returns receipt despite changed account/version');
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'different evidence')$q$,'changed evidence conflict','mfd_request_conflict');
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.mid(999),2,pg_temp.mid(1300),'manual review reference')$q$,'changed target conflict','mfd_request_conflict');
SELECT pg_temp.denied($q$SELECT public.reject_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference')$q$,'changed operation conflict','mfd_request_conflict');
SELECT pg_temp.denied($q$SELECT public.reject_mfd_application(pg_temp.app(10),3,pg_temp.mid(1301),'reject')$q$,'second terminal decision denied','mfd_application_decided');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.workspaces),'reviewer still sees no tenant workspace after approval');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.profiles WHERE user_id=pg_temp.mid(10) AND role='advisor' AND account_status='active'),'one active professional profile');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.mfd_applications a JOIN public.profiles p ON p.id=a.profile_id JOIN public.workspaces w ON w.id=a.workspace_id JOIN public.workspace_memberships m ON m.id=a.membership_id WHERE a.applicant_user_id=pg_temp.mid(10) AND a.status='approved' AND a.approved_arn=a.claimed_arn AND a.decision_note='manual review reference' AND w.owner_profile_id=p.id AND w.slug='mfd-'||a.id::text AND m.profile_id=p.id AND m.workspace_id=w.id AND m.role='admin' AND m.status='active' AND m.ended_at IS NULL),'approved result and ownership/membership binding');
SELECT pg_temp.ok((SELECT account_state='advisor' AND onboarding_completed FROM public.user_accounts WHERE user_id=pg_temp.mid(10)),'professional routing state');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.workspace_audit_logs WHERE action='mfd.application_provisioned' AND actor_user_id=pg_temp.mid(1) AND actor_id IS NULL AND actor_profile_id IS NULL),'audit uses reviewer auth UUID without business profile');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.mfd_application_events WHERE event_type='approved'),'one approval event');
SELECT pg_temp.ok((SELECT ap=(SELECT count(*) FROM public.advisor_profiles) AND euin=(SELECT count(*) FROM public.advisor_euin_assignments) AND links=(SELECT count(*) FROM public.investor_account_links) AND assignments=(SELECT count(*) FROM public.advisor_investor_assignments) AND portfolios=(SELECT count(*) FROM public.portfolios) AND orders=(SELECT count(*) FROM public.order_requests) AND nse=(SELECT count(*) FROM public.integration_accounts) AND nse_ops=(SELECT count(*) FROM public.integration_operations) AND connections=(SELECT count(*) FROM nse_reference.connections) AND grants=(SELECT count(*) FROM platform_authority.grants) AND platform_events=(SELECT count(*) FROM platform_authority.events) AND billing=(SELECT count(*) FROM public.workspace_billing) AND folio=(SELECT count(*) FROM public.folio_grants) AND reviews=(SELECT count(*) FROM public.verification_request_assignments) AND distributor=(SELECT count(*) FROM public.distributor_details) AND outbox=(SELECT count(*) FROM public.event_outbox) FROM mfd_counts),'all explicitly excluded entities unchanged');
SET LOCAL ROLE authenticated;
SELECT pg_temp.login(10);
SELECT pg_temp.ok(public.has_advisor_membership((SELECT workspace_id FROM public.mfd_applications WHERE applicant_user_id=auth.uid())),'approved applicant gets scoped professional membership');
SELECT pg_temp.ok((SELECT account_state='advisor' FROM public.bootstrap_identity()),'existing bootstrap recognizes approved tenant');
SELECT pg_temp.denied($q$SELECT public.submit_mfd_application(pg_temp.mid(1302),'Again','ARN',NULL)$q$,'approved applicant cannot apply again','mfd_applicant_ineligible');
-- Rejection preserves a separately changed identity and permits a new clean application later.
SELECT pg_temp.login(18);
SELECT public.submit_mfd_application(pg_temp.mid(1400),'Rejected MFD','ARN',NULL);
SELECT pg_temp.login(2);
SELECT public.start_mfd_application_review(pg_temp.app(18),1,pg_temp.mid(1401));
SELECT pg_temp.login(2,'aal2',302);
SELECT pg_temp.denied($q$SELECT public.reject_mfd_application(pg_temp.app(18),2,pg_temp.mid(1402),'')$q$,'rejection reason required','mfd_decision_note_required');
SELECT public.reject_mfd_application(pg_temp.app(18),2,pg_temp.mid(1402),'Please provide a clearer registration reference');
SELECT public.reject_mfd_application(pg_temp.app(18),2,pg_temp.mid(1402),'Please provide a clearer registration reference');
SELECT pg_temp.denied($q$SELECT public.reject_mfd_application(pg_temp.app(18),2,pg_temp.mid(1402),'changed')$q$,'rejection payload conflict','mfd_request_conflict');
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(18),2,pg_temp.mid(1403),'reviewed')$q$,'rejected cannot approve','mfd_application_decided');
SELECT pg_temp.login(18);
SELECT pg_temp.ok((public.get_my_mfd_application_context()->>'can_apply')::boolean,'rejected clean Explorer may reapply');
SELECT public.submit_mfd_application(pg_temp.mid(1404),'New application','ARN',NULL);
RESET ROLE;
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM public.profiles WHERE user_id=pg_temp.mid(18)) AND (SELECT account_state='explorer' FROM public.user_accounts WHERE user_id=pg_temp.mid(18)),'rejection preserves account without authority');
-- Eligibility is checked again, not assumed from submission.
SET LOCAL ROLE authenticated;
DO $$ DECLARE n integer; BEGIN
 FOR n IN 20..27 LOOP
  PERFORM pg_temp.login(n); PERFORM public.submit_mfd_application(pg_temp.mid(1500+n),'State race','ARN',NULL);
  PERFORM pg_temp.login(1); PERFORM public.start_mfd_application_review(pg_temp.app(n),1,pg_temp.mid(1600+n));
 END LOOP;
END $$;
RESET ROLE;
INSERT INTO public.profiles(user_id,role) VALUES(pg_temp.mid(20),'investor');
UPDATE public.user_accounts SET account_state='link_pending' WHERE user_id=pg_temp.mid(21);
UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=pg_temp.mid(22);
SELECT platform_authority.grant_authority(pg_temp.mid(23),'platform_admin',pg_temp.mid(1723),'new platform identity during review');
UPDATE auth.users SET deleted_at=now() WHERE id=pg_temp.mid(24);
UPDATE auth.users SET email_confirmed_at=NULL WHERE id=pg_temp.mid(25);
UPDATE auth.users SET is_anonymous=true WHERE id=pg_temp.mid(26);
INSERT INTO public.profiles(user_id,role,account_status) VALUES(pg_temp.mid(27),'advisor','suspended');
SET LOCAL ROLE authenticated;
SELECT pg_temp.login(1,'aal2',301);
DO $$ DECLARE n integer; BEGIN
 FOR n IN 20..27 LOOP
  PERFORM pg_temp.denied(format('SELECT public.approve_mfd_application(pg_temp.app(%s),2,%L,''manual review'')',n,pg_temp.mid(1800+n)),'changed identity denied '||n,'mfd_applicant_ineligible');
 END LOOP;
END $$;
SELECT public.reject_mfd_application(pg_temp.app(21),2,pg_temp.mid(1900),'Identity no longer eligible');
RESET ROLE;
SELECT pg_temp.ok((SELECT account_state='link_pending' FROM public.user_accounts WHERE user_id=pg_temp.mid(21)),'rejection never resets independently changed account');
SELECT platform_authority.revoke_authority((SELECT id FROM platform_authority.grants WHERE grant_request_id=pg_temp.mid(102)),pg_temp.mid(1901),'revoke review capability');
SET LOCAL ROLE authenticated;
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(10),2,pg_temp.mid(1300),'manual review reference')$q$,'revoked capability denies even receipt replay','platform_capability_required');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.denied($q$SELECT public.approve_mfd_application(pg_temp.app(20),2,pg_temp.mid(1999),'service shortcut')$q$,'service cannot call decision');
RESET ROLE;
DO $$ DECLARE t text; p record; BEGIN
 FOREACH t IN ARRAY ARRAY['public.mfd_applications','public.mfd_application_events','mfd_application_private.requests'] LOOP
  PERFORM pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid=t::regclass),'RLS '||t);
  PERFORM pg_temp.ok(NOT has_table_privilege('authenticated',t,'INSERT,UPDATE,DELETE,TRUNCATE'),'browser DML revoked '||t);
  PERFORM pg_temp.ok(NOT has_table_privilege('service_role',t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),'service DML revoked '||t);
 END LOOP;
 PERFORM pg_temp.ok((SELECT count(*)=2 FROM pg_policies WHERE tablename IN ('mfd_applications','mfd_application_events')),'exclusive policy count');
 FOR p IN SELECT oid,proname FROM pg_proc WHERE pronamespace='mfd_application_private'::regnamespace LOOP
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT has_function_privilege('service_role',p.oid,'EXECUTE'),'private helper denied '||p.proname);
 END LOOP;
 FOR p IN SELECT oid,proname FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN ('submit_mfd_application','start_mfd_application_review','approve_mfd_application','reject_mfd_application','get_my_mfd_application_context') LOOP
  PERFORM pg_temp.ok(has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT has_function_privilege('service_role',p.oid,'EXECUTE'),'public function ACL '||p.proname);
 END LOOP;
END $$;
ROLLBACK;
