-- Migration: Sprint 6.1 Canonical Hardening
-- Created: 2026-08-01 00:00:01
-- Author: Antigravity AI
-- Description: Resolves all Sprint 6.1 gaps, identity helper standardisation, RLS/RPC fixes, outbox extensions, dual billing, and referrals.

BEGIN;

-- 1. Re-define Membership helpers with public.current_user_profile_id() and strict SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.has_active_workspace_membership(p_workspace_id uuid)
RETURNS boolean AS $$
DECLARE
  v_profile_id uuid;
BEGIN
  v_profile_id := public.current_user_profile_id();
  IF v_profile_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.workspace_memberships
    WHERE workspace_id = p_workspace_id
      AND profile_id = v_profile_id
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.has_advisor_membership(p_workspace_id uuid)
RETURNS boolean AS $$
DECLARE
  v_profile_id uuid;
BEGIN
  v_profile_id := public.current_user_profile_id();
  IF v_profile_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.workspace_memberships
    WHERE workspace_id = p_workspace_id
      AND profile_id = v_profile_id
      AND role IN ('advisor', 'admin', 'operations')
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.has_investor_membership(p_workspace_id uuid)
RETURNS boolean AS $$
DECLARE
  v_profile_id uuid;
BEGIN
  v_profile_id := public.current_user_profile_id();
  IF v_profile_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.workspace_memberships
    WHERE workspace_id = p_workspace_id
      AND profile_id = v_profile_id
      AND role = 'investor'
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- 2. Correct sync_billing_workspace_limit Trigger Function for DELETE compatibility and role = 'investor'
CREATE OR REPLACE FUNCTION public.sync_billing_workspace_limit()
RETURNS trigger AS $$
DECLARE
  v_workspace_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_workspace_id := OLD.workspace_id;
  ELSE
    v_workspace_id := NEW.workspace_id;
  END IF;

  UPDATE public.workspace_billing
  SET current_client_count = (
    SELECT count(*) FROM public.workspace_memberships
    WHERE workspace_id = v_workspace_id
      AND role = 'investor'
      AND status = 'active'
  )
  WHERE workspace_id = v_workspace_id;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- 3. Alter order_requests table to add auto_approval_correlation_id
ALTER TABLE public.order_requests ADD COLUMN IF NOT EXISTS auto_approval_correlation_id uuid;

DROP INDEX IF EXISTS public.order_requests_auto_approval_correlation_uidx;
CREATE UNIQUE INDEX order_requests_auto_approval_correlation_uidx
ON public.order_requests(auto_approval_correlation_id)
WHERE auto_approval_correlation_id IS NOT NULL;


