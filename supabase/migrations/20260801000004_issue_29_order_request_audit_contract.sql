-- Issue #29: Corrective hardening for canonical order request metadata and audit separation.

BEGIN;

ALTER TABLE public.order_requests
  ADD COLUMN IF NOT EXISTS initiated_by_profile_id pg_catalog.uuid REFERENCES public.profiles(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD COLUMN IF NOT EXISTS initiated_by_role pg_catalog.text,
  ADD COLUMN IF NOT EXISTS initiation_channel pg_catalog.text,
  ADD COLUMN IF NOT EXISTS reviewed_by_profile_id pg_catalog.uuid REFERENCES public.profiles(id) ON DELETE SET NULL ON UPDATE CASCADE;

CREATE OR REPLACE FUNCTION public.is_order_mfd_profile(
  p_workspace_id pg_catalog.uuid,
  p_profile_id pg_catalog.uuid
)
RETURNS pg_catalog.bool AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS wm
    WHERE wm.workspace_id = p_workspace_id
      AND wm.profile_id = p_profile_id
      AND wm.role = 'advisor'
      AND wm.status = 'active'
  )
  OR EXISTS (
    SELECT 1
    FROM public.workspaces AS w
    JOIN public.workspace_memberships AS wm
      ON wm.workspace_id = w.id
     AND wm.profile_id = p_profile_id
     AND wm.role = 'admin'
     AND wm.status = 'active'
    WHERE w.id = p_workspace_id
      AND w.owner_profile_id = p_profile_id
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.is_order_mfd_profile(pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_order_mfd_profile(pg_catalog.uuid, pg_catalog.uuid) FROM anon;
REVOKE ALL ON FUNCTION public.is_order_mfd_profile(pg_catalog.uuid, pg_catalog.uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.is_order_mfd_profile(pg_catalog.uuid, pg_catalog.uuid) FROM service_role;

UPDATE public.order_requests AS o
SET reviewed_by_profile_id = o.reviewed_by
WHERE o.reviewed_by_profile_id IS NULL
  AND o.reviewed_by IS NOT NULL;

DO $$
DECLARE
  v_missing_count pg_catalog.int8;
  v_invalid_combo_count pg_catalog.int8;
  v_reviewer_mismatch_count pg_catalog.int8;
BEGIN
  SELECT pg_catalog.count(*) INTO v_reviewer_mismatch_count
  FROM public.order_requests AS o
  WHERE o.reviewed_by IS NOT NULL
    AND o.reviewed_by_profile_id IS NOT NULL
    AND o.reviewed_by <> o.reviewed_by_profile_id;

  IF v_reviewer_mismatch_count > 0 THEN
    RAISE EXCEPTION 'reviewer_profile_mismatch_existing_rows: % offending rows', v_reviewer_mismatch_count;
  END IF;

  SELECT pg_catalog.count(*) INTO v_missing_count
  FROM public.order_requests AS o
  WHERE o.workspace_id IS NULL
     OR o.investor_profile_id IS NULL
     OR o.initiated_by_profile_id IS NULL
     OR o.initiated_by_role IS NULL
     OR o.initiation_channel IS NULL;

  IF v_missing_count > 0 THEN
    RAISE EXCEPTION 'order_request_initiator_unresolved_existing_rows: % offending rows', v_missing_count;
  END IF;

  SELECT pg_catalog.count(*) INTO v_invalid_combo_count
  FROM public.order_requests AS o
  WHERE NOT (
    (o.initiated_by_role = 'investor' AND o.initiation_channel = 'investor_portal')
    OR (o.initiated_by_role = 'advisor' AND o.initiation_channel = 'advisor_portal')
  );

  IF v_invalid_combo_count > 0 THEN
    RAISE EXCEPTION 'invalid_order_initiation_metadata: % offending rows', v_invalid_combo_count;
  END IF;
END
$$;

ALTER TABLE public.order_requests
  ALTER COLUMN initiated_by_profile_id SET NOT NULL,
  ALTER COLUMN initiated_by_role SET NOT NULL,
  ALTER COLUMN initiation_channel SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = 'public.order_requests'::pg_catalog.regclass
      AND c.conname = 'order_requests_initiated_by_role_check'
  ) THEN
    ALTER TABLE public.order_requests
      ADD CONSTRAINT order_requests_initiated_by_role_check
      CHECK (initiated_by_role IN ('investor', 'advisor'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = 'public.order_requests'::pg_catalog.regclass
      AND c.conname = 'order_requests_initiation_channel_check'
  ) THEN
    ALTER TABLE public.order_requests
      ADD CONSTRAINT order_requests_initiation_channel_check
      CHECK (initiation_channel IN ('investor_portal', 'advisor_portal'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = 'public.order_requests'::pg_catalog.regclass
      AND c.conname = 'order_requests_role_channel_match'
  ) THEN
    ALTER TABLE public.order_requests
      ADD CONSTRAINT order_requests_role_channel_match
      CHECK (
        (initiated_by_role = 'investor' AND initiation_channel = 'investor_portal')
        OR (initiated_by_role = 'advisor' AND initiation_channel = 'advisor_portal')
      );
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION public.validate_order_request_canonical_contract()
RETURNS trigger AS $$
DECLARE
  v_caller_user_id pg_catalog.uuid;
  v_caller_profile_id pg_catalog.uuid;
  v_is_service_role pg_catalog.bool;
BEGIN
  IF NEW.reviewed_by IS NOT NULL
     AND NEW.reviewed_by_profile_id IS NOT NULL
     AND NEW.reviewed_by <> NEW.reviewed_by_profile_id THEN
    RAISE EXCEPTION 'reviewer_profile_mismatch';
  END IF;

  IF NEW.reviewed_by_profile_id IS NULL AND NEW.reviewed_by IS NOT NULL THEN
    NEW.reviewed_by_profile_id := NEW.reviewed_by;
  ELSIF NEW.reviewed_by IS NULL AND NEW.reviewed_by_profile_id IS NOT NULL THEN
    NEW.reviewed_by := NEW.reviewed_by_profile_id;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'draft'::public.order_status THEN
      RETURN NEW;
    END IF;

    v_caller_user_id := auth.uid();
    v_is_service_role := COALESCE(auth.role(), '') = 'service_role';

    IF v_caller_user_id IS NOT NULL THEN
      v_caller_profile_id := public.current_user_profile_id();

      IF v_caller_profile_id IS NULL THEN
        RAISE EXCEPTION 'profile_resolution_failed';
      END IF;

      IF NEW.initiated_by_profile_id IS NULL THEN
        NEW.initiated_by_profile_id := v_caller_profile_id;
      ELSIF NEW.initiated_by_profile_id <> v_caller_profile_id THEN
        RAISE EXCEPTION 'initiator_profile_mismatch';
      END IF;

      IF public.is_platform_admin() THEN
        RAISE EXCEPTION 'not_authorized';
      END IF;

      IF v_caller_profile_id = NEW.investor_profile_id THEN
        IF NEW.initiated_by_role IS NULL THEN
          NEW.initiated_by_role := 'investor';
        ELSIF NEW.initiated_by_role <> 'investor' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;

        IF NEW.initiation_channel IS NULL THEN
          NEW.initiation_channel := 'investor_portal';
        ELSIF NEW.initiation_channel <> 'investor_portal' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;
      ELSIF public.is_order_mfd_profile(NEW.workspace_id, v_caller_profile_id) THEN
        IF NEW.initiated_by_role IS NULL THEN
          NEW.initiated_by_role := 'advisor';
        ELSIF NEW.initiated_by_role <> 'advisor' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;

        IF NEW.initiation_channel IS NULL THEN
          NEW.initiation_channel := 'advisor_portal';
        ELSIF NEW.initiation_channel <> 'advisor_portal' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;
      ELSE
        RAISE EXCEPTION 'order_initiator_not_authorized';
      END IF;
    ELSIF v_is_service_role THEN
      IF NEW.initiated_by_profile_id IS NULL
         OR NEW.initiated_by_role IS NULL
         OR NEW.initiation_channel IS NULL THEN
        RAISE EXCEPTION 'order_request_canonical_metadata_missing';
      END IF;
    ELSE
      RAISE EXCEPTION 'profile_resolution_failed';
    END IF;
  ELSE
    IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
       OR NEW.investor_profile_id IS DISTINCT FROM OLD.investor_profile_id
       OR NEW.initiated_by_profile_id IS DISTINCT FROM OLD.initiated_by_profile_id
       OR NEW.initiated_by_role IS DISTINCT FROM OLD.initiated_by_role
       OR NEW.initiation_channel IS DISTINCT FROM OLD.initiation_channel THEN
      RAISE EXCEPTION 'order_initiation_metadata_immutable';
    END IF;
  END IF;

  IF NEW.workspace_id IS NULL
     OR NEW.investor_profile_id IS NULL
     OR NEW.initiated_by_profile_id IS NULL
     OR NEW.initiated_by_role IS NULL
     OR NEW.initiation_channel IS NULL THEN
    RAISE EXCEPTION 'order_request_canonical_metadata_missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS wm
    WHERE wm.workspace_id = NEW.workspace_id
      AND wm.profile_id = NEW.investor_profile_id
      AND wm.role = 'investor'
      AND wm.status = 'active'
  ) THEN
    RAISE EXCEPTION 'investor_workspace_relationship_required';
  END IF;

  IF NEW.initiated_by_role = 'investor' THEN
    IF NEW.initiation_channel <> 'investor_portal' THEN
      RAISE EXCEPTION 'invalid_order_initiation_metadata';
    END IF;

    IF NEW.initiated_by_profile_id <> NEW.investor_profile_id THEN
      RAISE EXCEPTION 'investor_initiator_mismatch';
    END IF;
  ELSIF NEW.initiated_by_role = 'advisor' THEN
    IF NEW.initiation_channel <> 'advisor_portal' THEN
      RAISE EXCEPTION 'invalid_order_initiation_metadata';
    END IF;

    IF NOT public.is_order_mfd_profile(NEW.workspace_id, NEW.initiated_by_profile_id) THEN
      RAISE EXCEPTION 'advisor_workspace_relationship_required';
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_order_initiation_metadata';
  END IF;

  IF NEW.reviewed_by_profile_id IS NOT NULL THEN
    IF NEW.reviewed_at IS NULL THEN
      NEW.reviewed_at := pg_catalog.now();
    END IF;

    IF NOT public.is_order_mfd_profile(NEW.workspace_id, NEW.reviewed_by_profile_id) THEN
      RAISE EXCEPTION 'reviewer_workspace_relationship_required';
    END IF;
  ELSIF NEW.reviewed_at IS NOT NULL THEN
    RAISE EXCEPTION 'reviewer_profile_required';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS validate_order_request_canonical_contract_trigger ON public.order_requests;
CREATE TRIGGER validate_order_request_canonical_contract_trigger
  BEFORE INSERT OR UPDATE ON public.order_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_order_request_canonical_contract();

CREATE OR REPLACE FUNCTION public.log_order_request_initiation_audit()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    event_type,
    target_type,
    entity_type,
    target_id,
    entity_id,
    new_state,
    payload
  ) VALUES (
    NEW.workspace_id,
    NEW.initiated_by_profile_id,
    NEW.initiated_by_profile_id,
    NEW.initiated_by_role,
    'order.initiated',
    'order.initiated',
    'order_requests',
    'order_requests',
    NEW.id,
    NEW.id,
    NEW.status::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'workspace_id', NEW.workspace_id,
      'investor_profile_id', NEW.investor_profile_id,
      'initiated_by_profile_id', NEW.initiated_by_profile_id,
      'initiated_by_role', NEW.initiated_by_role,
      'initiation_channel', NEW.initiation_channel,
      'status', NEW.status
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS order_request_initiation_audit_trigger ON public.order_requests;
CREATE TRIGGER order_request_initiation_audit_trigger
  AFTER INSERT ON public.order_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.log_order_request_initiation_audit();

CREATE OR REPLACE FUNCTION public.qualify_order(
  p_order_id pg_catalog.uuid,
  p_decision public.order_status,
  p_rejection_reason pg_catalog.text DEFAULT null
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id pg_catalog.uuid;
  v_investor_profile_id pg_catalog.uuid;
  v_initiated_by_profile_id pg_catalog.uuid;
  v_current_status public.order_status;
  v_current_profile_id pg_catalog.uuid;
  v_order public.order_requests;
BEGIN
  SELECT
    o.workspace_id,
    o.investor_profile_id,
    o.initiated_by_profile_id,
    o.status
  INTO
    v_workspace_id,
    v_investor_profile_id,
    v_initiated_by_profile_id,
    v_current_status
  FROM public.order_requests AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_current_status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_qualification_state';
  END IF;

  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'invalid_qualification_decision';
  END IF;

  v_current_profile_id := public.current_user_profile_id();
  IF v_current_profile_id IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  IF public.is_platform_admin() OR NOT public.is_order_mfd_profile(v_workspace_id, v_current_profile_id) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  UPDATE public.order_requests AS o
  SET status = p_decision,
      reviewed_by = v_current_profile_id,
      reviewed_by_profile_id = v_current_profile_id,
      reviewed_at = pg_catalog.now(),
      rejection_reason = p_rejection_reason,
      updated_at = pg_catalog.now()
  WHERE o.id = p_order_id
  RETURNING * INTO v_order;

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    event_type,
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
    'order.manual_qualification',
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    v_current_status::pg_catalog.text,
    p_decision::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'decision', p_decision,
      'rejection_reason', p_rejection_reason,
      'investor_profile_id', v_investor_profile_id,
      'initiated_by_profile_id', v_initiated_by_profile_id,
      'reviewed_by_profile_id', v_current_profile_id
    )
  );

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    event_type,
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
    'advisor',
    CASE WHEN p_decision = 'approved' THEN 'order.approved' ELSE 'order.rejected' END,
    CASE WHEN p_decision = 'approved' THEN 'order.approved' ELSE 'order.rejected' END,
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    p_rejection_reason,
    v_current_status::pg_catalog.text,
    p_decision::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'decision', p_decision,
      'reason', p_rejection_reason,
      'investor_profile_id', v_investor_profile_id,
      'initiated_by_profile_id', v_initiated_by_profile_id,
      'reviewed_by_profile_id', v_current_profile_id
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) TO authenticated;

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
  v_initiated_by_profile_id pg_catalog.uuid;
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
  SELECT
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      status,
      auto_approval_correlation_id,
      triggered_rule_id,
      triggered_rule_version
  INTO
      v_workspace_id,
      v_investor_profile_id,
      v_initiated_by_profile_id,
      v_status,
      v_existing_correlation_id,
      v_existing_rule_id,
      v_existing_rule_version
  FROM public.order_requests
  WHERE id = p_order_id
  FOR UPDATE;

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

  IF v_status <> 'pending_qualification' THEN
    RAISE EXCEPTION 'stale_order_state';
  END IF;

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

  IF p_decision = 'auto_approved' THEN
    IF p_rule_id IS NULL OR p_rule_version IS NULL THEN
      RAISE EXCEPTION 'rule_not_found';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.auto_approval_rules
      WHERE id = p_rule_id
    ) THEN
      RAISE EXCEPTION 'rule_not_found';
    END IF;

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

  UPDATE public.order_requests
  SET status = p_decision,
      triggered_rule_id = p_rule_id,
      triggered_rule_version = p_rule_version,
      auto_approval_correlation_id = p_correlation_id,
      updated_at = pg_catalog.now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  UPDATE public.event_outbox
  SET status = 'completed',
      updated_at = pg_catalog.now()
  WHERE id = p_correlation_id;

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    event_type,
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
    null,
    null,
    'system',
    'order.auto_qualified',
    'order.auto_approval_evaluated',
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
      'correlation_id', p_correlation_id,
      'investor_profile_id', v_investor_profile_id,
      'initiated_by_profile_id', v_initiated_by_profile_id,
      'claimed_by_profile_id', v_claimed_by,
      'claimed_at', v_claimed_at
    )
  );

  IF p_decision = 'auto_approved' THEN
    INSERT INTO public.workspace_audit_logs (
      workspace_id,
      actor_id,
      actor_profile_id,
      actor_type,
      action,
      event_type,
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
      null,
      null,
      'system',
      'order.approved',
      'order.approved',
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
        'correlation_id', p_correlation_id,
        'investor_profile_id', v_investor_profile_id,
        'initiated_by_profile_id', v_initiated_by_profile_id,
        'claimed_by_profile_id', v_claimed_by,
        'claimed_at', v_claimed_at
      )
    );
  END IF;

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid) TO service_role;

COMMIT;
