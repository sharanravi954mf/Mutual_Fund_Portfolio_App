-- Issue #39: finish the investor subscription lifecycle, payment idempotency,
-- and plan entitlement access contracts without rewriting the delivered schema.

BEGIN;

CREATE TABLE public.investor_subscription_audit_logs (
  id pg_catalog.uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  investor_subscription_id pg_catalog.uuid NOT NULL
    REFERENCES public.investor_subscriptions(id) ON DELETE RESTRICT,
  investor_profile_id pg_catalog.uuid NOT NULL
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  payment_event_id pg_catalog.uuid
    REFERENCES public.payment_events(id) ON DELETE RESTRICT,
  previous_status pg_catalog.text NOT NULL,
  new_status pg_catalog.text NOT NULL,
  reason pg_catalog.text NOT NULL,
  actor_user_id pg_catalog.uuid,
  occurred_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT investor_subscription_audit_statuses_check CHECK (
    previous_status IN ('trialing', 'active', 'past_due', 'suspended')
    AND new_status IN ('active', 'past_due', 'suspended', 'cancelled')
  )
);

COMMENT ON TABLE public.investor_subscription_audit_logs IS
  'Immutable audit trail for canonical investor subscription state transitions.';

ALTER TABLE public.investor_subscription_audit_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.payment_events
  ADD COLUMN investor_subscription_id pg_catalog.uuid
    REFERENCES public.investor_subscriptions(id) ON DELETE RESTRICT,
  ADD COLUMN applied_subscription_status pg_catalog.text;

ALTER TABLE public.payment_events
  ADD CONSTRAINT payment_events_applied_subscription_status_check CHECK (
    applied_subscription_status IS NULL
    OR applied_subscription_status IN ('active', 'past_due', 'suspended', 'cancelled')
  ),
  ADD CONSTRAINT payment_events_investor_subscription_owner_check CHECK (
    (workspace_id IS NOT NULL
      AND investor_subscription_id IS NULL
      AND applied_subscription_status IS NULL)
    OR workspace_id IS NULL
  );

CREATE OR REPLACE FUNCTION public.enforce_investor_subscription_transition()
RETURNS pg_catalog.trigger AS $$
BEGIN
  IF NEW.status IS NULL
     OR NEW.status = OLD.status
     OR NOT (
    (OLD.status = 'trialing' AND NEW.status = 'active')
    OR (OLD.status = 'active' AND NEW.status = 'past_due')
    OR (OLD.status = 'past_due' AND NEW.status = 'suspended')
    OR (OLD.status = 'suspended' AND NEW.status = 'cancelled')
  ) THEN
    RAISE EXCEPTION 'invalid_investor_subscription_transition'
      USING ERRCODE = 'P0001';
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER SET search_path = '';

