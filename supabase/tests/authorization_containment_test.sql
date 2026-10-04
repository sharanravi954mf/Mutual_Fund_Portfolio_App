-- Actual API roles; all identities/data are synthetic and rolled back.
BEGIN;
CREATE FUNCTION pg_temp.ident(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT md5('moneybowl-containment-'||n)::uuid $$;
CREATE FUNCTION pg_temp.ok(value boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; RAISE NOTICE 'PASS: %',label; END $$;
CREATE FUNCTION pg_temp.denied(statement text,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE statement; EXCEPTION WHEN insufficient_privilege OR raise_exception OR check_violation OR unique_violation THEN
    RAISE NOTICE 'PASS: %',label; RETURN;
  END;
  RAISE EXCEPTION 'FAIL (unexpected success): %',label;
END $$;
INSERT INTO auth.users(id,email,email_confirmed_at,raw_user_meta_data)
SELECT pg_temp.ident(n),'authz-'||n||'@example.test',now(),'{"role":"platform_admin","membership_role":"admin"}' FROM generate_series(1,12) n;
INSERT INTO public.profiles(id,user_id,role,account_status,full_name)
SELECT pg_temp.ident(n),pg_temp.ident(n),CASE WHEN n=8 THEN 'platform_admin' WHEN n IN (3,4) THEN 'investor' WHEN n IN (5,6) THEN 'admin' WHEN n=7 THEN 'operations' ELSE 'advisor' END,'active','Test '||n
FROM generate_series(1,12) n WHERE n NOT IN (9,10);
UPDATE public.user_accounts SET account_state='linked_investor' WHERE user_id IN (pg_temp.ident(3),pg_temp.ident(4));
INSERT INTO public.investor_account_links(user_id,profile_id,verification_method,verified_at)
VALUES(pg_temp.ident(3),pg_temp.ident(3),'test',now()),(pg_temp.ident(4),pg_temp.ident(4),'test',now());
INSERT INTO public.workspaces(id,name,slug,owner_profile_id)
VALUES(pg_temp.ident(100),'MFD A','authz-a',pg_temp.ident(5)),(pg_temp.ident(200),'MFD B','authz-b',pg_temp.ident(6));
INSERT INTO public.workspace_memberships(id,workspace_id,profile_id,role)
SELECT pg_temp.ident(w+n),pg_temp.ident(w),pg_temp.ident(n),r FROM (VALUES
(100,1,'advisor'),(100,3,'investor'),(100,5,'admin'),(100,7,'operations'),(100,12,'advisor'),
(200,2,'advisor'),(200,3,'investor'),(200,4,'investor'),(200,6,'admin')) v(w,n,r);
INSERT INTO public.advisor_investor_assignments(id,workspace_id,advisor_id,investor_id)
VALUES(pg_temp.ident(501),pg_temp.ident(100),pg_temp.ident(1),pg_temp.ident(3)),(pg_temp.ident(502),pg_temp.ident(200),pg_temp.ident(2),pg_temp.ident(3));
INSERT INTO public.portfolios(id,client_id,workspace_id)
VALUES(pg_temp.ident(1001),pg_temp.ident(3),pg_temp.ident(100)),(pg_temp.ident(2001),pg_temp.ident(3),pg_temp.ident(200)),(pg_temp.ident(2002),pg_temp.ident(4),pg_temp.ident(200));
INSERT INTO public.folio_references(id,registrar,normalized_folio_number,amc_identity,source_folio_masked)
VALUES(pg_temp.ident(600),'CAMS','AUTHZ600','authz-amc','***600'),(pg_temp.ident(601),'CAMS','AUTHZ601','authz-amc','***601');
INSERT INTO public.portfolio_folio_references(portfolio_id,folio_reference_id)
VALUES(pg_temp.ident(1001),pg_temp.ident(600)),(pg_temp.ident(2001),pg_temp.ident(600)),(pg_temp.ident(2002),pg_temp.ident(601));
INSERT INTO public.mutual_funds(id,scheme_code,scheme_name) VALUES(pg_temp.ident(700),'AUTHZ700','Authorization test');
INSERT INTO public.transactions(id,portfolio_id,mutual_fund_id,transaction_type,units,nav_at_transaction,amount,execution_date,folio_reference_id)
VALUES(pg_temp.ident(1101),pg_temp.ident(1001),pg_temp.ident(700),'BUY',10,10,100,current_date,pg_temp.ident(600)),
(pg_temp.ident(2101),pg_temp.ident(2001),pg_temp.ident(700),'BUY',10,10,100,current_date,pg_temp.ident(600));
INSERT INTO public.verification_requests(id,user_id,method_code,status,workspace_id)
VALUES(pg_temp.ident(801),pg_temp.ident(3),'folio','approved',pg_temp.ident(100)),
(pg_temp.ident(802),pg_temp.ident(3),'folio','approved',pg_temp.ident(200)),
(pg_temp.ident(803),pg_temp.ident(9),'advisor_assisted','pending_advisor_review',NULL);
INSERT INTO public.verification_folio_evidence(request_id,folio_reference_id,holder_relationship,evidence_source)
VALUES(pg_temp.ident(801),pg_temp.ident(600),'SOLE_HOLDER','INVESTOR_DECLARATION'),(pg_temp.ident(802),pg_temp.ident(600),'SOLE_HOLDER','INVESTOR_DECLARATION');
INSERT INTO public.verification_request_assignments(request_id,advisor_account_id)
VALUES(pg_temp.ident(801),pg_temp.ident(1)),(pg_temp.ident(802),pg_temp.ident(2));
INSERT INTO public.folio_grants(id,request_id,user_id,profile_id,folio_reference_id,holder_relationship,workspace_id)
VALUES(pg_temp.ident(901),pg_temp.ident(801),pg_temp.ident(3),pg_temp.ident(3),pg_temp.ident(600),'SOLE_HOLDER',pg_temp.ident(100));
SELECT vault.create_secret(repeat('synthetic-key-',4),'verification_candidate_token_encryption_key');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(1)::text,true);
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.portfolios),'Advisor A sees only A portfolio for shared investor X');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM public.portfolios WHERE id IN (pg_temp.ident(2001),pg_temp.ident(2002))),'shared and unrelated B portfolios denied');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.transactions),'transactions inherit exact persisted portfolio scope');
SELECT pg_temp.ok(NOT public.is_admin() AND NOT public.is_platform_admin(),'advisor persona is not global/platform authority');
SELECT pg_temp.ok(public.authorize_cams_kfintech_workspace(pg_temp.ident(100)),'single workspace ingestion works');
SELECT pg_temp.denied('select public.authorize_cams_kfintech_workspace(pg_temp.ident(200))','cross workspace ingestion denied');
SELECT pg_temp.ok(public.can_review_verification(pg_temp.ident(801)) AND NOT public.can_review_verification(pg_temp.ident(802)),'folio review exact workspace and assignment');
SELECT pg_temp.ok(NOT public.can_review_verification(pg_temp.ident(803)),'unscoped historical generic review fails closed');
SELECT pg_temp.denied('select public.get_folio_request_detail(pg_temp.ident(802))','B folio detail IDOR denied');
SELECT pg_temp.denied('select public.get_verification_review(pg_temp.ident(803))','unscoped generic detail denied');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.get_my_advisor_folio_requests()),'assigned folio queue scoped');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.list_order_folios(pg_temp.ident(3),pg_temp.ident(100))),'A folio order projection works');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.list_order_folios(pg_temp.ident(3),pg_temp.ident(200))),'B folio order projection denied');
SELECT pg_temp.ok(public.get_nse_read_context_v1(pg_temp.ident(203))#>>'{error,code}'='NOT_AUTHORIZED','cross workspace NSE public facade denied');
SELECT pg_temp.denied('select * from public.ingested_documents','persisted ingestion documents remain private');
SELECT pg_temp.denied('select * from public.cams_statements','unscoped legacy CAMS data denied');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.user_accounts),'advisor cannot enumerate all accounts');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.investor_account_links),'advisor cannot enumerate global investor links');

