-- Migration: Order Execution Engine, Subscriptions & Schema Extensions
-- Suffix: 20260801000000_brd_v1_2_1_execution_subscriptions_referrals.sql

BEGIN;

-- 1. Create Custom Enum Types for Orders
CREATE TYPE public.order_type AS ENUM ('buy', 'sell', 'switch');
CREATE TYPE public.order_status AS ENUM ('pending_qualification', 'auto_approved', 'approved', 'rejected', 'submitted_to_exchange');

-- 2. Create Order Requests Table
CREATE TABLE public.order_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  investor_id uuid not null references public.profiles(id) on delete cascade,
  scheme_code text not null,
  type public.order_type not null,
  amount numeric(15, 2) check (amount > 0),
  units numeric(12, 4) check (units > 0),
  status public.order_status not null default 'pending_qualification',
  auto_approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint order_requests_amount_or_units check (amount is not null or units is not null)
);

-- 3. Create Subscription Plans Table
CREATE TABLE public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  client_limit integer not null check (client_limit >= 0),
  monthly_price numeric(15, 2) not null check (monthly_price >= 0),
  created_at timestamptz not null default now()
);

-- Seed Subscription Plans
INSERT INTO public.subscription_plans (name, client_limit, monthly_price)
VALUES 
  ('Starter', 25, 0.00),
  ('Pro MFD', 999999, 1500.00),
  ('Enterprise Firm', 99999999, 5000.00)
ON CONFLICT (name) DO NOTHING;

-- 4. Create Workspace Billing Table
CREATE TABLE public.workspace_billing (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade unique,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null check (status in ('trialing', 'active', 'past_due', 'suspended', 'cancelled')) default 'trialing',
  current_client_count integer not null default 0 check (current_client_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 5. Create Payment Events Table (Idempotent Webhook Target)
CREATE TABLE public.payment_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  amount numeric(15, 2) not null check (amount >= 0),
  payment_id text not null unique, -- Idempotency key
  status text not null,
  created_at timestamptz not null default now()
);

-- 6. Create Investor Referrals Table
CREATE TABLE public.investor_referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_profile_id uuid not null references public.profiles(id) on delete cascade,
  referee_email text not null,
  referral_code text not null,
  token_hash text not null unique,
  created_at timestamptz not null default now()
);

-- 7. Create Referral Conversions Table
CREATE TABLE public.referral_conversions (
  id uuid primary key default gen_random_uuid(),
  referral_id uuid not null references public.investor_referrals(id) on delete cascade,
  referee_profile_id uuid not null references public.profiles(id) on delete cascade unique,
  converted_at timestamptz not null default now()
);

-- 8. Create Referral Rewards Table
CREATE TABLE public.referral_rewards (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  reward_type text not null check (reward_type in ('subscription_extension')) default 'subscription_extension',
  duration_days integer not null default 30 check (duration_days > 0),
  status text not null check (status in ('active', 'expired')) default 'active',
  created_at timestamptz not null default now()
);

-- 9. Create Family Delegations Table
CREATE TABLE public.family_delegations (
  id uuid primary key default gen_random_uuid(),
  owner_investor_id uuid not null references public.profiles(id) on delete cascade,
  delegate_investor_id uuid not null references public.profiles(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint family_delegations_no_self check (owner_investor_id <> delegate_investor_id),
  constraint family_delegations_unique unique (owner_investor_id, delegate_investor_id)
);

-- 10. Create Event Outbox Table
CREATE TABLE public.event_outbox (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  payload jsonb not null,
  status text not null check (status in ('pending', 'processing', 'completed', 'failed')) default 'pending',
  retry_count integer not null default 0 check (retry_count >= 0),
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 11. Transactional trigger to write event to outbox when order is created
CREATE OR REPLACE FUNCTION public.trigger_order_outbox_event()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.event_outbox (event_type, payload, status)
  VALUES (
    'order.created',
    jsonb_build_object(
      'order_id', NEW.id,
      'workspace_id', NEW.workspace_id,
      'investor_id', NEW.investor_id,
      'scheme_code', NEW.scheme_code,
      'type', NEW.type,
      'amount', NEW.amount,
      'units', NEW.units,
      'status', NEW.status
    ),
    'pending'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER order_created_outbox_trigger
  AFTER INSERT ON public.order_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_order_outbox_event();

-- 12. Enable Row-Level Security on all newly created tables
ALTER TABLE public.order_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_billing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investor_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_conversions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_delegations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_outbox ENABLE ROW LEVEL SECURITY;

-- 13. Order Requests RLS Policies with explicit WITH CHECK clauses
-- Select Policies
CREATE POLICY order_requests_investor_select ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (
    investor_id = auth.uid()
  );

CREATE POLICY order_requests_advisor_select ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.workspace_memberships wm
      WHERE wm.workspace_id = order_requests.workspace_id
        AND wm.profile_id = auth.uid()
        AND wm.role IN ('advisor', 'admin', 'operations')
        AND wm.status = 'active'
    )
  );

CREATE POLICY order_requests_admin_select ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
  );

