-- NSE SCH parser V2: accept an EOF-terminated final record observed in DEV UAT.
-- The 44-column schema and all row/identity validation remain unchanged.
BEGIN;

CREATE FUNCTION nse_reference.validate_sch_v2(p_snapshot uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; body text; rows integer; rejected integer:=0; category text:='nse_reference_sch_layout_invalid';
BEGIN
 SELECT * INTO STRICT s FROM nse_reference.snapshots WHERE id=p_snapshot AND file_type='SCH';
 PERFORM nse_reference.lock_download(s.workspace_id,s.download_id);
 body:=pg_catalog.convert_from(nse_reference.body(s.download_id),'UTF8');
 IF left(body,1)=chr(65279) THEN body:=substr(body,2); END IF;
 -- Accept only consistent LF or CRLF, with either one terminal newline or
 -- immediate EOF after the final record. Current NSE UAT SCH evidence on
 -- 2026-10-07 used CRLF between records and no final line ending. Quoting,
 -- escaping, controls and embedded BOM remain fail-closed.
 IF strpos(body,E'\r\n')>0 THEN
  IF strpos(replace(body,E'\r\n',''),E'\n')>0 THEN body:=''; END IF;
  body:=replace(body,E'\r\n',E'\n');
  IF strpos(body,E'\r')>0 THEN body:=''; END IF;
 END IF;
 IF body ~ '[\x01-\x09\x0B-\x1F\x7F]' OR strpos(body,chr(65279))>0 OR strpos(body,'"')>0 THEN
  body:='';
 END IF;
 -- Remove at most one terminal LF. If no LF is present, COMPLETE transport
 -- evidence has already proved EOF, so the final row remains intact. A blank
 -- line or a second terminal newline still becomes an invalid empty record.
 IF right(body,1)=E'\n' THEN
  body:=left(body,greatest(length(body)-1,0));
 END IF;
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

-- Preserve immutable historical validation receipts while moving only future SCH
-- jobs to the evidence-backed V2 framing profile. The registry remains immutable
-- before and after this owner-controlled migration.
DROP TRIGGER immutable ON nse_reference.validators;
DO $$
DECLARE changed integer;
BEGIN
  UPDATE nse_reference.validators
  SET parser_version='SCH_OBSERVED_44_V2', function_name='validate_sch_v2'
  WHERE file_type='SCH'
    AND parser_version='SCH_OBSERVED_44_V1'
    AND function_name='validate_sch_v1';
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed<>1 THEN
    RAISE EXCEPTION 'nse_reference_sch_validator_registry_unexpected';
  END IF;
END $$;
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON nse_reference.validators
  FOR EACH ROW EXECUTE FUNCTION nse_reference.immutable();

CREATE OR REPLACE FUNCTION public.search_nse_schemes(
  p_query text,
  p_limit integer DEFAULT 25
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  q text;
  requested_limit integer;
  v_snapshot_id uuid;
  v_snapshot_version bigint;
  v_snapshot_created_at timestamptz;
  result_items jsonb;
BEGIN
  IF NOT moneybowl_authz.account_active(auth.uid()) THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE='42501';
  END IF;

  q:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_query,'')));
  requested_limit:=coalesce(p_limit,25);
  IF pg_catalog.length(q)<2 OR pg_catalog.length(q)>100
     OR requested_limit<1 OR requested_limit>50 THEN
    RAISE EXCEPTION 'fund_search_request_invalid';
  END IF;

  SELECT s.id,s.version,s.created_at
    INTO v_snapshot_id,v_snapshot_version,v_snapshot_created_at
  FROM nse_reference.snapshots s
  JOIN nse_reference.validations v ON v.snapshot_id=s.id
  JOIN nse_reference.connections c
    ON c.id=s.connection_id AND c.workspace_id=s.workspace_id
  JOIN public.workspaces w ON w.id=s.workspace_id
  WHERE s.file_type='SCH'
    AND v.status='STAGED_VALIDATED'
    AND v.parser_version IN ('SCH_OBSERVED_44_V1','SCH_OBSERVED_44_V2')
    AND c.environment='UAT'
    AND c.enabled
    AND w.workspace_status='active'
  ORDER BY s.version DESC,s.created_at DESC,s.id DESC
  LIMIT 1;

  IF v_snapshot_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'source','NSE_INVEST_SCH',
      'available',false,
      'items','[]'::pg_catalog.jsonb
    );
  END IF;

  WITH candidates AS (
    SELECT
      i.scheme_code,
      r.scheme_name,
      r.amc_code,
      r.rta_agent_code,
      r.rta_scheme_code,
      r.amc_scheme_code,
      r.isin,
      r.scheme_type,
      r.plan_type,
      r.native_fields[27] AS amc_active_flag,
      CASE
        WHEN pg_catalog.lower(i.scheme_code)=q THEN 0
        WHEN pg_catalog.lower(r.scheme_name)=q THEN 1
        WHEN pg_catalog.strpos(pg_catalog.lower(r.scheme_name),q)=1 THEN 2
        WHEN pg_catalog.lower(r.isin)=q THEN 3
        WHEN pg_catalog.lower(r.amc_code)=q THEN 4
        ELSE 5
      END AS rank
    FROM nse_reference.sch_rows r
    JOIN nse_reference.scheme_identities i
      ON i.id=r.scheme_identity_id
     AND i.workspace_id=r.workspace_id
     AND i.connection_id=r.connection_id
    WHERE r.snapshot_id=v_snapshot_id
      AND (
        pg_catalog.strpos(pg_catalog.lower(i.scheme_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.scheme_name),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.amc_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.rta_agent_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.rta_scheme_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.amc_scheme_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.isin),q)>0
      )
    ORDER BY rank,r.scheme_name,i.scheme_code
    LIMIT requested_limit
  )
  SELECT coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'scheme_code',scheme_code,
        'scheme_name',scheme_name,
        'amc_code',amc_code,
        'rta_agent_code',rta_agent_code,
        'rta_scheme_code',rta_scheme_code,
        'amc_scheme_code',amc_scheme_code,
        'isin',isin,
        'scheme_type',scheme_type,
        'plan_type',plan_type,
        'amc_active_flag',amc_active_flag
      )
      ORDER BY rank,scheme_name,scheme_code
    ),
    '[]'::pg_catalog.jsonb
  ) INTO result_items
  FROM candidates;

  RETURN pg_catalog.jsonb_build_object(
    'source','NSE_INVEST_SCH',
    'available',true,
    'snapshot_version',v_snapshot_version,
    'snapshot_created_at',v_snapshot_created_at,
    'items',result_items
  );
END
$$;


REVOKE ALL ON FUNCTION nse_reference.validate_sch_v2(uuid) FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
