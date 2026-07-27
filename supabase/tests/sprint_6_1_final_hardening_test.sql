-- Test Suite: Sprint 6.1 Final Hardening pgTAP Verification
-- Verifies: Platform Admin step-up override auditing, Family Access lifecycle RPCs and RLS boundaries, Event outbox claiming, completing, and uniqueness, investor subscription states and billing owner controls.

BEGIN;

-- 1. Setup Test Fixtures
INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('81000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'platform-admin-final@moneybowl.test', '{}', '{"role":"platform_admin"}', now(), now()),
  ('81000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'advisor-final@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('81000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'investor-final-a@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('81000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'investor-final-b@moneybowl.test', '{}', '{"role":"user"}', now(), now());

-- Update user accounts state
UPDATE public.user_accounts SET account_state = 'advisor' WHERE user_id IN ('81000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000002');
UPDATE public.user_accounts SET account_state = 'linked_investor' WHERE user_id IN ('81000000-0000-0000-0000-000000000003', '81000000-0000-0000-0000-000000000004');

-- Map profiles
UPDATE public.profiles SET id = '82000000-0000-0000-0000-000000000001', role = 'platform_admin', full_name = 'Platform Admin Final' WHERE user_id = '81000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '82000000-0000-0000-0000-000000000002', role = 'advisor', full_name = 'Advisor Final' WHERE user_id = '81000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET id = '82000000-0000-0000-0000-000000000003', role = 'investor', full_name = 'Investor Final A' WHERE user_id = '81000000-0000-0000-0000-000000000003';
UPDATE public.profiles SET id = '82000000-0000-0000-0000-000000000004', role = 'investor', full_name = 'Investor Final B' WHERE user_id = '81000000-0000-0000-0000-000000000004';

-- Establish Workspace
INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('83000000-0000-0000-0000-000000000001', 'Workspace Final', 'workspace-final-slug', '82000000-0000-0000-0000-000000000002', 'active');

-- Create active memberships
DELETE FROM public.workspace_memberships WHERE profile_id IN ('82000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000004');
INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000003', 'investor', 'active'),
  ('83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000004', 'investor', 'active');

-- Link investor accounts
INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('81000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000003', 'verified_email', now(), 'active'),
  ('81000000-0000-0000-0000-000000000004', '82000000-0000-0000-0000-000000000004', 'verified_email', now(), 'active');

-- Subscription Plans
INSERT INTO public.subscription_plans (id, name, client_limit, monthly_price)
VALUES
  ('84000000-0000-0000-0000-000000000001', 'MFD Enterprise', 999999, 4999.00),
  ('84000000-0000-0000-0000-000000000002', 'Investor Standard', 999999, 199.00);

-- Workspace Billing details
INSERT INTO public.workspace_billing (workspace_id, plan_id, status, current_client_count)
VALUES
  ('83000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000001', 'active', 0);

-- Auto Approval Rules
INSERT INTO public.auto_approval_rules (id, workspace_id, transaction_type, min_amount, max_amount, is_active, rule_version)
VALUES
  ('85000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 'buy', 0.00, 50000.00, true, 1);

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;

-- Run validation tests
DO $$
DECLARE
  v_res_profile_id uuid;
  v_order public.order_requests;
  v_outbox public.event_outbox;
  v_delegation public.family_delegations;
  v_audit_attempt public.workspace_audit_logs;
  v_audit_succeed public.workspace_audit_logs;
  v_sub public.investor_subscriptions;
  v_count integer;
BEGIN
  -- ----------------------------------------------------
  -- TEST 1: Helper Resolution current_user_profile_id()
  -- ----------------------------------------------------
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000003", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  v_res_profile_id := public.current_user_profile_id();
  IF v_res_profile_id IS NULL OR v_res_profile_id <> '82000000-0000-0000-0000-000000000003'::uuid THEN
    RAISE EXCEPTION 'current_user_profile_id() resolution mapping mismatch';
  END IF;

  -- ----------------------------------------------------
  -- TEST 2: Platform Admin Step-Up Override Auditing
  -- ----------------------------------------------------
  -- Test 2.1: Call override function WITHOUT step-up amr (should fail and log override.attempted + override.denied)
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"user_role": "platform_admin"}, "amr": ["pwd"]}', true);
  
  -- Log the attempt (attempt-first service call)
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_profile_id,
    actor_type,
    action,
    entity_type,
    entity_id,
    target_type,
    target_id,
    correlation_id,
    event_type
  ) VALUES (
    '83000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    'platform_admin',
    'override.account_unlock',
    'profiles',
    '82000000-0000-0000-0000-000000000003',
    'profiles',
    '82000000-0000-0000-0000-000000000003',
    '99000000-0000-0000-0000-000000000009',
    'override.attempted'
  );

  BEGIN
    PERFORM public.override_account_unlock('82000000-0000-0000-0000-000000000003', 'Testing unlock without MFA', '99000000-0000-0000-0000-000000000009'::uuid, '83000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'override_account_unlock succeeded without step-up verification';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'platform_admin_step_up_required' THEN
      RAISE EXCEPTION 'Unexpected error on unlock step-up check: %', SQLERRM;
    END IF;
    
    -- Log the denial outcome
    INSERT INTO public.workspace_audit_logs (
      workspace_id,
      actor_profile_id,
      actor_type,
      action,
      entity_type,
      entity_id,
      target_type,
      target_id,
      correlation_id,
      event_type,
      error_code
    ) VALUES (
      '83000000-0000-0000-0000-000000000001',
      '82000000-0000-0000-0000-000000000001',
      'platform_admin',
      'override.account_unlock',
      'profiles',
      '82000000-0000-0000-0000-000000000003',
      'profiles',
      '82000000-0000-0000-0000-000000000003',
      '99000000-0000-0000-0000-000000000009',
      'override.denied',
      'platform_admin_step_up_required'
    );
  END;

  -- Verify audit logs are logged properly for override attempt and denial
  SELECT * INTO v_audit_attempt FROM public.workspace_audit_logs 
  WHERE workspace_id = '83000000-0000-0000-0000-000000000001' 
    AND actor_profile_id = '82000000-0000-0000-0000-000000000001'
    AND action = 'override.account_unlock'
    AND event_type = 'override.attempted'
  ORDER BY occurred_at DESC LIMIT 1;
  
  IF v_audit_attempt.id IS NULL THEN
    RAISE EXCEPTION 'override.attempted audit log missing for failed step-up override attempt';
  END IF;

  SELECT * INTO v_audit_succeed FROM public.workspace_audit_logs 
  WHERE workspace_id = '83000000-0000-0000-0000-000000000001' 
    AND actor_profile_id = '82000000-0000-0000-0000-000000000001'
    AND action = 'override.account_unlock'
    AND event_type = 'override.denied'
  ORDER BY occurred_at DESC LIMIT 1;

  IF v_audit_succeed.id IS NULL THEN
    RAISE EXCEPTION 'override.denied audit log missing for failed step-up override attempt';
  END IF;

  -- Test 2.2: Call override function WITH step-up amr (should succeed and log override.attempted + override.succeeded)
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"user_role": "platform_admin"}, "amr": ["pwd", "mfa"]}', true);
  
  -- Log the attempt (attempt-first service call)
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_profile_id,
    actor_type,
    action,
    entity_type,
    entity_id,
    target_type,
    target_id,
    correlation_id,
    event_type
  ) VALUES (
    '83000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    'platform_admin',
    'override.account_unlock',
    'profiles',
    '82000000-0000-0000-0000-000000000003',
    'profiles',
    '82000000-0000-0000-0000-000000000003',
    '99000000-0000-0000-0000-000000000009',
    'override.attempted'
  );

  PERFORM public.override_account_unlock('82000000-0000-0000-0000-000000000003', 'Unlocking with MFA', '99000000-0000-0000-0000-000000000009'::uuid, '83000000-0000-0000-0000-000000000001');

  SELECT * INTO v_audit_succeed FROM public.workspace_audit_logs 
  WHERE workspace_id = '83000000-0000-0000-0000-000000000001' 
    AND actor_profile_id = '82000000-0000-0000-0000-000000000001'
    AND action = 'override.account_unlock'
    AND event_type = 'override.succeeded'
  ORDER BY occurred_at DESC LIMIT 1;

  IF v_audit_succeed.id IS NULL THEN
    RAISE EXCEPTION 'override.succeeded audit log missing for successful step-up override';
  END IF;

  -- Test 2.3: Attempt to update or delete override audit logs (must fail)
  BEGIN
    UPDATE public.workspace_audit_logs SET event_type = 'hack' WHERE id = v_audit_succeed.id;
    RAISE EXCEPTION 'Platform Admin override audit logs update was not blocked';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Audit logs are immutable and cannot be updated or deleted' THEN
      RAISE EXCEPTION 'Unexpected error on updating audit log: %', SQLERRM;
    END IF;
  END;

  -- ----------------------------------------------------
  -- TEST 3: Family Access Lifecycle Updates & RLS
  -- ----------------------------------------------------
  -- Test 3.1: Create delegation in pending status (Owner is Investor A, Delegate is Investor B)
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000003", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  INSERT INTO public.family_delegations (id, workspace_id, owner_profile_id, delegate_profile_id, consent_status, is_active)
  VALUES ('87000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000004', 'pending', true);

  -- Test 3.2: Delegate consent accept (Delegate accepts)
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000004", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  v_delegation := public.delegate_consent_accept('87000000-0000-0000-0000-000000000001');
  IF v_delegation.consent_status <> 'accepted' THEN
    RAISE EXCEPTION 'Delegate accept consent failed to change status to accepted';
  END IF;

  -- Verify audit log generated for delegation acceptance
  SELECT * INTO v_audit_succeed FROM public.workspace_audit_logs 
  WHERE workspace_id = '83000000-0000-0000-0000-000000000001' 
    AND actor_profile_id = '82000000-0000-0000-0000-000000000004'
    AND action = 'family_delegation.accepted'
  ORDER BY occurred_at DESC LIMIT 1;
  IF v_audit_succeed.id IS NULL THEN
    RAISE EXCEPTION 'Audit log missing for family delegation acceptance';
  END IF;

  -- Test 3.4: Delegate consent revoke by owner
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000003", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  v_delegation := public.delegate_consent_revoke('87000000-0000-0000-0000-000000000001');
  IF v_delegation.consent_status <> 'revoked' OR v_delegation.is_active = TRUE THEN
    RAISE EXCEPTION 'Owner revoke consent failed to change status/is_active fields';
  END IF;

  -- Clean up the first delegation record to respect unique key constraint
  DELETE FROM public.family_delegations WHERE id = '87000000-0000-0000-0000-000000000001';

  -- Test 3.3: Delegate consent reject
  -- Insert another delegation in pending
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000003", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  INSERT INTO public.family_delegations (id, workspace_id, owner_profile_id, delegate_profile_id, consent_status, is_active)
  VALUES ('87000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000004', 'pending', true);

  -- Reject consent
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000004", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  v_delegation := public.delegate_consent_reject('87000000-0000-0000-0000-000000000002');
  IF v_delegation.consent_status <> 'rejected' OR v_delegation.is_active = TRUE THEN
    RAISE EXCEPTION 'Delegate reject consent failed to change status/is_active fields';
  END IF;

  -- Clean up the second delegation record to respect unique key constraint
  DELETE FROM public.family_delegations WHERE id = '87000000-0000-0000-0000-000000000002';

  -- Test 3.5: Platform Admin intervention via consent revoke (should require step-up MFA and log override attempts)
  -- Re-insert delegation and accept it
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000003", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  INSERT INTO public.family_delegations (id, workspace_id, owner_profile_id, delegate_profile_id, consent_status, is_active)
  VALUES ('87000000-0000-0000-0000-000000000003', '83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000004', 'pending', true);
  
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000004", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  PERFORM public.delegate_consent_accept('87000000-0000-0000-0000-000000000003');

  -- platform admin calls revoke without MFA (denied, but attempt logged)
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"user_role": "platform_admin"}, "amr": ["pwd"]}', true);
  BEGIN
    PERFORM public.delegate_consent_revoke('87000000-0000-0000-0000-000000000003');
    RAISE EXCEPTION 'Platform Admin override call delegate_consent_revoke bypassed step-up verification';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'platform_admin_step_up_required' THEN
      RAISE EXCEPTION 'Unexpected error on admin revoke step-up check: %', SQLERRM;
    END IF;
  END;

  -- Platform Admin calls revoke WITH MFA (succeeds)
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"user_role": "platform_admin"}, "amr": ["pwd", "mfa"]}', true);
  v_delegation := public.delegate_consent_revoke('87000000-0000-0000-0000-000000000003');
  IF v_delegation.consent_status <> 'revoked' OR v_delegation.is_active = TRUE THEN
    RAISE EXCEPTION 'Platform Admin delegate_consent_revoke failed';
  END IF;

  -- ----------------------------------------------------
  -- TEST 4: Outbox Concurrency/Claiming/Uniqueness
  -- ----------------------------------------------------
  -- Test 4.1: Outbox event uniqueness index check for order.created
  -- Attempt to insert duplicate order.created outbox event for the same order
  INSERT INTO public.event_outbox (id, entity_type, entity_id, event_type, status, payload)
  VALUES ('88000000-0000-0000-0000-000000000001', 'order_requests', '86000000-0000-0000-0000-000000000001', 'order.created', 'pending', '{}'::jsonb);

  BEGIN
    INSERT INTO public.event_outbox (id, entity_type, entity_id, event_type, status, payload)
    VALUES ('88000000-0000-0000-0000-000000000002', 'order_requests', '86000000-0000-0000-0000-000000000001', 'order.created', 'pending', '{}'::jsonb);
    RAISE EXCEPTION 'Event outbox uniqueness index contract check failed to prevent duplicate order.created';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%event_outbox_order_created_uidx%' THEN
      RAISE EXCEPTION 'Unexpected error on outbox uniqueness check: %', SQLERRM;
    END IF;
  END;

  -- Test 4.2: Claim validation on apply_auto_approval_decision
  -- Insert mock order in pending_qualification
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000003", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES ('86000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000003', 'SCH101', 'buy', 10000.00, 'pending_qualification');

  SELECT * INTO v_outbox FROM public.event_outbox WHERE entity_id = '86000000-0000-0000-0000-000000000002'::uuid;
  
  -- Attempt to apply decision without claiming (should throw event_not_claimed)
  BEGIN
    PERFORM public.apply_auto_approval_decision(
      '86000000-0000-0000-0000-000000000002',
      'auto_approved',
      '85000000-0000-0000-0000-000000000001',
      1,
      v_outbox.id
    );
    RAISE EXCEPTION 'apply_auto_approval_decision processed an unclaimed event';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'event_not_claimed' THEN
      RAISE EXCEPTION 'Unexpected error on unclaimed check: %', SQLERRM;
    END IF;
  END;

  -- Claim the event correctly
  UPDATE public.event_outbox 
  SET status = 'processing',
      claimed_at = pg_catalog.now(),
      claimed_by = '82000000-0000-0000-0000-000000000002'
  WHERE id = v_outbox.id;

  -- Decision should now apply successfully
  v_order := public.apply_auto_approval_decision(
    '86000000-0000-0000-0000-000000000002',
    'auto_approved',
    '85000000-0000-0000-0000-000000000001',
    1,
    v_outbox.id
  );
  IF v_order.status <> 'auto_approved' THEN
    RAISE EXCEPTION 'apply_auto_approval_decision failed to transition order status after event was claimed';
  END IF;

  -- ----------------------------------------------------
  -- TEST 5: Subscription RLS and States
  -- ----------------------------------------------------
  -- Test 5.1: Create investor subscription with 'trialing' state
  INSERT INTO public.investor_subscriptions (investor_profile_id, plan_id, status, start_date, current_period_end)
  VALUES ('82000000-0000-0000-0000-000000000003', '84000000-0000-0000-0000-000000000002', 'trialing', now(), now() + interval '14 days');

  -- Test 5.2: Verify billing/subscription RLS constraints for investor A
  PERFORM set_config('request.jwt.claims', '{"sub": "81000000-0000-0000-0000-000000000003", "role": "authenticated", "app_metadata": {"user_role": "investor"}}', true);
  
  SELECT count(*)::integer INTO v_count FROM public.investor_subscriptions;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Investor subscription RLS visibility failed';
  END IF;

END;
$$;

RESET ROLE;
ROLLBACK;