CREATE OR REPLACE FUNCTION public.audit_investor_subscription_transition()
RETURNS pg_catalog.trigger AS $$
DECLARE
  v_payment_event_id pg_catalog.uuid;
  v_reason pg_catalog.text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  v_payment_event_id := NULLIF(
    pg_catalog.current_setting('moneybowl.investor_payment_event_id', true),
    ''
  )::pg_catalog.uuid;
  v_reason := COALESCE(
    NULLIF(
      pg_catalog.current_setting('moneybowl.investor_subscription_transition_reason', true),
      ''
    ),
    'database_transition'
  );

  INSERT INTO public.investor_subscription_audit_logs (
    investor_subscription_id,
    investor_profile_id,
    payment_event_id,
    previous_status,
    new_status,
    reason,
    actor_user_id
  ) VALUES (
    NEW.id,
    NEW.investor_profile_id,
    v_payment_event_id,
    OLD.status,
    NEW.status,
    v_reason,
    auth.uid()
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.reject_investor_subscription_audit_mutation()
RETURNS pg_catalog.trigger AS $$
BEGIN
  RAISE EXCEPTION 'investor_subscription_audit_immutable'
    USING ERRCODE = 'P0001';
END;
$$ LANGUAGE plpgsql SECURITY INVOKER SET search_path = '';

DROP TRIGGER IF EXISTS investor_subscription_transition_guard
  ON public.investor_subscriptions;
CREATE TRIGGER investor_subscription_transition_guard
  BEFORE UPDATE OF status ON public.investor_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_investor_subscription_transition();

DROP TRIGGER IF EXISTS investor_subscription_transition_audit
  ON public.investor_subscriptions;
CREATE TRIGGER investor_subscription_transition_audit
  AFTER UPDATE OF status ON public.investor_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_investor_subscription_transition();

CREATE TRIGGER investor_subscription_audit_immutable
  BEFORE UPDATE OR DELETE ON public.investor_subscription_audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_investor_subscription_audit_mutation();

CREATE OR REPLACE FUNCTION public.transition_investor_subscription(
  p_investor_subscription_id pg_catalog.uuid,
  p_new_status pg_catalog.text,
  p_reason pg_catalog.text
)
RETURNS public.investor_subscriptions AS $$
DECLARE
  v_subscription public.investor_subscriptions;
BEGIN
  IF p_reason IS NULL OR pg_catalog.btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'subscription_transition_reason_required'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT subscription.*
  INTO v_subscription
  FROM public.investor_subscriptions AS subscription
  WHERE subscription.id = p_investor_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'investor_subscription_not_found'
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM pg_catalog.set_config(
    'moneybowl.investor_subscription_transition_reason',
    pg_catalog.btrim(p_reason),
    true
  );
  PERFORM pg_catalog.set_config('moneybowl.investor_payment_event_id', '', true);

  UPDATE public.investor_subscriptions
  SET status = p_new_status
  WHERE id = p_investor_subscription_id
  RETURNING * INTO v_subscription;

  RETURN v_subscription;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.process_investor_subscription_payment(
  p_investor_subscription_id pg_catalog.uuid,
  p_payment_id pg_catalog.text,
  p_amount pg_catalog.numeric,
  p_payment_status pg_catalog.text,
  p_new_subscription_status pg_catalog.text,
  p_reason pg_catalog.text
)
RETURNS TABLE (
  payment_event_id pg_catalog.uuid,
  investor_subscription_id pg_catalog.uuid,
  applied_subscription_status pg_catalog.text,
  replayed pg_catalog.bool
) AS $$
DECLARE
  v_subscription public.investor_subscriptions;
  v_existing public.payment_events;
  v_payment_event public.payment_events;
BEGIN
  IF p_payment_id IS NULL OR pg_catalog.btrim(p_payment_id) = '' THEN
    RAISE EXCEPTION 'payment_id_required' USING ERRCODE = 'P0001';
  END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN
    RAISE EXCEPTION 'invalid_payment_amount' USING ERRCODE = 'P0001';
  END IF;
  IF p_payment_status IS NULL OR pg_catalog.btrim(p_payment_status) = '' THEN
    RAISE EXCEPTION 'payment_status_required' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR pg_catalog.btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'subscription_transition_reason_required'
      USING ERRCODE = 'P0001';
  END IF;

  -- Serialise every delivery carrying the same external identifier before
  -- taking the subscription row lock. This covers duplicates across owners.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(pg_catalog.btrim(p_payment_id), 0)
  );

  SELECT subscription.*
  INTO v_subscription
  FROM public.investor_subscriptions AS subscription
  WHERE subscription.id = p_investor_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'investor_subscription_not_found'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT event.*
  INTO v_existing
  FROM public.payment_events AS event
  WHERE event.payment_id = pg_catalog.btrim(p_payment_id);

  IF FOUND THEN
    IF v_existing.workspace_id IS NULL
       AND v_existing.investor_profile_id = v_subscription.investor_profile_id
       AND v_existing.investor_subscription_id = v_subscription.id
       AND v_existing.amount = p_amount
       AND v_existing.status = pg_catalog.btrim(p_payment_status)
       AND v_existing.applied_subscription_status = p_new_subscription_status THEN
      RETURN QUERY SELECT
        v_existing.id,
        v_existing.investor_subscription_id,
        v_existing.applied_subscription_status,
        true;
      RETURN;
    END IF;

    RAISE EXCEPTION 'payment_id_conflict' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.payment_events (
    workspace_id,
    investor_profile_id,
    investor_subscription_id,
    amount,
    payment_id,
    status,
    applied_subscription_status
  ) VALUES (
    NULL,
    v_subscription.investor_profile_id,
    v_subscription.id,
    p_amount,
    pg_catalog.btrim(p_payment_id),
    pg_catalog.btrim(p_payment_status),
    p_new_subscription_status
  ) RETURNING * INTO v_payment_event;

  PERFORM pg_catalog.set_config(
    'moneybowl.investor_subscription_transition_reason',
    pg_catalog.btrim(p_reason),
    true
  );
  PERFORM pg_catalog.set_config(
    'moneybowl.investor_payment_event_id',
    v_payment_event.id::pg_catalog.text,
    true
  );

  UPDATE public.investor_subscriptions
  SET status = p_new_subscription_status
  WHERE id = v_subscription.id;

  RETURN QUERY SELECT
    v_payment_event.id,
    v_payment_event.investor_subscription_id,
    v_payment_event.applied_subscription_status,
    false;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