-- 4. Correct qualify_order RPC: advisor-only, platform admin denied, pending_review state only, approved/rejected decision only
CREATE OR REPLACE FUNCTION public.qualify_order(
  p_order_id uuid,
  p_decision public.order_status,
  p_rejection_reason text DEFAULT null
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id uuid;
  v_current_status public.order_status;
  v_current_profile_id uuid;
  v_order public.order_requests;
BEGIN
  -- 1. Pessimistic row locking
  SELECT workspace_id, status INTO v_workspace_id, v_current_status 
  FROM public.order_requests 
  WHERE id = p_order_id 
  FOR UPDATE;
  
  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- 2. Validate current state is exactly pending_review
  IF v_current_status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_qualification_state';
  END IF;

  -- 3. Validate decision is approved or rejected
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'invalid_qualification_decision';
  END IF;

  -- 4. Resolve caller profile and check advisor membership. Platform Admin/Investor/Delegate strictly denied.
  v_current_profile_id := public.current_user_profile_id();
  IF v_current_profile_id IS NULL OR NOT public.has_advisor_membership(v_workspace_id) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- 5. Mutate status
  UPDATE public.order_requests
  SET status = p_decision,
      reviewed_by = v_current_profile_id,
      reviewed_at = now(),
      rejection_reason = p_rejection_reason,
      updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- 6. Write immutable audit using database-loaded values
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    v_workspace_id,
    v_current_profile_id,
    'order.qualified',
    'order_requests',
    p_order_id,
    jsonb_build_object(
      'decision', p_decision,
      'rejection_reason', p_rejection_reason,
      'previous_status', v_current_status
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.qualify_order(uuid, public.order_status, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.qualify_order(uuid, public.order_status, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.qualify_order(uuid, public.order_status, text) TO authenticated;


-- 5. Correct cancel_order RPC: current_user_profile_id() resolution, pending_qualification/pending_review only, already_cancelled denial
CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id uuid,
  p_reason text DEFAULT null
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id uuid;
  v_investor_profile_id uuid;
  v_current_status public.order_status;
  v_current_profile_id uuid;
  v_order public.order_requests;
BEGIN
  -- 1. Pessimistic row locking
  SELECT workspace_id, investor_profile_id, status 
  INTO v_workspace_id, v_investor_profile_id, v_current_status 
  FROM public.order_requests 
  WHERE id = p_order_id 
  FOR UPDATE;
  
  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- 2. Rejects repeated cancellation immediately
  IF v_current_status = 'cancelled' THEN
    RAISE EXCEPTION 'already_cancelled';
  END IF;

  -- 3. Verify cancellation state bounds
  IF v_current_status NOT IN ('pending_qualification', 'pending_review') THEN
    RAISE EXCEPTION 'invalid_cancellation_state';
  END IF;

  -- 4. Resolve caller profile
  v_current_profile_id := public.current_user_profile_id();
  IF v_current_profile_id IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  -- 5. Authorize caller: owner or advisor in workspace. Platform Admin/Family Guests strictly denied.
  IF v_investor_profile_id = v_current_profile_id THEN
    -- Owner path
  ELSIF public.has_advisor_membership(v_workspace_id) THEN
    -- Advisor path
  ELSE
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- 6. Mutate status
  UPDATE public.order_requests
  SET status = 'cancelled',
      rejection_reason = COALESCE(p_reason, 'Cancelled by user'),
      updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- 7. Write immutable audit log using database-loaded values
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    v_workspace_id,
    v_current_profile_id,
    'order.cancelled',
    'order_requests',
    p_order_id,
    jsonb_build_object(
      'reason', p_reason,
      'previous_status', v_current_status
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.cancel_order(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_order(uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_order(uuid, text) TO authenticated;


-- 6. Align event_outbox table structure
ALTER TABLE public.event_outbox ADD COLUMN IF NOT EXISTS entity_id uuid;
ALTER TABLE public.event_outbox ADD COLUMN IF NOT EXISTS entity_type text;
ALTER TABLE public.event_outbox ADD COLUMN IF NOT EXISTS claimed_at timestamptz;
ALTER TABLE public.event_outbox ADD COLUMN IF NOT EXISTS claimed_by uuid;

-- 7. Update outbox trigger function to prevent duplicates and populate entity fields
CREATE OR REPLACE FUNCTION public.trigger_order_outbox_event()
RETURNS trigger AS $$
BEGIN
  -- Prevent duplicate order.created events
  IF EXISTS (
    SELECT 1 FROM public.event_outbox
    WHERE entity_id = NEW.id
      AND event_type = 'order.created'
  ) THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.event_outbox (event_type, entity_id, entity_type, payload, status)
  VALUES (
    'order.created',
    NEW.id,
    'order_request',
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- 8. Implement canonical apply_auto_approval_decision service RPC
CREATE OR REPLACE FUNCTION public.apply_auto_approval_decision(
  p_order_id uuid,
  p_decision public.order_status,
  p_rule_id uuid,
  p_rule_version integer,
  p_correlation_id uuid
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id uuid;
  v_current_status public.order_status;
  v_correlation_id uuid;
  v_order public.order_requests;
  v_outbox_status text;
  v_outbox_entity_id uuid;
  v_outbox_event_type text;
  v_rule_active boolean;
  v_rule_workspace uuid;
  v_rule_version integer;
BEGIN
  -- 1. Lock order
  SELECT workspace_id, status, auto_approval_correlation_id
  INTO v_workspace_id, v_current_status, v_correlation_id
  FROM public.order_requests
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  -- 2. Idempotent replay check (Replay check occurs before status check)
  IF v_correlation_id = p_correlation_id THEN
    -- Verify identical decision data matches
    SELECT * INTO v_order FROM public.order_requests WHERE id = p_order_id;
    IF v_order.status = p_decision AND 
       COALESCE(v_order.triggered_rule_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_rule_id, '00000000-0000-0000-0000-000000000000'::uuid) AND 
       COALESCE(v_order.triggered_rule_version, 0) = COALESCE(p_rule_version, 0) THEN
      RETURN v_order;
    ELSE
      RAISE EXCEPTION 'idempotency_conflict';
    END IF;
  END IF;

  -- 3. Stale-state status check
  IF v_current_status <> 'pending_qualification' THEN
    RAISE EXCEPTION 'stale_order_state';
  END IF;

  -- 4. Lock and validate outbox event
  SELECT status, entity_id, event_type
  INTO v_outbox_status, v_outbox_entity_id, v_outbox_event_type
  FROM public.event_outbox
  WHERE id = p_correlation_id
  FOR UPDATE;

  IF v_outbox_status IS NULL THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;

  IF v_outbox_event_type <> 'order.created' THEN
    RAISE EXCEPTION 'invalid_event_type';
  END IF;

  IF v_outbox_entity_id <> p_order_id THEN
    RAISE EXCEPTION 'event_order_mismatch';
  END IF;

  -- 5. Rule validation (conditional based on decision)
  IF p_decision = 'auto_approved' THEN
    IF p_rule_id IS NULL OR p_rule_version IS NULL THEN
      RAISE EXCEPTION 'missing_rule_details';
    END IF;

    SELECT is_active, workspace_id, rule_version
    INTO v_rule_active, v_rule_workspace, v_rule_version
    FROM public.auto_approval_rules
    WHERE id = p_rule_id;

    IF v_rule_active IS NULL THEN
      RAISE EXCEPTION 'rule_not_found';
    END IF;

    IF NOT v_rule_active THEN
      RAISE EXCEPTION 'inactive_rule';
    END IF;

    IF v_rule_workspace <> v_workspace_id THEN
      RAISE EXCEPTION 'rule_workspace_mismatch';
    END IF;

    IF v_rule_version <> p_rule_version THEN
      RAISE EXCEPTION 'rule_version_mismatch';
    END IF;

  ELSIF p_decision = 'pending_review' THEN
    IF p_rule_id IS NOT NULL OR p_rule_version IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_rule_for_review_status';
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_auto_approval_decision';
  END IF;

  -- 6. Apply transition and store rule context
  UPDATE public.order_requests
  SET status = p_decision,
      triggered_rule_id = p_rule_id,
      triggered_rule_version = p_rule_version,
      auto_approval_correlation_id = p_correlation_id,
      updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- 7. Write immutable audit log using database-loaded values
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    v_workspace_id,
    null, -- System service role actor
    'order.auto_qualified',
    'order_requests',
    p_order_id,
    jsonb_build_object(
      'decision', p_decision,
      'rule_id', p_rule_id,
      'rule_version', p_rule_version,
      'correlation_id', p_correlation_id,
      'previous_status', v_current_status
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(uuid, public.order_status, uuid, integer, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(uuid, public.order_status, uuid, integer, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_auto_approval_decision(uuid, public.order_status, uuid, integer, uuid) TO service_role;


-- 9. Correct RLS policies to use public.current_user_profile_id() instead of auth.uid()
-- Order Requests Policies
DROP POLICY IF EXISTS order_requests_investor_select ON public.order_requests;
CREATE POLICY order_requests_investor_select ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (
    investor_profile_id = public.current_user_profile_id()
    AND public.has_active_workspace_membership(workspace_id)
  );

DROP POLICY IF EXISTS order_requests_investor_insert ON public.order_requests;
CREATE POLICY order_requests_investor_insert ON public.order_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    investor_profile_id = public.current_user_profile_id()
    AND public.has_investor_membership(workspace_id)
    AND status = 'pending_qualification'
    AND NOT EXISTS (
      SELECT 1 FROM public.family_delegations fd
      WHERE fd.delegate_profile_id = public.current_user_profile_id()
        AND fd.owner_profile_id = investor_profile_id
        AND fd.workspace_id = workspace_id
        AND fd.consent_status = 'accepted'
        AND fd.is_active = TRUE
        AND (fd.expires_at IS NULL OR fd.expires_at > now())
    )
  );

DROP POLICY IF EXISTS order_requests_admin_update ON public.order_requests;

-- Family Delegations Policies
DROP POLICY IF EXISTS family_delegations_owner_all ON public.family_delegations;
CREATE POLICY family_delegations_owner_all ON public.family_delegations
  FOR ALL
  TO authenticated
  USING (owner_profile_id = public.current_user_profile_id())
  WITH CHECK (owner_profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS family_delegations_delegate_select ON public.family_delegations;
CREATE POLICY family_delegations_delegate_select ON public.family_delegations
  FOR SELECT
  TO authenticated
  USING (delegate_profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS family_delegate_read_policy ON public.portfolios;
CREATE POLICY family_delegate_read_policy ON public.portfolios
  FOR SELECT
  TO authenticated
  USING (
    public.current_user_profile_id() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.family_delegations fd
      WHERE fd.owner_profile_id = portfolios.client_id
        AND fd.delegate_profile_id = public.current_user_profile_id()
        AND fd.workspace_id = portfolios.workspace_id
        AND fd.consent_status = 'accepted'
        AND fd.is_active = TRUE
        AND (fd.expires_at IS NULL OR fd.expires_at > now())
    )
  );

-- Referrals Policies
DROP POLICY IF EXISTS referrals_select ON public.investor_referrals;
CREATE POLICY referrals_select ON public.investor_referrals
  FOR SELECT
  TO authenticated
  USING (referrer_profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS referrals_insert ON public.investor_referrals;
CREATE POLICY referrals_insert ON public.investor_referrals
  FOR INSERT
  TO authenticated
  WITH CHECK (referrer_profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS conversions_select ON public.referral_conversions;
CREATE POLICY conversions_select ON public.referral_conversions
  FOR SELECT
  TO authenticated
  USING (
    referee_profile_id = public.current_user_profile_id()
    OR EXISTS (
      SELECT 1 FROM public.investor_referrals ir
      WHERE ir.id = referral_conversions.referral_id
        AND ir.referrer_profile_id = public.current_user_profile_id()
    )
  );

DROP POLICY IF EXISTS rewards_select ON public.referral_rewards;
CREATE POLICY rewards_select ON public.referral_rewards
  FOR SELECT
  TO authenticated
  USING (profile_id = public.current_user_profile_id());

-- Advisor Profile Policies
DROP POLICY IF EXISTS advisor_profiles_advisor_all ON public.advisor_profiles;
CREATE POLICY advisor_profiles_advisor_all ON public.advisor_profiles
  FOR ALL
  TO authenticated
  USING (profile_id = public.current_user_profile_id() OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin')
  WITH CHECK (profile_id = public.current_user_profile_id() OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin');

-- CRM Notes Policies
DROP POLICY IF EXISTS crm_notes_select ON public.crm_notes;
CREATE POLICY crm_notes_select ON public.crm_notes
  FOR SELECT
  TO authenticated
  USING (
    public.has_advisor_membership(workspace_id)
    OR client_profile_id = public.current_user_profile_id()
  );

DROP POLICY IF EXISTS crm_notes_insert ON public.crm_notes;
CREATE POLICY crm_notes_insert ON public.crm_notes
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.has_advisor_membership(workspace_id)
    AND advisor_profile_id = public.current_user_profile_id()
  );


-- 10. Implement public.investor_subscriptions table and alter public.payment_events
CREATE TABLE IF NOT EXISTS public.investor_subscriptions (
  id uuid primary key default gen_random_uuid(),
  investor_profile_id uuid not null references public.profiles(id) on delete cascade unique,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null check (status in ('active', 'past_due', 'suspended', 'cancelled')) default 'active',
  start_date timestamptz not null default now(),
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

ALTER TABLE public.investor_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY investor_subscriptions_owner ON public.investor_subscriptions
  FOR SELECT
  TO authenticated
  USING (investor_profile_id = public.current_user_profile_id());

-- Alter payment_events
ALTER TABLE public.payment_events ADD COLUMN IF NOT EXISTS investor_profile_id uuid references public.profiles(id) on delete cascade;
ALTER TABLE public.payment_events ALTER COLUMN workspace_id DROP NOT NULL;

ALTER TABLE public.payment_events DROP CONSTRAINT IF EXISTS payment_events_billing_owner_xor;
ALTER TABLE public.payment_events ADD CONSTRAINT payment_events_billing_owner_xor
  CHECK (
    (workspace_id IS NOT NULL AND investor_profile_id IS NULL)
    OR (workspace_id IS NULL AND investor_profile_id IS NOT NULL)
  );


-- 11. Implement Platform Admin override RPCs (unlock account and access reset)
CREATE OR REPLACE FUNCTION public.override_account_unlock(
  p_target_profile_id uuid,
  p_reason text,
  p_correlation_id uuid
)
RETURNS void AS $$
DECLARE
  v_workspace_id uuid;
  v_admin_profile_id uuid;
BEGIN
  -- Verify actor is Platform Admin
  IF COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') <> 'platform_admin' THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF p_reason IS NULL OR p_reason = '' THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  IF p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;

  v_admin_profile_id := public.current_user_profile_id();

  -- Get target profile workspace
  SELECT workspace_id INTO v_workspace_id
  FROM public.workspace_memberships
  WHERE profile_id = p_target_profile_id
  LIMIT 1;

  -- Mutate
  UPDATE public.profiles
  SET account_status = 'active',
      updated_at = now()
  WHERE id = p_target_profile_id;

  -- Append separate succeeded event
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    COALESCE(v_workspace_id, '00000000-0000-0000-0000-000000000000'::uuid),
    v_admin_profile_id,
    'override.succeeded',
    'profiles',
    p_target_profile_id,
    jsonb_build_object(
      'action', 'account_unlock',
      'reason', p_reason,
      'correlation_id', p_correlation_id,
      'actor_type', 'platform_admin',
      'event_type', 'override.succeeded',
      'outcome', 'succeeded'
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.override_access_reset(
  p_target_profile_id uuid,
  p_reason text,
  p_correlation_id uuid
)
RETURNS void AS $$
DECLARE
  v_workspace_id uuid;
  v_admin_profile_id uuid;
BEGIN
  -- Verify actor is Platform Admin
  IF COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') <> 'platform_admin' THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF p_reason IS NULL OR p_reason = '' THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  IF p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;

  v_admin_profile_id := public.current_user_profile_id();

  -- Get target profile workspace
  SELECT workspace_id INTO v_workspace_id
  FROM public.workspace_memberships
  WHERE profile_id = p_target_profile_id
  LIMIT 1;

  -- Mutate
  UPDATE public.profiles
  SET account_status = 'active',
      updated_at = now()
  WHERE id = p_target_profile_id;

  -- Append separate succeeded event
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    COALESCE(v_workspace_id, '00000000-0000-0000-0000-000000000000'::uuid),
    v_admin_profile_id,
    'override.succeeded',
    'profiles',
    p_target_profile_id,
    jsonb_build_object(
      'action', 'access_reset',
      'reason', p_reason,
      'correlation_id', p_correlation_id,
      'actor_type', 'platform_admin',
      'event_type', 'override.succeeded',
      'outcome', 'succeeded'
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- 12. Create Family Access consenting and lifecycle RPCs
CREATE OR REPLACE FUNCTION public.delegate_consent_accept(
  p_delegation_id uuid
)
RETURNS public.family_delegations AS $$
DECLARE
  v_delegation public.family_delegations;
  v_caller_profile uuid;
BEGIN
  v_caller_profile := public.current_user_profile_id();
  IF v_caller_profile IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  SELECT * INTO v_delegation
  FROM public.family_delegations
  WHERE id = p_delegation_id
  FOR UPDATE;

  IF v_delegation.id IS NULL THEN
    RAISE EXCEPTION 'delegation_not_found';
  END IF;

  -- Must be delegate to accept
  IF v_delegation.delegate_profile_id <> v_caller_profile THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF v_delegation.consent_status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_delegation_state';
  END IF;

  UPDATE public.family_delegations
  SET consent_status = 'accepted',
      updated_at = now()
  WHERE id = p_delegation_id
  RETURNING * INTO v_delegation;

  -- Write immutable audit
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    v_delegation.workspace_id,
    v_caller_profile,
    'family_delegation.accepted',
    'family_delegations',
    p_delegation_id,
    jsonb_build_object(
      'previous_status', 'pending',
      'new_status', 'accepted'
    )
  );

  RETURN v_delegation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.delegate_consent_reject(
  p_delegation_id uuid
)
RETURNS public.family_delegations AS $$
DECLARE
  v_delegation public.family_delegations;
  v_caller_profile uuid;
BEGIN
  v_caller_profile := public.current_user_profile_id();
  IF v_caller_profile IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  SELECT * INTO v_delegation
  FROM public.family_delegations
  WHERE id = p_delegation_id
  FOR UPDATE;

  IF v_delegation.id IS NULL THEN
    RAISE EXCEPTION 'delegation_not_found';
  END IF;

  -- Must be delegate to reject
  IF v_delegation.delegate_profile_id <> v_caller_profile THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF v_delegation.consent_status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_delegation_state';
  END IF;

  UPDATE public.family_delegations
  SET consent_status = 'rejected',
      is_active = false,
      updated_at = now()
  WHERE id = p_delegation_id
  RETURNING * INTO v_delegation;

  -- Write immutable audit
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    v_delegation.workspace_id,
    v_caller_profile,
    'family_delegation.rejected',
    'family_delegations',
    p_delegation_id,
    jsonb_build_object(
      'previous_status', 'pending',
      'new_status', 'rejected'
    )
  );

  RETURN v_delegation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.delegate_consent_revoke(
  p_delegation_id uuid
)
RETURNS public.family_delegations AS $$
DECLARE
  v_delegation public.family_delegations;
  v_caller_profile uuid;
BEGIN
  v_caller_profile := public.current_user_profile_id();
  IF v_caller_profile IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  SELECT * INTO v_delegation
  FROM public.family_delegations
  WHERE id = p_delegation_id
  FOR UPDATE;

  IF v_delegation.id IS NULL THEN
    RAISE EXCEPTION 'delegation_not_found';
  END IF;

  -- Owner or delegate can revoke
  IF v_delegation.owner_profile_id <> v_caller_profile AND v_delegation.delegate_profile_id <> v_caller_profile THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF NOT v_delegation.is_active THEN
    RAISE EXCEPTION 'already_inactive';
  END IF;

  UPDATE public.family_delegations
  SET is_active = false,
      updated_at = now()
  WHERE id = p_delegation_id
  RETURNING * INTO v_delegation;

  -- Write immutable audit
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (
    v_delegation.workspace_id,
    v_caller_profile,
    'family_delegation.revoked',
    'family_delegations',
    p_delegation_id,
    jsonb_build_object(
      'previous_status', v_delegation.consent_status
    )
  );

  RETURN v_delegation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- 13. Create referral_conversions table if not exists (hardened referrals model)
CREATE TABLE IF NOT EXISTS public.referral_conversions (
  id uuid primary key default gen_random_uuid(),
  referral_id uuid not null references public.investor_referrals(id) on delete cascade,
  referee_profile_id uuid not null references public.profiles(id) on delete cascade unique,
  converted_at timestamptz not null default now()
);

ALTER TABLE public.referral_conversions ENABLE ROW LEVEL SECURITY;

CREATE POLICY conversions_select_resolved ON public.referral_conversions
  FOR SELECT
  TO authenticated
  USING (
    referee_profile_id = public.current_user_profile_id()
    OR EXISTS (
      SELECT 1 FROM public.investor_referrals ir
      WHERE ir.id = referral_conversions.referral_id
        AND ir.referrer_profile_id = public.current_user_profile_id()
    )
  );

COMMIT;
