-- B06.1: member-owned, bounded exact evidence and unvalidated reference versions.
-- No investor/UCC changes, credentials, worker route, parser or publication path.
BEGIN;
CREATE SCHEMA nse_reference;
REVOKE ALL ON SCHEMA nse_reference FROM PUBLIC, anon, authenticated, service_role;
CREATE TYPE nse_reference.file_type AS ENUM ('SCH','SIP','STP','SWP','NAV','SET');

CREATE TABLE nse_reference.connections (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  environment text NOT NULL CHECK (environment IN ('UAT','PRODUCTION')),
  member_code text NOT NULL CHECK (member_code ~ '^[A-Za-z0-9_-]{1,20}$'),
  api_base_url text NOT NULL CHECK (api_base_url ~ '^https://[a-z0-9]+([.-][a-z0-9]+)*(:[0-9]{1,5})?$' AND length(api_base_url)<=253),
  credential_slot text NOT NULL DEFAULT 'NSE_ENV_V1' CHECK (credential_slot='NSE_ENV_V1'),
  enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (id,workspace_id),
  UNIQUE (workspace_id,environment),
  UNIQUE (environment,member_code),
  -- The existing protected runtime has exactly one NSE_* bundle per environment.
  -- Sharing that slot across workspaces, even under another member name, is unsafe.
  UNIQUE (environment,credential_slot)
);
CREATE TABLE nse_reference.downloads (
  id uuid PRIMARY KEY,
  capture_token uuid NOT NULL,
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL,
  contract_version text NOT NULL DEFAULT '1.9.7' CHECK (contract_version='1.9.7'),
  endpoint_path text NOT NULL DEFAULT '/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD'
    CHECK (endpoint_path='/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD'),
  http_method text NOT NULL DEFAULT 'POST' CHECK (http_method='POST'),
  request_body text NOT NULL CHECK (request_body='{"file_type":"'||file_type::text||'"}'),
  request_sha256 bytea GENERATED ALWAYS AS (extensions.digest(request_body,'sha256')) STORED,
  started_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  FOREIGN KEY (connection_id,workspace_id) REFERENCES nse_reference.connections(id,workspace_id) ON DELETE RESTRICT,
  UNIQUE (id,workspace_id),
  UNIQUE (id,workspace_id,connection_id,file_type)
);
CREATE INDEX nse_reference_download_connection ON nse_reference.downloads(connection_id,started_at DESC);
CREATE TABLE nse_reference.evidence_chunks (
  download_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal BETWEEN 0 AND 63),
  byte_count integer NOT NULL CHECK (byte_count BETWEEN 1 AND 262144),
  sha256 bytea NOT NULL CHECK (octet_length(sha256)=32),
  ciphertext bytea NOT NULL,
  key_reference text NOT NULL DEFAULT 'integration_payload_encryption_key_v1'
    CHECK (key_reference='integration_payload_encryption_key_v1'),
  key_version integer NOT NULL DEFAULT 1 CHECK (key_version=1),
  PRIMARY KEY (download_id,ordinal),
  FOREIGN KEY (download_id,workspace_id) REFERENCES nse_reference.downloads(id,workspace_id) ON DELETE RESTRICT
);
CREATE TABLE nse_reference.results (
  download_id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL,
  capture_kind text NOT NULL CHECK (capture_kind IN ('COMPLETE','OVERSIZE','TRUNCATED','TRANSPORT_FAILED','UNVERIFIABLE')),
  http_status integer CHECK (http_status BETWEEN 100 AND 599),
  media_type text NOT NULL CHECK (media_type IN ('TEXT','OCTET_STREAM','JSON','OTHER','UNKNOWN')),
  declared_bytes bigint CHECK (declared_bytes>=0),
  identity_encoding boolean NOT NULL,
  eof boolean NOT NULL,
  captured_bytes integer NOT NULL CHECK (captured_bytes BETWEEN 0 AND 16777216),
  captured_sha256 bytea NOT NULL CHECK (octet_length(captured_sha256)=32),
  response_sha256 bytea CHECK (octet_length(response_sha256)=32),
  completed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  FOREIGN KEY (download_id,workspace_id) REFERENCES nse_reference.downloads(id,workspace_id) ON DELETE RESTRICT,
  UNIQUE (download_id,workspace_id),
  CHECK ((capture_kind='COMPLETE') = (response_sha256 IS NOT NULL)),
  CHECK (capture_kind<>'COMPLETE' OR (eof AND identity_encoding AND http_status IS NOT NULL
    AND declared_bytes IS NOT NULL AND declared_bytes=captured_bytes AND response_sha256=captured_sha256))
);
CREATE TABLE nse_reference.snapshots (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL,
  version bigint NOT NULL CHECK (version>0),
  previous_snapshot_id uuid,
  download_id uuid NOT NULL UNIQUE,
  stage text NOT NULL DEFAULT 'STAGED_UNVALIDATED' CHECK (stage='STAGED_UNVALIDATED'),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (connection_id,file_type,version),
  UNIQUE (id,workspace_id,connection_id,file_type),
  FOREIGN KEY (download_id,workspace_id,connection_id,file_type)
    REFERENCES nse_reference.downloads(id,workspace_id,connection_id,file_type) ON DELETE RESTRICT,
  FOREIGN KEY (download_id,workspace_id) REFERENCES nse_reference.results(download_id,workspace_id) ON DELETE RESTRICT,
  FOREIGN KEY (previous_snapshot_id,workspace_id,connection_id,file_type)
    REFERENCES nse_reference.snapshots(id,workspace_id,connection_id,file_type) ON DELETE RESTRICT,
  CHECK ((version=1)=(previous_snapshot_id IS NULL))
);
CREATE INDEX nse_reference_snapshot_previous ON nse_reference.snapshots(previous_snapshot_id);

