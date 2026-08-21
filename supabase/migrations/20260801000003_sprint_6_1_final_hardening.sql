-- 20260801000002_sprint_6_1_final_hardening.sql
-- Final Sprint 6.1 compliance and hardening migration

BEGIN;

-- 1. Add canonical columns to public.workspace_audit_logs if missing
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS actor_profile_id uuid references public.profiles(id);
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS actor_type text;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS entity_type text;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS entity_id uuid;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS reason text;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS correlation_id uuid;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS event_type text;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS outcome text;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS error_code text;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS previous_state text;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS new_state text;
ALTER TABLE public.workspace_audit_logs ADD COLUMN IF NOT EXISTS occurred_at timestamptz DEFAULT pg_catalog.now();

-- 2. Drop broad, non-compliant Platform Admin/Owner policies
DROP POLICY IF EXISTS auto_approval_rules_admin_all ON public.auto_approval_rules;
DROP POLICY IF EXISTS event_outbox_all ON public.event_outbox;
DROP POLICY IF EXISTS advisor_profiles_advisor_all ON public.advisor_profiles;
DROP POLICY IF EXISTS family_delegations_owner_all ON public.family_delegations;

-- 3. Create compliant, narrow RLS policies for auto_approval_rules
DROP POLICY IF EXISTS auto_approval_rules_admin_select ON public.auto_approval_rules;
CREATE POLICY auto_approval_rules_admin_select ON public.auto_approval_rules
  FOR SELECT TO authenticated
  USING (COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin');

DROP POLICY IF EXISTS auto_approval_rules_advisor_insert ON public.auto_approval_rules;
CREATE POLICY auto_approval_rules_advisor_insert ON public.auto_approval_rules
  FOR INSERT TO authenticated
  WITH CHECK (public.has_advisor_membership(workspace_id));

DROP POLICY IF EXISTS auto_approval_rules_advisor_update ON public.auto_approval_rules;
CREATE POLICY auto_approval_rules_advisor_update ON public.auto_approval_rules
  FOR UPDATE TO authenticated
  USING (public.has_advisor_membership(workspace_id))
  WITH CHECK (public.has_advisor_membership(workspace_id));

DROP POLICY IF EXISTS auto_approval_rules_advisor_delete ON public.auto_approval_rules;
CREATE POLICY auto_approval_rules_advisor_delete ON public.auto_approval_rules
  FOR DELETE TO authenticated
  USING (public.has_advisor_membership(workspace_id));

-- 4. Create select-only RLS policy for event_outbox
DROP POLICY IF EXISTS event_outbox_select_admin ON public.event_outbox;
CREATE POLICY event_outbox_select_admin ON public.event_outbox
  FOR SELECT TO authenticated
  USING (COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin');

-- 5. Create narrow RLS policies for advisor_profiles
DROP POLICY IF EXISTS advisor_profiles_select ON public.advisor_profiles;
CREATE POLICY advisor_profiles_select ON public.advisor_profiles
  FOR SELECT TO authenticated
  USING (profile_id = public.current_user_profile_id() OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin');

DROP POLICY IF EXISTS advisor_profiles_insert ON public.advisor_profiles;
CREATE POLICY advisor_profiles_insert ON public.advisor_profiles
  FOR INSERT TO authenticated
  WITH CHECK (profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS advisor_profiles_update ON public.advisor_profiles;
CREATE POLICY advisor_profiles_update ON public.advisor_profiles
  FOR UPDATE TO authenticated
  USING (profile_id = public.current_user_profile_id())
  WITH CHECK (profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS advisor_profiles_delete ON public.advisor_profiles;
CREATE POLICY advisor_profiles_delete ON public.advisor_profiles
  FOR DELETE TO authenticated
  USING (profile_id = public.current_user_profile_id());

-- 6. Create narrow RLS policies for family_delegations
DROP POLICY IF EXISTS family_delegations_owner_select ON public.family_delegations;
CREATE POLICY family_delegations_owner_select ON public.family_delegations
  FOR SELECT TO authenticated
  USING (owner_profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS family_delegations_delegate_select ON public.family_delegations;
CREATE POLICY family_delegations_delegate_select ON public.family_delegations
  FOR SELECT TO authenticated
  USING (delegate_profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS family_delegations_admin_select ON public.family_delegations;
CREATE POLICY family_delegations_admin_select ON public.family_delegations
  FOR SELECT TO authenticated
  USING (COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin');

DROP POLICY IF EXISTS family_delegations_insert ON public.family_delegations;
CREATE POLICY family_delegations_insert ON public.family_delegations
  FOR INSERT TO authenticated
  WITH CHECK (
    owner_profile_id = public.current_user_profile_id()
    AND consent_status = 'pending'
    AND is_active = TRUE
  );

-- 7. Document access RLS (family delegation alone must not grant document access)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'ingested_documents') THEN
    EXECUTE 'DROP POLICY IF EXISTS family_delegate_document_denial ON public.ingested_documents;';
  END IF;
END $$;

-- 8. Enforce unique constraint/index for event outbox logical events
CREATE UNIQUE INDEX IF NOT EXISTS event_outbox_order_created_uidx
ON public.event_outbox(entity_type, entity_id, event_type)
WHERE event_type = 'order.created';

-- 9. Redefine trigger function to utilize database unique constraint for duplicate prevention
CREATE OR REPLACE FUNCTION public.trigger_order_outbox_event()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.event_outbox (event_type, entity_id, entity_type, payload, status)
  VALUES (
    'order.created',
    NEW.id,
    'order_request',
    pg_catalog.jsonb_build_object(
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
  )
  ON CONFLICT (entity_type, entity_id, event_type) WHERE event_type = 'order.created' DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- 10. Update current_user_profile_id helpers grants
REVOKE ALL ON FUNCTION public.current_user_profile_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_profile_id() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_profile_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_profile_id() TO service_role;

-- 11. Redefine qualify_order with SET search_path = '' and fully qualified object references
CREATE OR REPLACE FUNCTION public.qualify_order(
  p_order_id pg_catalog.uuid,
  p_decision public.order_status,
  p_rejection_reason pg_catalog.text DEFAULT null
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id pg_catalog.uuid;
  v_current_status public.order_status;
  v_current_profile_id pg_catalog.uuid;
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
      reviewed_at = pg_catalog.now(),
      rejection_reason = p_rejection_reason,
      updated_at = pg_catalog.now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- 6. Write immutable audit using database-loaded values
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_workspace_id,
    v_current_profile_id,
    v_current_profile_id,
    'advisor',
    'order.qualified',
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    v_current_status::pg_catalog.text,
    p_decision::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'decision', p_decision,
      'rejection_reason', p_rejection_reason,
      'previous_status', v_current_status
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) TO authenticated;

-- 12. Redefine cancel_order with SET search_path = '' and fully qualified object references
CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id pg_catalog.uuid,
  p_reason pg_catalog.text DEFAULT null
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id pg_catalog.uuid;
  v_investor_profile_id pg_catalog.uuid;
  v_current_status public.order_status;
  v_current_profile_id pg_catalog.uuid;
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
      rejection_reason = coalesce(p_reason, 'Cancelled by user'),
      updated_at = pg_catalog.now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- 7. Write immutable audit log using database-loaded values
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    reason,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_workspace_id,
    v_current_profile_id,
    v_current_profile_id,
    CASE WHEN v_investor_profile_id = v_current_profile_id THEN 'investor' ELSE 'advisor' END,
    'order.cancelled',
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    p_reason,
    v_current_status::pg_catalog.text,
    'cancelled',
    pg_catalog.jsonb_build_object(
      'reason', p_reason,
      'previous_status', v_current_status
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.cancel_order(pg_catalog.uuid, pg_catalog.text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_order(pg_catalog.uuid, pg_catalog.text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_order(pg_catalog.uuid, pg_catalog.text) TO authenticated;

-- 13. Redefine apply_auto_approval_decision with SET search_path = '' and outbox claim validations
CREATE OR REPLACE FUNCTION public.apply_auto_approval_decision(
  p_order_id pg_catalog.uuid,
  p_decision public.order_status,
  p_rule_id pg_catalog.uuid,
  p_rule_version pg_catalog.int4,
  p_correlation_id pg_catalog.uuid
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id pg_catalog.uuid;
  v_investor_profile_id pg_catalog.uuid;
  v_status public.order_status;
  v_existing_correlation_id pg_catalog.uuid;
  v_existing_rule_id pg_catalog.uuid;
  v_existing_rule_version pg_catalog.int4;
  
  v_event_id pg_catalog.uuid;
  v_event_entity_id pg_catalog.uuid;
  v_event_type pg_catalog.text;
  v_event_status pg_catalog.text;
  v_claimed_at pg_catalog.timestamptz;
  v_claimed_by pg_catalog.uuid;
  
  v_order public.order_requests;
BEGIN
  -- Step 1: Lock the order row and load state
  SELECT
      workspace_id,
      investor_profile_id,
      status,
      auto_approval_correlation_id,
      triggered_rule_id,
      triggered_rule_version
  INTO
      v_workspace_id,
      v_investor_profile_id,
      v_status,
      v_existing_correlation_id,
      v_existing_rule_id,
      v_existing_rule_version
  FROM public.order_requests
  WHERE id = p_order_id
  FOR UPDATE;

  -- Step 2: Idempotent Replay Check (Before Stale-State Validation)
  IF v_existing_correlation_id = p_correlation_id THEN
    IF p_decision <> v_status THEN
      RAISE EXCEPTION 'idempotency_conflict';
    END IF;
    IF p_rule_id IS DISTINCT FROM v_existing_rule_id THEN
      RAISE EXCEPTION 'idempotency_conflict';
    END IF;
    IF p_rule_version IS DISTINCT FROM v_existing_rule_version THEN
      RAISE EXCEPTION 'idempotency_conflict';
    END IF;
    
    SELECT * INTO v_order FROM public.order_requests WHERE id = p_order_id;
    RETURN v_order;
  END IF;

  -- Step 3: Stale State Check
  IF v_status <> 'pending_qualification' THEN
    RAISE EXCEPTION 'stale_order_state';
  END IF;

  -- Step 4: Outbox Event & Correlation Binding Validation
  SELECT
      id,
      entity_id,
      event_type,
      status,
      claimed_at,
      claimed_by
  INTO
      v_event_id,
      v_event_entity_id,
      v_event_type,
      v_event_status,
      v_claimed_at,
      v_claimed_by
  FROM public.event_outbox
  WHERE id = p_correlation_id
  FOR UPDATE;

  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;

  IF v_event_type <> 'order.created' THEN
    RAISE EXCEPTION 'invalid_event_type';
  END IF;

  IF v_event_entity_id <> p_order_id THEN
    RAISE EXCEPTION 'event_order_mismatch';
  END IF;

  IF v_event_status = 'completed' THEN
    RAISE EXCEPTION 'event_already_completed';
  END IF;

  IF v_event_status <> 'processing' OR v_claimed_at IS NULL OR v_claimed_by IS NULL THEN
    RAISE EXCEPTION 'event_not_claimed';
  END IF;

  -- Step 5: Conditional Rule Validation
  IF p_decision = 'auto_approved' THEN
    IF p_rule_id IS NULL OR p_rule_version IS NULL THEN
      RAISE EXCEPTION 'rule_not_found';
    END IF;
    
    -- Validate that the rule exists
    IF NOT EXISTS (
      SELECT 1 FROM public.auto_approval_rules
      WHERE id = p_rule_id
    ) THEN
      RAISE EXCEPTION 'rule_not_found';
    END IF;

    -- Validate rule is active and belongs to order's workspace and matches version
    DECLARE
      v_rule_active pg_catalog.bool;
      v_rule_workspace pg_catalog.uuid;
      v_rule_version pg_catalog.int4;
    BEGIN
      SELECT is_active, workspace_id, rule_version
      INTO v_rule_active, v_rule_workspace, v_rule_version
      FROM public.auto_approval_rules
      WHERE id = p_rule_id;
      
      IF v_rule_workspace <> v_workspace_id THEN
        RAISE EXCEPTION 'rule_workspace_mismatch';
      END IF;
      
      IF NOT v_rule_active THEN
        RAISE EXCEPTION 'rule_inactive';
      END IF;
      
      IF v_rule_version <> p_rule_version THEN
        RAISE EXCEPTION 'rule_version_mismatch';
      END IF;
    END;
  ELSIF p_decision = 'pending_review' THEN
    IF p_rule_id IS NOT NULL OR p_rule_version IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_qualification_decision';
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_qualification_decision';
  END IF;

  -- Step 6: Apply state transition
  UPDATE public.order_requests
  SET status = p_decision,
      triggered_rule_id = p_rule_id,
      triggered_rule_version = p_rule_version,
      auto_approval_correlation_id = p_correlation_id,
      updated_at = pg_catalog.now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- Update event outbox to completed
  UPDATE public.event_outbox
  SET status = 'completed',
      updated_at = pg_catalog.now()
  WHERE id = p_correlation_id;

  -- Step 7: Record append-only audit log
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    correlation_id,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_workspace_id,
    v_investor_profile_id,
    v_investor_profile_id,
    'system',
    'order.auto_qualified',
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    p_correlation_id,
    v_status::pg_catalog.text,
    p_decision::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'decision', p_decision,
      'rule_id', p_rule_id,
      'rule_version', p_rule_version,
      'correlation_id', p_correlation_id
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid) TO service_role;

-- 14. Redefine Family Access lifecycle RPCs with SET search_path = '' and canonical audit columns
CREATE OR REPLACE FUNCTION public.delegate_consent_accept(
  p_delegation_id pg_catalog.uuid
)
RETURNS public.family_delegations AS $$
DECLARE
  v_delegation public.family_delegations;
  v_caller_profile pg_catalog.uuid;
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
      updated_at = pg_catalog.now()
  WHERE id = p_delegation_id
  RETURNING * INTO v_delegation;

  -- Write immutable audit
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_delegation.workspace_id,
    v_caller_profile,
    v_caller_profile,
    'investor',
    'family_delegation.accepted',
    'family_delegations',
    'family_delegations',
    p_delegation_id,
    p_delegation_id,
    'pending',
    'accepted',
    pg_catalog.jsonb_build_object(
      'previous_status', 'pending',
      'new_status', 'accepted'
    )
  );

  RETURN v_delegation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.delegate_consent_accept(pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delegate_consent_accept(pg_catalog.uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.delegate_consent_accept(pg_catalog.uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.delegate_consent_reject(
  p_delegation_id pg_catalog.uuid
)
RETURNS public.family_delegations AS $$
DECLARE
  v_delegation public.family_delegations;
  v_caller_profile pg_catalog.uuid;
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
      updated_at = pg_catalog.now()
  WHERE id = p_delegation_id
  RETURNING * INTO v_delegation;

  -- Write immutable audit
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_delegation.workspace_id,
    v_caller_profile,
    v_caller_profile,
    'investor',
    'family_delegation.rejected',
    'family_delegations',
    'family_delegations',
    p_delegation_id,
    p_delegation_id,
    'pending',
    'rejected',
    pg_catalog.jsonb_build_object(
      'previous_status', 'pending',
      'new_status', 'rejected'
    )
  );

  RETURN v_delegation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.delegate_consent_reject(pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delegate_consent_reject(pg_catalog.uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.delegate_consent_reject(pg_catalog.uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.delegate_consent_revoke(
  p_delegation_id pg_catalog.uuid
)
RETURNS public.family_delegations AS $$
DECLARE
  v_delegation public.family_delegations;
  v_caller_profile pg_catalog.uuid;
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

  -- Owner, delegate, or Platform Admin can revoke
  IF v_delegation.owner_profile_id <> v_caller_profile 
     AND v_delegation.delegate_profile_id <> v_caller_profile 
     AND coalesce((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') <> 'platform_admin' THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Platform Admin must require step-up MFA
  IF coalesce((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin' THEN
    IF NOT (coalesce(auth.jwt() -> 'amr', '[]'::jsonb) ? 'mfa') THEN
      RAISE EXCEPTION 'platform_admin_step_up_required';
    END IF;
  END IF;

  IF NOT v_delegation.is_active THEN
    RAISE EXCEPTION 'already_inactive';
  END IF;

  UPDATE public.family_delegations
  SET is_active = false,
      consent_status = 'revoked',
      updated_at = pg_catalog.now()
  WHERE id = p_delegation_id
  RETURNING * INTO v_delegation;

  -- Write immutable audit
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_delegation.workspace_id,
    v_caller_profile,
    v_caller_profile,
    'investor',
    'family_delegation.revoked',
    'family_delegations',
    'family_delegations',
    p_delegation_id,
    p_delegation_id,
    'active',
    'inactive',
    pg_catalog.jsonb_build_object(
      'previous_status', v_delegation.consent_status
    )
  );

  RETURN v_delegation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.delegate_consent_revoke(pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delegate_consent_revoke(pg_catalog.uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.delegate_consent_revoke(pg_catalog.uuid) TO authenticated;

-- 15. Redefine Platform Admin mutation RPCs with SET search_path = '' and no arbitrary LIMIT 1 lookups
CREATE OR REPLACE FUNCTION public.override_account_unlock(
  p_target_profile_id pg_catalog.uuid,
  p_reason pg_catalog.text,
  p_correlation_id pg_catalog.uuid,
  p_workspace_id pg_catalog.uuid
)
RETURNS void AS $$
DECLARE
  v_admin_profile_id pg_catalog.uuid;
BEGIN
  -- Verify actor is Platform Admin
  IF coalesce((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') <> 'platform_admin' THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Verify step-up MFA
  IF NOT (coalesce(auth.jwt() -> 'amr', '[]'::jsonb) ? 'mfa') THEN
    RAISE EXCEPTION 'platform_admin_step_up_required';
  END IF;

  IF p_reason IS NULL OR p_reason = '' THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  IF p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;

  IF p_workspace_id IS NULL THEN
    RAISE EXCEPTION 'workspace_id_required';
  END IF;

  -- Validate that the target profile is a member of the workspace
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_memberships
    WHERE profile_id = p_target_profile_id AND workspace_id = p_workspace_id
  ) THEN
    RAISE EXCEPTION 'profile_workspace_mismatch';
  END IF;

  v_admin_profile_id := public.current_user_profile_id();

  -- Mutate
  UPDATE public.profiles
  SET account_status = 'active',
      updated_at = pg_catalog.now()
  WHERE id = p_target_profile_id;

  -- Write domain audit inside the transaction
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    reason,
    correlation_id,
    event_type,
    outcome,
    payload
  ) VALUES (
    p_workspace_id,
    v_admin_profile_id,
    v_admin_profile_id,
    'platform_admin',
    'override.account_unlock',
    'profiles',
    'profiles',
    p_target_profile_id,
    p_target_profile_id,
    p_reason,
    p_correlation_id,
    'override.succeeded',
    'succeeded',
    pg_catalog.jsonb_build_object(
      'action', 'account_unlock',
      'reason', p_reason,
      'correlation_id', p_correlation_id,
      'actor_type', 'platform_admin',
      'event_type', 'override.succeeded',
      'outcome', 'succeeded'
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.override_account_unlock(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.override_account_unlock(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.override_account_unlock(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.override_access_reset(
  p_target_profile_id pg_catalog.uuid,
  p_reason pg_catalog.text,
  p_correlation_id pg_catalog.uuid,
  p_workspace_id pg_catalog.uuid
)
RETURNS void AS $$
DECLARE
  v_admin_profile_id pg_catalog.uuid;
BEGIN
  -- Verify actor is Platform Admin
  IF coalesce((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') <> 'platform_admin' THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Verify step-up MFA
  IF NOT (coalesce(auth.jwt() -> 'amr', '[]'::jsonb) ? 'mfa') THEN
    RAISE EXCEPTION 'platform_admin_step_up_required';
  END IF;

  IF p_reason IS NULL OR p_reason = '' THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  IF p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;

  IF p_workspace_id IS NULL THEN
    RAISE EXCEPTION 'workspace_id_required';
  END IF;

  -- Validate that the target profile is a member of the workspace
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_memberships
    WHERE profile_id = p_target_profile_id AND workspace_id = p_workspace_id
  ) THEN
    RAISE EXCEPTION 'profile_workspace_mismatch';
  END IF;

  v_admin_profile_id := public.current_user_profile_id();

  -- Mutate
  UPDATE public.profiles
  SET account_status = 'active',
      updated_at = pg_catalog.now()
  WHERE id = p_target_profile_id;

  -- Write domain audit inside the transaction
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    reason,
    correlation_id,
    event_type,
    outcome,
    payload
  ) VALUES (
    p_workspace_id,
    v_admin_profile_id,
    v_admin_profile_id,
    'platform_admin',
    'override.access_reset',
    'profiles',
    'profiles',
    p_target_profile_id,
    p_target_profile_id,
    p_reason,
    p_correlation_id,
    'override.succeeded',
    'succeeded',
    pg_catalog.jsonb_build_object(
      'action', 'access_reset',
      'reason', p_reason,
      'correlation_id', p_correlation_id,
      'actor_type', 'platform_admin',
      'event_type', 'override.succeeded',
      'outcome', 'succeeded'
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.override_access_reset(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.override_access_reset(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.override_access_reset(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.uuid) TO authenticated;

-- 16. Update investor_subscriptions status check constraint and set default to trialing
ALTER TABLE public.investor_subscriptions DROP CONSTRAINT IF EXISTS investor_subscriptions_status_check;
ALTER TABLE public.investor_subscriptions ADD CONSTRAINT investor_subscriptions_status_check CHECK (status in ('trialing', 'active', 'past_due', 'suspended', 'cancelled'));
ALTER TABLE public.investor_subscriptions ALTER COLUMN status SET DEFAULT 'trialing';

-- 17. Update payment_events RLS select policy to allow investor-profile-id matching SELECT
DROP POLICY IF EXISTS payment_events_select ON public.payment_events;
CREATE POLICY payment_events_select ON public.payment_events
  FOR SELECT
  TO authenticated
  USING (
    public.has_active_workspace_membership(workspace_id)
    OR investor_profile_id = public.current_user_profile_id()
    OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'user_role'), '') = 'platform_admin'
  );

-- 18. Redefine log_family_delegation_audit with profile-resolved current_user_profile_id()
CREATE OR REPLACE FUNCTION public.log_family_delegation_audit()
RETURNS trigger AS $$
DECLARE
  v_caller_profile_id pg_catalog.uuid;
  v_actor_profile_id pg_catalog.uuid;
  v_actor_type pg_catalog.text;
  v_action pg_catalog.text;
BEGIN
  v_caller_profile_id := public.current_user_profile_id();
  
  IF TG_OP = 'INSERT' THEN
    v_actor_profile_id := coalesce(v_caller_profile_id, NEW.owner_profile_id);
    v_actor_type := 'investor';
    
    INSERT INTO public.workspace_audit_logs (
      workspace_id,
      actor_id,
      actor_profile_id,
      actor_type,
      action,
      target_type,
      entity_type,
      target_id,
      entity_id,
      payload
    ) VALUES (
      NEW.workspace_id,
      v_actor_profile_id,
      v_actor_profile_id,
      v_actor_type,
      'family_delegation.created',
      'family_delegations',
      'family_delegations',
      NEW.id,
      NEW.id,
      pg_catalog.jsonb_build_object(
        'owner_profile_id', NEW.owner_profile_id,
        'delegate_profile_id', NEW.delegate_profile_id,
        'consent_status', NEW.consent_status,
        'expires_at', NEW.expires_at
      )
    );
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.consent_status IS DISTINCT FROM NEW.consent_status THEN
      v_actor_profile_id := coalesce(v_caller_profile_id, NEW.delegate_profile_id);
      v_actor_type := 'investor';
      IF NEW.consent_status = 'accepted' THEN
        v_action := 'family_delegation.accepted';
      ELSIF NEW.consent_status = 'rejected' THEN
        v_action := 'family_delegation.rejected';
      ELSIF NEW.consent_status = 'revoked' THEN
        v_action := 'family_delegation.revoked';
      ELSE
        v_action := 'family_delegation.consent_updated';
      END IF;

      INSERT INTO public.workspace_audit_logs (
        workspace_id,
        actor_id,
        actor_profile_id,
        actor_type,
        action,
        target_type,
        entity_type,
        target_id,
        entity_id,
        payload
      ) VALUES (
        NEW.workspace_id,
        v_actor_profile_id,
        v_actor_profile_id,
        v_actor_type,
        v_action,
        'family_delegations',
        'family_delegations',
        NEW.id,
        NEW.id,
        pg_catalog.jsonb_build_object(
          'owner_profile_id', NEW.owner_profile_id,
          'delegate_profile_id', NEW.delegate_profile_id,
          'consent_status', NEW.consent_status
        )
      );
    ELSIF OLD.is_active = TRUE AND NEW.is_active = FALSE THEN
      v_actor_profile_id := coalesce(v_caller_profile_id, NEW.owner_profile_id);
      v_actor_type := 'investor';

      INSERT INTO public.workspace_audit_logs (
        workspace_id,
        actor_id,
        actor_profile_id,
        actor_type,
        action,
        target_type,
        entity_type,
        target_id,
        entity_id,
        payload
      ) VALUES (
        NEW.workspace_id,
        v_actor_profile_id,
        v_actor_profile_id,
        v_actor_type,
        'family_delegation.revoked',
        'family_delegations',
        'family_delegations',
        NEW.id,
        NEW.id,
        pg_catalog.jsonb_build_object(
          'owner_profile_id', NEW.owner_profile_id,
          'delegate_profile_id', NEW.delegate_profile_id,
          'consent_status', NEW.consent_status
        )
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- 19. Dynamically drop old consent_status check constraint and add updated one allowing 'revoked'
DO $$
DECLARE
  v_const_name pg_catalog.text;
BEGIN
  SELECT constraint_name INTO v_const_name
  FROM information_schema.constraint_column_usage
  WHERE table_name = 'family_delegations' AND column_name = 'consent_status' LIMIT 1;
  
  IF v_const_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.family_delegations DROP CONSTRAINT ' || pg_catalog.quote_ident(v_const_name);
  END IF;
END;
$$;

ALTER TABLE public.family_delegations ADD CONSTRAINT family_delegations_consent_status_check CHECK (consent_status IN ('pending', 'accepted', 'rejected', 'revoked'));

COMMIT;
