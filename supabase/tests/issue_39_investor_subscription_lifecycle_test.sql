-- Issue #39 regression: investor lifecycle, atomic payment idempotency,
-- billing-owner separation, entitlement RLS, and exact API privileges.

BEGIN;

INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('39000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue39-investor-a@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('39000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue39-investor-b@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('39000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'issue39-advisor@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('39000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'issue39-platform-admin@moneybowl.test', '{}', '{"role":"platform_admin"}', now(), now());

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id IN (
  '39000000-0000-0000-0000-000000000001',
  '39000000-0000-0000-0000-000000000002'
);
UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id IN (
  '39000000-0000-0000-0000-000000000003',
  '39000000-0000-0000-0000-000000000004'
);

UPDATE public.profiles SET id = '39100000-0000-0000-0000-000000000001', role = 'investor'
WHERE user_id = '39000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '39100000-0000-0000-0000-000000000002', role = 'investor'
WHERE user_id = '39000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET id = '39100000-0000-0000-0000-000000000003', role = 'advisor'
WHERE user_id = '39000000-0000-0000-0000-000000000003';
UPDATE public.profiles SET id = '39100000-0000-0000-0000-000000000004', role = 'platform_admin'
WHERE user_id = '39000000-0000-0000-0000-000000000004';

INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES
  ('39000000-0000-0000-0000-000000000001', '39100000-0000-0000-0000-000000000001', 'verified_email', now(), 'active'),
  ('39000000-0000-0000-0000-000000000002', '39100000-0000-0000-0000-000000000002', 'verified_email', now(), 'active');

INSERT INTO public.subscription_plans (id, name, client_limit, monthly_price) VALUES
  ('39200000-0000-0000-0000-000000000001', 'Issue 39 Investor', 1, 199.00),
  ('39200000-0000-0000-0000-000000000002', 'Issue 39 Workspace', 25, 999.00),
  ('39200000-0000-0000-0000-000000000003', 'Issue 39 Unrelated', 5, 499.00);

INSERT INTO public.plan_entitlements (id, plan_id, entitlement_key, entitlement_value) VALUES
  ('39300000-0000-0000-0000-000000000001', '39200000-0000-0000-0000-000000000001', 'issue_39_investor_feature', 'true'),
  ('39300000-0000-0000-0000-000000000002', '39200000-0000-0000-0000-000000000002', 'issue_39_workspace_feature', 'true'),
  ('39300000-0000-0000-0000-000000000003', '39200000-0000-0000-0000-000000000003', 'issue_39_unrelated_feature', 'true');

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES (
  '39400000-0000-0000-0000-000000000001',
  'Issue 39 Workspace',
  'issue-39-workspace',
  '39100000-0000-0000-0000-000000000003',
  'active'
);
INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES (
  '39400000-0000-0000-0000-000000000001',
  '39100000-0000-0000-0000-000000000003',
  'admin',
  'active'
);
INSERT INTO public.workspace_billing (workspace_id, plan_id, status)
VALUES (
  '39400000-0000-0000-0000-000000000001',
  '39200000-0000-0000-0000-000000000002',
  'active'
);

INSERT INTO public.investor_subscriptions (
  id, investor_profile_id, plan_id
) VALUES
  ('39500000-0000-0000-0000-000000000001', '39100000-0000-0000-0000-000000000001', '39200000-0000-0000-0000-000000000001'),
  ('39500000-0000-0000-0000-000000000002', '39100000-0000-0000-0000-000000000002', '39200000-0000-0000-0000-000000000001');

DO $$
BEGIN
  IF (SELECT status FROM public.investor_subscriptions WHERE id = '39500000-0000-0000-0000-000000000001') <> 'trialing' THEN
    RAISE EXCEPTION 'new investor subscription did not default to trialing';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_policies WHERE schemaname = 'public' AND tablename = 'plan_entitlements') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'plan_entitlements'
         AND policyname = 'plan_entitlements_billing_select'
         AND cmd = 'SELECT'
         AND roles = ARRAY['authenticated']::name[]
     ) THEN
    RAISE EXCEPTION 'plan_entitlements policy set is not exact';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'plan_entitlements' AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'plan_entitlements RLS is not enabled';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_policies WHERE schemaname = 'public' AND tablename = 'investor_subscriptions') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname = 'public' AND tablename = 'investor_subscriptions'
         AND policyname = 'investor_subscriptions_owner' AND cmd = 'SELECT'
         AND roles = ARRAY['authenticated']::name[]
     )
     OR (SELECT count(*) FROM pg_catalog.pg_policies WHERE schemaname = 'public' AND tablename = 'payment_events') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname = 'public' AND tablename = 'payment_events'
         AND policyname = 'payment_events_select' AND cmd = 'SELECT'
         AND roles = ARRAY['authenticated']::name[]
     )
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname = 'public' AND tablename = 'investor_subscription_audit_logs'
     ) THEN
    RAISE EXCEPTION 'Issue #39 related policy sets are not exact';
  END IF;

  IF has_table_privilege('anon', 'public.plan_entitlements', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.plan_entitlements', 'SELECT')
     OR has_table_privilege('authenticated', 'public.plan_entitlements', 'INSERT,UPDATE,DELETE')
     OR NOT has_table_privilege('service_role', 'public.plan_entitlements', 'SELECT')
     OR has_table_privilege('service_role', 'public.plan_entitlements', 'INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon', 'public.investor_subscriptions', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.investor_subscriptions', 'INSERT,UPDATE,DELETE')
     OR has_table_privilege('service_role', 'public.investor_subscriptions', 'INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon', 'public.payment_events', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.payment_events', 'INSERT,UPDATE,DELETE')
     OR has_table_privilege('service_role', 'public.payment_events', 'INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon', 'public.investor_subscription_audit_logs', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.investor_subscription_audit_logs', 'SELECT,INSERT,UPDATE,DELETE')
     OR NOT has_table_privilege('service_role', 'public.investor_subscription_audit_logs', 'SELECT')
     OR has_table_privilege('service_role', 'public.investor_subscription_audit_logs', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'Issue #39 table privilege contract is not exact';
  END IF;

  IF EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS p
       CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) AS acl
       WHERE p.oid = 'public.transition_investor_subscription(uuid,text,text)'::pg_catalog.regprocedure
         AND acl.grantee = 0
         AND acl.privilege_type = 'EXECUTE'
     )
     OR has_function_privilege('authenticated', 'public.transition_investor_subscription(uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.transition_investor_subscription(uuid,text,text)', 'EXECUTE')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS p
       CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) AS acl
       WHERE p.oid = 'public.process_investor_subscription_payment(uuid,text,numeric,text,text,text)'::pg_catalog.regprocedure
         AND acl.grantee = 0
         AND acl.privilege_type = 'EXECUTE'
     )
     OR has_function_privilege('authenticated', 'public.process_investor_subscription_payment(uuid,text,numeric,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.process_investor_subscription_payment(uuid,text,numeric,text,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.can_read_plan_entitlement(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.can_read_plan_entitlement(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.can_read_plan_entitlement(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Issue #39 function privilege contract is not exact';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'process_investor_subscription_payment'
      AND p.prosecdef
      AND p.proconfig = ARRAY['search_path=""']::text[]
      AND p.prosrc LIKE '%pg_advisory_xact_lock%'
      AND p.prosrc LIKE '%FOR UPDATE%'
  ) THEN
    RAISE EXCEPTION 'payment processor is missing required concurrency/security fencing';
  END IF;
END;
$$;

-- Investor entitlement exposure starts in trialing and includes only own plan.
SELECT set_config('request.jwt.claims', '{"sub":"39000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.plan_entitlements) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM public.plan_entitlements
       WHERE entitlement_key = 'issue_39_investor_feature'
     ) THEN
    RAISE EXCEPTION 'trialing investor entitlement visibility is incorrect';
  END IF;

  BEGIN
    UPDATE public.investor_subscriptions
    SET status = 'active'
    WHERE id = '39500000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'authenticated direct subscription update was permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO public.payment_events (investor_profile_id, amount, payment_id, status)
    VALUES ('39100000-0000-0000-0000-000000000001', 1, 'issue39-direct-write', 'succeeded');
    RAISE EXCEPTION 'authenticated direct payment insert was permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;

-- Rejected skip before any successful mutation.
SET LOCAL ROLE service_role;
DO $$
BEGIN
  BEGIN
    PERFORM public.transition_investor_subscription(
      '39500000-0000-0000-0000-000000000002', 'past_due', 'skip attempt'
    );
    RAISE EXCEPTION 'skipped transition was permitted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_investor_subscription_transition' THEN RAISE; END IF;
  END;
END;
$$;

-- First payment atomically applies trialing -> active; exact replay is a no-op.
DO $$
DECLARE
  v_first record;
  v_replay record;
BEGIN
  SELECT * INTO v_first FROM public.process_investor_subscription_payment(
    '39500000-0000-0000-0000-000000000001',
    'issue39-payment-001', 199.00, 'succeeded', 'active', 'initial payment captured'
  );
  SELECT * INTO v_replay FROM public.process_investor_subscription_payment(
    '39500000-0000-0000-0000-000000000001',
    'issue39-payment-001', 199.00, 'succeeded', 'active', 'initial payment captured'
  );

  IF v_first.replayed OR NOT v_replay.replayed OR v_first.payment_event_id <> v_replay.payment_event_id THEN
    RAISE EXCEPTION 'exact payment replay was not idempotent';
  END IF;
  IF (SELECT count(*) FROM public.payment_events WHERE payment_id = 'issue39-payment-001') <> 1
     OR (SELECT count(*) FROM public.investor_subscription_audit_logs WHERE investor_subscription_id = '39500000-0000-0000-0000-000000000001') <> 1
     OR (SELECT status FROM public.investor_subscriptions WHERE id = '39500000-0000-0000-0000-000000000001') <> 'active' THEN
    RAISE EXCEPTION 'payment replay duplicated its financial or lifecycle effect';
  END IF;

  BEGIN
    PERFORM public.process_investor_subscription_payment(
      '39500000-0000-0000-0000-000000000001',
      'issue39-payment-001', 200.00, 'succeeded', 'active', 'conflicting replay'
    );
    RAISE EXCEPTION 'conflicting payment-id reuse was permitted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'payment_id_conflict' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- Payment visibility remains investor-owned.
SELECT set_config('request.jwt.claims', '{"sub":"39000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.payment_events WHERE payment_id = 'issue39-payment-001') <> 1 THEN
    RAISE EXCEPTION 'investor cannot see own payment event';
  END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub":"39000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.payment_events WHERE payment_id = 'issue39-payment-001') <> 0 THEN
    RAISE EXCEPTION 'investor can see another investor payment event';
  END IF;
END $$;
RESET ROLE;

-- Exercise every remaining forward state and fail closed at each denied edge.
SET LOCAL ROLE service_role;
DO $$
BEGIN
  PERFORM public.transition_investor_subscription('39500000-0000-0000-0000-000000000001', 'past_due', 'payment overdue');
  BEGIN
    PERFORM public.transition_investor_subscription('39500000-0000-0000-0000-000000000001', 'active', 'backward attempt');
    RAISE EXCEPTION 'backward transition was permitted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_investor_subscription_transition' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claims', '{"sub":"39000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.plan_entitlements) THEN
    RAISE EXCEPTION 'past_due investor retained entitlement access';
  END IF;
END $$;
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT public.transition_investor_subscription('39500000-0000-0000-0000-000000000001', 'suspended', 'delinquency threshold reached');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub":"39000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.plan_entitlements) THEN
    RAISE EXCEPTION 'suspended investor retained entitlement access';
  END IF;
END $$;
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT public.transition_investor_subscription('39500000-0000-0000-0000-000000000001', 'cancelled', 'subscription cancelled');
DO $$
BEGIN
  BEGIN
    PERFORM public.transition_investor_subscription('39500000-0000-0000-0000-000000000001', 'active', 'terminal recovery attempt');
    RAISE EXCEPTION 'cancelled subscription was not terminal';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_investor_subscription_transition' THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM public.investor_subscription_audit_logs WHERE investor_subscription_id = '39500000-0000-0000-0000-000000000001') <> 4 THEN
    RAISE EXCEPTION 'permitted lifecycle transitions were not audited exactly once';
  END IF;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claims', '{"sub":"39000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.plan_entitlements) THEN
    RAISE EXCEPTION 'cancelled investor retained entitlement access';
  END IF;
END $$;
RESET ROLE;

-- Workspace billing exposes only its current plan to an active member.
SELECT set_config('request.jwt.claims', '{"sub":"39000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.plan_entitlements) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.plan_entitlements WHERE entitlement_key = 'issue_39_workspace_feature') THEN
    RAISE EXCEPTION 'workspace entitlement visibility is incorrect';
  END IF;
END $$;
RESET ROLE;

-- Unrelated users and Platform Admin have no implicit plan-catalog bypass.
SELECT set_config('request.jwt.claims', '{"sub":"39000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"platform_admin"}}', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.plan_entitlements) THEN
    RAISE EXCEPTION 'unrelated Platform Admin received direct entitlement access';
  END IF;
END $$;
RESET ROLE;

-- The delivered owner XOR remains active for direct database writes.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payment_events (
      workspace_id, investor_profile_id, amount, payment_id, status
    ) VALUES (
      '39400000-0000-0000-0000-000000000001',
      '39100000-0000-0000-0000-000000000001',
      1.00,
      'issue39-xor-violation',
      'succeeded'
    );
    RAISE EXCEPTION 'payment billing-owner XOR was weakened';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END;
$$;

ROLLBACK;