-- Own the complete plan_entitlements RLS contract in this migration so a
-- permissive policy cannot be combined with the intended restrictive rule.
DO $$
DECLARE
  v_policy pg_catalog.record;
BEGIN
  FOR v_policy IN
    SELECT policyname
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'plan_entitlements'
  LOOP
    EXECUTE pg_catalog.format(
      'DROP POLICY %I ON public.plan_entitlements',
      v_policy.policyname
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_read_plan_entitlement(
  p_plan_id pg_catalog.uuid
)
RETURNS pg_catalog.bool AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.workspace_billing AS billing
    WHERE billing.plan_id = p_plan_id
      AND billing.status IN ('trialing', 'active')
      AND public.has_active_workspace_membership(billing.workspace_id)
  ) OR EXISTS (
    SELECT 1
    FROM public.investor_subscriptions AS subscription
    WHERE subscription.plan_id = p_plan_id
      AND subscription.investor_profile_id = public.current_user_profile_id()
      AND subscription.status IN ('trialing', 'active')
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

CREATE POLICY plan_entitlements_billing_select
  ON public.plan_entitlements
  FOR SELECT
  TO authenticated
  USING (public.can_read_plan_entitlement(plan_id));

-- API roles receive only the read surfaces and server-side mutation entry
-- points required by this contract.
REVOKE ALL ON TABLE public.investor_subscriptions FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.investor_subscriptions TO authenticated, service_role;

REVOKE ALL ON TABLE public.payment_events FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.payment_events TO authenticated, service_role;

REVOKE ALL ON TABLE public.plan_entitlements FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.plan_entitlements TO authenticated, service_role;

REVOKE ALL ON TABLE public.investor_subscription_audit_logs FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.investor_subscription_audit_logs TO service_role;

REVOKE ALL ON FUNCTION public.enforce_investor_subscription_transition() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.audit_investor_subscription_transition() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.reject_investor_subscription_audit_mutation() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.can_read_plan_entitlement(pg_catalog.uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_read_plan_entitlement(pg_catalog.uuid)
  TO authenticated;

REVOKE ALL ON FUNCTION public.transition_investor_subscription(pg_catalog.uuid, pg_catalog.text, pg_catalog.text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.transition_investor_subscription(pg_catalog.uuid, pg_catalog.text, pg_catalog.text)
  TO service_role;

REVOKE ALL ON FUNCTION public.process_investor_subscription_payment(pg_catalog.uuid, pg_catalog.text, pg_catalog.numeric, pg_catalog.text, pg_catalog.text, pg_catalog.text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.process_investor_subscription_payment(pg_catalog.uuid, pg_catalog.text, pg_catalog.numeric, pg_catalog.text, pg_catalog.text, pg_catalog.text)
  TO service_role;

COMMIT;
