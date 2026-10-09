-- M2 is inert on deployment. No secret, notification, Cron job or activation is provisioned.
BEGIN;
CREATE SCHEMA moneybowl_dispatch;
REVOKE ALL ON SCHEMA moneybowl_dispatch FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE moneybowl_dispatch.control (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  environment text CHECK (environment IN ('DEV','QA','PROD')),
  project_url text CHECK (project_url ~ '^https://[a-z0-9-]+[.]supabase[.]co$'),
  mode text NOT NULL DEFAULT 'disabled' CHECK (mode IN ('disabled','observe','active')),
  batch_token uuid,
  lease_until timestamptz,
  CHECK (mode = 'disabled' OR (environment IS NOT NULL AND project_url IS NOT NULL)),
  -- M1's persisted contracts are UAT-only. No QA/PROD activation flag bypass.
  CHECK (mode <> 'active' OR environment = 'DEV')
);
INSERT INTO moneybowl_dispatch.control(singleton) VALUES (true);
CREATE TABLE moneybowl_dispatch.attempts (
  event_id uuid PRIMARY KEY REFERENCES public.event_outbox(id) ON DELETE CASCADE,
  offered_at timestamptz NOT NULL,
  batch_token uuid NOT NULL
);
CREATE INDEX ON moneybowl_dispatch.attempts(batch_token);
CREATE TABLE moneybowl_dispatch.receipts (
  request_id uuid PRIMARY KEY,
  received_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);
CREATE INDEX ON moneybowl_dispatch.receipts(received_at);
ALTER TABLE moneybowl_dispatch.control ENABLE ROW LEVEL SECURITY;
ALTER TABLE moneybowl_dispatch.attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE moneybowl_dispatch.receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA moneybowl_dispatch FROM PUBLIC, anon, authenticated, service_role;