CREATE FUNCTION nse_reference.immutable() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'nse_reference_immutable'; END $$;
CREATE FUNCTION nse_reference.guard_connection() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF TG_OP='DELETE' OR (to_jsonb(NEW)-'enabled') IS DISTINCT FROM (to_jsonb(OLD)-'enabled') THEN
    RAISE EXCEPTION 'nse_reference_connection_identity_immutable';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER nse_reference_connection_identity BEFORE UPDATE OR DELETE ON nse_reference.connections
  FOR EACH ROW EXECUTE FUNCTION nse_reference.guard_connection();
CREATE FUNCTION nse_reference.audit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  INSERT INTO public.workspace_audit_logs(workspace_id,action,event_type,target_type,entity_type,target_id,entity_id,actor_type,reason,payload)
  VALUES(NEW.workspace_id,'nse.reference.connections','nse.reference.connections','nse_reference','nse_reference',NEW.id,NEW.id,
    'system','NSE member connection changed',pg_catalog.jsonb_build_object('enabled',NEW.enabled));
  RETURN NEW;
END $$;
CREATE FUNCTION nse_reference.audit_evidence() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id uuid:=COALESCE((to_jsonb(NEW)->>'id')::uuid,(to_jsonb(NEW)->>'download_id')::uuid);
BEGIN
  INSERT INTO public.workspace_audit_logs(workspace_id,action,event_type,target_type,entity_type,target_id,entity_id,actor_type,reason,payload)
  VALUES(NEW.workspace_id,'nse.reference.'||TG_TABLE_NAME,'nse.reference.'||TG_TABLE_NAME,
    'nse_reference','nse_reference',v_id,v_id,'system','NSE reference foundation','{}');
  RETURN NEW;
END $$;
CREATE TRIGGER nse_reference_connection_audit AFTER INSERT OR UPDATE ON nse_reference.connections
  FOR EACH ROW EXECUTE FUNCTION nse_reference.audit();
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['connections','downloads','evidence_chunks','results','snapshots'] LOOP
    EXECUTE format('ALTER TABLE nse_reference.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON TABLE nse_reference.%I FROM PUBLIC,anon,authenticated,service_role',t);
    IF t<>'connections' THEN
      EXECUTE format('CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON nse_reference.%I FOR EACH ROW EXECUTE FUNCTION nse_reference.immutable()',t);
    END IF;
    IF t IN ('downloads','results','snapshots') THEN
      EXECUTE format('CREATE TRIGGER audit AFTER INSERT ON nse_reference.%I FOR EACH ROW EXECUTE FUNCTION nse_reference.audit_evidence()',t);
    END IF;
  END LOOP;
