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

-- Trusted synthetic provisioning; public signup creates only an Explorer account.
INSERT INTO public.profiles(user_id,role)
VALUES ('d0010000-0000-4000-8000-000000000001','investor');

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
DECLARE fn record; role_name text;
BEGIN
  IF (SELECT mode FROM moneybowl_dispatch.control) <> 'disabled' THEN RAISE EXCEPTION 'enabled_by_migration'; END IF;
  FOR fn IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='moneybowl_dispatch' OR p.proname IN ('admit_outbox_dispatch','authorize_outbox_dispatch','finish_outbox_dispatch')
  LOOP
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
      IF has_function_privilege(role_name,fn.oid,'EXECUTE') THEN RAISE EXCEPTION 'browser_function_access'; END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE oid=fn.oid AND prosecdef
      AND NOT COALESCE(proconfig @> ARRAY['search_path=""'],false)) THEN RAISE EXCEPTION 'unsafe_search_path'; END IF;
  END LOOP;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_schema_privilege(role_name,'moneybowl_dispatch','USAGE') OR
      has_table_privilege(role_name,'moneybowl_dispatch.control','UPDATE') THEN RAISE EXCEPTION 'private_schema_exposed'; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='moneybowl_dispatch' AND c.relkind='r' AND NOT c.relrowsecurity) THEN RAISE EXCEPTION 'rls_missing'; END IF;
END $$;
SET LOCAL ROLE anon;
DO $$ BEGIN
  BEGIN
    PERFORM public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',gen_random_uuid(),NULL,ARRAY['integration.nse.ucc_registration_requested']);
    RAISE EXCEPTION 'anon_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.finish_outbox_dispatch(gen_random_uuid(),NULL);
    RAISE EXCEPTION 'authenticated_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE moneybowl_dispatch.control SET environment='DEV',project_url='https://synthetic-dev.supabase.co';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb; BEGIN
  r:=public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',gen_random_uuid(),NULL,ARRAY['integration.nse.ucc_registration_requested']);
  IF r->>'code'<>'disabled' THEN RAISE EXCEPTION 'disabled_admitted'; END IF;
END $$;
RESET ROLE;
UPDATE moneybowl_dispatch.control SET mode='active';
SET LOCAL ROLE service_role;
DO $$
DECLARE r jsonb; token uuid; request_id uuid:=gen_random_uuid(); event_id uuid:='d0060000-0000-4000-8000-000000000001';
BEGIN
  r:=public.admit_outbox_dispatch('QA','https://synthetic-dev.supabase.co','active',gen_random_uuid(),NULL,ARRAY['integration.nse.ucc_registration_requested']);
  IF r->>'code'<>'disabled' THEN RAISE EXCEPTION 'wrong_environment_admitted'; END IF;
  r:=public.admit_outbox_dispatch('DEV','https://wrong-project.supabase.co','active',gen_random_uuid(),NULL,ARRAY['integration.nse.ucc_registration_requested']);
  IF r->>'code'<>'disabled' THEN RAISE EXCEPTION 'wrong_project_admitted'; END IF;
  r:=public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',request_id,event_id,ARRAY['integration.nse.ucc_registration_requested']);
  IF r->>'code'<>'admitted' OR jsonb_array_length(r->'candidates')<>1 OR r::text LIKE '%must-not-leak%' THEN RAISE EXCEPTION 'event_admission_failed'; END IF;
  token:=(r->>'batch_token')::uuid;
  IF NOT public.authorize_outbox_dispatch(token,event_id,'DEV','https://synthetic-dev.supabase.co') OR
    public.authorize_outbox_dispatch(gen_random_uuid(),event_id,'DEV','https://synthetic-dev.supabase.co') THEN RAISE EXCEPTION 'admission_ownership_failed'; END IF;
  r:=public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',gen_random_uuid(),NULL,ARRAY['integration.nse.ucc_registration_requested']);
  IF r->>'code'<>'busy' THEN RAISE EXCEPTION 'parallel_admission_allowed'; END IF;
  IF public.finish_outbox_dispatch(gen_random_uuid(),NULL) THEN RAISE EXCEPTION 'foreign_release_allowed'; END IF;
  PERFORM public.finish_outbox_dispatch(token,NULL);
  r:=public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',request_id,event_id,ARRAY['integration.nse.ucc_registration_requested']);
  IF r->>'code'<>'replay' THEN RAISE EXCEPTION 'replay_admitted'; END IF;
  r:=public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',gen_random_uuid(),event_id,ARRAY['integration.nse.ucc_registration_requested']);
  IF jsonb_array_length(r->'candidates')<>0 THEN RAISE EXCEPTION 'duplicate_not_throttled'; END IF;
  PERFORM public.finish_outbox_dispatch((r->>'batch_token')::uuid,NULL);
  r:=public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',gen_random_uuid(),NULL,ARRAY['integration.nse.ucc_registration_requested','integration.nse.ucc_verification_requested']);
  IF jsonb_array_length(r->'candidates')<>2 THEN RAISE EXCEPTION 'recovery_retry_expired_lease_failed'; END IF;
  PERFORM public.finish_outbox_dispatch((r->>'batch_token')::uuid,NULL);