-- Full composed eligibility at the verified base: B07 approved write intents
-- (20261006105515) plus onboarding composition (20261007130243). Includes
-- integration operations, member-owned reference jobs, and onboarding operations.
-- Both dispatcher paths and the backward-compatible feed share these predicates.
CREATE FUNCTION moneybowl_dispatch.eligible_events(p_event_types text[], p_retry_delay_seconds integer, p_event_id uuid DEFAULT NULL)
RETURNS TABLE (
  event_outbox_id pg_catalog.uuid,
  event_type pg_catalog.text,
  event_status pg_catalog.text,
  retry_count pg_catalog.int4,
  claim_expires_at pg_catalog.timestamptz,
  created_at pg_catalog.timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  SELECT
    event.id AS event_outbox_id,
    event.event_type,
    event.status AS event_status,
    event.retry_count,
    event.claim_expires_at,
    event.created_at
  FROM public.event_outbox AS event
  JOIN public.integration_operations AS operation
    ON event.entity_type = 'integration_operation'
   AND operation.id = event.entity_id
  WHERE event.event_type = ANY (p_event_types)
    AND (p_event_id IS NULL OR event.id = p_event_id)
    AND NOT operation.ambiguous_outcome
    AND NOT operation.reconciliation_required
    AND (
      (
        event.status = 'pending'
        AND operation.state = 'QUEUED'
      )
      OR (
        event.status = 'failed'
        AND operation.state = 'SUBMISSION_FAILED'
        AND operation.retry_allowed
        AND event.updated_at <= pg_catalog.now()
          - pg_catalog.make_interval(secs => p_retry_delay_seconds)
      )
      OR (
        event.status = 'processing'
        AND event.claim_expires_at IS NOT NULL
        AND event.claim_expires_at <= pg_catalog.now()
        AND (operation.state IN ('QUEUED', 'SUBMITTING')
          OR (operation.operation_type IN ('ORDER_STATUS','PROV_ORDERS','CLIENT_READINESS','ORDER_FUNDING','SETTLEMENT_REDEMPTION','SIP_XSIP_REPORTS','STP_SWP_REPORTS','MANDATE_STATUS') AND operation.safety_class = 'READ_ONLY'
            AND operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed)
          OR (operation.operation_type IN ('BANK_MANDATE_WRITE','BANK_MANDATE_VERIFY') AND operation.state='SUBMISSION_FAILED' AND operation.retry_allowed))
      )
    )
  UNION ALL
  SELECT e.id,e.event_type,e.status,e.retry_count,e.claim_expires_at,e.created_at
  FROM public.event_outbox e JOIN nse_reference.jobs j ON j.event_id=e.id AND j.id=e.entity_id
  JOIN nse_reference.connections c ON c.id=j.connection_id AND c.workspace_id=j.workspace_id
  JOIN public.workspaces w ON w.id=j.workspace_id
  WHERE e.event_type='integration.nse.master_download_requested' AND e.entity_type='nse_reference_job'
    AND (p_event_id IS NULL OR e.id = p_event_id)
    AND e.event_type=ANY(p_event_types) AND e.payload='{}'::jsonb AND c.enabled AND c.environment='UAT'
    AND w.workspace_status='active' AND NOT EXISTS(SELECT 1 FROM nse_reference.completions done WHERE done.id=j.id)
    AND (e.status='pending' OR (e.status='processing' AND e.claim_expires_at<=pg_catalog.now()))
  UNION ALL
 SELECT e.id,e.event_type,e.status,e.retry_count,e.claim_expires_at,e.created_at FROM public.event_outbox e
 JOIN moneybowl_onboarding.kyc_operations o ON o.id=e.entity_id AND e.entity_type='onboarding_kyc_operation'
 WHERE (p_event_id IS NULL OR e.id = p_event_id) AND e.event_type=ANY(p_event_types) AND (
 (o.state='QUEUED' AND e.status='pending') OR
 (o.state='RETRY' AND e.status='failed' AND e.updated_at<=now()-make_interval(secs=>p_retry_delay_seconds)) OR
 (o.state IN ('CLAIMED','SUBMITTING') AND e.status='processing' AND o.lease_until<=now()));
$$;

CREATE OR REPLACE FUNCTION public.list_dispatchable_outbox_events(
  p_event_types pg_catalog.text[],
  p_limit pg_catalog.int4 DEFAULT 10,
  p_retry_delay_seconds pg_catalog.int4 DEFAULT 30
)
RETURNS TABLE (
  event_outbox_id pg_catalog.uuid,
  event_type pg_catalog.text,
  event_status pg_catalog.text,
  retry_count pg_catalog.int4,
  claim_expires_at pg_catalog.timestamptz,
  created_at pg_catalog.timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_event_types IS NULL
     OR pg_catalog.cardinality(p_event_types) < 1
     OR pg_catalog.cardinality(p_event_types) > 32 THEN
    RAISE EXCEPTION 'dispatch_event_types_invalid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.unnest(p_event_types) AS requested(event_type)
    WHERE NULLIF(pg_catalog.btrim(requested.event_type), '') IS NULL
       OR requested.event_type !~ '^[a-z0-9][a-z0-9_.-]{0,99}$'
  ) THEN
    RAISE EXCEPTION 'dispatch_event_type_invalid';
  END IF;

  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 50 THEN
    RAISE EXCEPTION 'dispatch_limit_invalid';
  END IF;

  IF p_retry_delay_seconds IS NULL
     OR p_retry_delay_seconds < 0
     OR p_retry_delay_seconds > 3600 THEN
    RAISE EXCEPTION 'dispatch_retry_delay_invalid';
  END IF;

  RETURN QUERY
  SELECT event.*
  FROM moneybowl_dispatch.eligible_events(p_event_types, p_retry_delay_seconds) AS event
  ORDER BY
    CASE WHEN event.event_status = 'processing' THEN 0 ELSE 1 END,
    event.created_at,
    event.event_outbox_id
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.list_dispatchable_outbox_events(
  pg_catalog.text[], pg_catalog.int4, pg_catalog.int4
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.list_dispatchable_outbox_events(
  pg_catalog.text[], pg_catalog.int4, pg_catalog.int4
) TO service_role;

-- Fixed secret name; no caller-selected secret/URL and no secret-returning RPC.
-- pg_net and Vault must be available before separately authorized commissioning.
-- SQL resolves those extension functions only when enabled; migration remains inert.
CREATE FUNCTION moneybowl_dispatch.notify(p_event_id uuid DEFAULT NULL, p_hop integer DEFAULT 0)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  c moneybowl_dispatch.control%ROWTYPE;
  k text;
  n jsonb;
  signing_input text;
  signature text;
  request_id uuid := pg_catalog.gen_random_uuid();
  issued_at bigint := pg_catalog.floor(EXTRACT(epoch FROM pg_catalog.clock_timestamp()));
  kind text := CASE WHEN p_event_id IS NULL THEN 'recovery' ELSE 'event' END;
  result bigint;
BEGIN
  SELECT * INTO c FROM moneybowl_dispatch.control WHERE singleton;
  IF c.mode = 'disabled' OR c.environment IS NULL OR c.project_url IS NULL THEN RETURN NULL; END IF;
  IF p_hop IS NULL OR p_hop NOT BETWEEN 0 AND 15 OR (p_event_id IS NOT NULL AND p_hop <> 0) THEN
    RAISE EXCEPTION 'outbox_notification_invalid';
  END IF;
  SELECT decrypted_secret INTO STRICT k FROM vault.decrypted_secrets
    WHERE name = 'moneybowl_outbox_notification_key';
  IF k IS NULL OR pg_catalog.length(k) NOT BETWEEN 32 AND 4096 OR k !~ '^[!-~]+$' THEN RAISE EXCEPTION 'outbox_notification_key_invalid'; END IF;
  signing_input := '1|' || request_id::text || '|' || issued_at::text || '|' || c.environment
    || '|' || c.project_url || '|' || kind || '|' || COALESCE(p_event_id::text, '-') || '|' || p_hop::text;
  signature := pg_catalog.encode(extensions.hmac(signing_input, k, 'sha256'), 'hex');
  n := pg_catalog.jsonb_build_object('version',1,'request_id',request_id,'issued_at',issued_at,
    'environment',c.environment,'project_url',c.project_url,'kind',kind,'event_outbox_id',p_event_id,'hop',p_hop);
  SELECT net.http_post(url := c.project_url || '/functions/v1/outbox-dispatcher/' || kind,
    body := n, headers := pg_catalog.jsonb_build_object('Content-Type','application/json','X-Outbox-Signature',signature),
    timeout_milliseconds := 75000) INTO result;
  RETURN result;
EXCEPTION WHEN OTHERS THEN
  -- Preserve committed financial work even if notification provisioning/queueing fails.
  -- Fixed diagnostic only: never SQLERRM, payload, signature, URL or credential.
  RAISE WARNING 'outbox_notification_unavailable';
  RETURN NULL;
END;
$$;

CREATE FUNCTION moneybowl_dispatch.on_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE event_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM moneybowl_dispatch.control WHERE singleton AND mode <> 'disabled') THEN
    RETURN NULL;
  END IF;
  -- One wake per INSERT statement, including bulk insertion. Remaining records drain
  -- through the same recovery path; no row payload is serialized or returned.
  SELECT inserted.id INTO event_id FROM m2_inserted_outbox inserted
    WHERE EXISTS (SELECT 1 FROM moneybowl_dispatch.eligible_events(ARRAY[inserted.event_type],30,inserted.id) eligible
      WHERE eligible.event_outbox_id = inserted.id)
    ORDER BY inserted.id LIMIT 1;
  IF event_id IS NOT NULL THEN PERFORM moneybowl_dispatch.notify(event_id,0); END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'outbox_notification_unavailable';
  RETURN NULL;
END;
$$;
CREATE TRIGGER m2_outbox_insert AFTER INSERT ON public.event_outbox
REFERENCING NEW TABLE AS m2_inserted_outbox
FOR EACH STATEMENT EXECUTE FUNCTION moneybowl_dispatch.on_insert();

CREATE FUNCTION public.admit_outbox_dispatch(
  p_environment text, p_project_url text, p_mode text, p_request_id uuid,
  p_event_id uuid, p_event_types text[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  c moneybowl_dispatch.control%ROWTYPE;
  token uuid := pg_catalog.gen_random_uuid();
  candidates jsonb;
BEGIN
  IF COALESCE(auth.role(),'') <> 'service_role' THEN RAISE EXCEPTION 'outbox_forbidden'; END IF;
  IF p_request_id IS NULL OR p_mode IS NULL OR p_mode NOT IN ('observe','active')
    OR p_event_types IS NULL OR pg_catalog.cardinality(p_event_types) NOT BETWEEN 1 AND 32 THEN
    RAISE EXCEPTION 'outbox_admission_invalid';
  END IF;
  -- A single project-wide admission lease bounds concurrent HTTP fanout to four.
  SELECT * INTO c FROM moneybowl_dispatch.control WHERE singleton FOR UPDATE;
  IF c.mode = 'disabled' OR c.mode IS DISTINCT FROM p_mode
    OR c.environment IS DISTINCT FROM p_environment OR c.project_url IS DISTINCT FROM p_project_url THEN
    RETURN pg_catalog.jsonb_build_object('code','disabled');
  END IF;
  IF c.lease_until > pg_catalog.now() THEN RETURN pg_catalog.jsonb_build_object('code','busy'); END IF;
  DELETE FROM moneybowl_dispatch.receipts WHERE received_at < pg_catalog.now() - interval '10 minutes';
  INSERT INTO moneybowl_dispatch.receipts(request_id) VALUES (p_request_id) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN pg_catalog.jsonb_build_object('code','replay'); END IF;
  -- Delivery fairness/cooldown only; this never claims or mutates event/operation state.
  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'event_outbox_id',q.event_outbox_id,'event_type',q.event_type)), '[]'::jsonb) INTO candidates
  FROM (
    SELECT e.* FROM moneybowl_dispatch.eligible_events(p_event_types,30,p_event_id) e
    LEFT JOIN moneybowl_dispatch.attempts a ON a.event_id = e.event_outbox_id
    WHERE (p_event_id IS NULL OR e.event_outbox_id = p_event_id)
      AND (p_mode = 'observe' OR a.offered_at IS NULL OR a.offered_at <= pg_catalog.now() - interval '15 minutes')
    ORDER BY a.offered_at NULLS FIRST,
      CASE WHEN e.event_status = 'processing' THEN 0 ELSE 1 END, e.created_at, e.event_outbox_id
    LIMIT 4
  ) q;
  UPDATE moneybowl_dispatch.control SET batch_token = token,
    lease_until = pg_catalog.now() + interval '150 seconds' WHERE singleton;
  IF p_mode = 'active' THEN
    INSERT INTO moneybowl_dispatch.attempts(event_id,offered_at,batch_token)
    SELECT (item->>'event_outbox_id')::uuid, pg_catalog.now(), token
    FROM pg_catalog.jsonb_array_elements(candidates) item
    ON CONFLICT (event_id) DO UPDATE SET offered_at = EXCLUDED.offered_at, batch_token = EXCLUDED.batch_token;
  END IF;
  RETURN pg_catalog.jsonb_build_object('code','admitted','batch_token',token,'candidates',candidates);