END $$;

-- Every mutating entry point locks the connection and rechecks current ownership.
CREATE FUNCTION nse_reference.lock_connection(p_workspace uuid,p_connection uuid)
RETURNS nse_reference.connections LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c nse_reference.connections;
BEGIN
  SELECT * INTO c FROM nse_reference.connections WHERE id=p_connection AND workspace_id=p_workspace FOR UPDATE;
  IF c.id IS NULL OR NOT c.enabled THEN RAISE EXCEPTION 'nse_reference_connection_unavailable'; END IF;
  PERFORM 1 FROM public.workspaces WHERE id=c.workspace_id AND workspace_status='active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'nse_reference_workspace_unavailable'; END IF;
  IF c.environment<>'UAT' THEN RAISE EXCEPTION 'nse_reference_production_disabled'; END IF;
  -- Defense if future migrations broaden the cardinality constraints.
  IF (SELECT count(*) FROM nse_reference.connections WHERE environment=c.environment AND
    (workspace_id=c.workspace_id OR member_code=c.member_code OR credential_slot=c.credential_slot))<>1 THEN
    RAISE EXCEPTION 'nse_reference_member_ambiguous';
  END IF;
  RETURN c;
END $$;
CREATE FUNCTION nse_reference.lock_download(p_workspace uuid,p_download uuid)
RETURNS nse_reference.downloads LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d nse_reference.downloads;
BEGIN
  SELECT * INTO d FROM nse_reference.downloads WHERE id=p_download AND workspace_id=p_workspace;
  IF d.id IS NULL THEN RAISE EXCEPTION 'nse_reference_download_unavailable'; END IF;
  PERFORM nse_reference.lock_connection(p_workspace,d.connection_id);
  PERFORM 1 FROM nse_reference.downloads WHERE id=d.id FOR UPDATE;
  RETURN d;
