-- Synthetic auth inserts only: no Auth API or email delivery. Rollback all data.
BEGIN;
CREATE FUNCTION pg_temp.assert(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %', label; END IF; END $$;

INSERT INTO auth.users(id,email,email_confirmed_at,raw_user_meta_data)
SELECT ('ef000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'signup-'||n||'@example.test', CASE WHEN n=1 THEN NULL ELSE now() END,
  jsonb_build_object('role', CASE n%3 WHEN 0 THEN 'platform_admin' WHEN 1 THEN 'advisor' ELSE 'admin' END,
    'membership_role','admin','full_name','untrusted','verified_email','claim@example.test')
FROM generate_series(1,14) n;
SELECT pg_temp.assert((SELECT count(*)=14 FROM public.user_accounts WHERE user_id::text LIKE 'ef000000%'), 'neutral accounts created');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM public.profiles WHERE user_id::text LIKE 'ef000000%'), 'metadata never creates profiles or roles');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM public.workspace_memberships m JOIN public.profiles p ON p.id=m.profile_id WHERE p.user_id::text LIKE 'ef000000%'), 'metadata never creates memberships');

INSERT INTO public.profiles(id,role,verified_email,email,user_id,account_status) VALUES
('ef100000-0000-0000-0000-000000000001','investor','signup-1@example.test','signup-1@example.test',NULL,'active'),
('ef100000-0000-0000-0000-000000000002','investor',' SIGNUP-2@EXAMPLE.TEST ',NULL,NULL,'active'),
('ef100000-0000-0000-0000-000000000004','investor','signup-4@example.test',NULL,NULL,'active'),
('ef100000-0000-0000-0000-000000000005','client','signup-4@example.test',NULL,NULL,'active'),
('ef100000-0000-0000-0000-000000000006','investor','signup-5@example.test',NULL,'ef000000-0000-0000-0000-000000000006','active'),
('ef100000-0000-0000-0000-000000000007','investor','signup-7@example.test',NULL,NULL,'active'),
('ef100000-0000-0000-0000-000000000008','investor','signup-8@example.test',NULL,NULL,'suspended'),
('ef100000-0000-0000-0000-000000000009','advisor',NULL,NULL,'ef000000-0000-0000-0000-000000000009','active'),
('ef100000-0000-0000-0000-000000000010','admin',NULL,NULL,'ef000000-0000-0000-0000-000000000010','active'),
('ef100000-0000-0000-0000-000000000011','platform_admin',NULL,NULL,'ef000000-0000-0000-0000-000000000011','active'),
('ef100000-0000-0000-0000-000000000012','investor',NULL,'signup-12@example.test',NULL,'active'),
('ef100000-0000-0000-0000-000000000013','investor','signup-13@example.test',NULL,NULL,'active');
INSERT INTO public.investor_account_links(user_id,profile_id,verification_method,verified_at)
VALUES ('ef000000-0000-0000-0000-000000000006','ef100000-0000-0000-0000-000000000007','legacy_migration',now());
INSERT INTO public.investor_account_links(user_id,profile_id,verification_method,verified_at,link_status)
VALUES ('ef000000-0000-0000-0000-000000000013','ef100000-0000-0000-0000-000000000013','verified_email',now(),'revoked');

