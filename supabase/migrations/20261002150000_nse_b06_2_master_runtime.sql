-- B06.2 owns member-reference orchestration. Investor operations stay unchanged.
BEGIN;
CREATE TABLE nse_reference.validators (
  file_type nse_reference.file_type PRIMARY KEY,
  parser_version text NOT NULL CHECK (parser_version ~ '^[A-Z0-9_]{1,80}$'),
  function_name text NOT NULL CHECK (function_name ~ ('^validate_'||lower(file_type::text)||'_v[1-9][0-9]*$'))
);
CREATE TABLE nse_reference.jobs (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL REFERENCES nse_reference.validators(file_type),
  idempotency_key uuid NOT NULL,
  event_id uuid NOT NULL UNIQUE DEFAULT pg_catalog.gen_random_uuid(),
  download_id uuid NOT NULL UNIQUE DEFAULT pg_catalog.gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  FOREIGN KEY (connection_id,workspace_id) REFERENCES nse_reference.connections(id,workspace_id),
  UNIQUE (connection_id,idempotency_key),
  UNIQUE (id,workspace_id)
);
CREATE TABLE nse_reference.validations (
  snapshot_id uuid PRIMARY KEY REFERENCES nse_reference.snapshots(id),
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL,
  parser_version text NOT NULL,
  validation_scope text NOT NULL CHECK (validation_scope ~ '^[A-Z_]{1,80}$'),
  source_sha256 bytea NOT NULL CHECK (octet_length(source_sha256)=32),
  status text NOT NULL CHECK (status IN ('STAGED_VALIDATED','REJECTED')),
  category text NOT NULL CHECK (category ~ '^nse_reference_[a-z_]{1,80}$'),
  row_count integer NOT NULL CHECK (row_count BETWEEN 0 AND 100000),
  rejected_rows integer NOT NULL CHECK (rejected_rows BETWEEN 0 AND 100000),
  publication_gate text NOT NULL DEFAULT 'BLOCKED' CHECK (publication_gate='BLOCKED'),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  FOREIGN KEY (snapshot_id,workspace_id,connection_id,file_type)
    REFERENCES nse_reference.snapshots(id,workspace_id,connection_id,file_type),
  UNIQUE (snapshot_id,workspace_id),
  CHECK ((status='STAGED_VALIDATED' AND row_count>0 AND rejected_rows=0) OR (status='REJECTED' AND row_count=0))
);
CREATE TABLE nse_reference.completions (
  id uuid PRIMARY KEY REFERENCES nse_reference.jobs(id),
  workspace_id uuid NOT NULL,
  snapshot_id uuid REFERENCES nse_reference.validations(snapshot_id),
  outcome text NOT NULL CHECK (outcome IN ('STAGED_VALIDATED','REJECTED','CAPTURE_FAILED','ABANDONED')),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  FOREIGN KEY (id,workspace_id) REFERENCES nse_reference.jobs(id,workspace_id),
  FOREIGN KEY (snapshot_id,workspace_id) REFERENCES nse_reference.validations(snapshot_id,workspace_id),
  CHECK ((snapshot_id IS NOT NULL)=(outcome IN ('STAGED_VALIDATED','REJECTED')))
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['validators','jobs','validations','completions'] LOOP
  EXECUTE format('ALTER TABLE nse_reference.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON nse_reference.%I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON nse_reference.%I FOR EACH ROW EXECUTE FUNCTION nse_reference.immutable()',t);
  IF t IN ('jobs','completions') THEN
   EXECUTE format('CREATE TRIGGER audit AFTER INSERT ON nse_reference.%I FOR EACH ROW EXECUTE FUNCTION nse_reference.audit_evidence()',t);
  END IF;
 END LOOP;
END $$;
CREATE UNIQUE INDEX event_outbox_one_master_job ON public.event_outbox(entity_id)
 WHERE event_type='integration.nse.master_download_requested';
CREATE FUNCTION nse_reference.guard_job_event() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP<>'INSERT' AND OLD.event_type='integration.nse.master_download_requested' THEN
  IF TG_OP='DELETE' OR ROW(NEW.id,NEW.event_type,NEW.entity_id,NEW.entity_type,NEW.payload,NEW.created_at)
   IS DISTINCT FROM ROW(OLD.id,OLD.event_type,OLD.entity_id,OLD.entity_type,OLD.payload,OLD.created_at) THEN
   RAISE EXCEPTION 'nse_reference_event_immutable'; END IF;
 ELSIF TG_OP='UPDATE' AND NEW.event_type='integration.nse.master_download_requested' THEN
  RAISE EXCEPTION 'nse_reference_event_immutable';
 END IF;
 IF TG_OP='INSERT' AND NEW.event_type='integration.nse.master_download_requested' THEN
  IF NEW.entity_type IS DISTINCT FROM 'nse_reference_job' OR NEW.payload IS DISTINCT FROM '{}'::jsonb
   OR NOT EXISTS(SELECT 1 FROM nse_reference.jobs j WHERE j.id=NEW.entity_id AND j.event_id=NEW.id) THEN
   RAISE EXCEPTION 'nse_reference_event_invalid'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER nse_reference_job_event BEFORE INSERT OR UPDATE OR DELETE ON public.event_outbox
 FOR EACH ROW EXECUTE FUNCTION nse_reference.guard_job_event();
CREATE FUNCTION nse_reference.guard_job_download() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM nse_reference.jobs j WHERE j.download_id=NEW.id
  AND ROW(j.workspace_id,j.connection_id,j.file_type) IS DISTINCT FROM ROW(NEW.workspace_id,NEW.connection_id,NEW.file_type)) THEN
  RAISE EXCEPTION 'nse_reference_job_download_mismatch'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER nse_reference_job_download BEFORE INSERT ON nse_reference.downloads
 FOR EACH ROW EXECUTE FUNCTION nse_reference.guard_job_download();
