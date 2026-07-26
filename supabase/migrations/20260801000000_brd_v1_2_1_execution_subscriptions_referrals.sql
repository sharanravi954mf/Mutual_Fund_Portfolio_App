-- Migration: Order Execution Engine, Subscriptions & Schema Extensions
-- Suffix: 20260801000000_brd_v1_2_1_execution_subscriptions_referrals.sql

BEGIN;

-- 1. Create Custom Enum Types for Orders
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_type') THEN
    CREATE TYPE public.order_type AS ENUM ('buy', 'sell', 'switch');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
    CREATE TYPE public.order_status AS ENUM ('pending_qualification', 'auto_approved', 'approved', 'rejected', 'submitted_to_exchange');
  END IF;
END
$$;

-- 2. Alter Profiles to add Global Identity Resolution fields (P1-3)
ALTER TABLE public.profiles 
  ADD COLUMN IF NOT EXISTS pan_hmac text,
  ADD COLUMN IF NOT EXISTS normalised_phone_hmac text,
  ADD COLUMN IF NOT EXISTS normalised_email_hmac text,
  ADD COLUMN IF NOT EXISTS identity_match_status text check (identity_match_status in ('unresolved', 'matched', 'manual_verification_required')) default 'unresolved';

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

-- 6. Create Auto-Approval Rules Table (P1-2)
CREATE TABLE public.auto_approval_rules (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  transaction_type public.order_type not null,
  min_amount numeric(15, 2) check (min_amount >= 0),
  max_amount numeric(15, 2) check (max_amount > min_amount),
  trusted_client_only boolean not null default false,
  category_restrictions text[],
  effective_from timestamptz not null default now(),
  is_active boolean not null default true,
  rule_version integer not null default 1 check (rule_version >= 1),
  created_at timestamptz not null default now()
);

-- 7. Create Order Requests Table
CREATE TABLE public.order_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  investor_profile_id uuid not null references public.profiles(id) on delete cascade,
  scheme_code text not null,
  type public.order_type not null,
  amount numeric(15, 2) check (amount > 0),
  units numeric(12, 4) check (units > 0),
  status public.order_status not null default 'pending_qualification',
  auto_approved boolean not null default false,
  triggered_rule_id uuid references public.auto_approval_rules(id) on delete set null,
  triggered_rule_version integer check (triggered_rule_version >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint order_requests_amount_or_units check (amount is not null or units is not null)
);

-- 8. Create Investor Referrals Table
CREATE TABLE public.investor_referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_profile_id uuid not null references public.profiles(id) on delete cascade,
  referee_email text not null,
  referral_code text not null,
  token_hash text not null unique,
  created_at timestamptz not null default now()
);

-- 9. Create Referral Conversions Table
CREATE TABLE public.referral_conversions (
  id uuid primary key default gen_random_uuid(),
  referral_id uuid not null references public.investor_referrals(id) on delete cascade,
  referee_profile_id uuid not null references public.profiles(id) on delete cascade unique,
  converted_at timestamptz not null default now()
);

-- 10. Create Referral Rewards Table
CREATE TABLE public.referral_rewards (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  reward_type text not null check (reward_type in ('subscription_extension')) default 'subscription_extension',
  duration_days integer not null default 30 check (duration_days > 0),
  status text not null check (status in ('active', 'expired')) default 'active',
  created_at timestamptz not null default now()
);

-- 11. Create Relationship-Scoped Family Delegations Table (P0-2)
CREATE TABLE public.family_delegations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  owner_profile_id uuid not null references public.profiles(id) on delete cascade,
  delegate_profile_id uuid not null references public.profiles(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint family_delegations_no_self check (owner_profile_id <> delegate_profile_id),
  constraint family_delegations_unique unique (workspace_id, owner_profile_id, delegate_profile_id)
);

-- 12. Create Subscription Feature Schemas & Custom Brandings (P1-4)
CREATE TABLE public.workspace_branding (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade unique,
  logo_url text,
  primary_color text,
  secondary_color text,
  created_at timestamptz not null default now()
);

CREATE TABLE public.advisor_profiles (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade unique,
  arn_number text not null,
  euin text,
  created_at timestamptz not null default now()
);

