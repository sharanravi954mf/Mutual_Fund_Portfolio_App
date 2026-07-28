-- Issue #28: Harden order lifecycle enums and cancel_order RPC contract.

BEGIN;

ALTER TABLE public.order_requests
  ADD COLUMN IF NOT EXISTS cancellation_reason pg_catalog.text,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamp with time zone;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint c
    WHERE c.conname = 'order_requests_status_not_draft'
      AND c.conrelid = 'public.order_requests'::pg_catalog.regclass
  ) THEN
    ALTER TABLE public.order_requests
      ADD CONSTRAINT order_requests_status_not_draft
      CHECK (status <> 'draft'::public.order_status);
  END IF;
END
$$;

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
  v_cancellation_reason pg_catalog.text;
  v_order public.order_requests;
BEGIN
  SELECT
    o.workspace_id,
    o.investor_profile_id,
    o.status
  INTO
    v_workspace_id,
    v_investor_profile_id,
    v_current_status
  FROM public.order_requests AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_current_profile_id := public.current_user_profile_id();
  IF v_current_profile_id IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  IF public.is_platform_admin() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF v_investor_profile_id = v_current_profile_id THEN
    -- Investor-owner cancellation path.
  ELSIF EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS wm
    WHERE wm.workspace_id = v_workspace_id
      AND wm.profile_id = v_current_profile_id
      AND wm.role IN ('advisor', 'admin', 'workspace_owner')
      AND wm.status = 'active'
  ) THEN
    -- Authorised MFD-side cancellation path.
  ELSE
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF v_current_status = 'cancelled' THEN
    RAISE EXCEPTION 'already_cancelled';
  END IF;

  IF v_current_status NOT IN ('pending_qualification', 'pending_review') THEN
    RAISE EXCEPTION 'invalid_cancellation_state';
  END IF;

  v_cancellation_reason := COALESCE(p_reason, 'Cancelled by user');

  UPDATE public.order_requests AS o
  SET status = 'cancelled',
      rejection_reason = v_cancellation_reason,
      cancellation_reason = v_cancellation_reason,
      cancelled_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  WHERE o.id = p_order_id
  RETURNING * INTO v_order;

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
    CASE
      WHEN v_investor_profile_id = v_current_profile_id THEN 'investor'
      ELSE 'advisor'
    END,
    'order.cancelled',
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    v_cancellation_reason,
    v_current_status::pg_catalog.text,
    'cancelled',
    pg_catalog.jsonb_build_object(
      'reason', v_cancellation_reason,
      'previous_status', v_current_status,
      'new_status', 'cancelled',
      'investor_profile_id', v_investor_profile_id
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.cancel_order(pg_catalog.uuid, pg_catalog.text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_order(pg_catalog.uuid, pg_catalog.text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_order(pg_catalog.uuid, pg_catalog.text) TO authenticated;

COMMIT;