END $$;
RESET ROLE;
-- Delivery bookkeeping cannot claim/complete events or change evidence/attempts.
DO $$ BEGIN
 IF (SELECT status FROM public.event_outbox WHERE id='d0060000-0000-4000-8000-000000000001') <> 'pending'
 OR (SELECT retry_count FROM public.event_outbox WHERE id='d0060000-0000-4000-8000-000000000001') <> 0 THEN RAISE EXCEPTION 'business_state_changed'; END IF;
END $$;
-- Retry eligibility and ambiguous/reconciliation exclusion are shared with legacy feed.
UPDATE moneybowl_dispatch.attempts SET offered_at=now()-interval '16 minutes';
UPDATE public.integration_operations SET state='SUBMITTING' WHERE id='d0050000-0000-4000-8000-000000000001';
UPDATE public.integration_operations SET state='RECONCILIATION_REQUIRED', ambiguous_outcome=true, reconciliation_required=true
  WHERE id='d0050000-0000-4000-8000-000000000001';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM moneybowl_dispatch.eligible_events(ARRAY['integration.nse.ucc_registration_requested'],30)
    WHERE event_outbox_id='d0060000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'ambiguous_resubmitted'; END IF;
  BEGIN UPDATE moneybowl_dispatch.control SET environment='QA'; RAISE EXCEPTION 'qa_activation_allowed';
    EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
-- Observation works in QA without creating dispatch attempts or enabling workers.
UPDATE moneybowl_dispatch.control SET mode='observe',environment='QA';
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb; BEGIN
  r:=public.admit_outbox_dispatch('QA','https://synthetic-dev.supabase.co','observe',gen_random_uuid(),NULL,ARRAY['integration.nse.ucc_verification_requested']);
  IF r->>'code'<>'admitted' THEN RAISE EXCEPTION 'qa_observe_failed'; END IF;
  IF public.authorize_outbox_dispatch((r->>'batch_token')::uuid,'d0060000-0000-4000-8000-000000000002','QA','https://synthetic-dev.supabase.co') THEN RAISE EXCEPTION 'qa_worker_authorized'; END IF;
  PERFORM public.finish_outbox_dispatch((r->>'batch_token')::uuid,NULL);
END $$;
RESET ROLE;
-- Test pg_net boundary without an HTTP transport. Queue insertion has the same
-- transaction semantics; real platform post-commit behavior is a commissioning check.
CREATE SCHEMA IF NOT EXISTS net;
CREATE TABLE moneybowl_dispatch.test_notifications(id bigint GENERATED ALWAYS AS IDENTITY, url text, body jsonb, headers jsonb);
CREATE OR REPLACE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}', params jsonb DEFAULT '{}',
  headers jsonb DEFAULT '{"Content-Type":"application/json"}', timeout_milliseconds integer DEFAULT 1000)
RETURNS bigint LANGUAGE plpgsql AS $$ DECLARE result bigint; BEGIN
  INSERT INTO moneybowl_dispatch.test_notifications(url,body,headers) VALUES(url,body,headers) RETURNING id INTO result;
  RETURN result;
END $$;
SELECT vault.create_secret(repeat('synthetic-notification-key-',3),'moneybowl_outbox_notification_key');
UPDATE moneybowl_dispatch.control SET mode='active',environment='DEV';
INSERT INTO public.integration_operations(
 id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,
 operation_type,api_key,contract_version,state,retry_allowed)
