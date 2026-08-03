-- Issue #33: deterministic claim/retry support for order-auto-approval-worker.

CREATE OR REPLACE FUNCTION public.claim_order_auto_approval_event(
  p_worker_id pg_catalog.uuid,
  p_event_outbox_id pg_catalog.uuid DEFAULT NULL,
  p_max_attempts pg_catalog.int4 DEFAULT 3
)
RETURNS TABLE (
  event_outbox_id pg_catalog.uuid,
  order_id pg_catalog.uuid,
  payload pg_catalog.jsonb,
  correlation_id pg_catalog.uuid,
  attempt pg_catalog.int4,
  claim_state pg_catalog.text,
  event_status pg_catalog.text,
  event_type pg_catalog.text
) AS $$
DECLARE
  v_event public.event_outbox;
BEGIN
  IF p_worker_id IS NULL THEN
    RAISE EXCEPTION 'worker_id_required';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts < 1 THEN
    RAISE EXCEPTION 'invalid_max_attempts';
  END IF;

  IF p_event_outbox_id IS NOT NULL THEN
    SELECT *
    INTO v_event
    FROM public.event_outbox AS event
    WHERE event.id = p_event_outbox_id
    FOR UPDATE;

    IF v_event.id IS NULL THEN
      RETURN QUERY SELECT
        NULL::pg_catalog.uuid,
        NULL::pg_catalog.uuid,
        NULL::pg_catalog.jsonb,
        NULL::pg_catalog.uuid,
        0::pg_catalog.int4,
        'not_found'::pg_catalog.text,
        NULL::pg_catalog.text,
        NULL::pg_catalog.text;
      RETURN;
    END IF;

    IF v_event.status = 'completed' THEN
      RETURN QUERY SELECT
        v_event.id,
        v_event.entity_id,
        v_event.payload,
        v_event.id,
        v_event.retry_count,
        'completed_replay'::pg_catalog.text,
        v_event.status,
        v_event.event_type;
      RETURN;
    END IF;

    IF v_event.status = 'processing' THEN
      RETURN QUERY SELECT
        v_event.id,
        v_event.entity_id,
        v_event.payload,
        v_event.id,
        v_event.retry_count,
        'active_in_progress'::pg_catalog.text,
        v_event.status,
        v_event.event_type;
      RETURN;
    END IF;

    IF v_event.retry_count >= p_max_attempts THEN
      RETURN QUERY SELECT
        v_event.id,
        v_event.entity_id,
        v_event.payload,
        v_event.id,
        v_event.retry_count,
        'terminal_failed'::pg_catalog.text,
        v_event.status,
        v_event.event_type;
      RETURN;
    END IF;

    UPDATE public.event_outbox AS event
    SET status = 'processing',
        retry_count = event.retry_count + 1,
        claimed_at = pg_catalog.now(),
        claimed_by = p_worker_id,
        error_message = NULL,
        updated_at = pg_catalog.now()
    WHERE event.id = p_event_outbox_id
      AND event.status IN ('pending', 'failed')
      AND event.retry_count < p_max_attempts
    RETURNING *
    INTO v_event;

    IF v_event.id IS NULL THEN
      RETURN QUERY SELECT
        p_event_outbox_id,
        NULL::pg_catalog.uuid,
        NULL::pg_catalog.jsonb,
        p_event_outbox_id,
        0::pg_catalog.int4,
        'active_in_progress'::pg_catalog.text,
        NULL::pg_catalog.text,
        NULL::pg_catalog.text;
      RETURN;
    END IF;

    RETURN QUERY SELECT
      v_event.id,
      v_event.entity_id,
      v_event.payload,
      v_event.id,
      v_event.retry_count,
      CASE WHEN v_event.retry_count = 1 THEN 'newly_claimed' ELSE 'retry_claimed' END,
      v_event.status,
      v_event.event_type;
    RETURN;
  END IF;

  WITH candidate AS (
    SELECT event.id
    FROM public.event_outbox AS event
    WHERE event.event_type = 'order.created'
      AND event.status IN ('pending', 'failed')
      AND event.retry_count < p_max_attempts
    ORDER BY event.created_at, event.id
    FOR UPDATE SKIP LOCKED
    LIMIT 1
  )
  UPDATE public.event_outbox AS event
  SET status = 'processing',
      retry_count = event.retry_count + 1,
      claimed_at = pg_catalog.now(),
      claimed_by = p_worker_id,
      error_message = NULL,
      updated_at = pg_catalog.now()
  FROM candidate
  WHERE event.id = candidate.id
  RETURNING event.*
  INTO v_event;

  IF v_event.id IS NULL THEN
    RETURN QUERY SELECT
      NULL::pg_catalog.uuid,
      NULL::pg_catalog.uuid,
      NULL::pg_catalog.jsonb,
      NULL::pg_catalog.uuid,
      0::pg_catalog.int4,
      'no_event'::pg_catalog.text,
      NULL::pg_catalog.text,
      NULL::pg_catalog.text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    v_event.id,
    v_event.entity_id,
    v_event.payload,
    v_event.id,
    v_event.retry_count,
    CASE WHEN v_event.retry_count = 1 THEN 'newly_claimed' ELSE 'retry_claimed' END,
    v_event.status,
    v_event.event_type;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.record_order_auto_approval_event_failure(
  p_event_outbox_id pg_catalog.uuid,
  p_worker_id pg_catalog.uuid,
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
  IF p_worker_id IS NULL THEN
    RAISE EXCEPTION 'worker_id_required';
  END IF;
  IF p_error_code IS NULL OR pg_catalog.btrim(p_error_code) = '' THEN
    RAISE EXCEPTION 'error_code_required';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts < 1 THEN
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
  IF v_event.status <> 'processing' OR v_event.claimed_at IS NULL OR v_event.claimed_by IS DISTINCT FROM p_worker_id THEN
    RAISE EXCEPTION 'event_not_claimed';
  END IF;

  v_terminal := NOT COALESCE(p_retryable, true) OR v_event.retry_count >= p_max_attempts;

  UPDATE public.event_outbox AS event
  SET status = 'failed',
      retry_count = CASE
        WHEN v_terminal THEN GREATEST(event.retry_count, p_max_attempts)
        ELSE event.retry_count
      END,
      error_message = pg_catalog.left(
        p_error_code || COALESCE(': ' || p_error_message, ''),
        1000
      ),
      updated_at = pg_catalog.now()
  WHERE event.id = p_event_outbox_id
  RETURNING *
  INTO v_event;

  RETURN v_event;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4) FROM anon;
REVOKE ALL ON FUNCTION public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4) FROM authenticated;
REVOKE ALL ON FUNCTION public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4) FROM service_role;
GRANT EXECUTE ON FUNCTION public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4) TO service_role;

REVOKE ALL ON FUNCTION public.record_order_auto_approval_event_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.int4) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_order_auto_approval_event_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.int4) FROM anon;
REVOKE ALL ON FUNCTION public.record_order_auto_approval_event_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.int4) FROM authenticated;
REVOKE ALL ON FUNCTION public.record_order_auto_approval_event_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.int4) FROM service_role;
GRANT EXECUTE ON FUNCTION public.record_order_auto_approval_event_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.int4) TO service_role;