END $$;
CREATE FUNCTION public.begin_nse_master_download(p_workspace_id uuid,p_connection_id uuid,p_file_type text,p_call_id uuid,
  p_environment text,p_member_code text,p_api_base_url text,p_capture_token uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c nse_reference.connections; d nse_reference.downloads;
BEGIN
  c:=nse_reference.lock_connection(p_workspace_id,p_connection_id);
  IF p_environment IS DISTINCT FROM c.environment OR p_member_code IS DISTINCT FROM c.member_code
    OR p_api_base_url IS DISTINCT FROM c.api_base_url THEN RAISE EXCEPTION 'nse_reference_runtime_binding_mismatch'; END IF;
  IF p_file_type IS NULL OR p_file_type NOT IN ('SCH','SIP','STP','SWP','NAV','SET') OR p_call_id IS NULL OR p_capture_token IS NULL THEN
    RAISE EXCEPTION 'nse_reference_request_invalid'; END IF;
  SELECT * INTO d FROM nse_reference.downloads WHERE id=p_call_id;
  IF d.id IS NOT NULL THEN
    IF d.workspace_id<>p_workspace_id OR d.connection_id<>p_connection_id OR d.file_type::text<>p_file_type OR d.capture_token<>p_capture_token THEN
      RAISE EXCEPTION 'nse_reference_idempotency_conflict'; END IF;
    -- An acknowledgement retry can recover the request, but must never resubmit HTTP.
  ELSE
    INSERT INTO nse_reference.downloads(id,capture_token,workspace_id,connection_id,file_type,request_body)
    VALUES(p_call_id,p_capture_token,p_workspace_id,p_connection_id,p_file_type::nse_reference.file_type,'{"file_type":"'||p_file_type||'"}') RETURNING * INTO d;
  END IF;
  RETURN pg_catalog.jsonb_build_object('download_id',d.id,'request_body',d.request_body);
END $$;
CREATE FUNCTION public.append_nse_master_chunk(p_workspace_id uuid,p_download_id uuid,p_ordinal integer,p_base64 text,p_sha256 text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b bytea; h bytea; old nse_reference.evidence_chunks; n integer; total bigint;
BEGIN
  PERFORM nse_reference.lock_download(p_workspace_id,p_download_id);
  IF p_base64 IS NULL OR length(p_base64)>349528 OR p_base64 !~ '^[A-Za-z0-9+/]*={0,2}$'
    OR p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' OR p_ordinal IS NULL OR p_ordinal NOT BETWEEN 0 AND 63 THEN
    RAISE EXCEPTION 'nse_reference_chunk_invalid'; END IF;
  BEGIN b:=pg_catalog.decode(p_base64,'base64'); EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'nse_reference_chunk_invalid'; END;
  IF octet_length(b) NOT BETWEEN 1 AND 262144 THEN RAISE EXCEPTION 'nse_reference_chunk_invalid'; END IF;
  h:=extensions.digest(b,'sha256');
  IF h<>pg_catalog.decode(p_sha256,'hex') THEN RAISE EXCEPTION 'nse_reference_integrity_mismatch'; END IF;
  SELECT * INTO old FROM nse_reference.evidence_chunks WHERE download_id=p_download_id AND ordinal=p_ordinal;
  IF old.download_id IS NOT NULL THEN
    IF old.sha256<>h OR old.byte_count<>octet_length(b) THEN RAISE EXCEPTION 'nse_reference_idempotency_conflict'; END IF;
    RETURN;
  END IF;
  IF EXISTS(SELECT 1 FROM nse_reference.results WHERE download_id=p_download_id) THEN RAISE EXCEPTION 'nse_reference_evidence_sealed'; END IF;
  SELECT count(*),COALESCE(sum(byte_count),0) INTO n,total FROM nse_reference.evidence_chunks WHERE download_id=p_download_id;
  IF p_ordinal<>n THEN RAISE EXCEPTION 'nse_reference_chunk_sequence_invalid'; END IF;
  IF total+octet_length(b)>16777216 THEN RAISE EXCEPTION 'nse_reference_evidence_oversize'; END IF;
  INSERT INTO nse_reference.evidence_chunks(download_id,workspace_id,ordinal,byte_count,sha256,ciphertext)
  VALUES(p_download_id,p_workspace_id,p_ordinal,octet_length(b),h,
    extensions.pgp_sym_encrypt_bytea(b,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'));
END $$;
CREATE FUNCTION nse_reference.body(p_download uuid) RETURNS bytea LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c nse_reference.evidence_chunks; b bytea; chunks bytea[]:=ARRAY[]::bytea[]; n integer:=0;
BEGIN
  FOR c IN SELECT * FROM nse_reference.evidence_chunks WHERE download_id=p_download ORDER BY ordinal LOOP
    b:=extensions.pgp_sym_decrypt_bytea(c.ciphertext,public.integration_payload_encryption_key(c.key_reference));
    IF c.ordinal<>n OR octet_length(b)<>c.byte_count OR extensions.digest(b,'sha256')<>c.sha256 THEN
      RAISE EXCEPTION 'nse_reference_integrity_mismatch'; END IF;
    chunks:=array_append(chunks,b); n:=n+1;
  END LOOP;
  RETURN COALESCE((SELECT string_agg(part,''::bytea ORDER BY ordinal) FROM unnest(chunks) WITH ORDINALITY AS chunk(part,ordinal)),''::bytea);
END $$;
CREATE FUNCTION public.finish_nse_master_download(p_workspace_id uuid,p_download_id uuid,p_capture_kind text,
  p_http_status integer,p_media_type text,p_declared_bytes bigint,p_identity_encoding boolean,p_eof boolean,p_sha256 text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b bytea; h bytea; r nse_reference.results;
BEGIN
  PERFORM nse_reference.lock_download(p_workspace_id,p_download_id);
  IF p_capture_kind IS NULL OR p_capture_kind NOT IN ('COMPLETE','OVERSIZE','TRUNCATED','TRANSPORT_FAILED','UNVERIFIABLE')
    OR p_media_type IS NULL OR p_media_type NOT IN ('TEXT','OCTET_STREAM','JSON','OTHER','UNKNOWN')
    OR p_identity_encoding IS NULL OR p_eof IS NULL OR (p_declared_bytes IS NOT NULL AND p_declared_bytes<0)
    OR (p_http_status IS NOT NULL AND p_http_status NOT BETWEEN 100 AND 599) THEN RAISE EXCEPTION 'nse_reference_result_invalid'; END IF;
  b:=nse_reference.body(p_download_id); h:=extensions.digest(b,'sha256');
  IF p_capture_kind='COMPLETE' AND (NOT p_eof OR NOT p_identity_encoding OR p_http_status IS NULL OR
    p_declared_bytes IS NULL OR p_declared_bytes<>octet_length(b) OR p_sha256 IS NULL OR p_sha256<>encode(h,'hex')) THEN
    RAISE EXCEPTION 'nse_reference_incomplete_evidence'; END IF;
  IF p_capture_kind<>'COMPLETE' AND p_sha256 IS NOT NULL THEN RAISE EXCEPTION 'nse_reference_partial_not_full_hash'; END IF;
  SELECT * INTO r FROM nse_reference.results WHERE download_id=p_download_id;
  IF r.download_id IS NOT NULL THEN
    IF ROW(r.capture_kind,r.http_status,r.media_type,r.declared_bytes,r.identity_encoding,r.eof)
      IS DISTINCT FROM ROW(p_capture_kind,p_http_status,p_media_type,p_declared_bytes,p_identity_encoding,p_eof) THEN
      RAISE EXCEPTION 'nse_reference_idempotency_conflict'; END IF;
  ELSE
    INSERT INTO nse_reference.results(download_id,workspace_id,capture_kind,http_status,media_type,declared_bytes,identity_encoding,eof,
      captured_bytes,captured_sha256,response_sha256)
    VALUES(p_download_id,p_workspace_id,p_capture_kind,p_http_status,p_media_type,p_declared_bytes,p_identity_encoding,p_eof,
      octet_length(b),h,CASE WHEN p_capture_kind='COMPLETE' THEN h END) RETURNING * INTO r;
  END IF;
  RETURN pg_catalog.jsonb_build_object('download_id',r.download_id,'capture_kind',r.capture_kind,'captured_bytes',r.captured_bytes,
    'captured_sha256',encode(r.captured_sha256,'hex'),'response_sha256',encode(r.response_sha256,'hex'));
END $$;
CREATE FUNCTION public.read_nse_master_chunk(p_workspace_id uuid,p_download_id uuid,p_ordinal integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c nse_reference.evidence_chunks; b bytea;
BEGIN
  PERFORM nse_reference.lock_download(p_workspace_id,p_download_id);
  SELECT * INTO c FROM nse_reference.evidence_chunks WHERE download_id=p_download_id AND ordinal=p_ordinal;
  IF c.download_id IS NULL THEN RAISE EXCEPTION 'nse_reference_chunk_unavailable'; END IF;
  b:=extensions.pgp_sym_decrypt_bytea(c.ciphertext,public.integration_payload_encryption_key(c.key_reference));
  IF octet_length(b)<>c.byte_count OR extensions.digest(b,'sha256')<>c.sha256 THEN RAISE EXCEPTION 'nse_reference_integrity_mismatch'; END IF;
  RETURN pg_catalog.jsonb_build_object('base64',replace(encode(b,'base64'),E'\n',''),'sha256',encode(c.sha256,'hex'),'byte_count',c.byte_count);
END $$;
CREATE FUNCTION public.stage_nse_reference_snapshot(p_workspace_id uuid,p_download_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d nse_reference.downloads; r nse_reference.results; s nse_reference.snapshots; prior nse_reference.snapshots; b bytea; t text;
BEGIN
  d:=nse_reference.lock_download(p_workspace_id,p_download_id);
  SELECT * INTO r FROM nse_reference.results WHERE download_id=d.id;
  IF r.download_id IS NULL OR r.capture_kind<>'COMPLETE' OR r.http_status<>200 OR r.captured_bytes=0
    OR r.media_type NOT IN ('TEXT','OCTET_STREAM') THEN RAISE EXCEPTION 'nse_reference_not_stageable'; END IF;
  b:=nse_reference.body(d.id);
  IF extensions.digest(b,'sha256')<>r.response_sha256 OR octet_length(b)<>r.captured_bytes THEN
    RAISE EXCEPTION 'nse_reference_integrity_mismatch'; END IF;
  BEGIN t:=pg_catalog.convert_from(b,'UTF8'); EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'nse_reference_not_text'; END;
  t:=pg_catalog.ltrim(t,E' \t\r\n'||chr(65279));
  -- Only a file candidate, never a successful variant parse. JSON/HTML errors cannot stage.
  IF t='' OR left(t,1) IN ('{','[','<') OR strpos(t,'|')=0 THEN RAISE EXCEPTION 'nse_reference_not_file'; END IF;
  SELECT * INTO s FROM nse_reference.snapshots WHERE download_id=d.id;
  IF s.id IS NULL THEN
    SELECT * INTO prior FROM nse_reference.snapshots WHERE connection_id=d.connection_id AND file_type=d.file_type ORDER BY version DESC LIMIT 1;
    INSERT INTO nse_reference.snapshots(workspace_id,connection_id,file_type,version,previous_snapshot_id,download_id)
    VALUES(d.workspace_id,d.connection_id,d.file_type,COALESCE(prior.version,0)+1,prior.id,d.id) RETURNING * INTO s;
  END IF;
  RETURN pg_catalog.jsonb_build_object('snapshot_id',s.id,'file_type',s.file_type,'version',s.version,'stage',s.stage,'previous_snapshot_id',s.previous_snapshot_id);
END $$;

-- A future parser obtains its manifest without direct private-table access.
CREATE FUNCTION public.get_nse_reference_snapshot(p_workspace_id uuid,p_snapshot_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; r nse_reference.results;
BEGIN
  SELECT * INTO s FROM nse_reference.snapshots WHERE id=p_snapshot_id AND workspace_id=p_workspace_id;
  IF s.id IS NULL THEN RAISE EXCEPTION 'nse_reference_snapshot_unavailable'; END IF;
  PERFORM nse_reference.lock_download(p_workspace_id,s.download_id);
  SELECT * INTO r FROM nse_reference.results WHERE download_id=s.download_id;
  RETURN pg_catalog.jsonb_build_object('snapshot_id',s.id,'workspace_id',s.workspace_id,'connection_id',s.connection_id,
    'file_type',s.file_type,'version',s.version,'previous_snapshot_id',s.previous_snapshot_id,'stage',s.stage,
    'download_id',s.download_id,'response_bytes',r.captured_bytes,'response_sha256',encode(r.response_sha256,'hex'),
    'chunk_count',(SELECT count(*) FROM nse_reference.evidence_chunks WHERE download_id=s.download_id));
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA nse_reference FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON TYPE nse_reference.file_type FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.begin_nse_master_download(uuid,uuid,text,uuid,text,text,text,uuid),
 public.append_nse_master_chunk(uuid,uuid,integer,text,text),
 public.finish_nse_master_download(uuid,uuid,text,integer,text,bigint,boolean,boolean,text),
 public.read_nse_master_chunk(uuid,uuid,integer), public.stage_nse_reference_snapshot(uuid,uuid), public.get_nse_reference_snapshot(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_nse_master_download(uuid,uuid,text,uuid,text,text,text,uuid),
 public.append_nse_master_chunk(uuid,uuid,integer,text,text),
 public.finish_nse_master_download(uuid,uuid,text,integer,text,bigint,boolean,boolean,text),
 public.read_nse_master_chunk(uuid,uuid,integer), public.stage_nse_reference_snapshot(uuid,uuid), public.get_nse_reference_snapshot(uuid,uuid) TO service_role;
COMMIT;
