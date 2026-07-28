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
  IF pg_catalog.has_function_privilege('anon', 'public.is_order_mfd_profile(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute internal is_order_mfd_profile helper';
  END IF;

  IF pg_catalog.has_function_privilege('authenticated', 'public.is_order_mfd_profile(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute internal is_order_mfd_profile helper';
  END IF;

  IF pg_catalog.has_function_privilege('service_role', 'public.is_order_mfd_profile(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role can execute internal is_order_mfd_profile helper';
  END IF;

  CREATE TEMP TABLE issue29_preflight_existing_orders (
    workspace_id pg_catalog.uuid,
    investor_profile_id pg_catalog.uuid,
    initiated_by_profile_id pg_catalog.uuid,
    initiated_by_role pg_catalog.text,
	    initiation_channel pg_catalog.text,
	    reviewed_by pg_catalog.uuid,
	    reviewed_by_profile_id pg_catalog.uuid,
	    reviewed_at pg_catalog.timestamptz
	  ) ON COMMIT DROP;

  INSERT INTO issue29_preflight_existing_orders (workspace_id, investor_profile_id)
  VALUES ('99200000-0000-0000-0000-000000000001', '99100000-0000-0000-0000-000000000003');

  BEGIN
    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
    FROM issue29_preflight_existing_orders AS o
    WHERE o.workspace_id IS NULL
       OR o.investor_profile_id IS NULL
       OR o.initiated_by_profile_id IS NULL
       OR o.initiated_by_role IS NULL
       OR o.initiation_channel IS NULL;

    IF v_count > 0 THEN
      RAISE EXCEPTION 'order_request_initiator_unresolved_existing_rows: % offending rows', v_count;
    END IF;

    RAISE EXCEPTION 'existing-row initiator preflight did not fail closed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'order_request_initiator_unresolved_existing_rows: 1%' THEN
      RAISE EXCEPTION 'Unexpected existing-row initiator preflight error: %', SQLERRM;
    END IF;
	  END;

	  TRUNCATE issue29_preflight_existing_orders;
	  INSERT INTO issue29_preflight_existing_orders (
	    workspace_id,
	    investor_profile_id,
	    initiated_by_profile_id,
	    initiated_by_role,
	    initiation_channel
	  ) VALUES (
	    '99200000-0000-0000-0000-000000000001',
	    '99100000-0000-0000-0000-000000000008',
	    '99100000-0000-0000-0000-000000000008',
	    'investor',
	    'investor_portal'
	  );

	  BEGIN
	    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
	    FROM issue29_preflight_existing_orders AS o
	    WHERE NOT EXISTS (
	      SELECT 1
	      FROM public.workspace_memberships AS wm
	      WHERE wm.workspace_id = o.workspace_id
	        AND wm.profile_id = o.investor_profile_id
	        AND wm.role = 'investor'
	        AND wm.status = 'active'
	    );

	    IF v_count > 0 THEN
	      RAISE EXCEPTION 'investor_workspace_relationship_required_existing_rows: % offending rows', v_count;
	    END IF;

	    RAISE EXCEPTION 'existing-row investor workspace preflight did not fail closed';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM NOT LIKE 'investor_workspace_relationship_required_existing_rows: 1%' THEN
	      RAISE EXCEPTION 'Unexpected existing-row investor workspace preflight error: %', SQLERRM;
	    END IF;
	  END;

	  TRUNCATE issue29_preflight_existing_orders;
	  INSERT INTO issue29_preflight_existing_orders (
	    workspace_id,
	    investor_profile_id,
	    initiated_by_profile_id,
	    initiated_by_role,
	    initiation_channel
	  ) VALUES (
	    '99200000-0000-0000-0000-000000000001',
	    '99100000-0000-0000-0000-000000000003',
	    '99100000-0000-0000-0000-000000000004',
	    'investor',
	    'investor_portal'
	  );

	  BEGIN
	    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
	    FROM issue29_preflight_existing_orders AS o
	    WHERE o.initiated_by_role = 'investor'
	      AND o.initiated_by_profile_id <> o.investor_profile_id;

	    IF v_count > 0 THEN
	      RAISE EXCEPTION 'investor_initiator_mismatch_existing_rows: % offending rows', v_count;
	    END IF;

	    RAISE EXCEPTION 'existing-row investor initiator preflight did not fail closed';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM NOT LIKE 'investor_initiator_mismatch_existing_rows: 1%' THEN
	      RAISE EXCEPTION 'Unexpected existing-row investor initiator preflight error: %', SQLERRM;
	    END IF;
	  END;

	  TRUNCATE issue29_preflight_existing_orders;
	  INSERT INTO issue29_preflight_existing_orders (
	    workspace_id,
	    investor_profile_id,
	    initiated_by_profile_id,
	    initiated_by_role,
	    initiation_channel
	  ) VALUES (
	    '99200000-0000-0000-0000-000000000001',
	    '99100000-0000-0000-0000-000000000003',
	    '99100000-0000-0000-0000-000000000006',
	    'advisor',
	    'advisor_portal'
	  );

	  BEGIN
	    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
	    FROM issue29_preflight_existing_orders AS o
	    WHERE o.initiated_by_role = 'advisor'
	      AND NOT public.is_order_mfd_profile(o.workspace_id, o.initiated_by_profile_id);

	    IF v_count > 0 THEN
	      RAISE EXCEPTION 'advisor_workspace_relationship_required_existing_rows: % offending rows', v_count;
	    END IF;

	    RAISE EXCEPTION 'existing-row advisor initiator preflight did not fail closed';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM NOT LIKE 'advisor_workspace_relationship_required_existing_rows: 1%' THEN
	      RAISE EXCEPTION 'Unexpected existing-row advisor initiator preflight error: %', SQLERRM;
	    END IF;
	  END;

	  TRUNCATE issue29_preflight_existing_orders;
	  INSERT INTO issue29_preflight_existing_orders (
	    workspace_id,
	    investor_profile_id,
	    initiated_by_profile_id,
	    initiated_by_role,
	    initiation_channel,
	    reviewed_at
	  ) VALUES (
	    '99200000-0000-0000-0000-000000000001',
	    '99100000-0000-0000-0000-000000000003',
	    '99100000-0000-0000-0000-000000000004',
	    'advisor',
	    'advisor_portal',
	    now()
	  );

	  BEGIN
	    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
	    FROM issue29_preflight_existing_orders AS o
	    WHERE o.reviewed_at IS NOT NULL
	      AND o.reviewed_by IS NULL
	      AND o.reviewed_by_profile_id IS NULL;

	    IF v_count > 0 THEN
	      RAISE EXCEPTION 'reviewed_at_without_reviewer_existing_rows: % offending rows', v_count;
	    END IF;

	    RAISE EXCEPTION 'existing-row reviewed_at preflight did not fail closed';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM NOT LIKE 'reviewed_at_without_reviewer_existing_rows: 1%' THEN
	      RAISE EXCEPTION 'Unexpected existing-row reviewed_at preflight error: %', SQLERRM;
	    END IF;
	  END;

	  TRUNCATE issue29_preflight_existing_orders;
	  INSERT INTO issue29_preflight_existing_orders (
	    workspace_id,
	    investor_profile_id,
	    initiated_by_profile_id,
	    initiated_by_role,
	    initiation_channel,
	    reviewed_by_profile_id
	  ) VALUES (
	    '99200000-0000-0000-0000-000000000001',
	    '99100000-0000-0000-0000-000000000003',
	    '99100000-0000-0000-0000-000000000004',
	    'advisor',
	    'advisor_portal',
	    '99100000-0000-0000-0000-000000000004'
	  );

	  BEGIN
	    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
	    FROM issue29_preflight_existing_orders AS o
	    WHERE o.reviewed_at IS NULL
	      AND (o.reviewed_by IS NOT NULL OR o.reviewed_by_profile_id IS NOT NULL);

	    IF v_count > 0 THEN
	      RAISE EXCEPTION 'reviewer_without_reviewed_at_existing_rows: % offending rows', v_count;
	    END IF;

	    RAISE EXCEPTION 'existing-row reviewer timestamp preflight did not fail closed';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM NOT LIKE 'reviewer_without_reviewed_at_existing_rows: 1%' THEN
	      RAISE EXCEPTION 'Unexpected existing-row reviewer timestamp preflight error: %', SQLERRM;
	    END IF;
	  END;

	  TRUNCATE issue29_preflight_existing_orders;
	  INSERT INTO issue29_preflight_existing_orders (
	    workspace_id,
	    investor_profile_id,
    initiated_by_profile_id,
    initiated_by_role,
	    initiation_channel,
	    reviewed_by,
	    reviewed_by_profile_id,
	    reviewed_at
	  ) VALUES (
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    '99100000-0000-0000-0000-000000000004',
	    'advisor',
	    'advisor_portal',
	    '99100000-0000-0000-0000-000000000004',
	    '99100000-0000-0000-0000-000000000005',
	    now()
	  );

  BEGIN
    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
    FROM issue29_preflight_existing_orders AS o
    WHERE o.reviewed_by IS NOT NULL
      AND o.reviewed_by_profile_id IS NOT NULL
      AND o.reviewed_by <> o.reviewed_by_profile_id;

    IF v_count > 0 THEN
      RAISE EXCEPTION 'reviewer_profile_mismatch_existing_rows: % offending rows', v_count;
    END IF;

    RAISE EXCEPTION 'existing-row reviewer preflight did not fail closed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'reviewer_profile_mismatch_existing_rows: 1%' THEN
      RAISE EXCEPTION 'Unexpected existing-row reviewer preflight error: %', SQLERRM;
	    END IF;
	  END;

	  TRUNCATE issue29_preflight_existing_orders;
	  INSERT INTO issue29_preflight_existing_orders (
	    workspace_id,
	    investor_profile_id,
	    initiated_by_profile_id,
	    initiated_by_role,
	    initiation_channel,
	    reviewed_by_profile_id,
	    reviewed_at
	  ) VALUES (
	    '99200000-0000-0000-0000-000000000001',
	    '99100000-0000-0000-0000-000000000003',
	    '99100000-0000-0000-0000-000000000004',
	    'advisor',
	    'advisor_portal',
	    '99100000-0000-0000-0000-000000000006',
	    now()
	  );

	  BEGIN
	    SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_count
	    FROM issue29_preflight_existing_orders AS o
	    WHERE COALESCE(o.reviewed_by_profile_id, o.reviewed_by) IS NOT NULL
	      AND NOT public.is_order_mfd_profile(
	        o.workspace_id,
	        COALESCE(o.reviewed_by_profile_id, o.reviewed_by)
	      );

	    IF v_count > 0 THEN
	      RAISE EXCEPTION 'reviewer_workspace_relationship_required_existing_rows: % offending rows', v_count;
	    END IF;

	    RAISE EXCEPTION 'existing-row reviewer relationship preflight did not fail closed';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM NOT LIKE 'reviewer_workspace_relationship_required_existing_rows: 1%' THEN
	      RAISE EXCEPTION 'Unexpected existing-row reviewer relationship preflight error: %', SQLERRM;
	    END IF;
	  END;

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
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

  PERFORM set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
    VALUES (
      '99300000-0000-0000-0000-000000000014',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      'SCH29-UNRESOLVED',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'unresolved caller inserted an order';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'profile_resolution_failed' THEN
      RAISE EXCEPTION 'Unexpected unresolved caller error: %', SQLERRM;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, scheme_code, type, amount, status)
    VALUES (
      '99300000-0000-0000-0000-000000000015',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      'SCH29-SERVICE-MISSING',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'service-role legacy insert without initiator metadata was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'order_request_canonical_metadata_missing' THEN
      RAISE EXCEPTION 'Unexpected service-role missing metadata error: %', SQLERRM;
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
    '99300000-0000-0000-0000-000000000016',
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    '99100000-0000-0000-0000-000000000004',
    'advisor',
    'advisor_portal',
    'SCH29-SERVICE-OK',
    'buy',
    100.00,
    'pending_qualification'
  )
  RETURNING * INTO v_order;

  IF v_order.initiated_by_profile_id <> '99100000-0000-0000-0000-000000000004'
     OR v_order.initiated_by_role <> 'advisor'
     OR v_order.initiation_channel <> 'advisor_portal' THEN
    RAISE EXCEPTION 'trusted service-role insert did not preserve explicit initiator metadata';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
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
      '99300000-0000-0000-0000-000000000017',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000007',
      '99100000-0000-0000-0000-000000000007',
      'investor',
      'investor_portal',
      'SCH29-INV-SPOOF',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'authenticated investor claimed another investor initiator';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'initiator_profile_mismatch' THEN
      RAISE EXCEPTION 'Unexpected investor spoofing error: %', SQLERRM;
    END IF;
	  END;

	  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000003', true);
	  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
	  BEGIN
	    INSERT INTO public.order_requests (
	      id,
	      workspace_id,
	      investor_profile_id,
	      initiated_by_profile_id,
	      initiated_by_role,
	      initiation_channel,
	      reviewed_by,
	      reviewed_by_profile_id,
	      reviewed_at,
	      scheme_code,
	      type,
	      amount,
	      status
	    ) VALUES (
	      '99300000-0000-0000-0000-000000000023',
	      '99200000-0000-0000-0000-000000000001',
	      '99100000-0000-0000-0000-000000000003',
	      '99100000-0000-0000-0000-000000000003',
	      'investor',
	      'investor_portal',
	      '99100000-0000-0000-0000-000000000004',
	      '99100000-0000-0000-0000-000000000004',
	      now(),
	      'SCH29-INV-PRE-REVIEW',
	      'buy',
	      100.00,
	      'pending_review'
	    );
	    RAISE EXCEPTION 'investor pre-populated advisor review metadata on insert';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM <> 'review_metadata_requires_qualification' THEN
	      RAISE EXCEPTION 'Unexpected investor reviewer pre-population error: %', SQLERRM;
	    END IF;
	  END;

	  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000004', true);
	  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
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
      '99300000-0000-0000-0000-000000000018',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      '99100000-0000-0000-0000-000000000005',
      'advisor',
      'advisor_portal',
      'SCH29-ADV-SPOOF',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'authenticated advisor claimed another advisor initiator';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'initiator_profile_mismatch' THEN
      RAISE EXCEPTION 'Unexpected advisor spoofing error: %', SQLERRM;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000001', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"platform_admin"}}', true);
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
      '99300000-0000-0000-0000-000000000019',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      '99100000-0000-0000-0000-000000000004',
      'advisor',
      'advisor_portal',
      'SCH29-ADMIN-SPOOF',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'platform admin spoofed an authorised advisor initiator';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'initiator_profile_mismatch' THEN
      RAISE EXCEPTION 'Unexpected platform admin spoofing error: %', SQLERRM;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000007', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000007","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
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
      '99300000-0000-0000-0000-000000000020',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      '99100000-0000-0000-0000-000000000004',
      'advisor',
      'advisor_portal',
      'SCH29-GUEST-SPOOF',
      'buy',
      100.00,
      'pending_qualification'
    );
    RAISE EXCEPTION 'family guest spoofed an authorised advisor initiator';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'initiator_profile_mismatch' THEN
      RAISE EXCEPTION 'Unexpected family guest spoofing error: %', SQLERRM;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000004', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
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

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
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

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000004', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
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

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000008', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000008","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
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

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000004', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
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
    IF SQLERRM <> 'initiator_profile_mismatch' THEN
      RAISE EXCEPTION 'Unexpected advisor spoofing error: %', SQLERRM;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000004', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
	      initiated_by_profile_id,
	      initiated_by_role,
	      initiation_channel,
	      reviewed_by,
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
	      '99100000-0000-0000-0000-000000000005',
	      '99100000-0000-0000-0000-000000000005',
	      now(),
	      'SCH29-BAD-REVIEWER',
	      'buy',
      100.00,
      'pending_review'
	    );
	    RAISE EXCEPTION 'advisor pre-populated another advisor review metadata on insert';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM <> 'review_metadata_requires_qualification' THEN
	      RAISE EXCEPTION 'Unexpected advisor reviewer pre-population error: %', SQLERRM;
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
      reviewed_by,
      reviewed_by_profile_id,
      reviewed_at,
      scheme_code,
      type,
      amount,
      status
    ) VALUES (
      '99300000-0000-0000-0000-000000000021',
      '99200000-0000-0000-0000-000000000001',
      '99100000-0000-0000-0000-000000000003',
      '99100000-0000-0000-0000-000000000004',
      'advisor',
      'advisor_portal',
      '99100000-0000-0000-0000-000000000004',
      '99100000-0000-0000-0000-000000000005',
      now(),
      'SCH29-REVIEWER-MISMATCH',
      'buy',
      100.00,
      'pending_review'
    );
    RAISE EXCEPTION 'mismatched reviewer fields were accepted on insert';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'reviewer_profile_mismatch' THEN
      RAISE EXCEPTION 'Unexpected reviewer insert mismatch error: %', SQLERRM;
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
    '99300000-0000-0000-0000-000000000022',
    '99200000-0000-0000-0000-000000000001',
    '99100000-0000-0000-0000-000000000003',
    '99100000-0000-0000-0000-000000000004',
    'advisor',
    'advisor_portal',
    'SCH29-REVIEWER-MISMATCH-UPD',
    'buy',
    100.00,
    'pending_review'
  );

  BEGIN
    UPDATE public.order_requests
    SET reviewed_by = '99100000-0000-0000-0000-000000000004',
        reviewed_by_profile_id = '99100000-0000-0000-0000-000000000005',
        reviewed_at = now()
    WHERE id = '99300000-0000-0000-0000-000000000022';
    RAISE EXCEPTION 'mismatched reviewer fields were accepted on update';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM <> 'reviewer_profile_mismatch' THEN
	      RAISE EXCEPTION 'Unexpected reviewer update mismatch error: %', SQLERRM;
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
	    '99300000-0000-0000-0000-000000000024',
	    '99200000-0000-0000-0000-000000000001',
	    '99100000-0000-0000-0000-000000000003',
	    '99100000-0000-0000-0000-000000000004',
	    'advisor',
	    'advisor_portal',
	    'SCH29-REVIEWER-SPOOF-UPD',
	    'buy',
	    100.00,
	    'pending_review'
	  );

	  BEGIN
	    UPDATE public.order_requests
	    SET status = 'approved',
	        reviewed_by = '99100000-0000-0000-0000-000000000005',
	        reviewed_by_profile_id = '99100000-0000-0000-0000-000000000005',
	        reviewed_at = now()
	    WHERE id = '99300000-0000-0000-0000-000000000024';
	    RAISE EXCEPTION 'advisor attributed qualification to another MFD profile';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM <> 'reviewer_profile_mismatch' THEN
	      RAISE EXCEPTION 'Unexpected reviewer spoofing update error: %', SQLERRM;
	    END IF;
	  END;

	  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000004', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"user_role":"mfd"}}', true);
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

	  BEGIN
	    UPDATE public.order_requests
	    SET reviewed_by_profile_id = '99100000-0000-0000-0000-000000000005'
	    WHERE id = '99300000-0000-0000-0000-000000000010';
	    RAISE EXCEPTION 'reviewed_by_profile_id changed after qualification';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM <> 'review_metadata_immutable' THEN
	      RAISE EXCEPTION 'Unexpected reviewer profile immutability error: %', SQLERRM;
	    END IF;
	  END;

	  BEGIN
	    UPDATE public.order_requests
	    SET reviewed_at = now() + interval '1 minute'
	    WHERE id = '99300000-0000-0000-0000-000000000010';
	    RAISE EXCEPTION 'reviewed_at changed after qualification';
	  EXCEPTION WHEN OTHERS THEN
	    IF SQLERRM <> 'review_metadata_immutable' THEN
	      RAISE EXCEPTION 'Unexpected reviewed_at immutability error: %', SQLERRM;
	    END IF;
	  END;

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

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000005', true);
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

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
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

  SELECT * INTO v_audit
  FROM public.workspace_audit_logs
  WHERE entity_id = '99300000-0000-0000-0000-000000000013'
    AND action = 'order.auto_qualified'
  LIMIT 1;

  IF v_audit.actor_type <> 'system'
     OR v_audit.actor_id IS NOT NULL
     OR v_audit.actor_profile_id IS NOT NULL
     OR v_audit.payload ->> 'investor_profile_id' <> '99100000-0000-0000-0000-000000000003'
     OR v_audit.payload ->> 'claimed_by_profile_id' <> '99100000-0000-0000-0000-000000000004' THEN
    RAISE EXCEPTION 'auto-approval evaluation audit incorrectly attributed system actor';
  END IF;

  SELECT * INTO v_audit
  FROM public.workspace_audit_logs
  WHERE entity_id = '99300000-0000-0000-0000-000000000013'
    AND action = 'order.approved'
  LIMIT 1;

  IF v_audit.actor_type <> 'system'
     OR v_audit.actor_id IS NOT NULL
     OR v_audit.actor_profile_id IS NOT NULL
     OR v_audit.payload ->> 'investor_profile_id' <> '99100000-0000-0000-0000-000000000003'
     OR v_audit.payload ->> 'claimed_by_profile_id' <> '99100000-0000-0000-0000-000000000004' THEN
    RAISE EXCEPTION 'auto-approval outcome audit incorrectly attributed system actor';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);
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
