-- B06.4: documented NAV observations, no valuation publication; SET remains blocked.
BEGIN;
CREATE SCHEMA nse_nav;
CREATE SCHEMA nse_set;
REVOKE ALL ON SCHEMA nse_nav, nse_set FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE nse_nav.validations (
  snapshot_id uuid NOT NULL,
  parser_version text NOT NULL CHECK (parser_version='NSE_NAV_WEB83_V1'),
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL DEFAULT 'NAV' CHECK (file_type='NAV'),
  source_sha256 bytea NOT NULL CHECK (octet_length(source_sha256)=32),
  layout_sha256 text NOT NULL DEFAULT '67ee2e34c7cf776a2731e950837bd3aa6f2e6f7e5f521cbdbbce5cc60aae307d'
    CHECK (layout_sha256='67ee2e34c7cf776a2731e950837bd3aa6f2e6f7e5f521cbdbbce5cc60aae307d'),
  status text NOT NULL CHECK (status IN ('VALIDATED_OBSERVATIONS','REJECTED')),
  row_count integer NOT NULL CHECK (row_count BETWEEN 0 AND 100000),
  rejection_code text CHECK (rejection_code IN ('nse_nav_encoding_invalid','nse_nav_framing_invalid','nse_nav_row_limit',
    'nse_nav_column_count','nse_nav_field_invalid','nse_nav_date_invalid','nse_nav_value_invalid','nse_nav_duplicate_identity')),
  rejected_line integer CHECK (rejected_line>0),
  api_compatibility text NOT NULL DEFAULT 'UNCOMMISSIONED' CHECK (api_compatibility='UNCOMMISSIONED'),
  publication_state text NOT NULL DEFAULT 'BLOCKED_CROSSWALK_AND_SOURCE_POLICY'
    CHECK (publication_state='BLOCKED_CROSSWALK_AND_SOURCE_POLICY'),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY(snapshot_id,parser_version),
  UNIQUE(snapshot_id,parser_version,workspace_id,status),
  FOREIGN KEY(snapshot_id,workspace_id,connection_id,file_type)
    REFERENCES nse_reference.snapshots(id,workspace_id,connection_id,file_type) ON DELETE RESTRICT,
  CHECK ((status='VALIDATED_OBSERVATIONS' AND row_count>0 AND rejection_code IS NULL AND rejected_line IS NULL)
    OR (status='REJECTED' AND row_count=0 AND rejection_code IS NOT NULL))
);
CREATE TABLE nse_nav.observations (
  snapshot_id uuid NOT NULL,
  parser_version text NOT NULL,
  workspace_id uuid NOT NULL,
  validation_status text NOT NULL DEFAULT 'VALIDATED_OBSERVATIONS' CHECK (validation_status='VALIDATED_OBSERVATIONS'),
  line_number integer NOT NULL CHECK (line_number>0),
  nav_date date NOT NULL,
  nse_scheme_code text NOT NULL CHECK (length(nse_scheme_code) BETWEEN 1 AND 30),
  scheme_name text NOT NULL CHECK (length(scheme_name) BETWEEN 1 AND 200),
  rta_scheme_code text NOT NULL CHECK (length(rta_scheme_code) BETWEEN 1 AND 10),
  dividend_reinvestment text NOT NULL CHECK (dividend_reinvestment IN ('Y','N','Z')),
  isin text NOT NULL CHECK (isin ~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$'),
  nav_value numeric NOT NULL CHECK (nav_value>0 AND nav_value<100000000000000),
  nav_lexeme text NOT NULL CHECK (length(nav_lexeme)<=14 AND nav_lexeme ~ '^(0|[1-9][0-9]*)(\.[0-9]+)?$' AND nav_lexeme::numeric=nav_value),
  rta_code text NOT NULL CHECK (length(rta_code) BETWEEN 1 AND 10),
  PRIMARY KEY(snapshot_id,parser_version,line_number),
  -- Two values/identities for one exchange scheme and date are ambiguous, even if equal.
  UNIQUE(snapshot_id,parser_version,nse_scheme_code,nav_date),
  FOREIGN KEY(snapshot_id,parser_version,workspace_id,validation_status)
    REFERENCES nse_nav.validations(snapshot_id,parser_version,workspace_id,status)
    DEFERRABLE INITIALLY DEFERRED
);
CREATE TABLE nse_set.assessments (
  snapshot_id uuid NOT NULL,
  assessment_version text NOT NULL DEFAULT 'NSE_SET_EVIDENCE_V1' CHECK (assessment_version='NSE_SET_EVIDENCE_V1'),
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL DEFAULT 'SET' CHECK (file_type='SET'),
  source_sha256 bytea NOT NULL CHECK (octet_length(source_sha256)=32),
  status text NOT NULL DEFAULT 'BLOCKED_LAYOUT_UNCHARACTERIZED' CHECK (status='BLOCKED_LAYOUT_UNCHARACTERIZED'),
  reason_code text NOT NULL DEFAULT 'WEB77_API_COMPATIBILITY_AND_HEADER_UNCONFIRMED'
    CHECK (reason_code='WEB77_API_COMPATIBILITY_AND_HEADER_UNCONFIRMED'),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY(snapshot_id,assessment_version),
  FOREIGN KEY(snapshot_id,workspace_id,connection_id,file_type)
    REFERENCES nse_reference.snapshots(id,workspace_id,connection_id,file_type) ON DELETE RESTRICT
);

CREATE FUNCTION nse_nav.audit_assessment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  INSERT INTO public.workspace_audit_logs(workspace_id,action,event_type,target_type,entity_type,target_id,entity_id,actor_type,reason,payload)
  VALUES(NEW.workspace_id,replace(TG_TABLE_SCHEMA,'_','.')||'.assessment',replace(TG_TABLE_SCHEMA,'_','.')||'.assessment',
    TG_TABLE_SCHEMA,TG_TABLE_SCHEMA,NEW.snapshot_id,NEW.snapshot_id,'system','NSE reference assessment',
    pg_catalog.jsonb_build_object('status',NEW.status,'source_sha256',pg_catalog.encode(NEW.source_sha256,'hex')));
  RETURN NEW;
END $$;
DO $$ DECLARE s text; t text; BEGIN
  FOR s,t IN VALUES ('nse_nav','validations'),('nse_nav','observations'),('nse_set','assessments') LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY',s,t);
    EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC,anon,authenticated,service_role',s,t);
    EXECUTE format('CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION nse_reference.immutable()',s,t);
    IF t<>'observations' THEN
      EXECUTE format('CREATE TRIGGER audit AFTER INSERT ON %I.%I FOR EACH ROW EXECUTE FUNCTION nse_nav.audit_assessment()',s,t);
    END IF;
  END LOOP;
END $$;

-- No caller-supplied rows, digest, parser identity or approval. Parse the durable bytes.
CREATE FUNCTION public.validate_nse_nav_snapshot(p_workspace_id uuid,p_snapshot_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  s nse_reference.snapshots; r nse_reference.results; v nse_nav.validations;
  b bytea; body text; lines text[]; fields text[]; line text; field text;
  line_no integer:=0; rows integer:=0; valuation_date date; rejection text; bad_line integer;
BEGIN
  SELECT * INTO s FROM nse_reference.snapshots WHERE id=p_snapshot_id AND workspace_id=p_workspace_id AND file_type='NAV';
  IF s.id IS NULL THEN RAISE EXCEPTION 'nse_nav_snapshot_unavailable'; END IF;
  PERFORM nse_reference.lock_download(p_workspace_id,s.download_id);
  SELECT * INTO r FROM nse_reference.results WHERE download_id=s.download_id;
  IF r.capture_kind IS DISTINCT FROM 'COMPLETE' OR r.http_status IS DISTINCT FROM 200
    OR r.media_type NOT IN ('TEXT','OCTET_STREAM') OR r.captured_bytes=0 THEN
    RAISE EXCEPTION 'nse_nav_evidence_unavailable'; END IF;
  b:=nse_reference.body(s.download_id);
  IF extensions.digest(b,'sha256') IS DISTINCT FROM r.response_sha256 OR octet_length(b)<>r.captured_bytes THEN
    RAISE EXCEPTION 'nse_reference_integrity_mismatch'; END IF;
  SELECT * INTO v FROM nse_nav.validations WHERE snapshot_id=s.id AND parser_version='NSE_NAV_WEB83_V1';
  IF v.snapshot_id IS NULL THEN
    -- This subtransaction rolls back ALL observations on the first rejected row.
    BEGIN
      BEGIN body:=pg_catalog.convert_from(b,'UTF8');
      EXCEPTION WHEN character_not_in_repertoire OR untranslatable_character THEN
        RAISE EXCEPTION USING MESSAGE='nse_nav_encoding_invalid',ERRCODE='N6401';
      END;
      IF left(body,1)=chr(65279) THEN body:=substring(body FROM 2); END IF;
      body:=replace(body,E'\r\n',E'\n');
      IF right(body,1)=E'\n' THEN body:=left(body,length(body)-1); END IF;
      IF body='' OR strpos(body,E'\r')>0 THEN
        RAISE EXCEPTION USING MESSAGE='nse_nav_framing_invalid',ERRCODE='N6401'; END IF;
      lines:=pg_catalog.string_to_array(body,E'\n');
      -- Match the shared runtime receipt bound before inserting any observations.
      IF cardinality(lines)>100000 THEN
        RAISE EXCEPTION USING MESSAGE='nse_nav_row_limit',ERRCODE='N6401'; END IF;
      FOREACH line IN ARRAY lines LOOP
        line_no:=line_no+1;
        IF line='' THEN RAISE EXCEPTION USING MESSAGE='nse_nav_framing_invalid',ERRCODE='N6401'; END IF;
        fields:=pg_catalog.string_to_array(line,'|');
        IF cardinality(fields)<>8 THEN RAISE EXCEPTION USING MESSAGE='nse_nav_column_count',ERRCODE='N6401'; END IF;
        FOREACH field IN ARRAY fields LOOP
          IF field='' OR field<>btrim(field) OR field ~ '[[:cntrl:]]' OR strpos(field,chr(65279))>0 THEN
            RAISE EXCEPTION USING MESSAGE='nse_nav_field_invalid',ERRCODE='N6401'; END IF;
        END LOOP;
        IF fields[1] !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
          RAISE EXCEPTION USING MESSAGE='nse_nav_date_invalid',ERRCODE='N6401'; END IF;
        BEGIN valuation_date:=fields[1]::date;
        EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
          RAISE EXCEPTION USING MESSAGE='nse_nav_date_invalid',ERRCODE='N6401'; END;
        IF valuation_date>(r.completed_at AT TIME ZONE 'UTC')::date THEN
          RAISE EXCEPTION USING MESSAGE='nse_nav_date_invalid',ERRCODE='N6401'; END IF;
        IF length(fields[2])>30 OR length(fields[3])>200 OR length(fields[4])>10 OR fields[5] NOT IN ('Y','N','Z')
          OR fields[6] !~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$' OR length(fields[8])>10 THEN
          RAISE EXCEPTION USING MESSAGE='nse_nav_field_invalid',ERRCODE='N6401'; END IF;
        IF length(fields[7])>14 OR fields[7] !~ '^(0|[1-9][0-9]*)(\.[0-9]+)?$' THEN
          RAISE EXCEPTION USING MESSAGE='nse_nav_value_invalid',ERRCODE='N6401'; END IF;
        IF fields[7]::numeric<=0 THEN RAISE EXCEPTION USING MESSAGE='nse_nav_value_invalid',ERRCODE='N6401'; END IF;
        BEGIN
          INSERT INTO nse_nav.observations(snapshot_id,parser_version,workspace_id,line_number,nav_date,nse_scheme_code,
            scheme_name,rta_scheme_code,dividend_reinvestment,isin,nav_value,nav_lexeme,rta_code)
          VALUES(s.id,'NSE_NAV_WEB83_V1',s.workspace_id,line_no,valuation_date,fields[2],fields[3],fields[4],fields[5],fields[6],fields[7]::numeric,fields[7],fields[8]);
        EXCEPTION WHEN unique_violation THEN
          RAISE EXCEPTION USING MESSAGE='nse_nav_duplicate_identity',ERRCODE='N6401'; END;
        rows:=rows+1;
      END LOOP;
    EXCEPTION WHEN SQLSTATE 'N6401' THEN
      rejection:=SQLERRM; bad_line:=NULLIF(line_no,0); rows:=0;
    END;
    INSERT INTO nse_nav.validations(snapshot_id,parser_version,workspace_id,connection_id,source_sha256,status,row_count,rejection_code,rejected_line)
    VALUES(s.id,'NSE_NAV_WEB83_V1',s.workspace_id,s.connection_id,r.response_sha256,
      CASE WHEN rejection IS NULL THEN 'VALIDATED_OBSERVATIONS' ELSE 'REJECTED' END,rows,rejection,bad_line) RETURNING * INTO v;
  END IF;
  RETURN pg_catalog.jsonb_build_object('snapshot_id',s.id,'workspace_id',s.workspace_id,'connection_id',s.connection_id,
    'download_id',s.download_id,'snapshot_version',s.version::text,'parser_version',v.parser_version,
    'source_sha256',encode(v.source_sha256,'hex'),'layout_sha256',v.layout_sha256,'status',v.status,'row_count',v.row_count,
    'rejection_code',v.rejection_code,'rejected_line',v.rejected_line,'api_compatibility',v.api_compatibility,'publication_state',v.publication_state);
END $$;

-- Explicit snapshot reads: never resolve a mutable latest/current pointer between pages.
CREATE FUNCTION public.read_nse_nav_observations(p_workspace_id uuid,p_snapshot_id uuid,p_after_line integer DEFAULT 0,p_limit integer DEFAULT 500)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; v nse_nav.validations; data jsonb; last_line integer;
BEGIN
  IF p_after_line IS NULL OR p_after_line<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'nse_nav_page_invalid'; END IF;
  SELECT * INTO s FROM nse_reference.snapshots WHERE id=p_snapshot_id AND workspace_id=p_workspace_id AND file_type='NAV';
  IF s.id IS NULL THEN RAISE EXCEPTION 'nse_nav_snapshot_unavailable'; END IF;
  PERFORM nse_reference.lock_download(p_workspace_id,s.download_id);
  SELECT * INTO v FROM nse_nav.validations WHERE snapshot_id=s.id AND parser_version='NSE_NAV_WEB83_V1';
  IF v.status IS DISTINCT FROM 'VALIDATED_OBSERVATIONS' THEN RAISE EXCEPTION 'nse_nav_not_validated'; END IF;
  IF p_after_line>v.row_count THEN RAISE EXCEPTION 'nse_nav_page_invalid'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('line_number',o.line_number,'nav_date',to_char(o.nav_date,'YYYY-MM-DD'),
    'nse_scheme_code',o.nse_scheme_code,'scheme_name',o.scheme_name,'rta_scheme_code',o.rta_scheme_code,
    'dividend_reinvestment',o.dividend_reinvestment,'isin',o.isin,'nav_value',o.nav_lexeme,'rta_code',o.rta_code) ORDER BY o.line_number),'[]'::jsonb),max(o.line_number)
  INTO data,last_line FROM (SELECT * FROM nse_nav.observations WHERE snapshot_id=s.id AND parser_version=v.parser_version
    AND line_number>p_after_line ORDER BY line_number LIMIT p_limit) o;
  RETURN jsonb_build_object('snapshot_id',s.id,'parser_version',v.parser_version,'source_sha256',encode(v.source_sha256,'hex'),
    'row_count',v.row_count,'observations',data,'next_after_line',CASE WHEN last_line<v.row_count THEN last_line END,
    'publication_state',v.publication_state);
