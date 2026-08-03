-- Issue #33 review hardening: gateway-safe worker lease fencing and
-- authoritative rule-evaluation context.

ALTER TABLE public.event_outbox
  ADD COLUMN IF NOT EXISTS claim_token pg_catalog.uuid,
  ADD COLUMN IF NOT EXISTS claim_expires_at pg_catalog.timestamptz;

ALTER TABLE public.auto_approval_rules
  ADD COLUMN IF NOT EXISTS effective_to pg_catalog.timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conname = 'auto_approval_rules_effective_window_check'
      AND conrelid = 'public.auto_approval_rules'::pg_catalog.regclass
  ) THEN
    ALTER TABLE public.auto_approval_rules
      ADD CONSTRAINT auto_approval_rules_effective_window_check
      CHECK (effective_to IS NULL OR effective_to > effective_from);
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.workspace_trusted_investors (
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  investor_profile_id pg_catalog.uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  trusted_by_profile_id pg_catalog.uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active pg_catalog.bool NOT NULL DEFAULT true,
  trusted_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  trust_reason pg_catalog.text,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  PRIMARY KEY (workspace_id, investor_profile_id)
);

ALTER TABLE public.workspace_trusted_investors ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.workspace_trusted_investors FROM PUBLIC;
REVOKE ALL ON TABLE public.workspace_trusted_investors FROM anon;
REVOKE ALL ON TABLE public.workspace_trusted_investors FROM authenticated;
REVOKE ALL ON TABLE public.workspace_trusted_investors FROM service_role;
GRANT SELECT ON TABLE public.workspace_trusted_investors TO service_role;

GRANT SELECT ON TABLE public.mutual_funds TO service_role;

CREATE OR REPLACE FUNCTION public.claim_order_auto_approval_event(
  p_event_outbox_id pg_catalog.uuid DEFAULT NULL,
  p_max_attempts pg_catalog.int4 DEFAULT 3,
  p_lease_seconds pg_catalog.int4 DEFAULT 120
)
RETURNS TABLE (
  event_outbox_id pg_catalog.uuid,
  order_id pg_catalog.uuid,
  payload pg_catalog.jsonb,
  correlation_id pg_catalog.uuid,
  attempt pg_catalog.int4,
  claim_state pg_catalog.text,
  event_status pg_catalog.text,
  event_type pg_catalog.text,
  entity_type pg_catalog.text,
  claim_token pg_catalog.uuid,
  claim_expires_at pg_catalog.timestamptz
) AS $$
DECLARE
  v_event public.event_outbox;
  v_token pg_catalog.uuid;