-- Investor grant for A must not authorize B even when both use the SAME folio.
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(3)::text,true);
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.portfolios),'investor sees only explicitly granted A folio');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.transactions),'investor transaction scope follows grant');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.list_order_folios(pg_temp.ident(3),pg_temp.ident(200))),'A grant cannot back B order folio projection');
SELECT pg_temp.denied($q$select * from public.issue_folio_submission_token('CAMS','AUTHZ600')$q$,'ambiguous two-argument folio token fails closed');
SELECT pg_temp.ok((SELECT submission_token IS NOT NULL FROM public.issue_folio_submission_token('CAMS','AUTHZ600',pg_temp.ident(100))),'explicit proven workspace folio token works');
SELECT pg_temp.denied($q$select * from public.issue_folio_submission_token('CAMS','AUTHZ601',pg_temp.ident(200))$q$,'unrelated investor folio token denied');

SELECT set_config('request.jwt.claim.sub',pg_temp.ident(5)::text,true);
SELECT pg_temp.ok(public.is_workspace_admin(pg_temp.ident(100)) AND NOT public.is_workspace_admin(pg_temp.ident(200)),'workspace admin exact scope');
SELECT pg_temp.ok(NOT public.is_platform_admin() AND NOT public.is_admin(),'workspace admin never platform admin');
SELECT pg_temp.denied($q$insert into public.workspace_memberships(workspace_id,profile_id,role) values(pg_temp.ident(100),pg_temp.ident(4),'investor')$q$,'admin cannot manufacture unrelated investor membership');
SELECT pg_temp.denied($q$insert into public.advisor_investor_assignments(workspace_id,advisor_id,investor_id) values(pg_temp.ident(100),pg_temp.ident(1),pg_temp.ident(4))$q$,'cross workspace assignment reference rejected');
SELECT pg_temp.denied($q$update public.advisor_investor_assignments set workspace_id=pg_temp.ident(200) where id=pg_temp.ident(501)$q$,'assignment scope immutable');
SELECT pg_temp.denied($q$select public.set_workspace_membership_status(pg_temp.ident(202),'suspended')$q$,'membership lifecycle RPC rejects BOLA');
INSERT INTO public.workspace_invitations(workspace_id,email,role,invited_by,token_hash,expires_at)
VALUES(pg_temp.ident(100),'authz-10@example.test','advisor',pg_temp.ident(6),encode(extensions.digest('authz-invite','sha256'),'hex'),now()+interval '1 day');
SELECT pg_temp.ok((SELECT invited_by=pg_temp.ident(5) FROM public.workspace_invitations WHERE workspace_id=pg_temp.ident(100)),'inviter identity is server-derived');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(10)::text,true);
SELECT pg_temp.ok(public.accept_workspace_invitation('authz-invite'),'verified invitation accepted');
SELECT pg_temp.ok(public.has_advisor_membership(pg_temp.ident(100)) AND NOT public.has_advisor_membership(pg_temp.ident(200)),'invitation grants only A authority');
SELECT pg_temp.ok(NOT public.is_admin(),'invitation does not grant global authority');
SELECT pg_temp.denied($q$select public.accept_workspace_invitation('authz-invite')$q$,'invitation replay rejected');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(9)::text,true);
SELECT pg_temp.ok((SELECT account_state='explorer' FROM public.bootstrap_identity()),'metadata-role signup remains Explorer');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.portfolios),'Explorer has no business data');
SELECT pg_temp.ok(NOT public.authorize_workspace_tools() AND NOT public.is_platform_admin(),'metadata grants no authority');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(11)::text,true);
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.portfolios),'global advisor without membership has no data authority');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(8)::text,true);
SELECT pg_temp.ok(public.is_platform_admin() AND public.is_admin(),'existing explicit platform authority retained');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.portfolios),'platform admin has no implicit portfolio access');
SELECT pg_temp.ok(NOT public.has_advisor_membership(pg_temp.ident(100)),'platform admin needs no MFD membership');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(7)::text,true);
SELECT pg_temp.ok(NOT public.has_advisor_membership(pg_temp.ident(100)),'operations cannot configure advisor approval rules');
SELECT pg_temp.denied('select public.authorize_cams_kfintech_workspace(pg_temp.ident(100))','operations cannot ingest');
RESET ROLE;

