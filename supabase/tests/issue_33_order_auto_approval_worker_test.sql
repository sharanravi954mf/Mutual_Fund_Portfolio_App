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
  ('a3350000-0000-4000-8000-000000000004', 'a3330000-0000-4000-8000-000000000001', 'a3320000-0000-4000-8000-000000000002', 'a3320000-0000-4000-8000-000000000002', 'investor', 'investor_portal', 'SCH33-MISMATCH', 'buy', 3000.00, 'pending_qualification');

DO $$
DECLARE
  v_auto_event public.event_outbox;
  v_review_event public.event_outbox;
  v_retry_event public.event_outbox;
  v_mismatch_event public.event_outbox;
  v_stale_event_id pg_catalog.uuid := 'a3360000-0000-4000-8000-000000000901';
  v_claim pg_catalog.record;
  v_retry_claim pg_catalog.record;
  v_order public.order_requests;
  v_audit_count_before pg_catalog.int8;
  v_audit_count_after pg_catalog.int8;
BEGIN
  IF NOT pg_catalog.has_function_privilege(
    'service_role',
    'public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role cannot execute claim_order_auto_approval_event';
  END IF;

  IF pg_catalog.has_function_privilege(
    'authenticated',
    'public.claim_order_auto_approval_event(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'authenticated can execute claim_order_auto_approval_event';
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
  INTO v_claim
  FROM public.claim_order_auto_approval_event(
    'a3370000-0000-4000-8000-000000000001',
    v_auto_event.id,
    3
  );

  IF v_claim.event_outbox_id <> v_auto_event.id OR v_claim.correlation_id <> v_auto_event.id THEN
    RAISE EXCEPTION 'claim did not bind correlation_id exactly to event_outbox.id';
  END IF;
  IF pg_catalog.pg_typeof(v_claim.correlation_id)::pg_catalog.text <> 'uuid' THEN
    RAISE EXCEPTION 'claim correlation_id is not PostgreSQL UUID typed';
  END IF;
  IF v_claim.attempt <> 1 OR v_claim.claim_state <> 'newly_claimed' THEN
    RAISE EXCEPTION 'first claim attempt was not deterministic';
  END IF;

  v_order := public.apply_auto_approval_decision(
    'a3350000-0000-4000-8000-000000000001',
    'auto_approved',
    'a3340000-0000-4000-8000-000000000001',
    7,
    v_claim.correlation_id
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
    v_auto_event.id
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
    'a3370000-0000-4000-8000-000000000002',
    v_review_event.id,
    3
  );

  v_order := public.apply_auto_approval_decision(
    'a3350000-0000-4000-8000-000000000002',
    'pending_review',
    NULL,
    NULL,
    v_claim.correlation_id
  );

  IF v_order.status <> 'pending_review'
     OR v_order.triggered_rule_id IS NOT NULL
     OR v_order.triggered_rule_version IS NOT NULL THEN
    RAISE EXCEPTION 'pending_review decision did not persist null rule fields';
  END IF;

  SELECT *
  INTO v_claim
  FROM public.claim_order_auto_approval_event(
    'a3370000-0000-4000-8000-000000000003',
    v_retry_event.id,
    3
  );

  PERFORM public.record_order_auto_approval_event_failure(
    v_retry_event.id,
    'a3370000-0000-4000-8000-000000000003',
    'temporary_rule_fetch_failed',
    'first deterministic retry fixture',
    true,
    3
  );

  SELECT *
  INTO v_retry_claim
  FROM public.claim_order_auto_approval_event(
    'a3370000-0000-4000-8000-000000000004',
    v_retry_event.id,
    3
  );

  IF v_retry_claim.correlation_id <> v_claim.correlation_id
     OR v_retry_claim.event_outbox_id <> v_claim.event_outbox_id
     OR v_retry_claim.attempt <> 2
     OR v_retry_claim.claim_state <> 'retry_claimed' THEN
    RAISE EXCEPTION 'retry did not reuse stable event-bound correlation';
  END IF;

  BEGIN
    PERFORM public.apply_auto_approval_decision(
      'a3350000-0000-4000-8000-000000000003',
      'pending_review',
      'a3340000-0000-4000-8000-000000000001',
      7,
      v_retry_event.id
    );
    RAISE EXCEPTION 'pending_review accepted non-null rule fields';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_qualification_decision' THEN
      RAISE EXCEPTION 'unexpected pending_review rule error: %', SQLERRM;
    END IF;
  END;

  UPDATE public.event_outbox
  SET status = 'processing',
      claimed_at = pg_catalog.now(),
      claimed_by = 'a3370000-0000-4000-8000-000000000005'
  WHERE id = v_mismatch_event.id;

  BEGIN
    PERFORM public.apply_auto_approval_decision(
      'a3350000-0000-4000-8000-000000000003',
      'pending_review',
      NULL,
      NULL,
      v_mismatch_event.id
    );
    RAISE EXCEPTION 'event/order mismatch was not rejected';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'event_order_mismatch' THEN
      RAISE EXCEPTION 'unexpected event/order mismatch error: %', SQLERRM;
    END IF;
  END;

  INSERT INTO public.event_outbox (
    id,
    entity_type,
    entity_id,
    event_type,
    status,
    claimed_at,
    claimed_by,
    payload
  ) VALUES (
    v_stale_event_id,
    'order_request_replay',
    'a3350000-0000-4000-8000-000000000001',
    'order.created',
    'processing',
    pg_catalog.now(),
    'a3370000-0000-4000-8000-000000000006',
    pg_catalog.jsonb_build_object('order_id', 'a3350000-0000-4000-8000-000000000001')
  );

  BEGIN
    PERFORM public.apply_auto_approval_decision(
      'a3350000-0000-4000-8000-000000000001',
      'pending_review',
      NULL,
      NULL,
      v_stale_event_id
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
  WHERE id = 'a3350000-0000-4000-8000-000000000001';

  IF v_order.status <> 'auto_approved'
     OR v_order.auto_approval_correlation_id <> v_auto_event.id
     OR v_order.triggered_rule_id <> 'a3340000-0000-4000-8000-000000000001'
     OR v_order.triggered_rule_version <> 7 THEN
    RAISE EXCEPTION 'stale replay changed the resolved decision';
  END IF;
END;
$$;

ROLLBACK;