CREATE TABLE public.advisor_euin_assignments (
  id uuid primary key default gen_random_uuid(),
  advisor_profile_id uuid not null references public.advisor_profiles(id) on delete cascade,
  euin text not null,
  status text check (status in ('active', 'inactive')) default 'active',
  created_at timestamptz not null default now()
);

CREATE TABLE public.crm_notes (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  client_profile_id uuid not null references public.profiles(id) on delete cascade,
  advisor_profile_id uuid not null references public.profiles(id) on delete cascade,
  note_text text not null,
  created_at timestamptz not null default now()
);

-- 13. Create Event Outbox Table
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

-- 14. Transactional Trigger to write event to outbox when order is created
CREATE OR REPLACE FUNCTION public.trigger_order_outbox_event()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.event_outbox (event_type, payload, status)
  VALUES (
    'order.created',
    jsonb_build_object(
      'order_id', NEW.id,
      'workspace_id', NEW.workspace_id,
      'investor_profile_id', NEW.investor_profile_id,
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

-- Helper function: check if user has active workspace membership
CREATE OR REPLACE FUNCTION public.has_active_workspace_membership(p_workspace_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.workspace_memberships
    WHERE workspace_id = p_workspace_id
      AND profile_id = auth.uid()
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function: check if user is advisor in workspace
CREATE OR REPLACE FUNCTION public.has_advisor_membership(p_workspace_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.workspace_memberships
    WHERE workspace_id = p_workspace_id
      AND profile_id = auth.uid()
      AND role IN ('advisor', 'admin', 'operations')
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 15. Enable Row-Level Security on all newly created tables
ALTER TABLE public.order_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_billing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auto_approval_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investor_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_conversions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_delegations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_branding ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advisor_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advisor_euin_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_outbox ENABLE ROW LEVEL SECURITY;

-- 16. Order Requests RLS Policies with explicit WITH CHECK clauses (P0-1)
-- Select Policies
CREATE POLICY order_requests_investor_select ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (
    investor_profile_id = auth.uid() 
    AND public.has_active_workspace_membership(workspace_id)
  );

CREATE POLICY order_requests_advisor_select ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (
    public.has_advisor_membership(workspace_id)
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
    investor_profile_id = auth.uid()
    AND public.has_active_workspace_membership(workspace_id)
    -- Enforce status restriction
    AND status = 'pending_qualification'
    -- Family guest delegates are read-only and blocked from inserting orders on behalf of other users
    AND NOT EXISTS (
      SELECT 1 FROM public.family_delegations fd
      WHERE fd.delegate_profile_id = auth.uid()
        AND fd.owner_profile_id = investor_profile_id
        AND fd.workspace_id = workspace_id
        AND fd.is_active = TRUE
    )
  );

-- Update Policies
CREATE POLICY order_requests_advisor_update ON public.order_requests
  FOR UPDATE
  TO authenticated
  USING (
    public.has_advisor_membership(workspace_id)
  )
  WITH CHECK (
    public.has_advisor_membership(workspace_id)
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

-- 17. Family Delegations RLS Policies (P0-2)
CREATE POLICY family_delegations_owner_all ON public.family_delegations
  FOR ALL
  TO authenticated
  USING (owner_profile_id = auth.uid())
  WITH CHECK (owner_profile_id = auth.uid());

CREATE POLICY family_delegations_delegate_select ON public.family_delegations
  FOR SELECT
  TO authenticated
  USING (delegate_profile_id = auth.uid());

-- 18. Realignment of family delegate select policy on portfolios (P0-2)
DROP POLICY IF EXISTS family_delegate_read_policy ON public.portfolios;
CREATE POLICY family_delegate_read_policy ON public.portfolios
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.family_delegations fd
      JOIN public.workspace_memberships wm_owner ON wm_owner.workspace_id = fd.workspace_id AND wm_owner.profile_id = portfolios.client_id AND wm_owner.status = 'active'
      JOIN public.workspace_memberships wm_delegate ON wm_delegate.workspace_id = fd.workspace_id AND wm_delegate.profile_id = auth.uid() AND wm_delegate.status = 'active'
      WHERE fd.delegate_profile_id = auth.uid()
        AND fd.owner_profile_id = portfolios.client_id
        AND fd.is_active = TRUE
    )
  );

-- 19. Auto Approval Rules RLS Policies
CREATE POLICY auto_approval_rules_select ON public.auto_approval_rules
  FOR SELECT
  TO authenticated
  USING (
    public.has_active_workspace_membership(workspace_id)
  );

CREATE POLICY auto_approval_rules_admin_all ON public.auto_approval_rules
  FOR ALL
  TO authenticated
  USING (
    public.has_advisor_membership(workspace_id)
    OR (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
  )
  WITH CHECK (
    public.has_advisor_membership(workspace_id)
    OR (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
  );

-- 20. Document Vault Security & Lineage - Deny Family Delegates Select (P0-3)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'ingested_documents') THEN
    EXECUTE 'ALTER TABLE public.ingested_documents ENABLE ROW LEVEL SECURITY;';
    EXECUTE 'DROP POLICY IF EXISTS family_delegate_document_denial ON public.ingested_documents;';
    EXECUTE 'CREATE POLICY family_delegate_document_denial ON public.ingested_documents FOR SELECT TO authenticated USING (NOT EXISTS (SELECT 1 FROM public.family_delegations fd WHERE fd.delegate_profile_id = auth.uid() AND fd.is_active = true));';
  END IF;
END
$$;

-- 21. Subscription Plans RLS (Read-only for all authenticated users)
CREATE POLICY subscription_plans_read ON public.subscription_plans
  FOR SELECT
  TO authenticated
  USING (true);

-- 22. Workspace Billing RLS
CREATE POLICY workspace_billing_select ON public.workspace_billing
  FOR SELECT
  TO authenticated
  USING (
    public.has_active_workspace_membership(workspace_id)
    OR (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
  );

CREATE POLICY workspace_billing_admin_all ON public.workspace_billing
  FOR ALL
  TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin');

-- 23. Payment Events RLS
CREATE POLICY payment_events_select ON public.payment_events
  FOR SELECT
  TO authenticated
  USING (
    public.has_active_workspace_membership(workspace_id)
    OR (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
  );

-- 24. Referrals, Conversions, and Rewards RLS
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

-- 25. Custom Brandings, Advisor Profiles, and CRM Notes RLS
CREATE POLICY workspace_branding_select ON public.workspace_branding
  FOR SELECT
  TO authenticated
  USING (public.has_active_workspace_membership(workspace_id));

CREATE POLICY workspace_branding_advisor_all ON public.workspace_branding
  FOR ALL
  TO authenticated
  USING (public.has_advisor_membership(workspace_id))
  WITH CHECK (public.has_advisor_membership(workspace_id));

CREATE POLICY advisor_profiles_read ON public.advisor_profiles
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY advisor_profiles_advisor_all ON public.advisor_profiles
  FOR ALL
  TO authenticated
  USING (profile_id = auth.uid() OR (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin')
  WITH CHECK (profile_id = auth.uid() OR (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin');

CREATE POLICY advisor_euin_select ON public.advisor_euin_assignments
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY crm_notes_select ON public.crm_notes
  FOR SELECT
  TO authenticated
  USING (
    public.has_advisor_membership(workspace_id)
    OR client_profile_id = auth.uid()
  );

CREATE POLICY crm_notes_insert ON public.crm_notes
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.has_advisor_membership(workspace_id)
    AND advisor_profile_id = auth.uid()
  );

-- 26. Event Outbox RLS (Platform admin or system role only)
CREATE POLICY event_outbox_all ON public.event_outbox
  FOR ALL
  TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin');

-- 27. Trigger functions to maintain billing counters and status
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

-- Check and create trigger
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'sync_billing_limit_on_membership_change') THEN
    CREATE TRIGGER sync_billing_limit_on_membership_change
      AFTER INSERT OR UPDATE OR DELETE ON public.workspace_memberships
      FOR EACH ROW
      EXECUTE FUNCTION public.sync_billing_workspace_limit();
  END IF;
END
$$;

COMMIT;