END $$;

CREATE FUNCTION public.assess_nse_set_snapshot(p_workspace_id uuid,p_snapshot_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; r nse_reference.results; a nse_set.assessments; b bytea;
BEGIN
  SELECT * INTO s FROM nse_reference.snapshots WHERE id=p_snapshot_id AND workspace_id=p_workspace_id AND file_type='SET';
  IF s.id IS NULL THEN RAISE EXCEPTION 'nse_set_snapshot_unavailable'; END IF;
  PERFORM nse_reference.lock_download(p_workspace_id,s.download_id);
  SELECT * INTO r FROM nse_reference.results WHERE download_id=s.download_id;
  IF r.capture_kind IS DISTINCT FROM 'COMPLETE' OR r.http_status IS DISTINCT FROM 200
    OR r.media_type NOT IN ('TEXT','OCTET_STREAM') OR r.captured_bytes=0 THEN
    RAISE EXCEPTION 'nse_set_evidence_unavailable'; END IF;
  b:=nse_reference.body(s.download_id);
  IF extensions.digest(b,'sha256') IS DISTINCT FROM r.response_sha256 OR octet_length(b)<>r.captured_bytes THEN
    RAISE EXCEPTION 'nse_reference_integrity_mismatch'; END IF;
  SELECT * INTO a FROM nse_set.assessments WHERE snapshot_id=s.id AND assessment_version='NSE_SET_EVIDENCE_V1';
  IF a.snapshot_id IS NULL THEN
    INSERT INTO nse_set.assessments(snapshot_id,workspace_id,connection_id,source_sha256)
    VALUES(s.id,s.workspace_id,s.connection_id,r.response_sha256) RETURNING * INTO a;
  END IF;
  RETURN jsonb_build_object('snapshot_id',s.id,'workspace_id',s.workspace_id,'connection_id',s.connection_id,
    'download_id',s.download_id,'snapshot_version',s.version::text,'source_sha256',encode(a.source_sha256,'hex'),
    'assessment_version',a.assessment_version,'status',a.status,'reason_code',a.reason_code);
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA nse_nav, nse_set FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.validate_nse_nav_snapshot(uuid,uuid), public.read_nse_nav_observations(uuid,uuid,integer,integer),
  public.assess_nse_set_snapshot(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.validate_nse_nav_snapshot(uuid,uuid), public.read_nse_nav_observations(uuid,uuid,integer,integer),
  public.assess_nse_set_snapshot(uuid,uuid) TO service_role;
-- B06.2's single runtime invokes these private adapters inside finalization.
-- Domain receipts retain their more precise observation/blocked status and evidence.
CREATE FUNCTION nse_reference.validate_nav_v1(p_snapshot uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; v jsonb;
BEGIN
 SELECT * INTO STRICT s FROM nse_reference.snapshots WHERE id=p_snapshot AND file_type='NAV';
 v:=public.validate_nse_nav_snapshot(s.workspace_id,s.id);
 IF v->>'status' NOT IN ('VALIDATED_OBSERVATIONS','REJECTED') OR v->>'status' IS NULL THEN
  RAISE EXCEPTION 'nse_nav_validation_invalid'; END IF;
 RETURN pg_catalog.jsonb_build_object('validation_scope','DOCUMENT_BACKED_UNCOMMISSIONED_OBSERVATIONS',
  'status',CASE WHEN v->>'status'='VALIDATED_OBSERVATIONS' THEN 'STAGED_VALIDATED' ELSE 'REJECTED' END,
  'category',CASE WHEN v->>'status'='VALIDATED_OBSERVATIONS' THEN 'nse_reference_nav_observations_uncommissioned'
    ELSE 'nse_reference_nav_layout_invalid' END,
  'row_count',(v->>'row_count')::integer,
  -- The parser stops at the first rejection; this is not a total invalid-row count.
  'rejected_rows',CASE WHEN v->>'rejected_line' IS NOT NULL THEN 1 ELSE 0 END);
END $$;
CREATE FUNCTION nse_reference.validate_set_v1(p_snapshot uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; assessment jsonb;
BEGIN
 SELECT * INTO STRICT s FROM nse_reference.snapshots WHERE id=p_snapshot AND file_type='SET';
 assessment:=public.assess_nse_set_snapshot(s.workspace_id,s.id);
 IF assessment->>'status' IS DISTINCT FROM 'BLOCKED_LAYOUT_UNCHARACTERIZED' THEN
  RAISE EXCEPTION 'nse_set_assessment_invalid'; END IF;
 -- REJECTED is terminal validation failure, not provider/business success. Zero
 -- rows have been interpreted, so do not invent a rejected-row count or calendar.
 RETURN pg_catalog.jsonb_build_object('validation_scope','EVIDENCE_ONLY_LAYOUT_UNCHARACTERIZED',
  'status','REJECTED','category','nse_reference_set_layout_uncharacterized','row_count',0,'rejected_rows',0);
END $$;
REVOKE ALL ON FUNCTION nse_reference.validate_nav_v1(uuid), nse_reference.validate_set_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO nse_reference.validators(file_type,parser_version,function_name) VALUES
 ('NAV','NSE_NAV_WEB83_V1','validate_nav_v1'),
 ('SET','NSE_SET_EVIDENCE_V1','validate_set_v1');
COMMIT;