-- A consent-backed Family Guest needs no workspace membership.
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(pg_temp.ident(16),'authz-16@example.test',now());
INSERT INTO public.profiles(id,user_id,role) VALUES(pg_temp.ident(16),pg_temp.ident(16),'investor');
INSERT INTO public.family_delegations(id,workspace_id,owner_profile_id,delegate_profile_id,consent_status,is_active)
VALUES(pg_temp.ident(950),pg_temp.ident(100),pg_temp.ident(3),pg_temp.ident(16),'accepted',true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(16)::text,true);
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.portfolios),'Family Guest sees delegated A portfolio without membership');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM public.portfolios WHERE workspace_id=pg_temp.ident(200)),'Family Guest consent cannot cross workspace');
RESET ROLE;
UPDATE public.family_delegations SET consent_status='revoked' WHERE id=pg_temp.ident(950);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.portfolios),'revoked family consent grants no portfolio access');
RESET ROLE;

-- Manual requests require proven context; no successful unrouteable request.
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(pg_temp.ident(17),'authz-17@example.test',now());
UPDATE public.user_accounts SET account_state='link_pending' WHERE user_id=pg_temp.ident(17);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(17)::text,true);
SELECT pg_temp.denied($q$select public.create_non_pan_verification_request('folio')$q$,'generic folio creation helper remains private');
SELECT pg_temp.denied($q$select public.create_verification_request('advisor_assisted')$q$,'unscoped manual submission fails before creating request');
SELECT pg_temp.denied($q$select public.create_verification_request('advisor_assisted',pg_temp.ident(200))$q$,'caller-selected unrelated workspace grants no request scope');
RESET ROLE;
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM public.verification_requests WHERE user_id=pg_temp.ident(17)),'failed routing leaves no unreviewable request');
INSERT INTO public.workspace_invitations(workspace_id,email,role,invited_by,token_hash,expires_at)
VALUES(pg_temp.ident(100),'authz-17@example.test','investor',pg_temp.ident(5),encode(extensions.digest('manual-invite','sha256'),'hex'),now()+interval '1 day');
DO $$ DECLARE req uuid; BEGIN
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(17)::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.list_my_verification_workspaces()),'verified server invitation supplies request workspace choices');
  SELECT request_id INTO req FROM public.create_verification_request('advisor_assisted');
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(1)::text,true);
  PERFORM pg_temp.ok(public.can_review_verification(req),'existing single trusted-workspace manual review remains routable');
  PERFORM public.reject_verification_request(req,1,'TEST_REJECT');
  EXECUTE 'RESET ROLE';
