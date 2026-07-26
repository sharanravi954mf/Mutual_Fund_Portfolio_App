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
    CREATE TYPE public.order_status AS ENUM ('draft', 'pending_qualification', 'pending_review', 'auto_approved', 'approved', 'rejected', 'cancelled');
  END IF;
END
$$;

-- 2. Alter Profiles to add Global Identity Resolution fields (P1-3)
ALTER TABLE public.profiles 
  ADD COLUMN IF NOT EXISTS pan_hmac text,
  ADD COLUMN IF NOT EXISTS normalised_phone_hmac text,
  ADD COLUMN IF NOT EXISTS normalised_email_hmac text,
  ADD COLUMN IF NOT EXISTS aadhaar_hmac text,
  ADD COLUMN IF NOT EXISTS identity_match_status text check (identity_match_status in ('unresolved', 'matched', 'manual_verification_required')) default 'unresolved';

-- 3. Alter Portfolios to add workspace_id column (P0-2)
ALTER TABLE public.portfolios 
  ADD COLUMN IF NOT EXISTS workspace_id uuid references public.workspaces(id) on delete cascade;

-- Populate portfolios workspace_id based on active client memberships where missing
UPDATE public.portfolios p
SET workspace_id = (
  SELECT workspace_id FROM public.workspace_memberships wm
  WHERE wm.profile_id = p.client_id
    AND wm.status = 'active'
  LIMIT 1
)
WHERE p.workspace_id IS NULL;

-- 4. Create Subscription Plans Table
CREATE TABLE public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  client_limit integer not null check (client_limit >= 0),
  monthly_price numeric(15, 2) not null check (monthly_price >= 0),
  created_at timestamptz not null default now()
);

-- Seed Subscription Plans
INSERT INTO public.subscription_plans (id, name, client_limit, monthly_price)
VALUES 
  ('11111111-1111-1111-1111-111111111111', 'Starter', 25, 0.00),
  ('22222222-2222-2222-2222-222222222222', 'Pro MFD', 999999, 1500.00),
  ('33333333-3333-3333-3333-333333333333', 'Enterprise Firm', 99999999, 5000.00)
ON CONFLICT (name) DO UPDATE 
SET client_limit = EXCLUDED.client_limit,
    monthly_price = EXCLUDED.monthly_price;

-- Create Plan Entitlements Table (P1-4)
CREATE TABLE public.plan_entitlements (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.subscription_plans(id) on delete cascade,
  entitlement_key text not null,
  entitlement_value text not null,
  created_at timestamptz not null default now(),
  constraint plan_entitlements_unique unique (plan_id, entitlement_key)
);

