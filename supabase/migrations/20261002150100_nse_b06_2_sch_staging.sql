-- Strict observed SCH layout. No vendor eligibility interpretation or publication.
BEGIN;
CREATE TABLE nse_reference.scheme_identities (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 workspace_id uuid NOT NULL,
 connection_id uuid NOT NULL,
 source_namespace text NOT NULL DEFAULT 'NSE_SCH' CHECK (source_namespace='NSE_SCH'),
 scheme_code text NOT NULL CHECK (length(scheme_code) BETWEEN 1 AND 128 AND scheme_code=btrim(scheme_code)),
 FOREIGN KEY (connection_id,workspace_id) REFERENCES nse_reference.connections(id,workspace_id),
 UNIQUE (connection_id,scheme_code), UNIQUE(id,workspace_id,connection_id)
);
CREATE TABLE nse_reference.sch_rows (
 snapshot_id uuid NOT NULL,
 workspace_id uuid NOT NULL,
 connection_id uuid NOT NULL,
 file_type nse_reference.file_type NOT NULL DEFAULT 'SCH' CHECK(file_type='SCH'),
 scheme_identity_id uuid NOT NULL,
 row_number integer NOT NULL CHECK(row_number BETWEEN 1 AND 100000),
 unique_sr_no text NOT NULL,
 rta_scheme_code text NOT NULL,
 amc_scheme_code text NOT NULL,
 isin text NOT NULL,
 amc_code text NOT NULL,
 scheme_type text NOT NULL,
 plan_type text NOT NULL,
 scheme_name text NOT NULL,
 rta_agent_code text NOT NULL,
 dividend_reinvestment_flag text NOT NULL,
 native_fields text[] NOT NULL CHECK(cardinality(native_fields)=44),
 PRIMARY KEY(snapshot_id,scheme_identity_id), UNIQUE(snapshot_id,scheme_identity_id,workspace_id), UNIQUE(snapshot_id,row_number), UNIQUE(snapshot_id,unique_sr_no),
 FOREIGN KEY (snapshot_id,workspace_id,connection_id,file_type) REFERENCES nse_reference.snapshots(id,workspace_id,connection_id,file_type),
 FOREIGN KEY (scheme_identity_id,workspace_id,connection_id) REFERENCES nse_reference.scheme_identities(id,workspace_id,connection_id)
);
-- Deliberately no APPROVED state or consumer. Future review must establish registrar
-- namespace, AMC, ISIN, plan/option and effective snapshot evidence, never code equality.
CREATE TABLE nse_reference.scheme_crosswalk_candidates (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 workspace_id uuid NOT NULL,
 snapshot_id uuid NOT NULL,
 scheme_identity_id uuid NOT NULL,
 candidate_fund_id uuid NOT NULL REFERENCES public.mutual_funds(id),
 target_namespace text NOT NULL CHECK (target_namespace IN ('CAMS','KFIN','AMFI','UNRESOLVED')),
 review_outcome text NOT NULL CHECK(review_outcome IN ('PROPOSED','AMBIGUOUS','REJECTED')),
 provenance_reference text NOT NULL CHECK(length(provenance_reference) BETWEEN 1 AND 250),
 created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 FOREIGN KEY (snapshot_id,scheme_identity_id) REFERENCES nse_reference.sch_rows(snapshot_id,scheme_identity_id),
 FOREIGN KEY (snapshot_id,scheme_identity_id,workspace_id) REFERENCES nse_reference.sch_rows(snapshot_id,scheme_identity_id,workspace_id)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['scheme_identities','sch_rows','scheme_crosswalk_candidates'] LOOP
  EXECUTE format('ALTER TABLE nse_reference.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON nse_reference.%I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON nse_reference.%I FOR EACH ROW EXECUTE FUNCTION nse_reference.immutable()',t);
 END LOOP;
END $$;
CREATE TRIGGER crosswalk_audit AFTER INSERT ON nse_reference.scheme_crosswalk_candidates
 FOR EACH ROW EXECUTE FUNCTION nse_reference.audit_evidence();
CREATE FUNCTION nse_reference.sch_header_v1() RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT 'UNIQUE SR NO|SCHEME CODE|RTA SCHEME CODE|AMC SCHEME CODE|ISIN|AMC CODE|SCHEME TYPE|PLAN TYPE|SCHEME NAME|PURCHASE ALLOWED|PURCHASE TRANSACTION MODE|NEW PURCHASE MIN AMOUNT|ADDITIONAL PURCHASE MIN AMOUNT|ADDITIONAL PURCHASE MAX AMOUNT|PURCHASE AMOUNT MULTIPLIER|PURCHASE CUTOFF TIME|REDEMPTION ALLOWED|REDEMPTION TRANSACTION MODE|REDEMPTION MIN QTY|REDEMPTION QTY MULTIPLIER|REDEMPTION MAX QTY|REDEMPTION MIN AMOUNT|REDEMPTION MAX AMOUNT|REDEMPTION AMOUNT MULTIPLIER|REDEMPTION CUTOFF TIME|RTA AGENT CODE|AMC ACTIVE FLAG|DIV REINVEST FLAG|SIP ALLOWED|STP ENABLED|SWP ENABLED|SWITCH ALLOWED|SETTLEMENT TYPE|AMC IND|FACE VALUE|SCHEME START DATE|MATURITY DATE|EXIT LOAD FLAG|EXIT LOAD|LOCK IN PERIOD_FLAG|LOCK IN PERIOD|CHANNEL PARTNER CODE|REOPENING DATE|OPEN/CLOSE ENDED SCHEME';
$$;
CREATE FUNCTION nse_reference.sch_records_v1(p_text text) RETURNS TABLE(row_number bigint,fields text[])
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT ordinal-1,string_to_array(line,'|') FROM unnest(string_to_array(p_text,E'\n')) WITH ORDINALITY t(line,ordinal)
 WHERE ordinal>1;
$$;
CREATE FUNCTION nse_reference.validate_sch_v1(p_snapshot uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; body text; rows integer; rejected integer:=0; category text:='nse_reference_sch_layout_invalid';
BEGIN
 SELECT * INTO STRICT s FROM nse_reference.snapshots WHERE id=p_snapshot AND file_type='SCH';
 PERFORM nse_reference.lock_download(s.workspace_id,s.download_id);
 body:=pg_catalog.convert_from(nse_reference.body(s.download_id),'UTF8');
 IF left(body,1)=chr(65279) THEN body:=substr(body,2); END IF;
 -- Accept only consistent LF or CRLF, one terminal newline, no quoting/escaping,
 -- controls or embedded BOM. These are fail-closed local support limits.
 IF strpos(body,E'\r\n')>0 THEN
  IF strpos(replace(body,E'\r\n',''),E'\n')>0 THEN body:=''; END IF;
  body:=replace(body,E'\r\n',E'\n');
  IF strpos(body,E'\r')>0 THEN body:=''; END IF;
 END IF;
 IF right(body,1)<>E'\n' OR body ~ '[\x01-\x09\x0B-\x1F\x7F]' OR strpos(body,chr(65279))>0 OR strpos(body,'"')>0 THEN
  body:='';
 END IF;
 body:=left(body,greatest(length(body)-1,0));
 IF split_part(body,E'\n',1) IS DISTINCT FROM nse_reference.sch_header_v1() THEN
  category:='nse_reference_sch_schema_unsupported';
 ELSE
  SELECT count(*) INTO rows FROM nse_reference.sch_records_v1(body);
  IF rows BETWEEN 1 AND 100000 THEN
   SELECT count(*) INTO rejected FROM nse_reference.sch_records_v1(body) r
   WHERE cardinality(fields)<>44 OR length(array_to_string(fields,'|'))>16384
    OR EXISTS(SELECT 1 FROM unnest(fields) value WHERE length(value)>2048)
    OR fields[1] !~ '^[0-9]{1,11}$'
    OR fields[2]='' OR length(fields[2])>128 OR fields[2]<>btrim(fields[2])
    OR fields[6]='' OR length(fields[6])>128 OR fields[6]<>btrim(fields[6])
    OR fields[9]='' OR length(fields[9])>512 OR fields[9]<>btrim(fields[9])
    OR (fields[5]<>'' AND fields[5] !~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$');
   IF rejected=0 AND (EXISTS(SELECT 1 FROM nse_reference.sch_records_v1(body) GROUP BY fields[2] HAVING count(*)>1)
    OR EXISTS(SELECT 1 FROM nse_reference.sch_records_v1(body) GROUP BY fields[1] HAVING count(*)>1)) THEN
    category:='nse_reference_sch_identity_ambiguous'; rejected:=rows;
   END IF;
   IF rejected=0 THEN
    INSERT INTO nse_reference.scheme_identities(workspace_id,connection_id,scheme_code)
     SELECT s.workspace_id,s.connection_id,fields[2] FROM nse_reference.sch_records_v1(body)
     ON CONFLICT(connection_id,scheme_code) DO NOTHING;
    INSERT INTO nse_reference.sch_rows(snapshot_id,workspace_id,connection_id,scheme_identity_id,row_number,
     unique_sr_no,rta_scheme_code,amc_scheme_code,isin,amc_code,scheme_type,plan_type,scheme_name,rta_agent_code,dividend_reinvestment_flag,native_fields)
     SELECT s.id,s.workspace_id,s.connection_id,i.id,r.row_number::integer,
      fields[1],fields[3],fields[4],fields[5],fields[6],fields[7],fields[8],fields[9],fields[26],fields[28],fields
     FROM nse_reference.sch_records_v1(body) r JOIN nse_reference.scheme_identities i ON i.connection_id=s.connection_id AND i.scheme_code=fields[2];
    RETURN pg_catalog.jsonb_build_object('validation_scope','STRUCTURE_AND_IDENTITY_ONLY','status','STAGED_VALIDATED','category','nse_reference_sch_layout_valid','row_count',rows,'rejected_rows',0);
   END IF;
  END IF;
 END IF;
 RETURN pg_catalog.jsonb_build_object('validation_scope','STRUCTURE_AND_IDENTITY_ONLY','status','REJECTED','category',category,'row_count',0,'rejected_rows',rejected);
END $$;
INSERT INTO nse_reference.validators(file_type,parser_version,function_name) VALUES('SCH','SCH_OBSERVED_44_V1','validate_sch_v1');
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA nse_reference FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
