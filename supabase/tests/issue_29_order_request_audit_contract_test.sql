-- Test Suite: Issue #29 canonical order request metadata and audit separation.

BEGIN;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('99000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue29-platform-admin@moneybowl.test', '{"user_role":"platform_admin"}', '{}', now(), now()),
  ('99000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue29-workspace-owner@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('99000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'issue29-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('99000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'issue29-advisor-a@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('99000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'issue29-advisor-b@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('99000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'issue29-unrelated-advisor@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('99000000-0000-0000-0000-000000000007', 'authenticated', 'authenticated', 'issue29-family-guest@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('99000000-0000-0000-0000-000000000008', 'authenticated', 'authenticated', 'issue29-other-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now());

UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id IN (
  '99000000-0000-0000-0000-000000000001',
  '99000000-0000-0000-0000-000000000002',
  '99000000-0000-0000-0000-000000000004',
  '99000000-0000-0000-0000-000000000005',
  '99000000-0000-0000-0000-000000000006'
);

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id IN (
  '99000000-0000-0000-0000-000000000003',
  '99000000-0000-0000-0000-000000000007',
  '99000000-0000-0000-0000-000000000008'
);

UPDATE public.profiles SET id = '99100000-0000-0000-0000-000000000001', role = 'platform_admin', full_name = 'Issue 29 Platform Admin'
WHERE user_id = '99000000-0000-0000-0000-000000000001';

UPDATE public.profiles SET id = '99100000-0000-0000-0000-000000000002', role = 'advisor', full_name = 'Issue 29 Workspace Owner'
WHERE user_id = '99000000-0000-0000-0000-000000000002';

UPDATE public.profiles SET id = '99100000-0000-0000-0000-000000000003', role = 'investor', full_name = 'Issue 29 Investor'
WHERE user_id = '99000000-0000-0000-0000-000000000003';

UPDATE public.profiles SET id = '99100000-0000-0000-0000-000000000004', role = 'advisor', full_name = 'Issue 29 Advisor A'
WHERE user_id = '99000000-0000-0000-0000-000000000004';

UPDATE public.profiles SET id = '99100000-0000-0000-0000-000000000005', role = 'advisor', full_name = 'Issue 29 Advisor B'
WHERE user_id = '99000000-0000-0000-0000-000000000005';

UPDATE public.profiles SET id = '99100000-0000-0000-0000-000000000006', role = 'advisor', full_name = 'Issue 29 Unrelated Advisor'
WHERE user_id = '99000000-0000-0000-0000-000000000006';

UPDATE public.profiles SET id = '99100000-0000-0000-0000-000000000007', role = 'investor', full_name = 'Issue 29 Family Guest'
WHERE user_id = '99000000-0000-0000-0000-000000000007';

UPDATE public.profiles SET id = '99100000-0000-0000-0000-000000000008', role = 'investor', full_name = 'Issue 29 Other Investor'
WHERE user_id = '99000000-0000-0000-0000-000000000008';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('99200000-0000-0000-0000-000000000001', 'Issue 29 Workspace A', 'issue-29-workspace-a', '99100000-0000-0000-0000-000000000002', 'active'),
  ('99200000-0000-0000-0000-000000000002', 'Issue 29 Workspace B', 'issue-29-workspace-b', '99100000-0000-0000-0000-000000000006', 'active');

DELETE FROM public.workspace_memberships
WHERE profile_id IN (
  '99100000-0000-0000-0000-000000000001',
  '99100000-0000-0000-0000-000000000002',
  '99100000-0000-0000-0000-000000000003',
  '99100000-0000-0000-0000-000000000004',
  '99100000-0000-0000-0000-000000000005',
  '99100000-0000-0000-0000-000000000006',
  '99100000-0000-0000-0000-000000000007',
  '99100000-0000-0000-0000-000000000008'
);

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('99200000-0000-0000-0000-000000000001', '99100000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('99200000-0000-0000-0000-000000000001', '99100000-0000-0000-0000-000000000003', 'investor', 'active'),
  ('99200000-0000-0000-0000-000000000001', '99100000-0000-0000-0000-000000000004', 'advisor', 'active'),
  ('99200000-0000-0000-0000-000000000001', '99100000-0000-0000-0000-000000000005', 'advisor', 'active'),
  ('99200000-0000-0000-0000-000000000002', '99100000-0000-0000-0000-000000000006', 'advisor', 'active'),
  ('99200000-0000-0000-0000-000000000001', '99100000-0000-0000-0000-000000000007', 'investor', 'active');

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES
  ('99000000-0000-0000-0000-000000000003', '99100000-0000-0000-0000-000000000003', 'verified_email', now(), 'active'),
  ('99000000-0000-0000-0000-000000000007', '99100000-0000-0000-0000-000000000007', 'verified_email', now(), 'active'),
  ('99000000-0000-0000-0000-000000000008', '99100000-0000-0000-0000-000000000008', 'verified_email', now(), 'active');

INSERT INTO public.family_delegations (id, workspace_id, owner_profile_id, delegate_profile_id, consent_status, is_active)
VALUES ('99400000-0000-0000-0000-000000000001', '99200000-0000-0000-0000-000000000001', '99100000-0000-0000-0000-000000000003', '99100000-0000-0000-0000-000000000007', 'accepted', true);

INSERT INTO public.auto_approval_rules (id, workspace_id, transaction_type, min_amount, max_amount, is_active, rule_version)
VALUES ('99500000-0000-0000-0000-000000000001', '99200000-0000-0000-0000-000000000001', 'buy', 0.00, 10000.00, true, 1);

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;

DO $$
DECLARE
  v_order public.order_requests;
  v_audit public.workspace_audit_logs;
  v_outbox public.event_outbox;
  v_count pg_catalog.int4;
BEGIN
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
  ) VALUES (
    '99300000-0000-0000-0000-000000000001',
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    '99100000-0000-0000-0000-000000000003',
    'investor',
    'investor_portal',
    'SCH29-INV',
    'buy',
    1000.00,
    'pending_qualification'
  )
  RETURNING * INTO v_order;

  IF v_order.initiated_by_profile_id <> '99100000-0000-0000-0000-000000000003'
     OR v_order.initiated_by_role <> 'investor'
     OR v_order.initiation_channel <> 'investor_portal' THEN
    RAISE EXCEPTION 'investor self-initiation metadata not persisted';
  END IF;

  SELECT * INTO v_audit
  FROM public.workspace_audit_logs
  WHERE entity_id = '99300000-0000-0000-0000-000000000001'
    AND action = 'order.initiated';

  IF v_audit.id IS NULL
     OR v_audit.actor_profile_id <> '99100000-0000-0000-0000-000000000003'
     OR v_audit.actor_type <> 'investor'
     OR v_audit.payload ->> 'initiation_channel' <> 'investor_portal' THEN
    RAISE EXCEPTION 'investor self-initiation audit metadata not persisted';
  END IF;

  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
  VALUES (
    '99300000-0000-0000-0000-000000000002',
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    'SCH29-LEGACY',
    'buy',
    1100.00,
    'pending_qualification'
  )
  RETURNING * INTO v_order;

  IF v_order.initiated_by_profile_id <> v_order.investor_profile_id
     OR v_order.initiated_by_role <> 'investor'
     OR v_order.initiation_channel <> 'investor_portal' THEN
    RAISE EXCEPTION 'legacy-style order insert was not safely defaulted';
  END IF;

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
  ) VALUES (
    '99300000-0000-0000-0000-000000000003',
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    '99100000-0000-0000-0000-000000000004',
    'advisor',
    'advisor_portal',
    'SCH29-ADV',
    'sell',
    1200.00,
    'pending_qualification'
  )
  RETURNING * INTO v_order;

  IF v_order.initiated_by_profile_id <> '99100000-0000-0000-0000-000000000004'
     OR v_order.initiated_by_role <> 'advisor'
     OR v_order.initiation_channel <> 'advisor_portal' THEN
    RAISE EXCEPTION 'advisor-assisted initiation metadata not persisted';
  END IF;

  BEGIN
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
    ) VALUES (
      '99300000-0000-0000-0000-000000000004',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      '99100000-0000-0000-0000-000000000003',
      'investor',
      'advisor_portal',
      'SCH29-BAD-COMBO',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'invalid investor/channel combination was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_order_initiation_metadata' THEN
      RAISE EXCEPTION 'Unexpected invalid investor/channel error: %', SQLERRM;
    END IF;
  END;

  BEGIN
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
    ) VALUES (
      '99300000-0000-0000-0000-000000000005',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      '99100000-0000-0000-0000-000000000004',
      'advisor',
      'investor_portal',
      'SCH29-BAD-COMBO-2',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'invalid advisor/channel combination was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'invalid_order_initiation_metadata' THEN
      RAISE EXCEPTION 'Unexpected invalid advisor/channel error: %', SQLERRM;
    END IF;
  END;

  BEGIN
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
    ) VALUES (
      '99300000-0000-0000-0000-000000000006',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000008',
      '99100000-0000-0000-0000-000000000008',
      'investor',
      'investor_portal',
      'SCH29-NO-INV-REL',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'order without active investor/workspace relationship was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'investor_workspace_relationship_required' THEN
      RAISE EXCEPTION 'Unexpected missing investor relationship error: %', SQLERRM;
    END IF;
  END;

  BEGIN
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
    ) VALUES (
      '99300000-0000-0000-0000-000000000007',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      '99100000-0000-0000-0000-000000000006',
      'advisor',
      'advisor_portal',
      'SCH29-NO-ADV-REL',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'order with unrelated advisor initiator was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'advisor_workspace_relationship_required' THEN
      RAISE EXCEPTION 'Unexpected missing advisor relationship error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      reviewed_by_profile_id,
      reviewed_at,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '99300000-0000-0000-0000-000000000008',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      '99100000-0000-0000-0000-000000000004',
      'advisor',
      'advisor_portal',
      '99100000-0000-0000-0000-000000000006',
      now(),
      'SCH29-BAD-REVIEWER',
      'buy',
      100.00,
      'pending_review'
    );
    RAISE EXCEPTION 'order with unrelated reviewer was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'reviewer_workspace_relationship_required' THEN
      RAISE EXCEPTION 'Unexpected missing reviewer relationship error: %', SQLERRM;
    END IF;
  END;

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
  ) VALUES (
    '99300000-0000-0000-0000-000000000010',
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    '99100000-0000-0000-0000-000000000004',
    'advisor',
    'advisor_portal',
    'SCH29-SAME-MFD',
    'buy',
    1300.00,
    'pending_review'
  );

  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
  v_order := public.qualify_order('99300000-0000-0000-0000-000000000010', 'approved', null);

  IF v_order.status <> 'approved'
     OR v_order.initiated_by_profile_id <> '99100000-0000-0000-0000-000000000004'
     OR v_order.reviewed_by_profile_id <> '99100000-0000-0000-0000-000000000004'
     OR v_order.reviewed_at IS NULL THEN
    RAISE EXCEPTION 'same-profile MFD initiation and review was not persisted';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.workspace_audit_logs
  WHERE entity_id = '99300000-0000-0000-0000-000000000010'
    AND action IN ('order.initiated', 'order.qualified', 'order.approved');

  IF v_count <> 3 THEN
    RAISE EXCEPTION 'manual approval audit events were not separated: %', v_count;
  END IF;

  SELECT * INTO v_audit
  FROM public.workspace_audit_logs
  WHERE entity_id = '99300000-0000-0000-0000-000000000010'
    AND action = 'order.approved'
  LIMIT 1;

  IF v_audit.payload ->> 'initiated_by_profile_id' <> '99100000-0000-0000-0000-000000000004'
     OR v_audit.payload ->> 'reviewed_by_profile_id' <> '99100000-0000-0000-0000-000000000004' THEN
    RAISE EXCEPTION 'manual approval audit did not capture initiator/reviewer metadata';
  END IF;

  BEGIN
    UPDATE public.workspace_audit_logs
    SET action = 'tampered'
    WHERE id = v_audit.id;
    RAISE EXCEPTION 'workspace_audit_logs update was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Audit logs are immutable and cannot be updated or deleted' THEN
      RAISE EXCEPTION 'Unexpected audit update immutability error: %', SQLERRM;
    END IF;
  END;

  BEGIN
    DELETE FROM public.workspace_audit_logs
    WHERE id = v_audit.id;
    RAISE EXCEPTION 'workspace_audit_logs delete was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Audit logs are immutable and cannot be updated or deleted' THEN
      RAISE EXCEPTION 'Unexpected audit delete immutability error: %', SQLERRM;
    END IF;
  END;

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
  ) VALUES (
    '99300000-0000-0000-0000-000000000011',
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    '99100000-0000-0000-0000-000000000004',
    'advisor',
    'advisor_portal',
    'SCH29-REJECT',
    'buy',
    1400.00,
    'pending_review'
  );

  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000005","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
  v_order := public.qualify_order('99300000-0000-0000-0000-000000000011', 'rejected', 'Needs offline confirmation');

  IF v_order.status <> 'rejected'
     OR v_order.reviewed_by_profile_id <> '99100000-0000-0000-0000-000000000005'
     OR v_order.rejection_reason <> 'Needs offline confirmation' THEN
    RAISE EXCEPTION 'different authorised advisor rejection was not persisted';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.workspace_audit_logs
  WHERE entity_id = '99300000-0000-0000-0000-000000000011'
    AND action IN ('order.initiated', 'order.qualified', 'order.rejected');

  IF v_count <> 3 THEN
    RAISE EXCEPTION 'manual rejection audit events were not separated: %', v_count;
  END IF;

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
  ) VALUES (
    '99300000-0000-0000-0000-000000000013',
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    '99100000-0000-0000-0000-000000000003',
    'investor',
    'investor_portal',
    'SCH29-AUTO',
    'buy',
    500.00,
    'pending_qualification'
  );

  SELECT * INTO v_outbox
  FROM public.event_outbox
  WHERE entity_id = '99300000-0000-0000-0000-000000000013'
    AND event_type = 'order.created'
  LIMIT 1;

  IF v_outbox.id IS NULL THEN
    RAISE EXCEPTION 'auto-approval outbox event not generated for Issue #29 order';
  END IF;

  UPDATE public.event_outbox
  SET status = 'processing',
      claimed_at = now(),
      claimed_by = '99100000-0000-0000-0000-000000000004'
  WHERE id = v_outbox.id;

  v_order := public.apply_auto_approval_decision(
    '99300000-0000-0000-0000-000000000013',
    'auto_approved',
    '99500000-0000-0000-0000-000000000001',
    1,
    v_outbox.id
  );

  IF v_order.status <> 'auto_approved' THEN
    RAISE EXCEPTION 'auto-approval decision did not persist expected final status';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.workspace_audit_logs
  WHERE entity_id = '99300000-0000-0000-0000-000000000013'
    AND action IN ('order.initiated', 'order.auto_qualified', 'order.approved');

  IF v_count <> 3 THEN
    RAISE EXCEPTION 'auto-approval evaluation/outcome audit events were not separated: %', v_count;
  END IF;

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
  ) VALUES (
    '99300000-0000-0000-0000-000000000012',
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    '99100000-0000-0000-0000-000000000003',
    'investor',
    'investor_portal',
    'SCH29-CANCEL',
    'buy',
    1500.00,
    'pending_qualification'
  );

  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
  v_order := public.cancel_order('99300000-0000-0000-0000-000000000012', 'Issue 29 cancellation compatibility');

  IF v_order.status <> 'cancelled'
     OR v_order.cancellation_reason <> 'Issue 29 cancellation compatibility'
     OR v_order.cancelled_at IS NULL THEN
    RAISE EXCEPTION 'Issue #28 cancellation fields regressed under Issue #29 metadata hardening';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
  FROM public.workspace_audit_logs
  WHERE entity_id = '99300000-0000-0000-0000-000000000012'
    AND action IN ('order.initiated', 'order.cancelled');

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'cancellation audit separation was not preserved: %', v_count;
  END IF;

  BEGIN
    UPDATE public.order_requests
    SET initiated_by_role = 'advisor'
    WHERE id = '99300000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'order initiation metadata update was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'order_initiation_metadata_immutable' THEN
      RAISE EXCEPTION 'Unexpected initiation metadata immutability error: %', SQLERRM;
    END IF;
  END;
END;
$$;

RESET ROLE;
ROLLBACK;