-- Seed Plan Entitlements (extended keys: advanced_analytics_enabled, support_sla_policy_id)
INSERT INTO public.plan_entitlements (plan_id, entitlement_key, entitlement_value)
VALUES
  -- Starter
  ('11111111-1111-1111-1111-111111111111', 'max_active_investors', '25'),
  ('11111111-1111-1111-1111-111111111111', 'mailbag_ingestion_enabled', 'true'),
  ('11111111-1111-1111-1111-111111111111', 'auto_approval_enabled', 'false'),
  ('11111111-1111-1111-1111-111111111111', 'white_label_enabled', 'false'),
  ('11111111-1111-1111-1111-111111111111', 'crm_enabled', 'false'),
  ('11111111-1111-1111-1111-111111111111', 'multi_advisor_enabled', 'false'),
  ('11111111-1111-1111-1111-111111111111', 'family_hub_enabled', 'false'),
  ('11111111-1111-1111-1111-111111111111', 'capital_gain_projection_enabled', 'false'),
  ('11111111-1111-1111-1111-111111111111', 'priority_support_enabled', 'false'),
  ('11111111-1111-1111-1111-111111111111', 'advanced_analytics_enabled', 'false'),
  ('11111111-1111-1111-1111-111111111111', 'support_sla_policy_id', 'starter-sla'),
  -- Pro MFD
  ('22222222-2222-2222-2222-222222222222', 'max_active_investors', '999999'),
  ('22222222-2222-2222-2222-222222222222', 'mailbag_ingestion_enabled', 'true'),
  ('22222222-2222-2222-2222-222222222222', 'auto_approval_enabled', 'true'),
  ('22222222-2222-2222-2222-222222222222', 'white_label_enabled', 'false'),
  ('22222222-2222-2222-2222-222222222222', 'crm_enabled', 'true'),
  ('22222222-2222-2222-2222-222222222222', 'multi_advisor_enabled', 'false'),
  ('22222222-2222-2222-2222-222222222222', 'family_hub_enabled', 'true'),
  ('22222222-2222-2222-2222-222222222222', 'capital_gain_projection_enabled', 'true'),
  ('22222222-2222-2222-2222-222222222222', 'priority_support_enabled', 'false'),
  ('22222222-2222-2222-2222-222222222222', 'advanced_analytics_enabled', 'true'),
  ('22222222-2222-2222-2222-222222222222', 'support_sla_policy_id', 'pro-sla'),
  -- Enterprise Firm
  ('33333333-3333-3333-3333-333333333333', 'max_active_investors', '99999999'),
  ('33333333-3333-3333-3333-333333333333', 'mailbag_ingestion_enabled', 'true'),
  ('33333333-3333-3333-3333-333333333333', 'auto_approval_enabled', 'true'),
  ('33333333-3333-3333-3333-333333333333', 'white_label_enabled', 'true'),
  ('33333333-3333-3333-3333-333333333333', 'crm_enabled', 'true'),
  ('33333333-3333-3333-3333-333333333333', 'multi_advisor_enabled', 'true'),
  ('33333333-3333-3333-3333-333333333333', 'family_hub_enabled', 'true'),
  ('33333333-3333-3333-3333-333333333333', 'capital_gain_projection_enabled', 'true'),
  ('33333333-3333-3333-3333-333333333333', 'priority_support_enabled', 'true'),
  ('33333333-3333-3333-3333-333333333333', 'advanced_analytics_enabled', 'true'),
  ('33333333-3333-3333-3333-333333333333', 'support_sla_policy_id', 'enterprise-sla')
ON CONFLICT (plan_id, entitlement_key) DO UPDATE 
SET entitlement_value = EXCLUDED.entitlement_value;

-- 5. Create Workspace Billing Table
CREATE TABLE public.workspace_billing (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade unique,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null check (status in ('trialing', 'active', 'past_due', 'suspended', 'cancelled')) default 'trialing',
  current_client_count integer not null default 0 check (current_client_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 6. Create Payment Events Table (Idempotent Webhook Target)
CREATE TABLE public.payment_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  amount numeric(15, 2) not null check (amount >= 0),
  payment_id text not null unique, -- Idempotency key
  status text not null,
  created_at timestamptz not null default now()
);

-- 7. Create Auto-Approval Rules Table (P1-2)
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

-- 8. Create Order Requests Table
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
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint order_requests_amount_or_units check (amount is not null or units is not null)
);

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