CREATE FUNCTION public.prepare_nse_master_download(p_workspace_id uuid,p_connection_id uuid,p_file_type text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs;
BEGIN
 PERFORM nse_reference.lock_connection(p_workspace_id,p_connection_id);
 IF p_idempotency_key IS NULL OR NOT EXISTS(SELECT 1 FROM nse_reference.validators WHERE file_type::text=p_file_type) THEN
  RAISE EXCEPTION 'nse_reference_variant_disabled'; END IF;
 SELECT * INTO j FROM nse_reference.jobs WHERE connection_id=p_connection_id AND idempotency_key=p_idempotency_key;
 IF j.id IS NOT NULL THEN
  IF j.file_type::text<>p_file_type THEN RAISE EXCEPTION 'nse_reference_idempotency_conflict'; END IF;
 ELSE
  INSERT INTO nse_reference.jobs(workspace_id,connection_id,file_type,idempotency_key)
   VALUES(p_workspace_id,p_connection_id,p_file_type::nse_reference.file_type,p_idempotency_key) RETURNING * INTO j;
  INSERT INTO public.event_outbox(id,event_type,entity_type,entity_id,payload)
   VALUES(j.event_id,'integration.nse.master_download_requested','nse_reference_job',j.id,'{}');
 END IF;
 RETURN pg_catalog.jsonb_build_object('job_id',j.id,'event_outbox_id',j.event_id);
END $$;
-- Lock order throughout: connection -> event -> evidence. Caller identity is never accepted.
CREATE FUNCTION nse_reference.lock_job(p_event uuid) RETURNS nse_reference.jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs;
BEGIN
 SELECT * INTO j FROM nse_reference.jobs WHERE event_id=p_event;
 IF j.id IS NULL THEN RAISE EXCEPTION 'nse_reference_job_unavailable'; END IF;
 PERFORM nse_reference.lock_connection(j.workspace_id,j.connection_id);
 PERFORM 1 FROM public.event_outbox WHERE id=p_event AND entity_id=j.id
  AND entity_type='nse_reference_job' AND event_type='integration.nse.master_download_requested' AND payload='{}'::jsonb FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'nse_reference_event_invalid'; END IF;
 RETURN j;
END $$;
CREATE FUNCTION nse_reference.owned_job(p_event uuid,p_token uuid) RETURNS nse_reference.jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs;
BEGIN
 j:=nse_reference.lock_job(p_event);
 IF p_token IS NULL OR NOT EXISTS(SELECT 1 FROM public.event_outbox WHERE id=p_event AND status='processing'
  AND claim_token=p_token AND claim_expires_at>pg_catalog.clock_timestamp()) THEN RAISE EXCEPTION 'nse_reference_claim_not_owned'; END IF;
 RETURN j;
END $$;
CREATE FUNCTION nse_reference.complete_job(p_job uuid,p_snapshot uuid,p_outcome text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs;
BEGIN
 SELECT * INTO STRICT j FROM nse_reference.jobs WHERE id=p_job;
 IF p_snapshot IS NOT NULL AND NOT EXISTS(SELECT 1 FROM nse_reference.validations v JOIN nse_reference.snapshots s ON s.id=v.snapshot_id
  WHERE s.id=p_snapshot AND s.download_id=j.download_id AND s.workspace_id=j.workspace_id AND s.connection_id=j.connection_id
   AND s.file_type=j.file_type AND v.status=p_outcome) THEN RAISE EXCEPTION 'nse_reference_completion_mismatch'; END IF;
 INSERT INTO nse_reference.completions(id,workspace_id,snapshot_id,outcome) VALUES(j.id,j.workspace_id,p_snapshot,p_outcome);
 UPDATE public.event_outbox SET status='completed',claim_token=NULL,claimed_by=NULL,claim_expires_at=NULL,
  error_message=NULL,updated_at=pg_catalog.clock_timestamp() WHERE id=j.event_id;
 RETURN pg_catalog.jsonb_build_object('outcome',p_outcome,'snapshot_id',p_snapshot);
END $$;
CREATE FUNCTION public.claim_nse_master_download(p_event_outbox_id uuid,p_claim_token uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs; e public.event_outbox; action text;
BEGIN
 IF p_claim_token IS NULL THEN RAISE EXCEPTION 'nse_reference_claim_not_owned'; END IF;
 j:=nse_reference.lock_job(p_event_outbox_id);
 SELECT * INTO e FROM public.event_outbox WHERE id=j.event_id;
 IF EXISTS(SELECT 1 FROM nse_reference.completions WHERE id=j.id) THEN RETURN '{"action":"DONE"}'::jsonb; END IF;
 IF e.status='processing' AND e.claim_expires_at>pg_catalog.clock_timestamp() AND e.claim_token IS DISTINCT FROM p_claim_token THEN
  RETURN '{"action":"BUSY"}'::jsonb;
 END IF;
 IF EXISTS(SELECT 1 FROM nse_reference.results WHERE download_id=j.download_id) THEN action:='FINALIZE';
 ELSIF EXISTS(SELECT 1 FROM nse_reference.downloads WHERE id=j.download_id) OR (e.retry_count>=3 AND NOT (e.status='processing' AND e.claim_token=p_claim_token
  AND e.claim_expires_at>pg_catalog.clock_timestamp())) THEN
  -- No fresh token can resend a begun call. Preserve unsealed evidence; no guessed result.
  PERFORM nse_reference.complete_job(j.id,NULL,'ABANDONED'); RETURN '{"action":"DONE"}'::jsonb;
 ELSE action:='CAPTURE'; END IF;
 IF e.status NOT IN ('pending','processing') THEN RAISE EXCEPTION 'nse_reference_event_invalid'; END IF;
 IF e.claim_token IS DISTINCT FROM p_claim_token OR e.claim_expires_at<=pg_catalog.clock_timestamp() THEN
  UPDATE public.event_outbox SET status='processing',retry_count=retry_count+1,claim_token=p_claim_token,
   claimed_by=p_claim_token,claimed_at=pg_catalog.clock_timestamp(),claim_expires_at=pg_catalog.clock_timestamp()+interval '300 seconds',
   updated_at=pg_catalog.clock_timestamp() WHERE id=j.event_id;
 END IF;
 RETURN pg_catalog.jsonb_build_object('action',action,'event_outbox_id',j.event_id,'workspace_id',j.workspace_id,
  'connection_id',j.connection_id,'download_id',j.download_id,'file_type',j.file_type,'environment','UAT');
END $$;
CREATE FUNCTION public.begin_nse_master_job_capture(p_event_outbox_id uuid,p_claim_token uuid,p_capture_token uuid,
 p_environment text,p_member_code text,p_api_base_url text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs;
BEGIN
 j:=nse_reference.owned_job(p_event_outbox_id,p_claim_token);
 RETURN public.begin_nse_master_download(j.workspace_id,j.connection_id,j.file_type::text,j.download_id,
  p_environment,p_member_code,p_api_base_url,p_capture_token);
END $$;
CREATE FUNCTION public.append_nse_master_job_chunk(p_event_outbox_id uuid,p_claim_token uuid,p_ordinal integer,p_base64 text,p_sha256 text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs;
BEGIN
 j:=nse_reference.owned_job(p_event_outbox_id,p_claim_token);
 PERFORM public.append_nse_master_chunk(j.workspace_id,j.download_id,p_ordinal,p_base64,p_sha256);
END $$;
CREATE FUNCTION public.finish_nse_master_job_capture(p_event_outbox_id uuid,p_claim_token uuid,p_capture_kind text,p_http_status integer,
 p_media_type text,p_declared_bytes bigint,p_identity_encoding boolean,p_eof boolean,p_sha256 text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs;
BEGIN
 j:=nse_reference.owned_job(p_event_outbox_id,p_claim_token);
 RETURN public.finish_nse_master_download(j.workspace_id,j.download_id,p_capture_kind,p_http_status,p_media_type,
  p_declared_bytes,p_identity_encoding,p_eof,p_sha256);
END $$;
CREATE FUNCTION nse_reference.validate_snapshot(p_workspace uuid,p_snapshot uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; v nse_reference.validators; result jsonb; h bytea; prior nse_reference.validations;
BEGIN
 SELECT * INTO s FROM nse_reference.snapshots WHERE id=p_snapshot AND workspace_id=p_workspace;
 IF s.id IS NULL THEN RAISE EXCEPTION 'nse_reference_snapshot_unavailable'; END IF;
 PERFORM nse_reference.lock_download(p_workspace,s.download_id);
 SELECT * INTO prior FROM nse_reference.validations WHERE snapshot_id=s.id;
 IF prior.snapshot_id IS NOT NULL THEN RETURN pg_catalog.to_jsonb(prior)-'source_sha256'; END IF;
 SELECT * INTO STRICT v FROM nse_reference.validators WHERE file_type=s.file_type;
 SELECT response_sha256 INTO h FROM nse_reference.results WHERE download_id=s.download_id AND capture_kind='COMPLETE';
 IF h IS NULL OR extensions.digest(nse_reference.body(s.download_id),'sha256')<>h THEN
  RAISE EXCEPTION 'nse_reference_integrity_mismatch'; END IF;
 -- Migration-owned plugin with a fixed private schema and (uuid)->jsonb signature.
 EXECUTE format('SELECT nse_reference.%I($1)',v.function_name) INTO result USING s.id;
 INSERT INTO nse_reference.validations(snapshot_id,workspace_id,connection_id,file_type,parser_version,validation_scope,source_sha256,status,category,row_count,rejected_rows)
  VALUES(s.id,s.workspace_id,s.connection_id,s.file_type,v.parser_version,result->>'validation_scope',h,result->>'status',result->>'category',
   (result->>'row_count')::integer,(result->>'rejected_rows')::integer) RETURNING * INTO prior;
 INSERT INTO public.workspace_audit_logs(workspace_id,action,event_type,target_type,entity_type,target_id,entity_id,actor_type,reason,payload)
  VALUES(s.workspace_id,'nse.reference.validation','nse.reference.validation','nse_reference','nse_reference',s.id,s.id,
   'system','NSE reference validation',pg_catalog.jsonb_build_object('status',prior.status,'parser_version',v.parser_version));
 RETURN pg_catalog.to_jsonb(prior)-'source_sha256';
END $$;
CREATE FUNCTION public.finalize_nse_master_download(p_event_outbox_id uuid,p_claim_token uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs; c nse_reference.completions; r nse_reference.results; s jsonb; v jsonb;
BEGIN
 j:=nse_reference.lock_job(p_event_outbox_id);
 SELECT * INTO c FROM nse_reference.completions WHERE id=j.id;
 IF c.id IS NOT NULL THEN RETURN pg_catalog.jsonb_build_object('outcome',c.outcome,'snapshot_id',c.snapshot_id); END IF;
 j:=nse_reference.owned_job(p_event_outbox_id,p_claim_token);
 SELECT * INTO r FROM nse_reference.results WHERE download_id=j.download_id;
 IF r.download_id IS NULL THEN RAISE EXCEPTION 'nse_reference_capture_unsealed'; END IF;
 IF r.capture_kind<>'COMPLETE' OR r.http_status<>200 OR r.media_type NOT IN ('TEXT','OCTET_STREAM') OR r.captured_bytes=0 THEN
  RETURN nse_reference.complete_job(j.id,NULL,'CAPTURE_FAILED'); END IF;
 BEGIN
  s:=public.stage_nse_reference_snapshot(j.workspace_id,j.download_id);
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT IN ('nse_reference_not_text','nse_reference_not_file') THEN RAISE; END IF;
  RETURN nse_reference.complete_job(j.id,NULL,'CAPTURE_FAILED');
 END;
 v:=nse_reference.validate_snapshot(j.workspace_id,(s->>'snapshot_id')::uuid);
 RETURN nse_reference.complete_job(j.id,(s->>'snapshot_id')::uuid,v->>'status');
END $$;

-- Service-only operational summary; no raw fields, provider diagnostics or credentials.
CREATE FUNCTION public.get_nse_master_download_job(p_workspace_id uuid,p_job_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j nse_reference.jobs; c nse_reference.completions; v nse_reference.validations; e public.event_outbox;
BEGIN
 SELECT * INTO j FROM nse_reference.jobs WHERE id=p_job_id AND workspace_id=p_workspace_id;
 IF j.id IS NULL THEN RAISE EXCEPTION 'nse_reference_job_unavailable'; END IF;
 PERFORM nse_reference.lock_connection(j.workspace_id,j.connection_id);
 SELECT * INTO c FROM nse_reference.completions WHERE id=j.id;
 SELECT * INTO v FROM nse_reference.validations WHERE snapshot_id=c.snapshot_id;
 SELECT * INTO e FROM public.event_outbox WHERE id=j.event_id;
 RETURN pg_catalog.jsonb_build_object('job_id',j.id,'file_type',j.file_type,'event_status',e.status,
  'download_id',j.download_id,'snapshot_id',c.snapshot_id,'outcome',c.outcome,'parser_version',v.parser_version,
  'validation_scope',v.validation_scope,'row_count',v.row_count,'rejected_rows',v.rejected_rows,
  'category',v.category,'publication_gate','BLOCKED');
END $$;
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
  SELECT feed.* FROM (
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
          OR (operation.operation_type IN ('ORDER_STATUS','PROV_ORDERS','CLIENT_READINESS','ORDER_FUNDING','SETTLEMENT_REDEMPTION','SIP_XSIP_REPORTS','STP_SWP_REPORTS') AND operation.safety_class = 'READ_ONLY'
            AND operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed))
      )
    )
  UNION ALL
  SELECT e.id,e.event_type,e.status,e.retry_count,e.claim_expires_at,e.created_at
  FROM public.event_outbox e JOIN nse_reference.jobs j ON j.event_id=e.id AND j.id=e.entity_id
  JOIN nse_reference.connections c ON c.id=j.connection_id AND c.workspace_id=j.workspace_id
  JOIN public.workspaces w ON w.id=j.workspace_id
  WHERE e.event_type='integration.nse.master_download_requested' AND e.entity_type='nse_reference_job'
    AND e.event_type=ANY(p_event_types) AND e.payload='{}'::jsonb AND c.enabled AND c.environment='UAT'
    AND w.workspace_status='active' AND NOT EXISTS(SELECT 1 FROM nse_reference.completions done WHERE done.id=j.id)
    AND (e.status='pending' OR (e.status='processing' AND e.claim_expires_at<=pg_catalog.now()))
  ) feed
  ORDER BY
    CASE WHEN feed.event_status = 'processing' THEN 0 ELSE 1 END,
    feed.created_at,
    feed.event_outbox_id
  LIMIT p_limit;
END;
$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA nse_reference FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.prepare_nse_master_download(uuid,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_nse_master_download(uuid,uuid,text,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.claim_nse_master_download(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_nse_master_download(uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.begin_nse_master_job_capture(uuid,uuid,uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_nse_master_job_capture(uuid,uuid,uuid,text,text,text) TO service_role;
REVOKE ALL ON FUNCTION public.append_nse_master_job_chunk(uuid,uuid,integer,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.append_nse_master_job_chunk(uuid,uuid,integer,text,text) TO service_role;
REVOKE ALL ON FUNCTION public.finish_nse_master_job_capture(uuid,uuid,text,integer,text,bigint,boolean,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finish_nse_master_job_capture(uuid,uuid,text,integer,text,bigint,boolean,boolean,text) TO service_role;
REVOKE ALL ON FUNCTION public.finalize_nse_master_download(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_nse_master_download(uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.get_nse_master_download_job(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_nse_master_download_job(uuid,uuid) TO service_role;
COMMIT;
