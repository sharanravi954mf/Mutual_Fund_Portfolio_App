-- Test Suite: Issue #33 order auto-approval worker database contract.

BEGIN;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('a3310000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'issue33-owner@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('a3310000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'issue33-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now());

UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id = 'a3310000-0000-4000-8000-000000000001';

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id = 'a3310000-0000-4000-8000-000000000002';

UPDATE public.profiles
SET id = 'a3320000-0000-4000-8000-000000000001',
    role = 'advisor',
    full_name = 'Issue 33 Owner'
WHERE user_id = 'a3310000-0000-4000-8000-000000000001';

UPDATE public.profiles
SET id = 'a3320000-0000-4000-8000-000000000002',
    role = 'investor',
    full_name = 'Issue 33 Investor'
WHERE user_id = 'a3310000-0000-4000-8000-000000000002';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES ('a3330000-0000-4000-8000-000000000001', 'Issue 33 Workspace', 'issue-33-workspace', 'a3320000-0000-4000-8000-000000000001', 'active');

DELETE FROM public.workspace_memberships
WHERE profile_id IN (
  'a3320000-0000-4000-8000-000000000001',
  'a3320000-0000-4000-8000-000000000002'
);

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('a3330000-0000-4000-8000-000000000001', 'a3320000-0000-4000-8000-000000000001', 'admin', 'active'),
  ('a3330000-0000-4000-8000-000000000001', 'a3320000-0000-4000-8000-000000000002', 'investor', 'active');

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES ('a3310000-0000-4000-8000-000000000002', 'a3320000-0000-4000-8000-000000000002', 'verified_email', now(), 'active');

INSERT INTO public.auto_approval_rules (
  id,
  workspace_id,
  transaction_type,
  min_amount,
  max_amount,
  trusted_client_only,
  is_active,
  rule_version
) VALUES (
  'a3340000-0000-4000-8000-000000000001',
  'a3330000-0000-4000-8000-000000000001',
  'buy',
  0.00,
  10000.00,
  false,
  true,
  7
);

INSERT INTO public.order_requests (
  id,
  workspace_id,
  investor_profile_id,
  initiated_by_profile_id,
  initiated_by_role,
  initiation_channel,
  scheme_code,
  type,
  amount,
  status
) VALUES
  ('a3350000-0000-4000-8000-000000000001', 'a3330000-0000-4000-8000-000000000001', 'a3320000-0000-4000-8000-000000000002', 'a3320000-0000-4000-8000-000000000002', 'investor', 'investor_portal', 'SCH33-AUTO', 'buy', 5000.00, 'pending_qualification'),
  ('a3350000-0000-4000-8000-000000000002', 'a3330000-0000-4000-8000-000000000001', 'a3320000-0000-4000-8000-000000000002', 'a3320000-0000-4000-8000-000000000002', 'investor', 'investor_portal', 'SCH33-REVIEW', 'buy', 15000.00, 'pending_qualification'),
  ('a3350000-0000-4000-8000-000000000003', 'a3330000-0000-4000-8000-000000000001', 'a3320000-0000-4000-8000-000000000002', 'a3320000-0000-4000-8000-000000000002', 'investor', 'investor_portal', 'SCH33-RETRY', 'buy', 3000.00, 'pending_qualification'),
  ('a3350000-0000-4000-8000-000000000004', 'a3330000-0000-4000-8000-000000000001', 'a3320000-0000-4000-8000-000000000002', 'a3320000-0000-4000-8000-000000000002', 'investor', 'investor_portal', 'SCH33-MISMATCH', 'buy', 3000.00, 'pending_qualification'),
  ('a3350000-0000-4000-8000-000000000005', 'a3330000-0000-4000-8000-000000000001', 'a3320000-0000-4000-8000-000000000002', 'a3320000-0000-4000-8000-000000000002', 'investor', 'investor_portal', 'SCH33-LEASE', 'buy', 3000.00, 'pending_qualification'),
  ('a3350000-0000-4000-8000-000000000006', 'a3330000-0000-4000-8000-000000000001', 'a3320000-0000-4000-8000-000000000002', 'a3320000-0000-4000-8000-000000000002', 'investor', 'investor_portal', 'SCH33-STALE', 'buy', 3000.00, 'pending_qualification');

DO $$
DECLARE
  v_auto_event public.event_outbox;
  v_review_event public.event_outbox;
  v_retry_event public.event_outbox;
  v_mismatch_event public.event_outbox;
  v_lease_event public.event_outbox;
  v_stale_event public.event_outbox;
  v_claim pg_catalog.record;
  v_auto_claim pg_catalog.record;
  v_retry_claim pg_catalog.record;
  v_old_claim_token pg_catalog.uuid;
  v_order public.order_requests;
  v_unrelated_before public.event_outbox;
  v_unrelated_after public.event_outbox;
  v_audit_count_before pg_catalog.int8;
  v_audit_count_after pg_catalog.int8;
BEGIN
  IF NOT pg_catalog.has_function_privilege(
    'service_role',
    'public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role cannot execute claim_order_auto_approval_event';
  END IF;

  IF pg_catalog.has_function_privilege(
    'authenticated',
    'public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'authenticated can execute claim_order_auto_approval_event';
  END IF;

  IF pg_catalog.has_function_privilege(
    'service_role',
    'public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role can execute old unfenced claim_order_auto_approval_event';
  END IF;

  IF pg_catalog.has_function_privilege(
    'service_role',
    'public.record_order_auto_approval_event_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.int4)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role can execute old unfenced record_order_auto_approval_event_failure';
  END IF;

  IF pg_catalog.has_function_privilege(
    'service_role',
    'public.apply_auto_approval_decision(pg_catalog.uuid, public.order_status, pg_catalog.uuid, pg_catalog.int4, pg_catalog.uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role can execute old unfenced apply_auto_approval_decision';
  END IF;

  SELECT *
  INTO v_auto_event
  FROM public.event_outbox
  WHERE entity_id = 'a3350000-0000-4000-8000-000000000001';

  SELECT *
  INTO v_review_event
  FROM public.event_outbox
  WHERE entity_id = 'a3350000-0000-4000-8000-000000000002';

  SELECT *
  INTO v_retry_event
  FROM public.event_outbox
  WHERE entity_id = 'a3350000-0000-4000-8000-000000000003';

  SELECT *
  INTO v_mismatch_event
  FROM public.event_outbox
  WHERE entity_id = 'a3350000-0000-4000-8000-000000000004';

  SELECT *
  INTO v_lease_event
  FROM public.event_outbox
  WHERE entity_id = 'a3350000-0000-4000-8000-000000000005';

  SELECT *
  INTO v_stale_event
  FROM public.event_outbox
  WHERE entity_id = 'a3350000-0000-4000-8000-000000000006';

  SELECT *
  INTO v_auto_claim
  FROM public.claim_order_auto_approval_event(
    v_auto_event.id,
    3,
    120
  );

  IF v_auto_claim.event_outbox_id <> v_auto_event.id OR v_auto_claim.correlation_id <> v_auto_event.id THEN
    RAISE EXCEPTION 'claim did not bind correlation_id exactly to event_outbox.id';
  END IF;

  SELECT *
  INTO v_claim
  FROM public.claim_order_auto_approval_event(
    v_lease_event.id,
    3,
    120
  );
  v_old_claim_token := v_claim.claim_token;

  SELECT *
  INTO v_retry_claim
  FROM public.claim_order_auto_approval_event(
    v_lease_event.id,
    3,
    120
  );

  IF v_retry_claim.claim_state <> 'active_in_progress' OR v_retry_claim.attempt <> 1 THEN
    RAISE EXCEPTION 'fresh processing claim was not protected';
  END IF;

  UPDATE public.event_outbox
  SET claim_expires_at = pg_catalog.now() - '1 second'::pg_catalog.interval
  WHERE id = v_lease_event.id;

  SELECT *
  INTO v_retry_claim
  FROM public.claim_order_auto_approval_event(
    v_lease_event.id,
    3,
    120
  );

  IF v_retry_claim.claim_state <> 'retry_claimed'
     OR v_retry_claim.attempt <> 2
     OR v_retry_claim.correlation_id <> v_claim.correlation_id
     OR v_retry_claim.claim_token = v_old_claim_token THEN
    RAISE EXCEPTION 'expired processing claim was not safely reclaimed';
  END IF;
  IF pg_catalog.pg_typeof(v_auto_claim.correlation_id)::pg_catalog.text <> 'uuid' THEN
    RAISE EXCEPTION 'claim correlation_id is not PostgreSQL UUID typed';
  END IF;
  IF v_auto_claim.attempt <> 1 OR v_auto_claim.claim_state <> 'newly_claimed' THEN
    RAISE EXCEPTION 'first claim attempt was not deterministic';
  END IF;

  v_order := public.apply_auto_approval_decision(
    'a3350000-0000-4000-8000-000000000001',
    'auto_approved',
    'a3340000-0000-4000-8000-000000000001',
    7,
    v_auto_claim.correlation_id,
    v_auto_claim.claim_token
  );

  IF v_order.status <> 'auto_approved'
     OR v_order.auto_approval_correlation_id <> v_auto_event.id
     OR v_order.triggered_rule_id <> 'a3340000-0000-4000-8000-000000000001'
     OR v_order.triggered_rule_version <> 7 THEN
    RAISE EXCEPTION 'auto_approved decision payload was not persisted correctly';
  END IF;

  SELECT pg_catalog.count(*)
  INTO v_audit_count_before
  FROM public.workspace_audit_logs
  WHERE correlation_id = v_auto_event.id;

  v_order := public.apply_auto_approval_decision(
    'a3350000-0000-4000-8000-000000000001',
    'auto_approved',
    'a3340000-0000-4000-8000-000000000001',
    7,
    v_auto_event.id,
    v_auto_claim.claim_token
  );

  SELECT pg_catalog.count(*)
  INTO v_audit_count_after
  FROM public.workspace_audit_logs
  WHERE correlation_id = v_auto_event.id;

  IF v_audit_count_after <> v_audit_count_before THEN
    RAISE EXCEPTION 'same-event replay duplicated decision/audit records';
  END IF;

  SELECT *
  INTO v_claim
  FROM public.claim_order_auto_approval_event(
    v_review_event.id,
    3,
    120
  );

  v_order := public.apply_auto_approval_decision(
    'a3350000-0000-4000-8000-000000000002',
    'pending_review',
    NULL,
    NULL,
    v_claim.correlation_id,
    v_claim.claim_token
  );

  IF v_order.status <> 'pending_review'
     OR v_order.triggered_rule_id IS NOT NULL
     OR v_order.triggered_rule_version IS NOT NULL THEN
    RAISE EXCEPTION 'pending_review decision did not persist null rule fields';
  END IF;

  SELECT *
  INTO v_claim
  FROM public.claim_order_auto_approval_event(
    v_retry_event.id,
    3,
    120
  );
  v_old_claim_token := v_claim.claim_token;

  PERFORM public.record_order_auto_approval_claim_failure(
    v_retry_event.id,
    v_claim.claim_token,
    'temporary_rule_fetch_failed',
    'first deterministic retry fixture',
    true,
    3
  );

  SELECT *
  INTO v_retry_claim
  FROM public.claim_order_auto_approval_event(
    v_retry_event.id,
    3,
    120
  );

  IF v_retry_claim.correlation_id <> v_claim.correlation_id
     OR v_retry_claim.event_outbox_id <> v_claim.event_outbox_id
     OR v_retry_claim.attempt <> 2
     OR v_retry_claim.claim_state <> 'retry_claimed' THEN
    RAISE EXCEPTION 'retry did not reuse stable event-bound correlation';
  END IF;

  BEGIN
    PERFORM public.record_order_auto_approval_claim_failure(
      v_retry_event.id,
      v_old_claim_token,
      'old_worker_failure_after_reclaim',
      'old owner must be fenced',
      true,
      3
    );
    RAISE EXCEPTION 'old worker recorded failure after reclaim';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'claim_not_owned' THEN
      RAISE EXCEPTION 'unexpected old-worker failure fence error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    PERFORM public.apply_auto_approval_decision(
      'a3350000-0000-4000-8000-000000000003',
      'pending_review',
      NULL,
      NULL,
      v_retry_event.id,
      v_old_claim_token
    );
    RAISE EXCEPTION 'old worker applied decision after reclaim';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'claim_not_owned' THEN
      RAISE EXCEPTION 'unexpected old-worker decision fence error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    PERFORM public.apply_auto_approval_decision(
      'a3350000-0000-4000-8000-000000000003',
      'pending_review',
      'a3340000-0000-4000-8000-000000000001',
      7,
      v_retry_event.id,
      v_retry_claim.claim_token
    );
    RAISE EXCEPTION 'pending_review accepted non-null rule fields';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_qualification_decision' THEN
      RAISE EXCEPTION 'unexpected pending_review rule error: %', SQLERRM;
    END IF;
  END;

  INSERT INTO public.event_outbox (
    id,
    entity_type,
    entity_id,
    event_type,
    status,
    retry_count,
    claimed_at,
    claimed_by,
    claim_token,
    claim_expires_at,
    error_message,
    payload
  ) VALUES (
    'a3360000-0000-4000-8000-000000000902',
    'ingested_document',
    'a3350000-0000-4000-8000-000000000001',
    'statement.imported',
    'pending',
    0,
    NULL,
    NULL,
    NULL,
    NULL,
    'must-remain',
    '{}'::pg_catalog.jsonb
  );

  SELECT *
  INTO v_unrelated_before
  FROM public.event_outbox
  WHERE id = 'a3360000-0000-4000-8000-000000000902';

  SELECT *
  INTO v_claim
  FROM public.claim_order_auto_approval_event(
    'a3360000-0000-4000-8000-000000000902',
    3,
    120
  );

  IF v_claim.claim_state <> 'invalid_event' THEN
    RAISE EXCEPTION 'unrelated explicit event did not return invalid_event';
  END IF;

  SELECT *
  INTO v_unrelated_after
  FROM public.event_outbox
  WHERE id = 'a3360000-0000-4000-8000-000000000902';

  IF v_unrelated_before.status IS DISTINCT FROM v_unrelated_after.status
     OR v_unrelated_before.retry_count IS DISTINCT FROM v_unrelated_after.retry_count
     OR v_unrelated_before.claimed_at IS DISTINCT FROM v_unrelated_after.claimed_at
     OR v_unrelated_before.claimed_by IS DISTINCT FROM v_unrelated_after.claimed_by
     OR v_unrelated_before.error_message IS DISTINCT FROM v_unrelated_after.error_message THEN
    RAISE EXCEPTION 'unrelated explicit event was mutated by rejected claim';
  END IF;

  INSERT INTO public.event_outbox (
    id,
    entity_type,
    entity_id,
    event_type,
    status,
    claimed_at,
    claimed_by,
    claim_token,
    claim_expires_at,
    payload
  ) VALUES (
    'a3360000-0000-4000-8000-000000000903',
    'order_request_replay',
    'a3350000-0000-4000-8000-000000000004',
    'order.created',
    'processing',
    pg_catalog.now(),
    'a3370000-0000-4000-8000-000000000007',
    'a3370000-0000-4000-8000-000000000007',
    pg_catalog.now() + '120 seconds'::pg_catalog.interval,
    pg_catalog.jsonb_build_object('order_id', 'a3350000-0000-4000-8000-000000000004')
  );

  BEGIN
    PERFORM public.apply_auto_approval_decision(
      'a3350000-0000-4000-8000-000000000004',
      'pending_review',
      NULL,
      NULL,
      'a3360000-0000-4000-8000-000000000903',
      'a3370000-0000-4000-8000-000000000007'
    );
    RAISE EXCEPTION 'wrong outbox entity_type was not rejected';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_event_entity_type' THEN
      RAISE EXCEPTION 'unexpected entity_type fence error: %', SQLERRM;
    END IF;
  END;

  UPDATE public.event_outbox
  SET status = 'processing',
      claimed_at = pg_catalog.now(),
      claimed_by = 'a3370000-0000-4000-8000-000000000005',
      claim_token = 'a3370000-0000-4000-8000-000000000005',
      claim_expires_at = pg_catalog.now() + '120 seconds'::pg_catalog.interval
  WHERE id = v_mismatch_event.id;

  BEGIN
    PERFORM public.apply_auto_approval_decision(
      'a3350000-0000-4000-8000-000000000003',
      'pending_review',
      NULL,
      NULL,
      v_mismatch_event.id,
      'a3370000-0000-4000-8000-000000000005'
    );
    RAISE EXCEPTION 'event/order mismatch was not rejected';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'event_order_mismatch' THEN
      RAISE EXCEPTION 'unexpected event/order mismatch error: %', SQLERRM;
    END IF;
  END;

  v_order := public.apply_auto_approval_decision(
    'a3350000-0000-4000-8000-000000000003',
    'pending_review',
    NULL,
    NULL,
    v_retry_event.id,
    v_retry_claim.claim_token
  );

  IF v_order.status <> 'pending_review' OR v_order.auto_approval_correlation_id <> v_retry_event.id THEN
    RAISE EXCEPTION 'new claim owner could not complete reclaimed event';
  END IF;

  UPDATE public.order_requests
  SET status = 'auto_approved',
      auto_approval_correlation_id = NULL,
      triggered_rule_id = 'a3340000-0000-4000-8000-000000000001',
      triggered_rule_version = 7
  WHERE id = 'a3350000-0000-4000-8000-000000000006';

  UPDATE public.event_outbox
  SET status = 'processing',
      claimed_at = pg_catalog.now(),
      claimed_by = 'a3370000-0000-4000-8000-000000000006',
      claim_token = 'a3370000-0000-4000-8000-000000000006',
      claim_expires_at = pg_catalog.now() + '120 seconds'::pg_catalog.interval
  WHERE id = v_stale_event.id;

  BEGIN
    PERFORM public.apply_auto_approval_decision(
      'a3350000-0000-4000-8000-000000000006',
      'pending_review',
      NULL,
      NULL,
      v_stale_event.id,
      'a3370000-0000-4000-8000-000000000006'
    );
    RAISE EXCEPTION 'different event against resolved order was not stale';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'stale_order_state' THEN
      RAISE EXCEPTION 'unexpected stale replay error: %', SQLERRM;
    END IF;
  END;

  SELECT *
  INTO v_order
  FROM public.order_requests
  WHERE id = 'a3350000-0000-4000-8000-000000000006';

  IF v_order.status <> 'auto_approved'
     OR v_order.auto_approval_correlation_id IS NOT NULL
     OR v_order.triggered_rule_id <> 'a3340000-0000-4000-8000-000000000001'
     OR v_order.triggered_rule_version <> 7 THEN
    RAISE EXCEPTION 'stale replay changed the resolved decision';
  END IF;
END;
$$;

ROLLBACK;
