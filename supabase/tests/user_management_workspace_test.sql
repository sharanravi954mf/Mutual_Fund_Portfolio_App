-- Test Suite: User Management & Workspace Foundation
-- Verifies multi-tenant isolation, assignments, invitations, audit logs, and RLS enforcements.

BEGIN;

-- 1. Setup Platform Admin and Workspace test fixtures
-- Authenticated Users
INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('61000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'platform-admin@moneyball.test', '{}', '{"role":"platform_admin"}', now(), now()),
  ('61000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'a-admin@moneyball.test', '{}', '{"role":"user"}', now(), now()),
  ('61000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'a-advisor@moneyball.test', '{}', '{"role":"user"}', now(), now()),
  ('61000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'a-investor@moneyball.test', '{}', '{"role":"user"}', now(), now()),
  ('61000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'b-advisor@moneyball.test', '{}', '{"role":"user"}', now(), now()),
  ('61000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'b-investor@moneyball.test', '{}', '{"role":"user"}', now(), now());

-- User accounts
UPDATE public.user_accounts SET account_state = 'advisor' WHERE user_id IN ('61000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000003', '61000000-0000-0000-0000-000000000005');
UPDATE public.user_accounts SET account_state = 'linked_investor' WHERE user_id IN ('61000000-0000-0000-0000-000000000004', '61000000-0000-0000-0000-000000000006');

-- Link default personal profiles that triggers created to deterministic IDs
-- Profile mappings:
-- User 1: '62000000-0000-0000-0000-000000000001' (Platform Admin)
-- User 2: '62000000-0000-0000-0000-000000000002' (Workspace A Admin)
-- User 3: '62000000-0000-0000-0000-000000000003' (Workspace A Advisor)
-- User 4: '62000000-0000-0000-0000-000000000004' (Workspace A Investor)
-- User 5: '62000000-0000-0000-0000-000000000005' (Workspace B Advisor)
-- User 6: '62000000-0000-0000-0000-000000000006' (Workspace B Investor)
UPDATE public.profiles SET id = '62000000-0000-0000-0000-000000000001', role = 'platform_admin', full_name = 'Platform Admin' WHERE user_id = '61000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '62000000-0000-0000-0000-000000000002', role = 'advisor', full_name = 'Workspace A Admin' WHERE user_id = '61000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET id = '62000000-0000-0000-0000-000000000003', role = 'advisor', full_name = 'Workspace A Advisor' WHERE user_id = '61000000-0000-0000-0000-000000000003';
UPDATE public.profiles SET id = '62000000-0000-0000-0000-000000000004', role = 'investor', full_name = 'Workspace A Investor' WHERE user_id = '61000000-0000-0000-0000-000000000004';
UPDATE public.profiles SET id = '62000000-0000-0000-0000-000000000005', role = 'advisor', full_name = 'Workspace B Advisor' WHERE user_id = '61000000-0000-0000-0000-000000000005';
UPDATE public.profiles SET id = '62000000-0000-0000-0000-000000000006', role = 'investor', full_name = 'Workspace B Investor' WHERE user_id = '61000000-0000-0000-0000-000000000006';

-- Establish distinct Workspaces
-- Workspace A: '63000000-0000-0000-0000-000000000001'
-- Workspace B: '63000000-0000-0000-0000-000000000002'
INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('63000000-0000-0000-0000-000000000001', 'Workspace A', 'workspace-a', '62000000-0000-0000-0000-000000000002', 'active'),
  ('63000000-0000-0000-0000-000000000002', 'Workspace B', 'workspace-b', '62000000-0000-0000-0000-000000000005', 'active');

-- Clear pre-populated memberships for these profiles that trigger created so we map them cleanly
DELETE FROM public.workspace_memberships WHERE profile_id IN ('62000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000003', '62000000-0000-0000-0000-000000000004', '62000000-0000-0000-0000-000000000005', '62000000-0000-0000-0000-000000000006');

-- Set Workspace memberships
INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('63000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('63000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000003', 'advisor', 'active'),
  ('63000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000004', 'investor', 'active'),
  ('63000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000005', 'advisor', 'active'),
  ('63000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000006', 'investor', 'active');

-- Link investor profiles
INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('61000000-0000-0000-0000-000000000004', '62000000-0000-0000-0000-000000000004', 'verified_email', now(), 'active'),
  ('61000000-0000-0000-0000-000000000006', '62000000-0000-0000-0000-000000000006', 'verified_email', now(), 'active');

-- Dummy portfolios inside Workspaces
INSERT INTO public.portfolios (id, client_id, total_invested_value, current_market_value)
VALUES
  ('64000000-0000-0000-0000-000000000004', '62000000-0000-0000-0000-000000000004', 10000.0, 12000.0),
  ('64000000-0000-0000-0000-000000000006', '62000000-0000-0000-0000-000000000006', 10000.0, 12000.0);

-- Switch role to authenticated to execute RLS and logic tests
SET ROLE authenticated;

DO $$
DECLARE
  v_count integer;
  v_assigned_id uuid;
  v_token text := 'xyz123abc456plaintextinvitetoken';
  v_hash text;
  v_result boolean;
BEGIN
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  -------------------------------------------------------------
  -- TEST 1: Cross-workspace profile and portfolio isolation --
  -------------------------------------------------------------
  -- Login as Workspace A Advisor
  PERFORM set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000003', true);
  
  -- Should only view Workspace A profiles
  SELECT count(*) INTO v_count FROM public.profiles;
  IF v_count <> 3 THEN -- Platform Admin is not a member of A, A-Admin, A-Advisor, A-Investor should be visible (3 profiles)
    RAISE EXCEPTION 'Workspace isolation failed on profiles. Visible profiles count: %', v_count;
  END IF;

  -- Should only view Workspace A portfolios
  SELECT count(*) INTO v_count FROM public.portfolios;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Workspace isolation failed on portfolios. Visible portfolios count: %', v_count;
  END IF;

  -------------------------------------------------------------
  -- TEST 2: Platform Admin No Global Business-Table Bypass   --
  -------------------------------------------------------------
  -- Login as Platform Admin
  PERFORM set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000001', true);
  
  -- Issue #31: Platform Admin must not receive unrestricted cross-workspace extraction.
  SELECT count(*) INTO v_count FROM public.profiles;
  IF v_count >= 6 THEN
    RAISE EXCEPTION 'Platform Admin retained global profile extraction. Visible profiles count: %', v_count;
  END IF;

  -------------------------------------------------------------
  -- TEST 3: Workspace Admin Isolation                        --
  -------------------------------------------------------------
  -- Login as Workspace A Admin
  PERFORM set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000002', true);
  
  -- Try to query Workspace B memberships -> should return 0 rows
  SELECT count(*) INTO v_count FROM public.workspace_memberships WHERE workspace_id = '63000000-0000-0000-0000-000000000002';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Workspace Admin bypassed isolation. Visible Org B memberships: %', v_count;
  END IF;

  -------------------------------------------------------------
  -- TEST 4: Advisor-Investor Assignment Validation           --
  -------------------------------------------------------------
  -- Try to create an assignment inside Workspace A -> should succeed
  INSERT INTO public.advisor_investor_assignments (advisor_id, investor_id, assigned_by)
  VALUES ('62000000-0000-0000-0000-000000000003', '62000000-0000-0000-0000-000000000004', '62000000-0000-0000-0000-000000000002')
  RETURNING id INTO v_assigned_id;

  -- Try to assign advisor from A to investor in B -> should fail trigger same workspace constraint
  BEGIN
    INSERT INTO public.advisor_investor_assignments (advisor_id, investor_id, assigned_by)
    VALUES ('62000000-0000-0000-0000-000000000003', '62000000-0000-0000-0000-000000000006', '62000000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'Cross-workspace advisor assignment should have failed';
  EXCEPTION WHEN OTHERS THEN
    IF sqlerrm = 'Cross-workspace advisor assignment should have failed' THEN RAISE; END IF;
  END;

  -- Try to insert duplicate active assignment -> should fail unique index constraint
  BEGIN
    INSERT INTO public.advisor_investor_assignments (advisor_id, investor_id, assigned_by)
    VALUES ('62000000-0000-0000-0000-000000000003', '62000000-0000-0000-0000-000000000004', '62000000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'Duplicate active advisor assignment should have failed';
  EXCEPTION WHEN OTHERS THEN
    IF sqlerrm = 'Duplicate active advisor assignment should have failed' THEN RAISE; END IF;
  END;

  -- End the assignment (soft-delete)
  UPDATE public.advisor_investor_assignments
  SET ended_at = now(), status = 'ended'
  WHERE id = v_assigned_id;

  -- Inserting another assignment now should succeed since previous one is ended
  INSERT INTO public.advisor_investor_assignments (advisor_id, investor_id, assigned_by)
  VALUES ('62000000-0000-0000-0000-000000000003', '62000000-0000-0000-0000-000000000004', '62000000-0000-0000-0000-000000000002');

  -------------------------------------------------------------
  -- TEST 5: Secure Invitations & Hashing                     --
  -------------------------------------------------------------
  -- Create pending invitation for Workspace A
  INSERT INTO public.workspace_invitations (workspace_id, email, role, invited_by, token_hash, expires_at)
  VALUES ('63000000-0000-0000-0000-000000000001', 'invitee@moneyball.test', 'investor', '62000000-0000-0000-0000-000000000002', v_hash, now() + interval '1 day');

  -- Login as invitee (B-Investor who is not a member of Workspace A)
  PERFORM set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000006', true);
  
  -- Try to accept valid invitation -> should succeed
  v_result := public.accept_workspace_invitation(v_token);
  IF NOT v_result THEN
    RAISE EXCEPTION 'Accepting valid invitation failed';
  END IF;

  -- Try to accept it again (replay check) -> should fail
  BEGIN
    v_result := public.accept_workspace_invitation(v_token);
    RAISE EXCEPTION 'Replaying accepted invitation token should have failed';
  EXCEPTION WHEN OTHERS THEN
    IF sqlerrm = 'Replaying accepted invitation token should have failed' THEN RAISE; END IF;
  END;

END;
$$;

-- Restore role to test trigger immutability under postgres (bypassing RLS)
RESET ROLE;

DO $$
BEGIN
  -------------------------------------------------------------
  -- TEST 6: Audit Log Immutability                           --
  -------------------------------------------------------------
  -- Try to update audit log -> should fail trigger block
  BEGIN
    UPDATE public.workspace_audit_logs SET action = 'tampered';
    RAISE EXCEPTION 'Updating audit logs should be blocked';
  EXCEPTION WHEN OTHERS THEN
    IF sqlerrm = 'Updating audit logs should be blocked' THEN RAISE; END IF;
  END;

  -- Try to delete audit log -> should fail trigger block
  BEGIN
    DELETE FROM public.workspace_audit_logs;
    RAISE EXCEPTION 'Deleting audit logs should be blocked';
  EXCEPTION WHEN OTHERS THEN
    IF sqlerrm = 'Deleting audit logs should be blocked' THEN RAISE; END IF;
  END;

END;
$$;

-- Restore role
RESET ROLE;

ROLLBACK;