END;
$$;

CREATE FUNCTION public.authorize_outbox_dispatch(
  p_batch_token uuid, p_event_id uuid, p_environment text, p_project_url text
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF COALESCE(auth.role(),'') <> 'service_role' THEN RAISE EXCEPTION 'outbox_forbidden'; END IF;
  RETURN EXISTS (
    SELECT 1 FROM moneybowl_dispatch.control c
    JOIN moneybowl_dispatch.attempts a ON a.batch_token = c.batch_token
    JOIN public.event_outbox e ON e.id = a.event_id
    WHERE c.singleton AND c.mode = 'active' AND c.environment = 'DEV'
      AND c.environment = p_environment AND c.project_url = p_project_url
      AND c.batch_token = p_batch_token AND c.lease_until > pg_catalog.now() AND a.event_id = p_event_id
      AND EXISTS (SELECT 1 FROM moneybowl_dispatch.eligible_events(ARRAY[e.event_type],30,e.id) eligible
        WHERE eligible.event_outbox_id = e.id)
  );
END;
$$;

CREATE FUNCTION public.finish_outbox_dispatch(p_batch_token uuid, p_next_hop integer DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE c moneybowl_dispatch.control%ROWTYPE;
BEGIN
  IF COALESCE(auth.role(),'') <> 'service_role' THEN RAISE EXCEPTION 'outbox_forbidden'; END IF;
  IF p_next_hop IS NOT NULL AND p_next_hop NOT BETWEEN 1 AND 15 THEN RAISE EXCEPTION 'outbox_hop_invalid'; END IF;
  SELECT * INTO c FROM moneybowl_dispatch.control WHERE singleton FOR UPDATE;
  IF c.batch_token IS DISTINCT FROM p_batch_token OR p_batch_token IS NULL
    OR c.lease_until <= pg_catalog.now() THEN RETURN false; END IF;
  UPDATE moneybowl_dispatch.control SET batch_token = NULL, lease_until = NULL WHERE singleton;
  IF c.mode = 'active' AND p_next_hop IS NOT NULL THEN
    PERFORM moneybowl_dispatch.notify(NULL,p_next_hop);
  END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA moneybowl_dispatch FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admit_outbox_dispatch(text,text,text,uuid,uuid,text[]),
  public.authorize_outbox_dispatch(uuid,uuid,text,text), public.finish_outbox_dispatch(uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admit_outbox_dispatch(text,text,text,uuid,uuid,text[]),
  public.authorize_outbox_dispatch(uuid,uuid,text,text), public.finish_outbox_dispatch(uuid,integer)
  TO service_role;
COMMIT;