SET LOCAL ROLE authenticated;
DO $$ DECLARE r record; n integer; BEGIN
  PERFORM set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-000000000001',true);
  BEGIN PERFORM public.bootstrap_identity(); RAISE EXCEPTION 'unverified accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'email_verification_required' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-000000000006',true);
  BEGIN PERFORM public.bootstrap_identity(); RAISE EXCEPTION 'conflicting link accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'account_unavailable' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-000000000002',true);
  SELECT * INTO r FROM public.bootstrap_identity();
  PERFORM pg_temp.assert(r.account_state='linked_investor' AND r.resolution='automatic_link','verified unique canonical investor linked');
  SELECT * INTO r FROM public.bootstrap_identity();
  PERFORM pg_temp.assert(r.resolution='existing_link','bootstrap replay idempotent');
  PERFORM pg_temp.assert((SELECT count(*)=1 FROM public.investor_account_links WHERE user_id=auth.uid()),'one active link');
  PERFORM pg_temp.assert((SELECT count(*)=1 FROM public.profiles),'linked profile readable under real RLS');
  FOREACH n IN ARRAY ARRAY[3,4,5,7,8,12,13,14] LOOP
    PERFORM set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-'||lpad(n::text,12,'0'),true);
    SELECT * INTO r FROM public.bootstrap_identity();
    PERFORM pg_temp.assert(r.account_state='explorer' AND r.resolution='no_match','zero/ambiguous/owned/linked/suspended/untrusted/revoked remain indistinguishable Explorers: '||n);
  END LOOP;
  PERFORM pg_temp.assert((SELECT count(*)=0 FROM public.profiles),'Explorer requires no profile');
  PERFORM pg_temp.assert(public.complete_onboarding_choice('link_pending')='link_pending','Explorer can begin existing linking flow');
  SELECT * INTO r FROM public.bootstrap_identity();
  PERFORM pg_temp.assert(r.account_state='link_pending','explicit linking choice survives bootstrap');
  PERFORM public.complete_onboarding_choice('explorer');
  FOR n IN 9..10 LOOP
    PERFORM set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-'||lpad(n::text,12,'0'),true);
    SELECT * INTO r FROM public.bootstrap_identity();
    PERFORM pg_temp.assert(r.account_state='advisor','trusted advisor/admin retained');
    PERFORM pg_temp.assert((SELECT count(*)>=1 FROM public.profiles WHERE user_id=auth.uid()),'staff own profile readable');
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-000000000011',true);
  PERFORM pg_temp.assert((SELECT account_state='explorer' FROM public.bootstrap_identity()),'legacy platform label needs separate authority, not advisor state');
  PERFORM set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-000000000003',true);
  PERFORM pg_temp.assert(NOT public.is_admin(), 'public account has no advisor authority');
  BEGIN PERFORM public.approve_verification_request('ef999999-0000-0000-0000-000000000001','ef100000-0000-0000-0000-000000000004',1,NULL);
    RAISE EXCEPTION 'approval bypass';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'Advisor authorization is required' THEN RAISE; END IF; END;
  BEGIN UPDATE public.user_accounts SET account_state='advisor' WHERE user_id=auth.uid(); RAISE EXCEPTION 'identity mutation allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO public.profiles(user_id,role) VALUES(auth.uid(),'admin'); RAISE EXCEPTION 'profile mutation allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO public.investor_account_links(user_id,profile_id,verification_method) VALUES(auth.uid(),'ef100000-0000-0000-0000-000000000004','metadata'); RAISE EXCEPTION 'link mutation allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.assert((SELECT user_id IS NULL FROM public.profiles WHERE id='ef100000-0000-0000-0000-000000000001'),'unverified profile not claimed');
SELECT pg_temp.assert((SELECT user_id='ef000000-0000-0000-0000-000000000006' FROM public.profiles WHERE id='ef100000-0000-0000-0000-000000000006'),'existing owner not overwritten');
UPDATE auth.users SET email_confirmed_at=now() WHERE id='ef000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-000000000001',true);
SELECT pg_temp.assert((SELECT account_state='linked_investor' FROM public.bootstrap_identity()),'verification return links formerly unverified identity');
RESET ROLE;
-- Trusted invitation; reject recipient mismatch and accept only after verification.
INSERT INTO public.workspaces(id,name,slug,owner_profile_id) VALUES('ef200000-0000-0000-0000-000000000001','Signup test','signup-test','ef100000-0000-0000-0000-000000000010');
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role) VALUES('ef200000-0000-0000-0000-000000000001','ef100000-0000-0000-0000-000000000010','admin');
INSERT INTO public.workspace_invitations(workspace_id,email,role,invited_by,token_hash,expires_at)
VALUES('ef200000-0000-0000-0000-000000000001','signup-3@example.test','advisor','ef100000-0000-0000-0000-000000000010',encode(extensions.digest('synthetic-invitation','sha256'),'hex'),now()+interval '1 day');
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 PERFORM set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-000000000004',true);
 BEGIN PERFORM public.accept_workspace_invitation('synthetic-invitation'); RAISE EXCEPTION 'wrong recipient accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'invitation_unavailable' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub','ef000000-0000-0000-0000-000000000003',true);
 PERFORM pg_temp.assert(public.accept_workspace_invitation('synthetic-invitation'),'verified recipient accepted');
 PERFORM pg_temp.assert((SELECT account_state='advisor' FROM public.bootstrap_identity()),'trusted invitation grants staff role');
 BEGIN PERFORM public.accept_workspace_invitation('synthetic-invitation'); RAISE EXCEPTION 'invitation replay accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'invitation_unavailable' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
DO $$ DECLARE fn text; t text; BEGIN
 FOREACH fn IN ARRAY ARRAY['handle_new_user()','bootstrap_identity()','complete_onboarding_choice(text)','accept_workspace_invitation(text)'] LOOP
  PERFORM pg_temp.assert(NOT has_function_privilege('anon','public.'||fn,'EXECUTE'),'anonymous function denied: '||fn);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['profiles','user_accounts','investor_account_links'] LOOP
  PERFORM pg_temp.assert(NOT has_table_privilege('authenticated','public.'||t,'INSERT,UPDATE,DELETE'),'browser mutations denied: '||t);
  PERFORM pg_temp.assert((SELECT relrowsecurity FROM pg_class WHERE oid=('public.'||t)::regclass),'RLS enabled: '||t);
 END LOOP;
END $$;
ROLLBACK;