-- Insert Policies
CREATE POLICY order_requests_investor_insert ON public.order_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    investor_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.workspace_memberships wm
      WHERE wm.workspace_id = order_requests.workspace_id
        AND wm.profile_id = auth.uid()
        AND wm.status = 'active'
    )
    -- Family guest delegates are read-only and blocked from inserting orders on behalf of other users
    AND NOT EXISTS (
      SELECT 1 FROM public.family_delegations fd
      WHERE fd.delegate_investor_id = auth.uid()
        AND fd.owner_investor_id = investor_id
        AND fd.is_active = TRUE
    )
  );

-- Update Policies
CREATE POLICY order_requests_advisor_update ON public.order_requests
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.workspace_memberships wm
      WHERE wm.workspace_id = order_requests.workspace_id
        AND wm.profile_id = auth.uid()
        AND wm.role IN ('advisor', 'admin', 'operations')
        AND wm.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workspace_memberships wm
      WHERE wm.workspace_id = order_requests.workspace_id
        AND wm.profile_id = auth.uid()
        AND wm.role IN ('advisor', 'admin', 'operations')
        AND wm.status = 'active'
    )
  );

CREATE POLICY order_requests_admin_update ON public.order_requests
  FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
  )
  WITH CHECK (
    (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
  );

-- 14. Family Delegations RLS Policies
CREATE POLICY family_delegations_owner_all ON public.family_delegations
  FOR ALL
  TO authenticated
  USING (owner_investor_id = auth.uid())
  WITH CHECK (owner_investor_id = auth.uid());

CREATE POLICY family_delegations_delegate_select ON public.family_delegations
  FOR SELECT
  TO authenticated
  USING (delegate_investor_id = auth.uid());

-- 15. Portfolios Family Read RLS Policies realignment
DROP POLICY IF EXISTS family_delegate_read_policy ON public.portfolios;
CREATE POLICY family_delegate_read_policy ON public.portfolios
  FOR SELECT
  TO authenticated
  USING (
    client_id IN (
      SELECT owner_investor_id FROM public.family_delegations
      WHERE delegate_investor_id = auth.uid() AND is_active = TRUE
    )
  );

-- 16. Subscription Plans RLS (Read-only for all authenticated users)
CREATE POLICY subscription_plans_read ON public.subscription_plans
  FOR SELECT
  TO authenticated
  USING (true);

-- 17. Workspace Billing RLS
CREATE POLICY workspace_billing_select ON public.workspace_billing
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.workspace_memberships wm
      WHERE wm.workspace_id = workspace_billing.workspace_id
        AND wm.profile_id = auth.uid()
        AND wm.status = 'active'
    )
    OR (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
  );

CREATE POLICY workspace_billing_admin_all ON public.workspace_billing
  FOR ALL
  TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin');

-- 18. Payment Events RLS
CREATE POLICY payment_events_select ON public.payment_events
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.workspace_memberships wm
      WHERE wm.workspace_id = payment_events.workspace_id
        AND wm.profile_id = auth.uid()
        AND wm.status = 'active'
    )
    OR (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
  );

-- 19. Referrals, Conversions, and Rewards RLS
CREATE POLICY referrals_select ON public.investor_referrals
  FOR SELECT
  TO authenticated
  USING (referrer_profile_id = auth.uid());

CREATE POLICY referrals_insert ON public.investor_referrals
  FOR INSERT
  TO authenticated
  WITH CHECK (referrer_profile_id = auth.uid());

CREATE POLICY conversions_select ON public.referral_conversions
  FOR SELECT
  TO authenticated
  USING (
    referee_profile_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.investor_referrals ir
      WHERE ir.id = referral_conversions.referral_id
        AND ir.referrer_profile_id = auth.uid()
    )
  );

CREATE POLICY rewards_select ON public.referral_rewards
  FOR SELECT
  TO authenticated
  USING (profile_id = auth.uid());

-- 20. Event Outbox RLS (Platform admin or system role only)
CREATE POLICY event_outbox_all ON public.event_outbox
  FOR ALL
  TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin');

-- 21. Trigger functions to maintain billing counters and status
CREATE OR REPLACE FUNCTION public.sync_billing_workspace_limit()
RETURNS trigger AS $$
BEGIN
  UPDATE public.workspace_billing
  SET current_client_count = (
    SELECT count(*) FROM public.workspace_memberships
    WHERE workspace_id = NEW.workspace_id
      AND role = 'client'
      AND status = 'active'
  )
  WHERE workspace_id = NEW.workspace_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER sync_billing_limit_on_membership_change
  AFTER INSERT OR UPDATE OR DELETE ON public.workspace_memberships
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_billing_workspace_limit();

COMMIT;
