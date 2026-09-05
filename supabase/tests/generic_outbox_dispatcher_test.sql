BEGIN;

INSERT INTO auth.users(
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES (
  'd0010000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'dispatcher-test@moneybowl.invalid',
  '{"user_role":"investor"}',
  '{}',
  now(),
  now()
);

UPDATE public.profiles
SET
  id = 'd0020000-0000-4000-8000-000000000001',
  role = 'investor',
  full_name = 'DISPATCHER SYNTHETIC',
  phone_number = '0000000001'
WHERE user_id = 'd0010000-0000-4000-8000-000000000001';

INSERT INTO public.workspaces(
  id, name, slug, owner_profile_id, workspace_status
) VALUES (
  'd0030000-0000-4000-8000-000000000001',
  'Dispatcher Test Workspace',
  'dispatcher-test-workspace',
  'd0020000-0000-4000-8000-000000000001',
  'active'
);

DELETE FROM public.workspace_memberships
WHERE profile_id = 'd0020000-0000-4000-8000-000000000001';

INSERT INTO public.workspace_memberships(
  workspace_id, profile_id, role, status
) VALUES (
  'd0030000-0000-4000-8000-000000000001',
  'd0020000-0000-4000-8000-000000000001',
  'investor',
  'active'
);

INSERT INTO public.integration_accounts(
  id, workspace_id, investor_profile_id, integration_key,
  integration_environment, state, integration_metadata
) VALUES (
  'd0040000-0000-4000-8000-000000000001',
  'd0030000-0000-4000-8000-000000000001',
  'd0020000-0000-4000-8000-000000000001',
  'NSE_INVEST',
  'UAT',
  'REGISTRATION_PENDING',
  '{}'
);

INSERT INTO public.integration_operations(
  id, workspace_id, integration_account_id, integration_key,
  integration_environment, category, safety_class, operation_type,
  api_key, contract_version, state, retry_allowed
) VALUES
(
  'd0050000-0000-4000-8000-000000000001',
  'd0030000-0000-4000-8000-000000000001',
  'd0040000-0000-4000-8000-000000000001',
  'NSE_INVEST', 'UAT', 'REFERENCE_DATA', 'READ_ONLY',
  'DISPATCH_TEST', 'DISPATCH_TEST', 'TEST_1', 'QUEUED', false
),
(
  'd0050000-0000-4000-8000-000000000002',
  'd0030000-0000-4000-8000-000000000001',
  'd0040000-0000-4000-8000-000000000001',
  'NSE_INVEST', 'UAT', 'REFERENCE_DATA', 'READ_ONLY',
  'DISPATCH_TEST', 'DISPATCH_TEST', 'TEST_1', 'SUBMISSION_FAILED', true
),
(
  'd0050000-0000-4000-8000-000000000003',
  'd0030000-0000-4000-8000-000000000001',
  'd0040000-0000-4000-8000-000000000001',
  'NSE_INVEST', 'UAT', 'REFERENCE_DATA', 'READ_ONLY',
  'DISPATCH_TEST', 'DISPATCH_TEST', 'TEST_1', 'BUSINESS_FAILED', false
),
(
  'd0050000-0000-4000-8000-000000000004',
  'd0030000-0000-4000-8000-000000000001',
  'd0040000-0000-4000-8000-000000000001',
  'NSE_INVEST', 'UAT', 'REFERENCE_DATA', 'READ_ONLY',
  'DISPATCH_TEST', 'DISPATCH_TEST', 'TEST_1', 'QUEUED', false
),
(
  'd0050000-0000-4000-8000-000000000005',
  'd0030000-0000-4000-8000-000000000001',
  'd0040000-0000-4000-8000-000000000001',
  'NSE_INVEST', 'UAT', 'REFERENCE_DATA', 'READ_ONLY',
  'DISPATCH_TEST', 'DISPATCH_TEST', 'TEST_1', 'QUEUED', false
),
(
  'd0050000-0000-4000-8000-000000000006',
  'd0030000-0000-4000-8000-000000000001',
  'd0040000-0000-4000-8000-000000000001',
  'NSE_INVEST', 'UAT', 'REFERENCE_DATA', 'READ_ONLY',
  'DISPATCH_TEST', 'DISPATCH_TEST', 'TEST_1', 'SUCCESS', false
);

INSERT INTO public.event_outbox(
  id, event_type, payload, status, entity_id, entity_type
) VALUES
(
  'd0060000-0000-4000-8000-000000000001',
  'integration.nse.ucc_registration_requested',
  '{"secret":"must-not-leak"}',
  'pending',
  'd0050000-0000-4000-8000-000000000001',
  'integration_operation'
),
(
  'd0060000-0000-4000-8000-000000000002',
  'integration.nse.ucc_verification_requested',
  '{}',
  'failed',
  'd0050000-0000-4000-8000-000000000002',
  'integration_operation'
),
(
  'd0060000-0000-4000-8000-000000000003',
  'integration.nse.ucc_verification_requested',
  '{}',
  'failed',
  'd0050000-0000-4000-8000-000000000003',
  'integration_operation'
),
(
  'd0060000-0000-4000-8000-000000000004',
  'integration.nse.ucc_verification_requested',
  '{}',
  'processing',
  'd0050000-0000-4000-8000-000000000004',
  'integration_operation'
),
(
  'd0060000-0000-4000-8000-000000000005',
  'integration.nse.ucc_verification_requested',
  '{}',
  'processing',
  'd0050000-0000-4000-8000-000000000005',
  'integration_operation'
),
(
  'd0060000-0000-4000-8000-000000000006',
  'integration.nse.ucc_registration_requested',
  '{}',
  'completed',
  'd0050000-0000-4000-8000-000000000006',
  'integration_operation'
);

UPDATE public.event_outbox
SET
  retry_count = 1,
  updated_at = now() - interval '31 seconds'
WHERE id = 'd0060000-0000-4000-8000-000000000002';

UPDATE public.event_outbox
SET
  retry_count = 1,
  updated_at = now() - interval '31 seconds'
WHERE id = 'd0060000-0000-4000-8000-000000000003';

UPDATE public.event_outbox
SET
  retry_count = 1,
  claim_expires_at = now() + interval '5 minutes'
WHERE id = 'd0060000-0000-4000-8000-000000000004';

UPDATE public.event_outbox
SET
  retry_count = 1,
  claim_expires_at = now() - interval '1 second'
WHERE id = 'd0060000-0000-4000-8000-000000000005';

DO $$
DECLARE
  v_count pg_catalog.int4;
  v_json pg_catalog.jsonb;
BEGIN
  IF pg_catalog.has_function_privilege(
    'anon',
    'public.list_dispatchable_outbox_events(text[],integer,integer)',
    'EXECUTE'
  ) OR pg_catalog.has_function_privilege(
    'authenticated',
    'public.list_dispatchable_outbox_events(text[],integer,integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'dispatcher_feed_browser_executable';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
    'service_role',
    'public.list_dispatchable_outbox_events(text[],integer,integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'dispatcher_feed_service_role_not_executable';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.list_dispatchable_outbox_events(
    ARRAY[
      'integration.nse.ucc_registration_requested',
      'integration.nse.ucc_verification_requested'
    ],
    10,
    30
  );

  IF v_count <> 3 THEN
    RAISE EXCEPTION 'dispatcher_feed_candidate_count_invalid:%', v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.list_dispatchable_outbox_events(
      ARRAY[
        'integration.nse.ucc_registration_requested',
        'integration.nse.ucc_verification_requested'
      ],
      10,
      30
    )
    WHERE event_outbox_id = 'd0060000-0000-4000-8000-000000000001'
      AND event_status = 'pending'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.list_dispatchable_outbox_events(
      ARRAY[
        'integration.nse.ucc_registration_requested',
        'integration.nse.ucc_verification_requested'
      ],
      10,
      30
    )
    WHERE event_outbox_id = 'd0060000-0000-4000-8000-000000000002'
      AND event_status = 'failed'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.list_dispatchable_outbox_events(
      ARRAY[
        'integration.nse.ucc_registration_requested',
        'integration.nse.ucc_verification_requested'
      ],
      10,
      30
    )
    WHERE event_outbox_id = 'd0060000-0000-4000-8000-000000000005'
      AND event_status = 'processing'
  ) THEN
    RAISE EXCEPTION 'dispatcher_feed_expected_candidate_missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.list_dispatchable_outbox_events(
      ARRAY[
        'integration.nse.ucc_registration_requested',
        'integration.nse.ucc_verification_requested'
      ],
      10,
      30
    )
    WHERE event_outbox_id IN (
      'd0060000-0000-4000-8000-000000000003',
      'd0060000-0000-4000-8000-000000000004',
      'd0060000-0000-4000-8000-000000000006'
    )
  ) THEN
    RAISE EXCEPTION 'dispatcher_feed_non_dispatchable_candidate_exposed';
  END IF;

  SELECT to_jsonb(candidate) INTO v_json
  FROM public.list_dispatchable_outbox_events(
    ARRAY['integration.nse.ucc_registration_requested'],
    10,
    30
  ) AS candidate
  WHERE candidate.event_outbox_id =
    'd0060000-0000-4000-8000-000000000001';

  IF v_json ? 'payload'
     OR v_json::text LIKE '%must-not-leak%' THEN
    RAISE EXCEPTION 'dispatcher_feed_payload_leaked';
  END IF;

  BEGIN
    PERFORM public.list_dispatchable_outbox_events(
      ARRAY[]::text[],
      10,
      30
    );
    RAISE EXCEPTION 'dispatcher_feed_empty_event_types_accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'dispatcher_feed_empty_event_types_accepted' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM public.list_dispatchable_outbox_events(
      ARRAY['INVALID EVENT TYPE'],
      10,
      30
    );
    RAISE EXCEPTION 'dispatcher_feed_invalid_event_type_accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'dispatcher_feed_invalid_event_type_accepted' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM public.list_dispatchable_outbox_events(
      ARRAY['integration.nse.ucc_registration_requested'],
      51,
      30
    );
    RAISE EXCEPTION 'dispatcher_feed_invalid_limit_accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'dispatcher_feed_invalid_limit_accepted' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM public.list_dispatchable_outbox_events(
      ARRAY['integration.nse.ucc_registration_requested'],
      10,
      3601
    );
    RAISE EXCEPTION 'dispatcher_feed_invalid_retry_delay_accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'dispatcher_feed_invalid_retry_delay_accepted' THEN
      RAISE;
    END IF;
  END;
END;
$$;

ROLLBACK;
