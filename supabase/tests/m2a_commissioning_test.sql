BEGIN;
CREATE FUNCTION pg_temp.check_it(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'M2A_FAIL:%',label; END IF; RAISE NOTICE 'M2A_PASS:%',label; END $$;
CREATE FUNCTION pg_temp.reject(stmt text, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE stmt; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM=expected THEN RAISE NOTICE 'M2A_PASS:%',expected; RETURN; END IF; RAISE;
 END;
 RAISE EXCEPTION 'M2A_EXPECTED_REJECTION:%',expected;
END $$;
SELECT pg_temp.check_it((SELECT mode='disabled' FROM moneybowl_dispatch.control),'fresh_disabled');
SELECT pg_temp.check_it((SELECT count(*)=1 AND NOT bool_or(active) FROM cron.job WHERE jobname='moneybowl-outbox-recovery'),'fresh_single_inactive_cron');
SELECT moneybowl_dispatch.provision_recovery();
SELECT moneybowl_dispatch.provision_recovery();
SELECT pg_temp.check_it((SELECT count(*)=1 AND NOT bool_or(active) FROM cron.job WHERE jobname='moneybowl-outbox-recovery'),'schedule_idempotent');
SELECT pg_temp.check_it((moneybowl_dispatch.commission_status()->>'extensions_ready')::boolean,'extensions_installed');
SAVEPOINT wrong_schedule;
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname='moneybowl-outbox-recovery'),command:='SELECT 1;');
SELECT pg_temp.reject('SELECT moneybowl_dispatch.provision_recovery()','commission_schedule_conflict');
ROLLBACK TO wrong_schedule;

SELECT pg_temp.check_it(NOT (moneybowl_dispatch.commission_status()->>'key_present')::boolean,'no_secret_fallback');
SELECT pg_temp.check_it(NOT has_schema_privilege('service_role','moneybowl_dispatch','USAGE'),'private_schema');
SET LOCAL ROLE anon;
DO $$ BEGIN PERFORM moneybowl_dispatch.commission_status(); RAISE EXCEPTION 'anon_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$ BEGIN PERFORM moneybowl_dispatch.commission('rollback','{}'); RAISE EXCEPTION 'service_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
CREATE TEMP TABLE args AS SELECT jsonb_build_object('environment','DEV','project_ref','abcdefghijklmnopqrst','revision',repeat('a',40),
 'id',gen_random_uuid(),'actor','synthetic-owner','ticket','TEST-M2A') AS a;
SELECT moneybowl_dispatch.commission('bind',a) FROM args;
SELECT moneybowl_dispatch.commission('bind',a) FROM args;
SELECT pg_temp.check_it((SELECT count(*)=1 FROM moneybowl_dispatch.commission_audit WHERE action='bind'),'bind_idempotent');
SELECT pg_temp.reject(format('SELECT moneybowl_dispatch.commission(''status'',%L::jsonb)',a||'{"environment":"QA"}'), 'commission_project_mismatch') FROM args;
SELECT pg_temp.reject(format('SELECT moneybowl_dispatch.commission(''status'',%L::jsonb)',a||'{"project_ref":"wrongprojectabcdefgh"}'), 'commission_project_mismatch') FROM args;
SELECT pg_temp.reject('SELECT moneybowl_dispatch.commission_probe(''recovery'')','commission_observe_required');
SELECT vault.create_secret(repeat('synthetic-only-m2a-',4),'moneybowl_outbox_notification_key');
SELECT pg_temp.check_it((moneybowl_dispatch.commission_status()->>'key_present')::boolean,'secret_presence');
-- Probes use the real pg_net enqueue API inside this rollback-only transaction.
SELECT moneybowl_dispatch.commission_probe('readiness');
SELECT pg_temp.check_it((SELECT count(*)=1 FROM moneybowl_dispatch.commission_probes),'probe_enqueued');
-- Hosted response fixtures are synthetic, never NSE calls. Deno tests prove Edge side effects are zero.
INSERT INTO moneybowl_dispatch.commission_probes(id,nonce,issued_at,kind) VALUES
 (90001,'11111111-1111-4111-8111-111111111111',1,'readiness'),
 (90002,'22222222-2222-4222-8222-222222222222',1,'recovery'),
 (90003,'22222222-2222-4222-8222-222222222222',1,'recovery'),
 (90004,'33333333-3333-4333-8333-333333333333',1,'readiness');
INSERT INTO net._http_response(id,status_code,content,timed_out) VALUES
 (90001,200,'{"code":"outbox_ready","mode":"observe","environment":"DEV","project_url":"https://abcdefghijklmnopqrst.supabase.co"}',false),
 (90002,200,'{"code":"outbox_processed","count":0}',false),
 (90003,202,'{"code":"outbox_replay"}',false),
 (90004,200,'{"code":"outbox_ready","mode":"active","environment":"DEV","project_url":"https://abcdefghijklmnopqrst.supabase.co"}',false);
