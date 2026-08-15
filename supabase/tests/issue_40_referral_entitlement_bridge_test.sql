-- Issue #40 corrective regression: referral rewards authorize only the
-- canonical Premium Investor features for a trusted, server-derived window.

BEGIN;

INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('40e00000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'issue40-entitlement-referrer@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('40e00000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'issue40-entitlement-referee@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('40e00000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'issue40-entitlement-unrelated@moneybowl.test', '{}', '{"role":"user"}', now(), now()),
  ('40e00000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'issue40-entitlement-advisor@moneybowl.test', '{}', '{"role":"user"}', now(), now());

UPDATE public.user_accounts SET account_state = 'linked_investor'
WHERE user_id IN (
  '40e00000-0000-4000-8000-000000000001',
  '40e00000-0000-4000-8000-000000000002',
  '40e00000-0000-4000-8000-000000000003'
);
UPDATE public.user_accounts SET account_state = 'advisor'
WHERE user_id = '40e00000-0000-4000-8000-000000000004';

UPDATE public.profiles SET id = '40e10000-0000-4000-8000-000000000001', role = 'investor', account_status = 'active'
WHERE user_id = '40e00000-0000-4000-8000-000000000001';
UPDATE public.profiles SET id = '40e10000-0000-4000-8000-000000000002', role = 'investor', account_status = 'active'
WHERE user_id = '40e00000-0000-4000-8000-000000000002';
UPDATE public.profiles SET id = '40e10000-0000-4000-8000-000000000003', role = 'investor', account_status = 'active'
WHERE user_id = '40e00000-0000-4000-8000-000000000003';
UPDATE public.profiles SET id = '40e10000-0000-4000-8000-000000000004', role = 'advisor', account_status = 'active'
WHERE user_id = '40e00000-0000-4000-8000-000000000004';

INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES
  ('40e00000-0000-4000-8000-000000000001', '40e10000-0000-4000-8000-000000000001', 'verified_email', now(), 'active'),
  ('40e00000-0000-4000-8000-000000000002', '40e10000-0000-4000-8000-000000000002', 'verified_email', now(), 'active'),
  ('40e00000-0000-4000-8000-000000000003', '40e10000-0000-4000-8000-000000000003', 'verified_email', now(), 'active');

INSERT INTO public.subscription_plans (id, name, client_limit, monthly_price)
VALUES
  ('40e20000-0000-4000-8000-000000000001', 'Issue 40 Investor Entitlement Test', 1, 199.00),
  ('40e20000-0000-4000-8000-000000000002', 'Issue 40 Workspace Entitlement Test', 25, 999.00);

INSERT INTO public.plan_entitlements (id, plan_id, entitlement_key, entitlement_value)
VALUES
  ('40e30000-0000-4000-8000-000000000001', '40e20000-0000-4000-8000-000000000001', 'family_hub_enabled', 'true'),
  ('40e30000-0000-4000-8000-000000000002', '40e20000-0000-4000-8000-000000000002', 'family_hub_enabled', 'true');

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES (
  '40e40000-0000-4000-8000-000000000001',
  'Issue 40 Entitlement Workspace',
  'issue-40-entitlement-workspace',
  '40e10000-0000-4000-8000-000000000004',
  'active'
);
INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('40e40000-0000-4000-8000-000000000001', '40e10000-0000-4000-8000-000000000004', 'admin', 'active'),
  ('40e40000-0000-4000-8000-000000000001', '40e10000-0000-4000-8000-000000000003', 'investor', 'active');
INSERT INTO public.workspace_billing (workspace_id, plan_id, status)
VALUES (
  '40e40000-0000-4000-8000-000000000001',
  '40e20000-0000-4000-8000-000000000002',
  'active'
);

DO $$
BEGIN
  IF has_function_privilege('anon', 'public.has_investor_entitlement(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.has_investor_entitlement(text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.has_investor_entitlement(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'referral entitlement authorizer privilege contract is not exact';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS function
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = function.pronamespace
    WHERE namespace.nspname = 'public'
      AND function.proname = 'has_investor_entitlement'
      AND function.prosecdef
      AND function.provolatile = 's'
      AND function.proconfig = ARRAY['search_path=""']::pg_catalog.text[]
      AND function.prosrc LIKE '%reward.created_at%'
      AND function.prosrc LIKE '%reward.duration_days%'
      AND function.prosrc NOT LIKE '%workspace_billing%'
  ) THEN
    RAISE EXCEPTION 'referral entitlement authorizer security/time contract is missing';
  END IF;
END;
$$;

-- Create one conversion through the same caller-bound RPC used by onboarding.
SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE issue_40_entitlement_values AS
SELECT referral_code
FROM public.get_or_create_investor_referral();
GRANT SELECT ON issue_40_entitlement_values TO authenticated;
GRANT SELECT ON issue_40_entitlement_values TO anon;
RESET ROLE;

CREATE TEMP TABLE issue_40_entitlement_claim (
  claim_token pg_catalog.text NOT NULL
);
GRANT SELECT ON issue_40_entitlement_claim TO authenticated;
GRANT INSERT ON issue_40_entitlement_claim TO anon;
SET LOCAL ROLE anon;
INSERT INTO issue_40_entitlement_claim(claim_token)
SELECT claim_token
FROM public.create_referral_onboarding_claim(
  (SELECT referral_code FROM issue_40_entitlement_values)
);
RESET ROLE;

-- This test is intentionally one transaction. Move the privileged Auth
-- fixture timestamp after the server claim to emulate the real later signup
-- transaction while keeping the production comparison server-owned.
UPDATE auth.users
SET created_at = pg_catalog.clock_timestamp() + pg_catalog.make_interval(secs => 1)
WHERE id = '40e00000-0000-4000-8000-000000000002';

SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000002","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
SELECT * FROM public.bind_referral_onboarding_claim(
  (SELECT claim_token FROM issue_40_entitlement_claim)
);
SELECT * FROM public.process_investor_referral_conversion(
  (SELECT claim_token FROM issue_40_entitlement_claim)
);
DO $$
DECLARE
  v_key pg_catalog.text;
BEGIN
  IF (SELECT pg_catalog.count(*) FROM public.referral_rewards) <> 1
     OR EXISTS (
       SELECT 1 FROM public.referral_rewards WHERE duration_days <> 30
     ) THEN
    -- RLS exposes only the referee's row in this caller context.
    RAISE EXCEPTION 'referee reward did not use the server-owned 30-day term';
  END IF;

  FOREACH v_key IN ARRAY ARRAY[
    'multi_advisor_enabled',
    'family_hub_enabled',
    'capital_gain_projection_enabled',
    'priority_support_enabled',
    'advanced_analytics_enabled'
  ] LOOP
    IF NOT public.has_investor_entitlement(v_key) THEN
      RAISE EXCEPTION 'referee did not receive referral Premium entitlement %', v_key;
    END IF;
  END LOOP;

  IF public.has_investor_entitlement('crm_enabled')
     OR public.has_investor_entitlement('auto_approval_enabled')
     OR public.has_investor_entitlement('mailbag_ingestion_enabled') THEN
    RAISE EXCEPTION 'referral reward exposed an MFD-only entitlement';
  END IF;
END;
$$;
RESET ROLE;

-- The referrer receives the same feature authorization.
SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF NOT public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'referrer did not receive referral Premium entitlement';
  END IF;
END;
$$;
RESET ROLE;

-- Time, not the status flag alone, ends access after thirty days.
UPDATE public.referral_rewards
SET created_at = pg_catalog.now() - pg_catalog.make_interval(days => 31)
WHERE profile_id = '40e10000-0000-4000-8000-000000000001';
SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'expired-by-time reward retained Premium access';
  END IF;
END;
$$;
RESET ROLE;

-- A trusted server-side status expiry also denies reward access.
UPDATE public.referral_rewards
SET status = 'expired'
WHERE profile_id = '40e10000-0000-4000-8000-000000000002';
SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000002","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'status-expired reward retained Premium access';
  END IF;
END;
$$;
RESET ROLE;

-- Paid/trial Investor access remains an independent OR source. Once that
-- subscription leaves trialing/active, the already-expired reward cannot mask it.
INSERT INTO public.investor_subscriptions (
  id, investor_profile_id, plan_id, status
) VALUES (
  '40e50000-0000-4000-8000-000000000001',
  '40e10000-0000-4000-8000-000000000002',
  '40e20000-0000-4000-8000-000000000001',
  'trialing'
);
SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000002","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF NOT public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'trialing subscription lost its existing entitlement behavior';
  END IF;
END;
$$;
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT public.transition_investor_subscription(
  '40e50000-0000-4000-8000-000000000001', 'active', 'entitlement interaction test'
);
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000002","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF NOT public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'active subscription lost its existing entitlement behavior';
  END IF;
END;
$$;
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT public.transition_investor_subscription(
  '40e50000-0000-4000-8000-000000000001', 'past_due', 'entitlement interaction test'
);
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000002","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'past_due subscription or expired reward retained access';
  END IF;
END;
$$;
RESET ROLE;

-- Workspace membership/billing never feeds this Investor capability check.
SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000003","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'mapped Investor inherited workspace Premium entitlement';
  END IF;
END;
$$;
RESET ROLE;

-- The existing MFD-side workspace plan path remains intact and cannot be
-- repurposed as an Investor capability.
SELECT set_config('request.jwt.claims', '{"sub":"40e00000-0000-4000-8000-000000000004","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF NOT public.can_read_plan_entitlement('40e20000-0000-4000-8000-000000000002')
     OR (SELECT count(*) FROM public.plan_entitlements) <> 1
     OR public.has_investor_entitlement('family_hub_enabled') THEN
    RAISE EXCEPTION 'workspace isolation or authorised MFD entitlement behavior regressed';
  END IF;
END;
$$;
RESET ROLE;

ROLLBACK;