BEGIN
  IF p_max_attempts IS NULL OR p_max_attempts < 1 OR p_max_attempts > 10 THEN
    RAISE EXCEPTION 'invalid_max_attempts';
  END IF;
  IF p_lease_seconds IS NULL OR p_lease_seconds < 15 OR p_lease_seconds > 3600 THEN
    RAISE EXCEPTION 'invalid_lease_seconds';
  END IF;

  IF p_event_outbox_id IS NOT NULL THEN
    SELECT *
    INTO v_event
    FROM public.event_outbox AS event
    WHERE event.id = p_event_outbox_id
    FOR UPDATE;

    IF v_event.id IS NULL THEN
      RETURN QUERY SELECT NULL::pg_catalog.uuid, NULL::pg_catalog.uuid, NULL::pg_catalog.jsonb, NULL::pg_catalog.uuid, 0::pg_catalog.int4, 'not_found'::pg_catalog.text, NULL::pg_catalog.text, NULL::pg_catalog.text, NULL::pg_catalog.text, NULL::pg_catalog.uuid, NULL::pg_catalog.timestamptz;
      RETURN;
    END IF;

    IF v_event.event_type <> 'order.created' OR v_event.entity_type <> 'order_request' OR v_event.entity_id IS NULL THEN
      RETURN QUERY SELECT v_event.id, v_event.entity_id, v_event.payload, v_event.id, v_event.retry_count, 'invalid_event'::pg_catalog.text, v_event.status, v_event.event_type, v_event.entity_type, v_event.claim_token, v_event.claim_expires_at;
      RETURN;
    END IF;

    IF v_event.status = 'completed' THEN
      RETURN QUERY SELECT v_event.id, v_event.entity_id, v_event.payload, v_event.id, v_event.retry_count, 'completed_replay'::pg_catalog.text, v_event.status, v_event.event_type, v_event.entity_type, v_event.claim_token, v_event.claim_expires_at;
      RETURN;
    END IF;

    IF v_event.status = 'processing' AND v_event.claim_expires_at > pg_catalog.now() THEN
      RETURN QUERY SELECT v_event.id, v_event.entity_id, v_event.payload, v_event.id, v_event.retry_count, 'active_in_progress'::pg_catalog.text, v_event.status, v_event.event_type, v_event.entity_type, v_event.claim_token, v_event.claim_expires_at;
      RETURN;
    END IF;

    IF v_event.retry_count >= p_max_attempts THEN
      RETURN QUERY SELECT v_event.id, v_event.entity_id, v_event.payload, v_event.id, v_event.retry_count, 'terminal_failed'::pg_catalog.text, v_event.status, v_event.event_type, v_event.entity_type, v_event.claim_token, v_event.claim_expires_at;
      RETURN;
    END IF;

    v_token := pg_catalog.gen_random_uuid();
    UPDATE public.event_outbox AS event
    SET status = 'processing',
        retry_count = event.retry_count + 1,
        claimed_at = pg_catalog.now(),
        claimed_by = v_token,
        claim_token = v_token,
        claim_expires_at = pg_catalog.now() + (p_lease_seconds::pg_catalog.text || ' seconds')::pg_catalog.interval,
        error_message = NULL,
        updated_at = pg_catalog.now()
    WHERE event.id = p_event_outbox_id
      AND event.event_type = 'order.created'
      AND event.entity_type = 'order_request'
      AND event.entity_id IS NOT NULL
      AND (
        event.status IN ('pending', 'failed')
        OR (event.status = 'processing' AND COALESCE(event.claim_expires_at, '-infinity'::pg_catalog.timestamptz) <= pg_catalog.now())
      )
      AND event.retry_count < p_max_attempts
    RETURNING *
    INTO v_event;

    IF v_event.id IS NULL THEN
      RETURN QUERY SELECT p_event_outbox_id, NULL::pg_catalog.uuid, NULL::pg_catalog.jsonb, p_event_outbox_id, 0::pg_catalog.int4, 'active_in_progress'::pg_catalog.text, NULL::pg_catalog.text, NULL::pg_catalog.text, NULL::pg_catalog.text, NULL::pg_catalog.uuid, NULL::pg_catalog.timestamptz;
      RETURN;
    END IF;

    RETURN QUERY SELECT v_event.id, v_event.entity_id, v_event.payload, v_event.id, v_event.retry_count, CASE WHEN v_event.retry_count = 1 THEN 'newly_claimed' ELSE 'retry_claimed' END, v_event.status, v_event.event_type, v_event.entity_type, v_event.claim_token, v_event.claim_expires_at;
    RETURN;
  END IF;

  WITH candidate AS (
    SELECT event.id, pg_catalog.gen_random_uuid() AS token
    FROM public.event_outbox AS event
    WHERE event.event_type = 'order.created'
      AND event.entity_type = 'order_request'
      AND event.entity_id IS NOT NULL
      AND event.retry_count < p_max_attempts
      AND (
        event.status IN ('pending', 'failed')
        OR (event.status = 'processing' AND COALESCE(event.claim_expires_at, '-infinity'::pg_catalog.timestamptz) <= pg_catalog.now())
      )
    ORDER BY event.created_at, event.id
    FOR UPDATE SKIP LOCKED
    LIMIT 1
  )
  UPDATE public.event_outbox AS event
  SET status = 'processing',
      retry_count = event.retry_count + 1,
      claimed_at = pg_catalog.now(),
      claimed_by = candidate.token,
      claim_token = candidate.token,
      claim_expires_at = pg_catalog.now() + (p_lease_seconds::pg_catalog.text || ' seconds')::pg_catalog.interval,
      error_message = NULL,
      updated_at = pg_catalog.now()
  FROM candidate
  WHERE event.id = candidate.id
  RETURNING event.*
  INTO v_event;

  IF v_event.id IS NULL THEN
    RETURN QUERY SELECT NULL::pg_catalog.uuid, NULL::pg_catalog.uuid, NULL::pg_catalog.jsonb, NULL::pg_catalog.uuid, 0::pg_catalog.int4, 'no_event'::pg_catalog.text, NULL::pg_catalog.text, NULL::pg_catalog.text, NULL::pg_catalog.text, NULL::pg_catalog.uuid, NULL::pg_catalog.timestamptz;
    RETURN;
  END IF;

  RETURN QUERY SELECT v_event.id, v_event.entity_id, v_event.payload, v_event.id, v_event.retry_count, CASE WHEN v_event.retry_count = 1 THEN 'newly_claimed' ELSE 'retry_claimed' END, v_event.status, v_event.event_type, v_event.entity_type, v_event.claim_token, v_event.claim_expires_at;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.record_order_auto_approval_claim_failure(
  p_event_outbox_id pg_catalog.uuid,
  p_claim_token pg_catalog.uuid,
  p_error_code pg_catalog.text,
  p_error_message pg_catalog.text DEFAULT NULL,
  p_retryable pg_catalog.bool DEFAULT true,
  p_max_attempts pg_catalog.int4 DEFAULT 3
)
RETURNS public.event_outbox AS $$
DECLARE
  v_event public.event_outbox;
  v_terminal pg_catalog.bool;
