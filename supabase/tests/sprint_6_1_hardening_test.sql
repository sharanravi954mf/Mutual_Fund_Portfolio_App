-- Test Suite: Sprint 6.1 Hardening & Compliance Verification
-- Verifies: profile resolution, cancel validation, qualify constraints, auto-approval rules, family delegations, dual billing, referrals, and audit log immutability.

BEGIN;

-- 1. Setup Test Fixtures
INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('71000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'platform-admin@moneybowl.test', '{}', '{"role":"platform_admin"}', now(), now()),
  ('71000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'advisor-a@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('71000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'investor-a@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('71000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'investor-b@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('71000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'advisor-b@moneybowl.test', '{}', '{"role":"user"}', now(), now());

-- Update user accounts state
UPDATE public.user_accounts SET account_state = 'advisor' WHERE user_id IN ('71000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000005');
UPDATE public.user_accounts SET account_state = 'linked_investor' WHERE user_id IN ('71000000-0000-0000-0000-000000000003', '71000000-0000-0000-0000-000000000004');

-- Map profiles
UPDATE public.profiles SET id = '72000000-0000-0000-0000-000000000001', role = 'platform_admin', full_name = 'Platform Admin' WHERE user_id = '71000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '72000000-0000-0000-0000-000000000002', role = 'advisor', full_name = 'Workspace A Advisor' WHERE user_id = '71000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET id = '72000000-0000-0000-0000-000000000003', role = 'investor', full_name = 'Workspace A Investor A' WHERE user_id = '71000000-0000-0000-0000-000000000003';
UPDATE public.profiles SET id = '72000000-0000-0000-0000-000000000004', role = 'investor', full_name = 'Workspace A Investor B' WHERE user_id = '71000000-0000-0000-0000-000000000004';
UPDATE public.profiles SET id = '72000000-0000-0000-0000-000000000005', role = 'advisor', full_name = 'Workspace B Advisor' WHERE user_id = '71000000-0000-0000-0000-000000000005';

-- Establish Workspace A and Workspace B
INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('73000000-0000-0000-0000-000000000001', 'Workspace A', 'workspace-a-test', '72000000-0000-0000-0000-000000000002', 'active'),
  ('73000000-0000-0000-0000-000000000002', 'Workspace B', 'workspace-b-test', '72000000-0000-0000-0000-000000000005', 'active');

-- Clear pre-populated memberships for testing
DELETE FROM public.workspace_memberships WHERE profile_id IN ('72000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000003', '72000000-0000-0000-0000-000000000004', '72000000-0000-0000-0000-000000000005');

-- Create active memberships
INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', 'investor', 'active'),
  ('73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000004', 'investor', 'active'),
  ('73000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000005', 'advisor', 'active');

-- Link investor accounts
INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('71000000-0000-0000-0000-000000000003', '72000000-0000-0000-0000-000000000003', 'verified_email', now(), 'active'),
  ('71000000-0000-0000-0000-000000000004', '72000000-0000-0000-0000-000000000004', 'verified_email', now(), 'active');

-- Subscription Plans
INSERT INTO public.subscription_plans (id, name, type, price, currency)
VALUES
  ('74000000-0000-0000-0000-000000000001', 'MFD Growth', 'advisor', 2999.00, 'INR'),
  ('74000000-0000-0000-0000-000000000002', 'Premium Investor', 'investor', 499.00, 'INR');

-- Workspace Billing details
INSERT INTO public.workspace_billing (workspace_id, plan_id, status, current_client_count)
VALUES
  ('73000000-0000-0000-0000-000000000001', '74000000-0000-0000-0000-000000000001', 'active', 0),
  ('73000000-0000-0000-0000-000000000002', '74000000-0000-0000-0000-000000000001', 'active', 0);

-- Auto Approval Rules
INSERT INTO public.auto_approval_rules (id, workspace_id, transaction_type, min_amount, max_amount, is_active, rule_version)
VALUES
  ('75000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', 'purchase', 0.00, 10000.00, true, 1);

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;

-- Execute checks
DO $$
DECLARE
  v_res_profile_id uuid;
  v_order public.order_requests;
  v_outbox public.event_outbox;
  v_delegation public.family_delegations;
  v_billing public.workspace_billing;
  v_err_msg text;
BEGIN
  -- 1. Verify current_user_profile_id() resolution mapping
  PERFORM set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000003', true);
  v_res_profile_id := public.current_user_profile_id();
  IF v_res_profile_id IS NULL OR v_res_profile_id <> '72000000-0000-0000-0000-000000000003'::uuid THEN
    RAISE EXCEPTION 'current_user_profile_id() failed to resolve profile ID';
  END IF;

  -- 2. Verify cancel_order validates state bounds and handles already_cancelled exception
  -- Insert a mock order request in pending_qualification
  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES ('76000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', 'SCH101', 'purchase', 5000.00, 'pending_qualification');

  -- Verify client owner can cancel
  v_order := public.cancel_order('76000000-0000-0000-0000-000000000001', 'Test cancellation');
  IF v_order.status <> 'cancelled' THEN
    RAISE EXCEPTION 'cancel_order failed to transition status to cancelled';
  END IF;

  -- Verify repeated cancellation returns already_cancelled exception
  BEGIN
    PERFORM public.cancel_order('76000000-0000-0000-0000-000000000001', 'Repeated cancel');
    RAISE EXCEPTION 'Repeated cancellation did not throw already_cancelled';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'already_cancelled' THEN
      RAISE EXCEPTION 'Unexpected error on repeated cancellation: %', SQLERRM;
    END IF;
  END;

  -- 3. Verify qualify_order limits qualification strictly to pending_review and advisor roles
  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES ('76000000-0000-0000-0000-000000000002', '73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', 'SCH101', 'purchase', 5000.00, 'pending_review');

  -- Verify advisor in workspace A can qualify
  PERFORM set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000002', true);
  v_order := public.qualify_order('76000000-0000-0000-0000-000000000002', 'approved', 'Verified order');
  IF v_order.status <> 'approved' THEN
    RAISE EXCEPTION 'qualify_order failed to approve pending_review order';
  END IF;

  -- Verify qualify_order fails on non-pending_review state
  BEGIN
    PERFORM public.qualify_order('76000000-0000-0000-0000-000000000002', 'approved', 'Re-approval attempt');
    RAISE EXCEPTION 'qualify_order did not reject final-state qualification';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_qualification_state' THEN
      RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
    END IF;
  END;

  -- Verify platform admin cannot qualify order manually
  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES ('76000000-0000-0000-0000-000000000003', '73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', 'SCH101', 'purchase', 5000.00, 'pending_review');

  PERFORM set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);
  BEGIN
    PERFORM public.qualify_order('76000000-0000-0000-0000-000000000003', 'approved', 'Admin qualification attempt');
    RAISE EXCEPTION 'Platform Admin bypass occurred during manual qualification';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'not_authorized' THEN
      RAISE EXCEPTION 'Unexpected error on admin qualify: %', SQLERRM;
    END IF;
  END;

  -- 4. Verify apply_auto_approval_decision idempotency and rule validations
  -- Create order and find matching outbox event ID
  PERFORM set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000003', true);
  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES ('76000000-0000-0000-0000-000000000004', '73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', 'SCH101', 'purchase', 2000.00, 'pending_qualification');

  SELECT * INTO v_outbox FROM public.event_outbox WHERE entity_id = '76000000-0000-0000-0000-000000000004'::uuid LIMIT 1;
  IF v_outbox.id IS NULL THEN
    RAISE EXCEPTION 'Event outbox record not generated on order insert';
  END IF;

  -- Call apply_auto_approval_decision
  v_order := public.apply_auto_approval_decision(
    '76000000-0000-0000-0000-000000000004',
    'auto_approved',
    '75000000-0000-0000-0000-000000000001',
    1,
    v_outbox.id
  );
  IF v_order.status <> 'auto_approved' THEN
    RAISE EXCEPTION 'Auto approval decision was not applied';
  END IF;

  -- Replay check: second identical call returns success
  v_order := public.apply_auto_approval_decision(
    '76000000-0000-0000-0000-000000000004',
    'auto_approved',
    '75000000-0000-0000-0000-000000000001',
    1,
    v_outbox.id
  );

  -- Replay check with conflict throws exception
  BEGIN
    PERFORM public.apply_auto_approval_decision(
      '76000000-0000-0000-0000-000000000004',
      'pending_review',
      null,
      null,
      v_outbox.id
    );
    RAISE EXCEPTION 'Idempotency conflict not detected';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'idempotency_conflict' THEN
      RAISE EXCEPTION 'Unexpected error on replay conflict: %', SQLERRM;
    END IF;
  END;

  -- 5. Verify Family Access consent lifecycle RPCs
  PERFORM set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000003', true);
  INSERT INTO public.family_delegations (id, workspace_id, owner_profile_id, delegate_profile_id, consent_status, is_active)
  VALUES ('77000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', '72000000-0000-0000-0000-000000000004', 'pending', true);

  -- Accept consent (requires delegate user)
  PERFORM set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000004', true);
  v_delegation := public.delegate_consent_accept('77000000-0000-0000-0000-000000000001');
  IF v_delegation.consent_status <> 'accepted' THEN
    RAISE EXCEPTION 'delegate_consent_accept failed';
  END IF;

  -- Revoke delegation (by owner)
  PERFORM set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000003', true);
  v_delegation := public.delegate_consent_revoke('77000000-0000-0000-0000-000000000001');
  IF v_delegation.is_active THEN
    RAISE EXCEPTION 'delegate_consent_revoke failed';
  END IF;

  -- 6. Verify Dual billing XOR constraints
  -- Valid workspace payment
  INSERT INTO public.payment_events (workspace_id, amount, payment_id, status)
  VALUES ('73000000-0000-0000-0000-000000000001', 2999.00, 'PAY-WS-001', 'success');

  -- Valid investor payment
  INSERT INTO public.payment_events (investor_profile_id, amount, payment_id, status)
  VALUES ('72000000-0000-0000-0000-000000000003', 499.00, 'PAY-INV-001', 'success');

  -- Invalid dual payment (violates XOR constraint)
  BEGIN
    INSERT INTO public.payment_events (workspace_id, investor_profile_id, amount, payment_id, status)
    VALUES ('73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', 100.00, 'PAY-BAD-001', 'success');
    RAISE EXCEPTION 'XOR billing owner constraint was bypassed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%payment_events_billing_owner_xor%' THEN
      RAISE EXCEPTION 'Unexpected error on XOR check: %', SQLERRM;
    END IF;
  END;

  -- 7. Verify Referrals converted mappings
  INSERT INTO public.investor_referrals (id, referrer_profile_id, referee_email, referral_code, token_hash)
  VALUES ('78000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', 'referee@test.com', 'REF100', 'tokenhash123');

  INSERT INTO public.referral_conversions (referral_id, referee_profile_id)
  VALUES ('78000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000004');

  -- 8. Verify Audit log immutability
  BEGIN
    UPDATE public.workspace_audit_logs SET action = 'tampered' WHERE workspace_id = '73000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'Audit log update immutability trigger was bypassed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Audit logs are immutable and cannot be updated or deleted' THEN
      RAISE EXCEPTION 'Unexpected error on audit update check: %', SQLERRM;
    END IF;
  END;

  BEGIN
    DELETE FROM public.workspace_audit_logs WHERE workspace_id = '73000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'Audit log delete immutability trigger was bypassed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Audit logs are immutable and cannot be updated or deleted' THEN
      RAISE EXCEPTION 'Unexpected error on audit delete check: %', SQLERRM;
    END IF;
  END;

  -- 9. Verify DELETE trigger safety handles OLD row values in sync_billing_workspace_limit
  INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
  VALUES ('73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', 'investor', 'active')
  ON CONFLICT (workspace_id, profile_id) WHERE (ended_at IS NULL) DO UPDATE SET status = 'active';

  DELETE FROM public.workspace_memberships
  WHERE workspace_id = '73000000-0000-0000-0000-000000000001'
    AND profile_id = '72000000-0000-0000-0000-000000000003';

  SELECT * INTO v_billing FROM public.workspace_billing WHERE workspace_id = '73000000-0000-0000-0000-000000000001';
  -- Active client count should remain safely updated without throwing record error during DELETE
  IF v_billing.current_client_count IS NULL THEN
    RAISE EXCEPTION 'sync_billing_workspace_limit failed during membership deletion';
  END IF;

END;
$$;

RESET ROLE;
ROLLBACK;