SELECT moneybowl_dispatch.commission('observe',a||'{"probe_id":90001}') FROM args;
SELECT moneybowl_dispatch.commission('record_observe',a||jsonb_build_object('id',gen_random_uuid(),'probe_id',90002,'replay_id',90003)) FROM args;
SELECT pg_temp.check_it((SELECT count(*)=0 FROM moneybowl_dispatch.attempts),'observe_no_delivery_attempts');
SELECT moneybowl_dispatch.commission_probe('recovery') AS canonical_recovery_id \gset
SELECT moneybowl_dispatch.commission_probe('recovery',:canonical_recovery_id) AS canonical_replay_id \gset
SELECT pg_temp.check_it((SELECT a.body=b.body AND a.headers=b.headers FROM net.http_request_queue a,net.http_request_queue b
 WHERE a.id=:canonical_recovery_id AND b.id=:canonical_replay_id),'canonical_signer_and_replay_identical');
SELECT pg_temp.reject('UPDATE moneybowl_dispatch.commission_audit SET actor=''changed''','commission_audit_immutable');
SELECT pg_temp.reject('DELETE FROM moneybowl_dispatch.commission_audit','commission_audit_immutable');

SELECT moneybowl_dispatch.commission('rollback',a||jsonb_build_object('id',gen_random_uuid())) FROM args;
SELECT pg_temp.check_it((SELECT mode='disabled' FROM moneybowl_dispatch.control),'rollback_disabled_first');
SELECT pg_temp.check_it((SELECT NOT active FROM cron.job WHERE jobname='moneybowl-outbox-recovery'),'rollback_schedule_disabled');
UPDATE args SET a=a||jsonb_build_object('id',gen_random_uuid(),'probe_id',90004,'expires_at',now()+interval '10 minutes','oracle_retired',false,'backlog_authorized',true);
SELECT pg_temp.reject(format('SELECT moneybowl_dispatch.commission(''activate'',%L::jsonb)',a),'commission_approval_invalid') FROM args;
SELECT pg_temp.check_it((SELECT mode='disabled' FROM moneybowl_dispatch.control),'failed_activation_disabled');
UPDATE args SET a=a||'{"oracle_retired":true}';
SELECT pg_temp.reject(format('SELECT moneybowl_dispatch.commission(''activate'',%L::jsonb)',a||jsonb_build_object('expires_at',now()-interval '1 second')),'commission_approval_invalid') FROM args;
SELECT pg_temp.reject(format('SELECT moneybowl_dispatch.commission(''activate'',%L::jsonb)',a||jsonb_build_object('revision',repeat('b',40))),'commission_observe_stale') FROM args;
SELECT pg_temp.reject(format('SELECT moneybowl_dispatch.commission(''activate'',%L::jsonb)',a||'{"probe_id":90001}'),'commission_edge_not_active') FROM args;

SELECT moneybowl_dispatch.commission('activate',a) FROM args;
SELECT moneybowl_dispatch.commission('activate',a) FROM args;
SELECT pg_temp.check_it((SELECT mode='active' FROM moneybowl_dispatch.control),'approved_dev_active');
SELECT pg_temp.check_it((SELECT active FROM cron.job WHERE jobname='moneybowl-outbox-recovery'),'approved_schedule_active');
SELECT pg_temp.check_it((SELECT oracle_retired AND backlog_authorized AND expires_at>created_at AND readiness_probe=90004
 FROM moneybowl_dispatch.commission_audit WHERE action='activate'),'approval_evidence_persisted');

SELECT moneybowl_dispatch.provision_recovery();
SELECT pg_temp.check_it((SELECT active FROM cron.job WHERE jobname='moneybowl-outbox-recovery'),'redeploy_preserves_existing_activation');
SELECT moneybowl_dispatch.commission('rollback',a||jsonb_build_object('id',gen_random_uuid())) FROM args;
SELECT pg_temp.reject(format('SELECT moneybowl_dispatch.commission(''activate'',%L::jsonb)',a),'commission_approval_consumed') FROM args;
-- Fresh synthetic QA/PROD identities retain the same disabled implementation and guards.
UPDATE moneybowl_dispatch.commission_identity SET environment='QA'; UPDATE moneybowl_dispatch.control SET environment='QA';
SELECT pg_temp.reject(format('SELECT moneybowl_dispatch.commission(''activate'',%L::jsonb)',a||'{"environment":"QA"}'),'commission_activation_dev_only') FROM args;
UPDATE moneybowl_dispatch.commission_identity SET environment='PROD'; UPDATE moneybowl_dispatch.control SET environment='PROD';
SELECT pg_temp.reject(format('SELECT moneybowl_dispatch.commission(''activate'',%L::jsonb)',a||'{"environment":"PROD"}'),'commission_activation_dev_only') FROM args;
SELECT pg_temp.check_it((SELECT mode='disabled' FROM moneybowl_dispatch.control),'non_dev_still_disabled');
ROLLBACK;
