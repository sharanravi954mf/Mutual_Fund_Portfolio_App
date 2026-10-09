-- M2A: hosted GitHub integration installs infrastructure, never activates dispatch.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault;
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE TABLE moneybowl_dispatch.commission_identity (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 environment text NOT NULL CHECK(environment IN ('DEV','QA','PROD')),
 project_ref text NOT NULL CHECK(project_ref ~ '^[a-z0-9]{20}$')
);
CREATE TABLE moneybowl_dispatch.commission_audit (
 id uuid PRIMARY KEY,
 action text NOT NULL CHECK(action IN ('observe','activate','rollback','bind')),
 revision text NOT NULL CHECK(revision ~ '^[a-f0-9]{40}$'),
 actor text NOT NULL CHECK(actor ~ '^[A-Za-z0-9_.@ -]{1,100}$'),
 ticket text NOT NULL CHECK(ticket ~ '^[A-Za-z0-9_.:/-]{1,200}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 database_actor name NOT NULL DEFAULT session_user,
 expires_at timestamptz,
 oracle_retired boolean,
 backlog_authorized boolean,
 readiness_probe bigint,
 recovery_probe bigint,
 CHECK(action<>'activate' OR (expires_at IS NOT NULL AND oracle_retired IS TRUE
  AND backlog_authorized IS TRUE AND readiness_probe IS NOT NULL))
);
CREATE TABLE moneybowl_dispatch.commission_probes (
 id bigint PRIMARY KEY,
 nonce uuid NOT NULL,
 issued_at bigint NOT NULL,
 kind text NOT NULL CHECK(kind IN ('readiness','recovery')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE moneybowl_dispatch.commission_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE moneybowl_dispatch.commission_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE moneybowl_dispatch.commission_probes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON moneybowl_dispatch.commission_identity,moneybowl_dispatch.commission_audit,
 moneybowl_dispatch.commission_probes FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION moneybowl_dispatch.commission_audit_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'commission_audit_immutable'; END $$;
REVOKE ALL ON FUNCTION moneybowl_dispatch.commission_audit_immutable() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER commission_audit_immutable BEFORE UPDATE OR DELETE ON moneybowl_dispatch.commission_audit
FOR EACH ROW EXECUTE FUNCTION moneybowl_dispatch.commission_audit_immutable();

CREATE FUNCTION moneybowl_dispatch.provision_recovery() RETURNS bigint
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE j bigint; existing_active boolean;
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(720021);
 IF (SELECT count(*) FROM cron.job WHERE jobname='moneybowl-outbox-recovery')>1 THEN
  RAISE EXCEPTION 'commission_schedule_duplicate';
 END IF;
 SELECT jobid,active INTO j,existing_active FROM cron.job WHERE jobname='moneybowl-outbox-recovery';
 IF j IS NOT NULL AND EXISTS(SELECT 1 FROM cron.job WHERE jobid=j AND
   (username<>current_user OR database<>current_database() OR command<>'SELECT moneybowl_dispatch.notify(NULL,0);')) THEN
  RAISE EXCEPTION 'commission_schedule_conflict';
 END IF;
 IF j IS NULL THEN
  j:=cron.schedule('moneybowl-outbox-recovery','*/15 * * * *','SELECT moneybowl_dispatch.notify(NULL,0);');
  PERFORM cron.alter_job(j,active:=false);
 ELSE
  PERFORM cron.alter_job(j,schedule:='*/15 * * * *',active:=existing_active);
 END IF;
 RETURN j;
END $$;

CREATE FUNCTION moneybowl_dispatch.commission_status() RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object(
  'mode',c.mode,'environment',i.environment,'project_ref',i.project_ref,
  'binding_matches',c.environment=i.environment AND c.project_url='https://' || i.project_ref || '.supabase.co',
  'key_present',(SELECT count(*)=1 FROM vault.secrets WHERE name='moneybowl_outbox_notification_key'),
  'extensions_ready',(SELECT count(*)=4 FROM pg_extension WHERE extname IN ('pg_net','pg_cron','pgcrypto','supabase_vault')),
  'schedule_count',(SELECT count(*) FROM cron.job WHERE jobname='moneybowl-outbox-recovery'),
  'schedule_ready',EXISTS(SELECT 1 FROM cron.job WHERE jobname='moneybowl-outbox-recovery' AND schedule='*/15 * * * *'
    AND command='SELECT moneybowl_dispatch.notify(NULL,0);' AND username=current_user AND database=current_database()),
  'schedule_active',coalesce((SELECT bool_or(active) FROM cron.job WHERE jobname='moneybowl-outbox-recovery'),false),
  'inflight',(SELECT count(*) FROM public.event_outbox WHERE status='processing')+
    (SELECT count(*) FROM moneybowl_onboarding.kyc_operations WHERE state IN ('CLAIMED','SUBMITTING'))+
    CASE WHEN c.lease_until>now() THEN 1 ELSE 0 END,
  'pending',(SELECT count(*) FROM public.event_outbox WHERE status='pending'),
  'ambiguous',(SELECT count(*) FROM public.integration_operations WHERE ambiguous_outcome OR reconciliation_required)+
    (SELECT count(*) FROM moneybowl_onboarding.kyc_operations WHERE state='RECONCILIATION_REQUIRED' OR (transmission='MAYBE_SENT' AND state IN ('CLAIMED','SUBMITTING','RETRY'))),
  'last_cron_status',(SELECT status FROM cron.job_run_details WHERE jobid IN (SELECT jobid FROM cron.job WHERE jobname='moneybowl-outbox-recovery') ORDER BY runid DESC LIMIT 1),
  'last_observe',(SELECT max(created_at) FROM moneybowl_dispatch.commission_audit WHERE action='observe'))
 FROM moneybowl_dispatch.control c LEFT JOIN moneybowl_dispatch.commission_identity i USING(singleton) WHERE c.singleton;
$$;

-- Only the database owner can enqueue these bounded, fixed-destination probes.
-- No key, signature, headers or raw response is ever returned to the controller.
CREATE FUNCTION moneybowl_dispatch.commission_probe(p_kind text, p_replay bigint DEFAULT NULL) RETURNS bigint
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE c moneybowl_dispatch.control%ROWTYPE; k text; nonce uuid:=gen_random_uuid();
 issued bigint:=floor(extract(epoch FROM clock_timestamp())); n jsonb; sig text; result bigint;
BEGIN
 SELECT * INTO c FROM moneybowl_dispatch.control WHERE singleton FOR UPDATE;
 IF p_kind NOT IN ('readiness','recovery') OR p_kind IS NULL OR c.environment IS NULL OR c.project_url IS NULL THEN
  RAISE EXCEPTION 'commission_probe_invalid'; END IF;
 IF p_kind='recovery' AND c.mode<>'observe' THEN RAISE EXCEPTION 'commission_observe_required'; END IF;
 IF p_kind='recovery' AND p_replay IS NULL THEN
  -- Exercise M2's canonical signer and recovery notification, not a substitute.
  result:=moneybowl_dispatch.notify(NULL,0);
  IF result IS NULL THEN RAISE EXCEPTION 'commission_enqueue_failed'; END IF;
  SELECT convert_from(q.body,'UTF8')::jsonb INTO STRICT n FROM net.http_request_queue q WHERE q.id=result;
  INSERT INTO moneybowl_dispatch.commission_probes(id,nonce,issued_at,kind)
   VALUES(result,(n->>'request_id')::uuid,(n->>'issued_at')::bigint,p_kind);
  RETURN result;
 END IF;
 IF p_replay IS NOT NULL THEN
  SELECT p.nonce,p.issued_at INTO STRICT nonce,issued FROM moneybowl_dispatch.commission_probes p
   WHERE p.id=p_replay AND p.kind=p_kind AND p.created_at>now()-interval '4 minutes';
 END IF;
 SELECT decrypted_secret INTO STRICT k FROM vault.decrypted_secrets WHERE name='moneybowl_outbox_notification_key';
 IF k IS NULL OR length(k) NOT BETWEEN 32 AND 4096 OR k !~ '^[!-~]+$' THEN RAISE EXCEPTION 'commission_key_invalid'; END IF;
 n:=jsonb_build_object('version',1,'request_id',nonce,'issued_at',issued,'environment',c.environment,
  'project_url',c.project_url,'kind',p_kind,'event_outbox_id',NULL,'hop',0);
 sig:=encode(extensions.hmac('1|'||nonce::text||'|'||issued::text||'|'||c.environment||'|'||c.project_url||'|'||p_kind||'|-|0',k,'sha256'),'hex');
 result:=net.http_post(url:=c.project_url||'/functions/v1/outbox-dispatcher/'||p_kind,body:=n,
  headers:=jsonb_build_object('Content-Type','application/json','X-Outbox-Signature',sig),timeout_milliseconds:=10000);
 INSERT INTO moneybowl_dispatch.commission_probes(id,nonce,issued_at,kind) VALUES(result,nonce,issued,p_kind);
 DELETE FROM moneybowl_dispatch.commission_probes WHERE created_at<now()-interval '1 day';
 RETURN result;
END $$;

CREATE FUNCTION moneybowl_dispatch.commission_result(p_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE r net._http_response%ROWTYPE; body jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM moneybowl_dispatch.commission_probes WHERE id=p_id) THEN RAISE EXCEPTION 'commission_probe_unknown'; END IF;
 SELECT * INTO r FROM net._http_response WHERE id=p_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('pending',true); END IF;
 IF r.timed_out OR r.error_msg IS NOT NULL OR octet_length(r.content)>12000 THEN RETURN jsonb_build_object('failed',true); END IF;
 BEGIN body:=r.content::jsonb; EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('failed',true); END;
 IF body->>'code' NOT IN ('outbox_ready','outbox_processed','outbox_replay','outbox_disabled') OR body->>'code' IS NULL THEN
  RETURN jsonb_build_object('failed',true,'status',r.status_code); END IF;
 -- Routes originate in the trusted generated Edge contract; controller checks exact parity.
 RETURN jsonb_build_object('status',r.status_code,'code',body->>'code','mode',body->>'mode',
  'environment',body->>'environment','project_url',body->>'project_url','routes',body->'routes','count',body->'count');
END $$;

CREATE FUNCTION moneybowl_dispatch.commission(p_action text,p_args jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE c moneybowl_dispatch.control%ROWTYPE; i moneybowl_dispatch.commission_identity%ROWTYPE;
 s jsonb; r jsonb; j bigint; audit_id uuid; rev text:=p_args->>'revision';
 env text:=p_args->>'environment'; ref text:=p_args->>'project_ref';
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(720021);
 IF env IS NULL OR env NOT IN ('DEV','QA','PROD') OR ref IS NULL OR ref !~ '^[a-z0-9]{20}$'
  OR rev IS NULL OR rev !~ '^[a-f0-9]{40}$' THEN RAISE EXCEPTION 'commission_config_invalid'; END IF;
 SELECT * INTO c FROM moneybowl_dispatch.control WHERE singleton FOR UPDATE;
 SELECT * INTO i FROM moneybowl_dispatch.commission_identity WHERE singleton;
 IF i.singleton AND (i.environment<>env OR i.project_ref<>ref) THEN RAISE EXCEPTION 'commission_project_mismatch'; END IF;
 IF c.environment IS NOT NULL AND (c.environment<>env OR c.project_url<>'https://'||ref||'.supabase.co') THEN
  RAISE EXCEPTION 'commission_project_mismatch'; END IF;
 IF p_action='status' THEN RETURN moneybowl_dispatch.commission_status(); END IF;
 IF p_action='bind' THEN
  IF c.mode<>'disabled' THEN RAISE EXCEPTION 'commission_disabled_required'; END IF;
  INSERT INTO moneybowl_dispatch.commission_identity(environment,project_ref) VALUES(env,ref) ON CONFLICT DO NOTHING;
  UPDATE moneybowl_dispatch.control SET environment=env,project_url='https://'||ref||'.supabase.co' WHERE singleton;
 ELSIF p_action='rollback' THEN
  -- First committed controller operation: stop admissions even if Edge management is unavailable.
  UPDATE moneybowl_dispatch.control SET mode='disabled' WHERE singleton;
  FOR j IN SELECT jobid FROM cron.job WHERE jobname='moneybowl-outbox-recovery' LOOP
   PERFORM cron.alter_job(j,active:=false);
  END LOOP;
 ELSIF NOT coalesce(i.singleton,false) THEN RAISE EXCEPTION 'commission_bootstrap_required';
 ELSIF p_action='schedule' THEN PERFORM moneybowl_dispatch.provision_recovery(); RETURN moneybowl_dispatch.commission_status();
 ELSIF p_action='observe' THEN
  IF c.mode='active' THEN RAISE EXCEPTION 'commission_active_conflict'; END IF;
  r:=moneybowl_dispatch.commission_result((p_args->>'probe_id')::bigint);
  IF r->>'code' IS DISTINCT FROM 'outbox_ready' OR r->>'mode' IS DISTINCT FROM 'observe' OR r->>'environment' IS DISTINCT FROM env
   OR r->>'project_url' IS DISTINCT FROM c.project_url OR NOT EXISTS(SELECT 1 FROM moneybowl_dispatch.commission_probes
   WHERE id=(p_args->>'probe_id')::bigint AND created_at>now()-interval '2 minutes') THEN RAISE EXCEPTION 'commission_edge_not_observe'; END IF;
  UPDATE moneybowl_dispatch.control SET mode='observe' WHERE singleton;
  RETURN moneybowl_dispatch.commission_status();
 ELSIF p_action='record_observe' THEN
  IF c.mode<>'observe' THEN RAISE EXCEPTION 'commission_observe_required'; END IF;
  r:=moneybowl_dispatch.commission_result((p_args->>'probe_id')::bigint);
  IF r->>'code' IS DISTINCT FROM 'outbox_processed' OR (r->>'status')::int<>200 OR NOT EXISTS(SELECT 1 FROM moneybowl_dispatch.commission_probes
   WHERE id=(p_args->>'probe_id')::bigint AND kind='recovery' AND created_at>now()-interval '2 minutes') THEN RAISE EXCEPTION 'commission_observe_failed'; END IF;
  IF NOT EXISTS(SELECT 1 FROM moneybowl_dispatch.commission_probes a JOIN moneybowl_dispatch.commission_probes b ON a.nonce=b.nonce AND a.issued_at=b.issued_at AND a.kind=b.kind WHERE a.id=(p_args->>'probe_id')::bigint AND b.id=(p_args->>'replay_id')::bigint AND a.id<>b.id) THEN RAISE EXCEPTION 'commission_replay_invalid'; END IF;
  r:=moneybowl_dispatch.commission_result((p_args->>'replay_id')::bigint);
  IF r->>'code' IS DISTINCT FROM 'outbox_replay' OR (r->>'status')::int IS DISTINCT FROM 202 THEN RAISE EXCEPTION 'commission_replay_failed'; END IF;
 ELSIF p_action='activate' THEN
  IF env<>'DEV' THEN RAISE EXCEPTION 'commission_activation_dev_only'; END IF;
  s:=moneybowl_dispatch.commission_status();
  IF c.mode='active' AND EXISTS(SELECT 1 FROM moneybowl_dispatch.commission_audit WHERE id=(p_args->>'id')::uuid AND action='activate' AND revision=rev
   AND actor=p_args->>'actor' AND ticket=p_args->>'ticket' AND expires_at=(p_args->>'expires_at')::timestamptz)
   THEN RETURN s; END IF;
  IF EXISTS(SELECT 1 FROM moneybowl_dispatch.commission_audit WHERE id=(p_args->>'id')::uuid) THEN RAISE EXCEPTION 'commission_approval_consumed'; END IF;
  IF c.mode<>'disabled' OR (s->>'inflight')::int<>0 OR NOT (s->>'key_present')::boolean OR NOT (s->>'schedule_ready')::boolean
   OR (s->>'schedule_count')::int<>1 OR NOT (s->>'extensions_ready')::boolean THEN RAISE EXCEPTION 'commission_not_ready'; END IF;
  IF NOT EXISTS(SELECT 1 FROM moneybowl_dispatch.commission_audit WHERE action='observe' AND revision=rev
   AND created_at>now()-interval '15 minutes') THEN RAISE EXCEPTION 'commission_observe_stale'; END IF;
  IF (p_args->>'expires_at')::timestamptz<=clock_timestamp() OR (p_args->>'expires_at')::timestamptz>clock_timestamp()+interval '15 minutes'
   OR NOT coalesce((p_args->>'oracle_retired')::boolean,false) OR NOT coalesce((p_args->>'backlog_authorized')::boolean,false)
   OR p_args->>'expires_at' IS NULL THEN RAISE EXCEPTION 'commission_approval_invalid'; END IF;
  r:=moneybowl_dispatch.commission_result((p_args->>'probe_id')::bigint);
  IF r->>'code' IS DISTINCT FROM 'outbox_ready' OR r->>'mode' IS DISTINCT FROM 'active' OR r->>'environment' IS DISTINCT FROM env
   OR r->>'project_url' IS DISTINCT FROM c.project_url OR NOT EXISTS(SELECT 1 FROM moneybowl_dispatch.commission_probes
   WHERE id=(p_args->>'probe_id')::bigint AND kind='readiness' AND created_at>now()-interval '2 minutes') THEN RAISE EXCEPTION 'commission_edge_not_active'; END IF;
  UPDATE moneybowl_dispatch.control SET mode='active' WHERE singleton;
  SELECT jobid INTO STRICT j FROM cron.job WHERE jobname='moneybowl-outbox-recovery';
  PERFORM cron.alter_job(j,active:=true);
 ELSE RAISE EXCEPTION 'commission_action_invalid'; END IF;
 audit_id:=(p_args->>'id')::uuid;
 IF EXISTS(SELECT 1 FROM moneybowl_dispatch.commission_audit WHERE id=audit_id AND
   (action<>CASE WHEN p_action='record_observe' THEN 'observe' ELSE p_action END OR revision<>rev OR actor<>p_args->>'actor' OR ticket<>p_args->>'ticket')) THEN
  RAISE EXCEPTION 'commission_audit_conflict'; END IF;
 INSERT INTO moneybowl_dispatch.commission_audit(id,action,revision,actor,ticket,
  expires_at,oracle_retired,backlog_authorized,readiness_probe,recovery_probe)
 VALUES(audit_id,CASE WHEN p_action='record_observe' THEN 'observe' ELSE p_action END,rev,p_args->>'actor',p_args->>'ticket',
  CASE WHEN p_action='activate' THEN (p_args->>'expires_at')::timestamptz END,
  CASE WHEN p_action='activate' THEN (p_args->>'oracle_retired')::boolean END,
  CASE WHEN p_action='activate' THEN (p_args->>'backlog_authorized')::boolean END,
  CASE WHEN p_action='activate' THEN (p_args->>'probe_id')::bigint END,
  CASE WHEN p_action='record_observe' THEN (p_args->>'probe_id')::bigint END) ON CONFLICT DO NOTHING;
 RETURN moneybowl_dispatch.commission_status();
END $$;

REVOKE ALL ON FUNCTION moneybowl_dispatch.provision_recovery(),moneybowl_dispatch.commission_status(),
 moneybowl_dispatch.commission_probe(text,bigint),moneybowl_dispatch.commission_result(bigint),moneybowl_dispatch.commission(text,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
-- Existing GitHub integration applies this migration in every independently bound project.
-- New jobs are inactive, existing activation is preserved, no secrets or binding are invented.
SELECT moneybowl_dispatch.provision_recovery();
DO $$ BEGIN
 IF NOT (moneybowl_dispatch.commission_status()->>'extensions_ready')::boolean OR
    NOT (moneybowl_dispatch.commission_status()->>'schedule_ready')::boolean THEN
  RAISE EXCEPTION 'commission_deployment_verification_failed'; END IF;
END $$;
COMMIT;