END $$;

-- Complete multi-MFD folio lifecycle, including exact token/request binding.
DO $$ DECLARE tok text; req uuid; v integer; other_token text; BEGIN
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(3)::text,true);
  EXECUTE 'set local role authenticated';
  SELECT submission_token INTO tok FROM public.issue_folio_submission_token('CAMS','AUTHZ-600',pg_temp.ident(200));
  SELECT request_id,version INTO req,v FROM public.submit_folio_verification(tok,'SOLE_HOLDER',pg_temp.ident(990));
  PERFORM pg_temp.ok(v=1,'folio submission creates scoped request');
  PERFORM pg_temp.denied(format('select public.submit_folio_verification(%L,''SOLE_HOLDER'',pg_temp.ident(990))',tok),'consumed token replay cannot create another request');
  SELECT submission_token INTO other_token FROM public.issue_folio_submission_token('CAMS','AUTHZ600',pg_temp.ident(100));
  PERFORM pg_temp.denied(format('select public.submit_folio_verification(%L,''SOLE_HOLDER'',pg_temp.ident(991))',other_token),'open B request cannot be reused for A token');
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(1)::text,true);
  PERFORM pg_temp.denied(format('select public.begin_folio_review(%L,1)',req),'A advisor cannot review B folio request');
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(2)::text,true);
  SELECT version INTO v FROM public.begin_folio_review(req,1);
  PERFORM pg_temp.ok(v=2,'B assigned advisor begins review');
  SELECT version INTO v FROM public.approve_folio_verification(req,2,'VERIFIED_SOLE_HOLDER');
  PERFORM pg_temp.ok(v=3,'B assigned advisor approves same investor same folio independently');
  PERFORM pg_temp.denied(format('select public.approve_folio_verification(%L,2,''VERIFIED_SOLE_HOLDER'')',req),'folio approval replay/version conflict rejected');
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(3)::text,true);
  PERFORM pg_temp.ok((SELECT count(*)=2 FROM public.portfolios),'investor independently approved in both workspaces');
  EXECUTE 'reset role';
  SELECT id INTO req FROM public.folio_grants WHERE request_id=req;
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(2)::text,true);
  EXECUTE 'set local role authenticated';
  PERFORM pg_temp.ok(public.revoke_folio_grant(req,3,'TEST_REVOKE')='revoked','B reviewer revokes only B grant');
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(3)::text,true);
  PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.portfolios),'B revocation leaves independent A grant intact');
  SELECT request_id INTO req FROM public.submit_folio_verification(other_token,'JOINT_HOLDER',pg_temp.ident(992));
  EXECUTE 'reset role';
  UPDATE public.user_accounts SET account_state='advisor' WHERE user_id=pg_temp.ident(3);
  EXECUTE 'set local role authenticated';
  PERFORM pg_temp.ok((SELECT status='cancelled' FROM public.cancel_folio_verification(req,1)),'advisor persona can cancel their own investor request');
  EXECUTE 'reset role';
  UPDATE public.user_accounts SET account_state='linked_investor' WHERE user_id=pg_temp.ident(3);