-- Helper function: check if user is investor in workspace
CREATE OR REPLACE FUNCTION public.has_investor_membership(p_workspace_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.workspace_memberships
    WHERE workspace_id = p_workspace_id
      AND profile_id = auth.uid()
      AND role = 'investor'
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Hardened qualify_order RPC with step-by-step validations & row locking (P0-1, P0-2)
CREATE OR REPLACE FUNCTION public.qualify_order(
  p_order_id uuid,
  p_decision public.order_status,
  p_rejection_reason text DEFAULT null
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id uuid;
  v_current_status public.order_status;
  v_order public.order_requests;
BEGIN
  -- 1. Pessimistic row locking for concurrency protection
  SELECT workspace_id, status INTO v_workspace_id, v_current_status 
  FROM public.order_requests 
  WHERE id = p_order_id 
  FOR UPDATE;
  
  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- 2. Idempotent check: return immediately if order is already qualified or cancelled
  IF v_current_status IN ('approved', 'rejected', 'cancelled', 'auto_approved') THEN
    SELECT * INTO v_order FROM public.order_requests WHERE id = p_order_id;
    RETURN v_order;
  END IF;

  -- 3. Verify advisor membership or platform admin override
  IF NOT (public.has_advisor_membership(v_workspace_id) OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin') THEN
    RAISE EXCEPTION 'Unauthorized: Only advisors or platform admins can qualify orders.';
  END IF;

  -- 4. State validation check (Race-Condition Guard P0-1):
  -- Direct advisor intervention during pending_qualification is blocked to prevent race conditions.
  -- Advisors qualify orders only when status = 'pending_review'.
  -- Platform admins/system roles can transition from pending_qualification to auto_approved or pending_review.
  IF v_current_status = 'pending_qualification' THEN
    IF COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') <> 'platform_admin' THEN
      RAISE EXCEPTION 'Race Guard Exception: Advisors cannot qualify orders in pending_qualification state directly.';
    END IF;
    IF p_decision NOT IN ('auto_approved', 'pending_review') THEN
      RAISE EXCEPTION 'Invalid Transition: pending_qualification orders must transition to auto_approved or pending_review.';
    END IF;
  ELSIF v_current_status = 'pending_review' THEN
    IF p_decision NOT IN ('approved', 'rejected') THEN
      RAISE EXCEPTION 'Invalid Transition: pending_review orders must transition to approved or rejected.';
    END IF;
  ELSE
    RAISE EXCEPTION 'Invalid State: Order is not in a valid pending state.';
  END IF;

  -- 5. Mutate ONLY status, reviewed_by, reviewed_at, and rejection_reason
  UPDATE public.order_requests
  SET status = p_decision,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      rejection_reason = p_rejection_reason,
      updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- 6. Write immutable event to workspace_audit_logs
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    v_workspace_id,
    auth.uid(),
    'order.qualified',
    'order_requests',
    p_order_id,
    jsonb_build_object(
      'decision', p_decision,
      'rejection_reason', p_rejection_reason
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Revoke default public execution & grant to authenticated (P0-3)
REVOKE ALL ON FUNCTION public.qualify_order FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.qualify_order TO authenticated;

-- Order Cancellation Path RPC (P0-3)
CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id uuid,
  p_reason text DEFAULT null
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id uuid;
  v_investor_profile_id uuid;
  v_current_status public.order_status;
  v_order public.order_requests;
BEGIN
  -- 1. Pessimistic row locking for concurrency protection (Acquire Lock)
  SELECT workspace_id, investor_profile_id, status 
  INTO v_workspace_id, v_investor_profile_id, v_current_status 
  FROM public.order_requests 
  WHERE id = p_order_id 
  FOR UPDATE;
  
  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- 2. Idempotent check
  IF v_current_status = 'cancelled' THEN
    SELECT * INTO v_order FROM public.order_requests WHERE id = p_order_id;
    RETURN v_order;
  END IF;

  -- 3. Verify actor: Caller must be order owner or advisor in matching workspace (Verify Actor)
  IF NOT (
    (v_investor_profile_id = auth.uid() AND public.has_investor_membership(v_workspace_id))
    OR public.has_advisor_membership(v_workspace_id)
    OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized: You do not have permission to cancel this order.';
  END IF;

  -- 4. Validate state: Permits cancellation on pending_qualification and pending_review.
  -- Rejects cancellation on auto_approved, approved, rejected, or cancelled orders.
  IF v_current_status NOT IN ('draft', 'pending_qualification', 'pending_review') THEN
    RAISE EXCEPTION 'Invalid State: Cannot cancel an order that has already been qualified or processed.';
  END IF;

  -- 5. Mutate status and rejection reason
  UPDATE public.order_requests
  SET status = 'cancelled',
      rejection_reason = COALESCE(p_reason, 'Cancelled by user'),
      updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- 6. Write immutable event to workspace_audit_logs (Record immutable audit entry)
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    v_workspace_id,
    auth.uid(),
    'order.cancelled',
    'order_requests',
    p_order_id,
    jsonb_build_object(
      'reason', p_reason
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Revoke default public execution & grant to authenticated (P0-3)
REVOKE ALL ON FUNCTION public.cancel_order FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_order TO authenticated;

-- 9. Create Investor Referrals Table
CREATE TABLE public.investor_referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_profile_id uuid not null references public.profiles(id) on delete cascade,
  referee_email text not null,
  referral_code text not null,
  token_hash text not null unique,
  created_at timestamptz not null default now()
);

-- 10. Create Referral Conversions Table
CREATE TABLE public.referral_conversions (
  id uuid primary key default gen_random_uuid(),
  referral_id uuid not null references public.investor_referrals(id) on delete cascade,
  referee_profile_id uuid not null references public.profiles(id) on delete cascade unique,
  converted_at timestamptz not null default now()
);

-- 11. Create Referral Rewards Table
CREATE TABLE public.referral_rewards (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  reward_type text not null check (reward_type in ('subscription_extension')) default 'subscription_extension',
  duration_days integer not null default 30 check (duration_days > 0),
  status text not null check (status in ('active', 'expired')) default 'active',
  created_at timestamptz not null default now()
);

-- 12. Create Workspace-Scoped Family Delegations Table (P0-2)
CREATE TABLE public.family_delegations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  owner_profile_id uuid not null references public.profiles(id) on delete cascade,
  delegate_profile_id uuid not null references public.profiles(id) on delete cascade,
  consent_status text not null check (consent_status in ('pending', 'accepted', 'rejected')) default 'pending',
  is_active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint family_delegations_no_self check (owner_profile_id <> delegate_profile_id),
  constraint family_delegations_unique unique (workspace_id, owner_profile_id, delegate_profile_id)
);

-- Triggers for logging family delegation audits (P0-3)
CREATE OR REPLACE FUNCTION public.log_family_delegation_audit()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
    VALUES (
      NEW.workspace_id,
      auth.uid(),
      'family_delegation.created',
      'family_delegations',
      NEW.id,
      jsonb_build_object(
        'owner_profile_id', NEW.owner_profile_id,
        'delegate_profile_id', NEW.delegate_profile_id,
        'consent_status', NEW.consent_status,
        'expires_at', NEW.expires_at
      )
    );
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.consent_status IS DISTINCT FROM NEW.consent_status THEN
      INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
      VALUES (
        NEW.workspace_id,
        auth.uid(),
        'family_delegation.consent_updated',
        'family_delegations',
        NEW.id,
        jsonb_build_object(
          'owner_profile_id', NEW.owner_profile_id,
          'delegate_profile_id', NEW.delegate_profile_id,
          'consent_status', NEW.consent_status
        )
      );
    END IF;
    IF OLD.is_active = TRUE AND NEW.is_active = FALSE THEN
      INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
      VALUES (
        NEW.workspace_id,
        auth.uid(),
        'family_delegation.revoked',
        'family_delegations',
        NEW.id,
        jsonb_build_object(
          'owner_profile_id', NEW.owner_profile_id,
          'delegate_profile_id', NEW.delegate_profile_id
        )
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER log_family_delegation_audit_trg
  AFTER INSERT OR UPDATE ON public.family_delegations
  FOR EACH ROW
  EXECUTE FUNCTION public.log_family_delegation_audit();

-- 13. Create Subscription Feature Schemas & Custom Brandings (P1-4)
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

-- 14. Create Event Outbox Table
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

-- 15. Transactional Trigger to write event to outbox when order is created
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

-- 16. Enable Row-Level Security on all newly created tables
ALTER TABLE public.order_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_entitlements ENABLE ROW LEVEL SECURITY;
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

-- 17. Order Requests RLS Policies with explicit WITH CHECK clauses (P0-1)
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
    COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin'
  );

-- Insert Policies
CREATE POLICY order_requests_investor_insert ON public.order_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    investor_profile_id = auth.uid()
    AND public.has_investor_membership(workspace_id)
    -- Enforce status restriction
    AND status = 'pending_qualification'
    -- Family guest delegates are read-only and blocked from inserting orders on behalf of other users
    AND NOT EXISTS (
      SELECT 1 FROM public.family_delegations fd
      WHERE fd.delegate_profile_id = auth.uid()
        AND fd.owner_profile_id = investor_profile_id
        AND fd.workspace_id = workspace_id
        AND fd.consent_status = 'accepted'
        AND fd.is_active = TRUE
    )
  );

-- Revoke Direct Update and Delete permissions on order_requests from authenticated users (P0-1)
REVOKE UPDATE, DELETE ON public.order_requests FROM authenticated;

-- Admin update override (since platform admins bypass RLS and direct constraints)
CREATE POLICY order_requests_admin_update ON public.order_requests
  FOR UPDATE
  TO authenticated
  USING (
    COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin'
  )
  WITH CHECK (
    COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin'
  );

-- 18. Family Delegations RLS Policies (P0-2)
CREATE POLICY family_delegations_owner_all ON public.family_delegations
  FOR ALL
  TO authenticated
  USING (owner_profile_id = auth.uid())
  WITH CHECK (owner_profile_id = auth.uid());

CREATE POLICY family_delegations_delegate_select ON public.family_delegations
  FOR SELECT
  TO authenticated
  USING (delegate_profile_id = auth.uid());

-- 19. Workspace-Matched portfolios family read RLS policy with explicit consent status check (P0-3)
DROP POLICY IF EXISTS family_delegate_read_policy ON public.portfolios;
CREATE POLICY family_delegate_read_policy ON public.portfolios
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.family_delegations fd
      WHERE fd.owner_profile_id = portfolios.client_id
        AND fd.delegate_profile_id = auth.uid()
        AND fd.workspace_id = portfolios.workspace_id
        AND fd.consent_status = 'accepted'
        AND fd.is_active = TRUE
        AND (fd.expires_at IS NULL OR fd.expires_at > now())
    )
  );

-- 20. Auto Approval Rules RLS Policies
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
    OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin'
  )
  WITH CHECK (
    public.has_advisor_membership(workspace_id)
    OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin'
  );

