-- Core Auth and RBAC regression tests.
-- Verifies that:
-- 1. Active advisor can view all user accounts/profiles.
-- 2. Suspended/inactive advisor is blocked.
-- 3. Active linked investor can view own portfolios/profiles.
-- 4. Suspended/inactive linked investor is blocked.

BEGIN;

-- 1. Set up test users and profiles
-- Note: inserting into auth.users automatically triggers handle_new_user()
-- which inserts default profiles and user_accounts.
INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('51000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'active-advisor@sharanfincorp.test', '{}', '{}', now(), now()),
  ('51000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'suspended-advisor@sharanfincorp.test', '{}', '{}', now(), now()),
  ('51000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'active-investor@sharanfincorp.test', '{}', '{}', now(), now()),
  ('51000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'suspended-investor@sharanfincorp.test', '{}', '{}', now(), now());

-- Update user accounts state
UPDATE public.user_accounts SET account_state = 'advisor' WHERE user_id IN ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002');
UPDATE public.user_accounts SET account_state = 'linked_investor' WHERE user_id IN ('51000000-0000-0000-0000-000000000003', '51000000-0000-0000-0000-000000000004');

-- Update the automatically created profiles with proper IDs, roles, and status
UPDATE public.profiles SET id = '52000000-0000-0000-0000-000000000001', full_name = 'Active Advisor', role = 'advisor', account_status = 'active' WHERE user_id = '51000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '52000000-0000-0000-0000-000000000002', full_name = 'Suspended Advisor', role = 'advisor', account_status = 'suspended' WHERE user_id = '51000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET id = '52000000-0000-0000-0000-000000000003', full_name = 'Active Investor', role = 'investor', account_status = 'active' WHERE user_id = '51000000-0000-0000-0000-000000000003';
UPDATE public.profiles SET id = '52000000-0000-0000-0000-000000000004', full_name = 'Suspended Investor', role = 'investor', account_status = 'suspended' WHERE user_id = '51000000-0000-0000-0000-000000000004';

-- Link investor accounts using hardcoded IDs
INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('51000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000003', 'verified_email', now(), 'active'),
  ('51000000-0000-0000-0000-000000000004', '52000000-0000-0000-0000-000000000004', 'verified_email', now(), 'active');

-- Create dummy portfolios
INSERT INTO public.portfolios (id, client_id, total_invested_value, current_market_value)
VALUES
  ('53000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000003', 10000.0, 12000.0),
  ('53000000-0000-0000-0000-000000000004', '52000000-0000-0000-0000-000000000004', 10000.0, 12000.0);

-- Switch role to authenticated to enforce RLS policies during tests
SET ROLE authenticated;

DO $$
BEGIN
  -- Test 1: Active Advisor evaluation
  PERFORM set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000001', true);
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Active advisor was rejected from is_admin()';
  END IF;

  -- Test 2: Suspended Advisor evaluation
  PERFORM set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000002', true);
  IF public.is_admin() THEN
    RAISE EXCEPTION 'Suspended advisor was approved in is_admin()';
  END IF;

  -- Test 3: Active Investor link evaluation
  PERFORM set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000003', true);
  IF NOT public.has_active_investor_link('52000000-0000-0000-0000-000000000003') THEN
    RAISE EXCEPTION 'Active investor has_active_investor_link was rejected';
  END IF;

  -- Test 4: Suspended Investor link evaluation
  PERFORM set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000004', true);
  IF public.has_active_investor_link('52000000-0000-0000-0000-000000000004') THEN
    RAISE EXCEPTION 'Suspended investor has_active_investor_link was approved';
  END IF;
END;
$$;

-- Switch role back to postgres to clean up and rollback transaction
RESET ROLE;

ROLLBACK;