END $$;

-- Scoped PAN verification still links an existing imported investor identity.
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(pg_temp.ident(13),'authz-13@example.test',now());
UPDATE public.user_accounts SET account_state='link_pending' WHERE user_id=pg_temp.ident(13);
INSERT INTO public.profiles(id,role,full_name) VALUES(pg_temp.ident(14),'investor','Scope Candidate A'),(pg_temp.ident(15),'investor','Scope Candidate B');
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role) VALUES(pg_temp.ident(100),pg_temp.ident(14),'investor'),(pg_temp.ident(200),pg_temp.ident(15),'investor');
SELECT vault.create_secret(repeat('synthetic-pan-key-',4),'pan_encryption_key');
SELECT vault.create_secret(repeat('synthetic-hmac-key-',4),'pan_lookup_hmac_key');
INSERT INTO public.profile_pan_records(profile_id,pan_ciphertext,pan_lookup_hmac,masked_pan,source,source_system,status)
VALUES(pg_temp.ident(14),extensions.pgp_sym_encrypt('ABCDE1234F',public.pan_encryption_key()),extensions.hmac('ABCDE1234F',public.pan_lookup_hmac_key(),'sha256'),'******234F','IMPORT','CAMS','OBSERVED');
DO $$ DECLARE req uuid; token text; BEGIN
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(13)::text,true);
  EXECUTE 'set local role authenticated';
  SELECT request_id INTO req FROM public.submit_pan_verification('ABCDE1234F');
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(2)::text,true);
  PERFORM pg_temp.denied(format('select public.get_verification_review(%L)',req),'B reviewer cannot read A PAN request');
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(1)::text,true);
  PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.search_verification_candidates(req,'Scope Candidate')),'candidate search is limited to request workspace');
  SELECT candidate_token INTO token FROM public.search_verification_candidates(req,'Scope Candidate');
  PERFORM pg_temp.denied(format('select public.approve_verification_request(%L,pg_temp.ident(14),1,NULL)',req),'tokenless identity approval disabled');
  PERFORM pg_temp.ok(public.approve_verification_candidate(req,token,1,NULL)='approved','generic facade preserves PAN evidence verification');
  PERFORM pg_temp.denied(format('select public.approve_verification_candidate(%L,%L,1,NULL)',req,token),'identity approval replay rejected');
  PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(13)::text,true);
  PERFORM pg_temp.ok((SELECT profile_id=pg_temp.ident(14) FROM public.investor_account_links WHERE user_id=auth.uid()),'verified investor identity linked');
  EXECUTE 'reset role';