SELECT ('d0080000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 'd0030000-0000-4000-8000-000000000001','d0040000-0000-4000-8000-000000000001',
 'NSE_INVEST','UAT','REFERENCE_DATA','READ_ONLY','DISPATCH_TEST','DISPATCH_TEST','TEST_1','QUEUED',false
FROM generate_series(1,60) i;
SAVEPOINT notification_rollback;
INSERT INTO public.event_outbox(id,event_type,payload,status,entity_id,entity_type)
SELECT ('d0070000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
  'integration.nse.ucc_registration_requested','{"PAN":"must-not-copy"}', 'pending',
  ('d0080000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'integration_operation' FROM generate_series(1,60) i;
DO $$ DECLARE n record; expected text; BEGIN
  IF (SELECT count(*) FROM moneybowl_dispatch.test_notifications)<>1 THEN RAISE EXCEPTION 'bulk_notification_not_coalesced'; END IF;
  SELECT * INTO n FROM moneybowl_dispatch.test_notifications;
  IF n.body::text LIKE '%must-not-copy%' OR (SELECT count(*) FROM jsonb_object_keys(n.body))<>8 THEN RAISE EXCEPTION 'notification_payload_leak'; END IF;
  expected:='1|'||(n.body->>'request_id')||'|'||(n.body->>'issued_at')||'|DEV|https://synthetic-dev.supabase.co|event|'||(n.body->>'event_outbox_id')||'|0';
  IF n.headers->>'X-Outbox-Signature' <> encode(extensions.hmac(expected,repeat('synthetic-notification-key-',3),'sha256'),'hex') THEN RAISE EXCEPTION 'hmac_invalid'; END IF;
END $$;
ROLLBACK TO notification_rollback;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM moneybowl_dispatch.test_notifications) OR EXISTS (SELECT 1 FROM public.event_outbox WHERE id::text LIKE 'd007%') THEN RAISE EXCEPTION 'rollback_notification_leak'; END IF;
END $$;
-- Notification failure must not roll back business events; recovery can still find them.
CREATE OR REPLACE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}', params jsonb DEFAULT '{}',
  headers jsonb DEFAULT '{"Content-Type":"application/json"}', timeout_milliseconds integer DEFAULT 1000)
RETURNS bigint LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic_queue_failure'; END $$;
INSERT INTO public.event_outbox(id,event_type,payload,status,entity_id,entity_type)
SELECT ('d0070000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
  'integration.nse.ucc_registration_requested','{}','pending',
  ('d0080000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'integration_operation' FROM generate_series(1,60) i;
-- A specific event beyond the original 50-row feed limit remains reachable.
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb; total integer:=0; count_batch integer; BEGIN
  r:=public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',gen_random_uuid(),
    'd0070000-0000-4000-8000-000000000060',ARRAY['integration.nse.ucc_registration_requested']);
  IF jsonb_array_length(r->'candidates')<>1 THEN RAISE EXCEPTION 'event_after_50_starved'; END IF;
  PERFORM public.finish_outbox_dispatch((r->>'batch_token')::uuid,NULL);
  LOOP
    r:=public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',gen_random_uuid(),NULL,ARRAY['integration.nse.ucc_registration_requested']);
    count_batch:=jsonb_array_length(r->'candidates');
    IF count_batch>4 THEN RAISE EXCEPTION 'batch_unbounded'; END IF;
    total:=total+count_batch;
    PERFORM public.finish_outbox_dispatch((r->>'batch_token')::uuid,NULL);
    EXIT WHEN count_batch=0;
    IF total>60 THEN RAISE EXCEPTION 'backlog_loop'; END IF;
  END LOOP;
  IF total<>59 THEN RAISE EXCEPTION 'backlog_starvation:%',total; END IF;
END $$;
RESET ROLE;
-- Interruption: abandoned admission is recoverable after its lease, with a new fence.
UPDATE moneybowl_dispatch.control SET batch_token=gen_random_uuid(),lease_until=now()-interval '1 second';
UPDATE moneybowl_dispatch.attempts SET offered_at=now()-interval '16 minutes';
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb; BEGIN
  r:=public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','active',gen_random_uuid(),NULL,ARRAY['integration.nse.ucc_registration_requested']);
  IF r->>'code'<>'admitted' OR jsonb_array_length(r->'candidates')<>4 THEN RAISE EXCEPTION 'interruption_recovery_failed'; END IF;
  PERFORM public.finish_outbox_dispatch((r->>'batch_token')::uuid,1);
END $$;
RESET ROLE;
-- Advisory/lint validation of new functions; transition relation exists only inside trigger.
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
DO $$ DECLARE fn record; finding record; BEGIN
  FOR fn IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_language l ON l.oid=p.prolang WHERE l.lanname='plpgsql' AND
    ((n.nspname='moneybowl_dispatch' AND p.proname<>'on_insert') OR
     (n.nspname='public' AND p.proname IN ('admit_outbox_dispatch','authorize_outbox_dispatch','finish_outbox_dispatch','list_dispatchable_outbox_events')))
  LOOP
    FOR finding IN SELECT * FROM extensions.plpgsql_check_function_tb(fn.oid::regprocedure,fatal_errors:=false) LOOP
      IF finding.level='error' THEN RAISE EXCEPTION 'm2_lint_failed:%:%',fn.oid::regprocedure,finding.message; END IF;
    END LOOP;
  END LOOP;
END $$;
ROLLBACK;