-- 21. Plan Entitlements RLS
CREATE POLICY plan_entitlements_select ON public.plan_entitlements
  FOR SELECT
  TO authenticated
  USING (true);

-- 22. Document Vault Security & Lineage - Deny Family Delegates Select (P0-3)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'ingested_documents') THEN
    EXECUTE 'ALTER TABLE public.ingested_documents ENABLE ROW LEVEL SECURITY;';
    EXECUTE 'DROP POLICY IF EXISTS family_delegate_document_denial ON public.ingested_documents;';
    EXECUTE 'CREATE POLICY family_delegate_document_denial ON public.ingested_documents FOR SELECT TO authenticated USING (NOT EXISTS (SELECT 1 FROM public.family_delegations fd WHERE fd.delegate_profile_id = auth.uid() AND fd.consent_status = ''accepted'' AND fd.is_active = true));';
  END IF;
END
$$;

-- 23. Subscription Plans RLS (Read-only for all authenticated users)
CREATE POLICY subscription_plans_read ON public.subscription_plans
  FOR SELECT
  TO authenticated
  USING (true);

-- 24. Workspace Billing RLS
CREATE POLICY workspace_billing_select ON public.workspace_billing
  FOR SELECT
  TO authenticated
  USING (
    public.has_active_workspace_membership(workspace_id)
    OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin'
  );

CREATE POLICY workspace_billing_admin_all ON public.workspace_billing
  FOR ALL
  TO authenticated
  USING (COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin')
  WITH CHECK (COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin');

-- 25. Payment Events RLS
CREATE POLICY payment_events_select ON public.payment_events
  FOR SELECT
  TO authenticated
  USING (
    public.has_active_workspace_membership(workspace_id)
    OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin'
  );

-- 26. Referrals, Conversions, and Rewards RLS
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

-- 27. Custom Brandings, Advisor Profiles, and CRM Notes RLS
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
  USING (profile_id = auth.uid() OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin')
  WITH CHECK (profile_id = auth.uid() OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin');

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

-- 28. Event Outbox RLS (Platform admin or system role only)
CREATE POLICY event_outbox_all ON public.event_outbox
  FOR ALL
  TO authenticated
  USING (COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin')
  WITH CHECK (COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin');

-- 29. Trigger functions to maintain billing counters and status
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