END $$;

-- Lifecycle uses fresh DB state, even with the same retained JWT.
DO $$ DECLARE condition text; restore text; BEGIN
  FOREACH condition IN ARRAY ARRAY[
    'update public.workspace_memberships set ended_at=now() where id=pg_temp.ident(101)',
    'update public.workspace_memberships set status=''suspended'' where id=pg_temp.ident(101)',
    'update public.workspaces set workspace_status=''suspended'' where id=pg_temp.ident(100)',
    'update public.profiles set account_status=''inactive'' where id=pg_temp.ident(1)',
    'update auth.users set banned_until=now()+interval ''1 hour'' where id=pg_temp.ident(1)',
    'update auth.users set deleted_at=now() where id=pg_temp.ident(1)'
  ] LOOP
    EXECUTE condition;
    PERFORM set_config('request.jwt.claim.sub',pg_temp.ident(1)::text,true);
    EXECUTE 'set local role authenticated';
    PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.portfolios),'lifecycle denies portfolio: '||condition);
    PERFORM pg_temp.ok(NOT public.can_select_order_request(pg_temp.ident(100),pg_temp.ident(3)),'lifecycle denies orders');
    PERFORM pg_temp.ok(NOT public.can_review_verification(pg_temp.ident(801)),'lifecycle denies folio review');
    PERFORM pg_temp.denied('select public.authorize_cams_kfintech_workspace(pg_temp.ident(100))','lifecycle denies ingestion');
    EXECUTE 'reset role';
    UPDATE public.workspace_memberships SET status='active',ended_at=NULL WHERE id=pg_temp.ident(101);
    UPDATE public.workspaces SET workspace_status='active' WHERE id=pg_temp.ident(100);
    UPDATE public.profiles SET account_status='active' WHERE id=pg_temp.ident(1);
    UPDATE auth.users SET banned_until=NULL,deleted_at=NULL WHERE id=pg_temp.ident(1);
  END LOOP;
END $$;
-- NSE checks the relationship's workspace, even if actor independently joins B.
INSERT INTO public.workspace_memberships(id,workspace_id,profile_id,role) VALUES(pg_temp.ident(201),pg_temp.ident(200),pg_temp.ident(1),'advisor');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(1)::text,true);
SELECT pg_temp.ok(nse_app.can_target(pg_temp.ident(1),pg_temp.ident(103)),'NSE A assignment works');
SELECT pg_temp.ok(NOT nse_app.can_target(pg_temp.ident(1),pg_temp.ident(203)),'NSE A assignment cannot be reused in B');
UPDATE public.advisor_investor_assignments SET ended_at=now(),status='ended' WHERE id=pg_temp.ident(501);
SELECT pg_temp.ok(NOT nse_app.can_target(pg_temp.ident(1),pg_temp.ident(103)),'ended advisor relationship grants no NSE authority');
UPDATE public.advisor_investor_assignments SET ended_at=NULL,status='active' WHERE id=pg_temp.ident(501);
UPDATE public.verification_request_assignments SET active=false WHERE request_id=pg_temp.ident(801);
SELECT pg_temp.ok(NOT public.can_review_verification(pg_temp.ident(801)),'ended request assignment grants no review authority');
UPDATE public.verification_request_assignments SET active=true WHERE request_id=pg_temp.ident(801);
DELETE FROM public.workspace_memberships WHERE id=pg_temp.ident(201);
SELECT pg_temp.denied($q$insert into public.folio_grants(request_id,user_id,profile_id,folio_reference_id,holder_relationship,workspace_id) values(pg_temp.ident(802),pg_temp.ident(3),pg_temp.ident(3),pg_temp.ident(600),'SOLE_HOLDER',pg_temp.ident(100))$q$,'grant cannot reference another workspace request');