BEGIN
  IF p_event_outbox_id IS NULL THEN
    RAISE EXCEPTION 'event_outbox_id_required';
  END IF;
  IF p_claim_token IS NULL THEN
    RAISE EXCEPTION 'claim_token_required';
  END IF;
  IF p_error_code IS NULL OR pg_catalog.btrim(p_error_code) = '' THEN
    RAISE EXCEPTION 'error_code_required';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts < 1 OR p_max_attempts > 10 THEN
    RAISE EXCEPTION 'invalid_max_attempts';
  END IF;

  SELECT *
  INTO v_event
  FROM public.event_outbox AS event
  WHERE event.id = p_event_outbox_id
  FOR UPDATE;

  IF v_event.id IS NULL THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;
  IF v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token THEN
    RAISE EXCEPTION 'claim_not_owned';
  END IF;

  v_terminal := NOT COALESCE(p_retryable, true) OR v_event.retry_count >= p_max_attempts;

  UPDATE public.event_outbox AS event
  SET status = 'failed',
      retry_count = CASE WHEN v_terminal THEN GREATEST(event.retry_count, p_max_attempts) ELSE event.retry_count END,
      error_message = pg_catalog.left(p_error_code || COALESCE(': ' || p_error_message, ''), 1000),
      updated_at = pg_catalog.now()
  WHERE event.id = p_event_outbox_id
  RETURNING *
  INTO v_event;

  RETURN v_event;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.apply_auto_approval_decision(
  p_order_id pg_catalog.uuid,
  p_decision public.order_status,
  p_rule_id pg_catalog.uuid,
  p_rule_version pg_catalog.int4,
  p_correlation_id pg_catalog.uuid,
  p_claim_token pg_catalog.uuid
)
RETURNS public.order_requests AS $$
DECLARE
  v_status public.order_status;
  v_existing_correlation_id pg_catalog.uuid;
  v_existing_rule_id pg_catalog.uuid;
  v_existing_rule_version pg_catalog.int4;
  v_event public.event_outbox;
  v_order public.order_requests;
BEGIN
  SELECT status, auto_approval_correlation_id, triggered_rule_id, triggered_rule_version
  INTO v_status, v_existing_correlation_id, v_existing_rule_id, v_existing_rule_version
  FROM public.order_requests
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_existing_correlation_id = p_correlation_id THEN
    IF p_decision <> v_status OR p_rule_id IS DISTINCT FROM v_existing_rule_id OR p_rule_version IS DISTINCT FROM v_existing_rule_version THEN
      RAISE EXCEPTION 'idempotency_conflict';
    END IF;
    SELECT * INTO v_order FROM public.order_requests WHERE id = p_order_id;
    RETURN v_order;
  END IF;

  IF p_claim_token IS NULL THEN
    RAISE EXCEPTION 'claim_token_required';
  END IF;

  SELECT *
  INTO v_event
  FROM public.event_outbox AS event
  WHERE event.id = p_correlation_id
  FOR UPDATE;

  IF v_event.id IS NULL THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;
  IF v_event.event_type <> 'order.created' THEN
    RAISE EXCEPTION 'invalid_event_type';
  END IF;
  IF v_event.entity_type <> 'order_request' THEN
    RAISE EXCEPTION 'invalid_event_entity_type';
  END IF;
  IF v_event.entity_id <> p_order_id THEN
    RAISE EXCEPTION 'event_order_mismatch';
  END IF;
  IF v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token THEN
    RAISE EXCEPTION 'claim_not_owned';
  END IF;

  RETURN public.apply_auto_approval_decision(
    p_order_id,
    p_decision,
    p_rule_id,
    p_rule_version,
    p_correlation_id
  );
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4) TO service_role;

REVOKE ALL ON FUNCTION public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.record_order_auto_approval_claim_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.int4) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_order_auto_approval_claim_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.int4) TO service_role;

REVOKE ALL ON FUNCTION public.record_order_auto_approval_event_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.int4) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid, pg_catalog.uuid) TO service_role;

REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid) FROM PUBLIC, anon, authenticated, service_role;