-- Initiate, then revoke historical initiator; a currently authorized second
-- advisor can still cancel/review the accepted order without rewriting history.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(1)::text,true);
INSERT INTO public.order_requests(id,workspace_id,investor_profile_id,scheme_code,type,amount)
VALUES(pg_temp.ident(3001),pg_temp.ident(100),pg_temp.ident(3),'AUTHZ700','buy',100),
(pg_temp.ident(3003),pg_temp.ident(100),pg_temp.ident(3),'AUTHZ700','buy',100);
SELECT pg_temp.denied($q$insert into public.order_requests(workspace_id,investor_profile_id,scheme_code,type,amount) values(pg_temp.ident(200),pg_temp.ident(3),'AUTHZ700','buy',100)$q$,'order initiation cross workspace denied');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(2)::text,true);
INSERT INTO public.order_requests(id,workspace_id,investor_profile_id,scheme_code,type,amount)
VALUES(pg_temp.ident(3004),pg_temp.ident(200),pg_temp.ident(3),'AUTHZ700','buy',100);
RESET ROLE;
UPDATE public.order_requests SET status='pending_review' WHERE id IN (pg_temp.ident(3003),pg_temp.ident(3004));
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(1)::text,true);
SELECT pg_temp.denied($q$select public.qualify_order(pg_temp.ident(3004),'approved')$q$,'qualification denies another workspace for the same investor');
SELECT pg_temp.denied($q$select public.cancel_order(pg_temp.ident(3004),'test')$q$,'cancellation denies another workspace for the same investor');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(3)::text,true);
SELECT pg_temp.denied($q$select public.qualify_order(pg_temp.ident(3003),'approved')$q$,'investor cannot self-qualify an order');
RESET ROLE;
UPDATE public.workspace_memberships SET ended_at=now() WHERE id=pg_temp.ident(101);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(1)::text,true);
SELECT pg_temp.denied('select public.cancel_order(pg_temp.ident(3001),''test'')','revoked initiator cannot cancel');
SELECT pg_temp.denied($q$select public.qualify_order(pg_temp.ident(3003),'approved')$q$,'revoked advisor cannot qualify');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(12)::text,true);
SELECT pg_temp.ok((public.qualify_order(pg_temp.ident(3003),'approved')).status='approved','active second advisor qualifies after historical initiator revocation');
SELECT pg_temp.denied($q$select public.qualify_order(pg_temp.ident(3003),'approved')$q$,'qualification replay rejected');
SELECT pg_temp.ok((public.cancel_order(pg_temp.ident(3001),'test')).status='cancelled','active second advisor cancels after historical initiator revocation');
SELECT pg_temp.denied('select public.cancel_order(pg_temp.ident(3001),''test'')','order cancellation replay rejected');
SELECT set_config('request.jwt.claim.sub',pg_temp.ident(3)::text,true);
INSERT INTO public.order_requests(id,workspace_id,investor_profile_id,scheme_code,type,amount)
VALUES(pg_temp.ident(3002),pg_temp.ident(100),pg_temp.ident(3),'AUTHZ700','buy',100);
SELECT pg_temp.ok((public.cancel_order(pg_temp.ident(3002),'test')).status='cancelled','existing investor order flow works');
RESET ROLE;

-- Exact policy/ACL contract, including every overload and trigger-only helper.
SELECT pg_temp.ok((SELECT count(*)=1 FROM pg_policies WHERE schemaname='public' AND tablename='portfolios'),'one exclusive portfolio policy');
SELECT pg_temp.ok((SELECT count(*)=1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions'),'one exclusive transaction policy');
SELECT pg_temp.ok(NOT has_table_privilege('authenticated','public.workspace_memberships','INSERT,UPDATE,DELETE'),'no membership admission bypass');
SELECT pg_temp.ok(NOT has_function_privilege('anon','public.is_admin()','EXECUTE'),'anon admin helper denied');
SELECT pg_temp.ok(NOT has_function_privilege('authenticated','public.issue_folio_submission_token(uuid,uuid)','EXECUTE'),'legacy unscoped token helper private');
SELECT pg_temp.ok(NOT has_schema_privilege('authenticated','moneybowl_authz','USAGE'),'internal authorization schema private');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='moneybowl_authz' AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE'))),'all internal helpers inaccessible to API roles');
ROLLBACK;
