-- B06.3: reference-only product profiles registered with the shared B06.2 runtime.
BEGIN;
CREATE TABLE nse_reference.systematic_validations (
  snapshot_id uuid NOT NULL,
  parser_version text NOT NULL CHECK (parser_version='nse-systematic-web-v1'),
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL CHECK (file_type IN ('SIP','STP','SWP')),
  layout_id text NOT NULL CHECK (layout_id='NSE_WEB_'||file_type::text||'_V1'),
  source_sha256 bytea NOT NULL CHECK (octet_length(source_sha256)=32),
  header_sha256 bytea NOT NULL CHECK (octet_length(header_sha256)=32),
  source_bytes integer NOT NULL CHECK (source_bytes BETWEEN 1 AND 16777216),
  row_count integer NOT NULL CHECK (row_count BETWEEN 1 AND 100000),
  rejected_rows integer NOT NULL DEFAULT 0 CHECK (rejected_rows=0),
  authority text NOT NULL DEFAULT 'REFERENCE_ONLY' CHECK (authority='REFERENCE_ONLY'),
  validated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY (snapshot_id,parser_version),
  UNIQUE(snapshot_id,workspace_id,connection_id,file_type,parser_version),
  FOREIGN KEY(snapshot_id,workspace_id,connection_id,file_type)
    REFERENCES nse_reference.snapshots(id,workspace_id,connection_id,file_type) ON DELETE RESTRICT
);
CREATE TABLE nse_reference.sip_products (
  snapshot_id uuid NOT NULL,
  parser_version text NOT NULL,
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL DEFAULT 'SIP' CHECK (file_type='SIP'),
  source_line integer NOT NULL CHECK (source_line BETWEEN 2 AND 100001),
  source_row_sha256 bytea NOT NULL CHECK (octet_length(source_row_sha256)=32),
  amc_code text NOT NULL CHECK (char_length(amc_code) BETWEEN 1 AND 100),
  amc_name text NOT NULL CHECK (char_length(amc_name) BETWEEN 1 AND 255),
  scheme_code text NOT NULL CHECK (char_length(scheme_code) BETWEEN 1 AND 30),
  scheme_name text NOT NULL CHECK (char_length(scheme_name) BETWEEN 1 AND 200),
  transaction_mode text NOT NULL CHECK (char_length(transaction_mode) BETWEEN 1 AND 1),
  frequency text NOT NULL CHECK (char_length(frequency) BETWEEN 1 AND 15),
  dates text NOT NULL CHECK (char_length(dates) BETWEEN 1 AND 100),
  minimum_gap integer NOT NULL CHECK (minimum_gap BETWEEN 0 AND 99999),
  maximum_gap integer NOT NULL CHECK (maximum_gap BETWEEN 0 AND 99999),
  installment_gap integer NOT NULL CHECK (installment_gap BETWEEN 0 AND 99999),
  status text NOT NULL CHECK (char_length(status) BETWEEN 1 AND 1),
  minimum_installment_amount numeric(12,2) NOT NULL CHECK (minimum_installment_amount>=0),
  maximum_installment_amount numeric(12,2) NOT NULL CHECK (maximum_installment_amount>=0),
  multiplier_amount integer NOT NULL CHECK (multiplier_amount BETWEEN 0 AND 99999),
  minimum_installments integer NOT NULL CHECK (minimum_installments BETWEEN 0 AND 99999),
  maximum_installments integer NOT NULL CHECK (maximum_installments BETWEEN 0 AND 99999),
  scheme_isin text NOT NULL CHECK (char_length(scheme_isin) BETWEEN 1 AND 12),
  scheme_type text NOT NULL CHECK (char_length(scheme_type) BETWEEN 1 AND 25),
  pause_flag text NOT NULL CHECK (pause_flag='N'),
  pause_minimum_installments text NOT NULL CHECK (pause_minimum_installments=''),
  pause_maximum_installments text NOT NULL CHECK (pause_maximum_installments=''),
  pause_modification_count text NOT NULL CHECK (pause_modification_count=''),
  filler1 text NOT NULL CHECK (filler1=''),
  filler2 text NOT NULL CHECK (filler2=''),
  filler3 text NOT NULL CHECK (filler3=''),
  filler4 text NOT NULL CHECK (filler4=''),
  filler5 text NOT NULL CHECK (filler5=''),
  PRIMARY KEY(snapshot_id,parser_version,source_line),
  UNIQUE(snapshot_id,parser_version,source_row_sha256),
  FOREIGN KEY(snapshot_id,workspace_id,connection_id,file_type,parser_version)
    REFERENCES nse_reference.systematic_validations(snapshot_id,workspace_id,connection_id,file_type,parser_version) ON DELETE RESTRICT
);
CREATE INDEX sip_products_scheme ON nse_reference.sip_products(snapshot_id,parser_version,scheme_code,source_line);
CREATE TABLE nse_reference.stp_products (
  snapshot_id uuid NOT NULL,
  parser_version text NOT NULL,
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL DEFAULT 'STP' CHECK (file_type='STP'),
  source_line integer NOT NULL CHECK (source_line BETWEEN 2 AND 100001),
  source_row_sha256 bytea NOT NULL CHECK (octet_length(source_row_sha256)=32),
  amc_code text NOT NULL CHECK (char_length(amc_code) BETWEEN 1 AND 100),
  amc_name text NOT NULL CHECK (char_length(amc_name) BETWEEN 1 AND 255),
  scheme_code text NOT NULL CHECK (char_length(scheme_code) BETWEEN 1 AND 30),
  scheme_name text NOT NULL CHECK (char_length(scheme_name) BETWEEN 1 AND 200),
  scheme_isin text NOT NULL CHECK (char_length(scheme_isin) BETWEEN 1 AND 12),
  scheme_type text NOT NULL CHECK (char_length(scheme_type) BETWEEN 1 AND 25),
  transaction_mode text NOT NULL CHECK (char_length(transaction_mode) BETWEEN 1 AND 2),
  in_minimum_installment_amount numeric(12,2) NOT NULL CHECK (in_minimum_installment_amount>=0),
  in_maximum_installment_amount numeric(12,2) NOT NULL CHECK (in_maximum_installment_amount>=0),
  in_multiplier_amount integer NOT NULL CHECK (in_multiplier_amount BETWEEN 0 AND 99999),
  out_minimum_installment_amount numeric(12,2) NOT NULL CHECK (out_minimum_installment_amount>=0),
  out_maximum_installment_amount numeric(12,2) NOT NULL CHECK (out_maximum_installment_amount>=0),
  out_multiplier_amount integer NOT NULL CHECK (out_multiplier_amount BETWEEN 0 AND 99999),
  minimum_installment_units numeric(12,2) NOT NULL CHECK (minimum_installment_units>=0),
  maximum_installment_units numeric(12,2) NOT NULL CHECK (maximum_installment_units>=0),
  multiplier_units integer NOT NULL CHECK (multiplier_units BETWEEN 0 AND 99999),
  minimum_installments integer NOT NULL CHECK (minimum_installments BETWEEN 0 AND 99999),
  maximum_installments integer NOT NULL CHECK (maximum_installments BETWEEN 0 AND 99999),
  registration_in integer NOT NULL CHECK (registration_in BETWEEN 0 AND 9),
  registration_out integer NOT NULL CHECK (registration_out BETWEEN 0 AND 9),
  frequency text NOT NULL CHECK (char_length(frequency) BETWEEN 1 AND 15),
  dates text NOT NULL CHECK (char_length(dates) BETWEEN 1 AND 100),
  minimum_gap integer NOT NULL CHECK (minimum_gap BETWEEN 0 AND 99999),
  maximum_gap integer NOT NULL CHECK (maximum_gap BETWEEN 0 AND 99999),
  installment_gap integer NOT NULL CHECK (installment_gap BETWEEN 0 AND 99999),
  status text NOT NULL CHECK (char_length(status) BETWEEN 1 AND 1),
  PRIMARY KEY(snapshot_id,parser_version,source_line),
  UNIQUE(snapshot_id,parser_version,source_row_sha256),
  FOREIGN KEY(snapshot_id,workspace_id,connection_id,file_type,parser_version)
    REFERENCES nse_reference.systematic_validations(snapshot_id,workspace_id,connection_id,file_type,parser_version) ON DELETE RESTRICT
);
CREATE INDEX stp_products_scheme ON nse_reference.stp_products(snapshot_id,parser_version,scheme_code,source_line);
CREATE TABLE nse_reference.swp_products (
  snapshot_id uuid NOT NULL,
  parser_version text NOT NULL,
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL DEFAULT 'SWP' CHECK (file_type='SWP'),
  source_line integer NOT NULL CHECK (source_line BETWEEN 2 AND 100001),
  source_row_sha256 bytea NOT NULL CHECK (octet_length(source_row_sha256)=32),
  amc_code text NOT NULL CHECK (char_length(amc_code) BETWEEN 1 AND 100),
  amc_name text NOT NULL CHECK (char_length(amc_name) BETWEEN 1 AND 255),
  scheme_code text NOT NULL CHECK (char_length(scheme_code) BETWEEN 1 AND 30),
  scheme_name text NOT NULL CHECK (char_length(scheme_name) BETWEEN 1 AND 200),
  scheme_isin text NOT NULL CHECK (char_length(scheme_isin) BETWEEN 1 AND 12),
  scheme_type text NOT NULL CHECK (char_length(scheme_type) BETWEEN 1 AND 25),
  transaction_mode text NOT NULL CHECK (char_length(transaction_mode) BETWEEN 1 AND 2),
  minimum_installment_amount numeric(12,2) NOT NULL CHECK (minimum_installment_amount>=0),
  maximum_installment_amount numeric(12,2) NOT NULL CHECK (maximum_installment_amount>=0),
  multiplier_amount integer NOT NULL CHECK (multiplier_amount BETWEEN 0 AND 99999),
  minimum_installment_units numeric(12,3) NOT NULL CHECK (minimum_installment_units>=0),
  maximum_installment_units numeric(12,3) NOT NULL CHECK (maximum_installment_units>=0),
  multiplier_units integer NOT NULL CHECK (multiplier_units BETWEEN 0 AND 99999),
  minimum_installments integer NOT NULL CHECK (minimum_installments BETWEEN 0 AND 99999),
  maximum_installments integer NOT NULL CHECK (maximum_installments BETWEEN 0 AND 99999),
  frequency text NOT NULL CHECK (char_length(frequency) BETWEEN 1 AND 15),
  dates text NOT NULL CHECK (char_length(dates) BETWEEN 1 AND 100),
  minimum_gap integer NOT NULL CHECK (minimum_gap BETWEEN 0 AND 99999),
  maximum_gap integer NOT NULL CHECK (maximum_gap BETWEEN 0 AND 99999),
  installment_gap integer NOT NULL CHECK (installment_gap BETWEEN 0 AND 99999),
  status text NOT NULL CHECK (char_length(status) BETWEEN 1 AND 1),
  PRIMARY KEY(snapshot_id,parser_version,source_line),
  UNIQUE(snapshot_id,parser_version,source_row_sha256),
  FOREIGN KEY(snapshot_id,workspace_id,connection_id,file_type,parser_version)
    REFERENCES nse_reference.systematic_validations(snapshot_id,workspace_id,connection_id,file_type,parser_version) ON DELETE RESTRICT
);
CREATE INDEX swp_products_scheme ON nse_reference.swp_products(snapshot_id,parser_version,scheme_code,source_line);
-- The append-only publication ledger is the current-pointer history. Current is the
-- highest snapshot version in this scope; staging/validation cannot change it.
CREATE TABLE nse_reference.systematic_publications (
  snapshot_id uuid PRIMARY KEY,
  parser_version text NOT NULL,
  workspace_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  file_type nse_reference.file_type NOT NULL,
  version bigint NOT NULL CHECK(version>0),
  previous_snapshot_id uuid,
  published_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE(connection_id,file_type,version),
  UNIQUE(snapshot_id,workspace_id,connection_id,file_type),
  FOREIGN KEY(snapshot_id,workspace_id,connection_id,file_type,parser_version)
    REFERENCES nse_reference.systematic_validations(snapshot_id,workspace_id,connection_id,file_type,parser_version) ON DELETE RESTRICT,
  FOREIGN KEY(previous_snapshot_id,workspace_id,connection_id,file_type)
    REFERENCES nse_reference.systematic_publications(snapshot_id,workspace_id,connection_id,file_type) ON DELETE RESTRICT,
  CHECK(previous_snapshot_id IS DISTINCT FROM snapshot_id)
);
CREATE INDEX systematic_publication_previous ON nse_reference.systematic_publications(previous_snapshot_id);

CREATE FUNCTION nse_reference.systematic_headers(kind text) RETURNS text[]
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT CASE kind
 WHEN 'SIP' THEN ARRAY['AMC CODE','AMC NAME','SCHEME CODE','SCHEME NAME','SIP TRANSACTION MODE','SIP FREQUENCY','SIP DATES','SIP MINIMUM GAP','SIP MAXIMUM GAP','SIP INSTALLMENT GAP','SIP STATUS','SIP MINIMUM INSTALLMENT AMOUNT','SIP MAXIMUM INSTALLMENT AMOUNT','SIP MULTIPLIER AMOUNT','SIP MINIMUM INSTALLMENT NUMBERS','SIP MAXIMUM INSTALLMENT NUMBERS','SCHEME ISIN','SCHEME TYPE','PAUSE FLAG','PAUSE MINIMUM INSTALLMENTS','PAUSE MAXIMUM INSTALLMENTS','PAUSE MODIFICATION COUNT','FILLER 1','FILLER 2','FILLER 3','FILLER 4','FILLER 5']
 WHEN 'STP' THEN ARRAY['AMC CODE','AMC NAME','NSE SCHEME CODE','SCHEME NAME','SCHEME ISIN','SCHEME TYPE','ASTP TRANSACTION MODE','ASTP IN MINIMUM INSTALLMENT AMOUNT','ASTP IN MAXIMUM INSTALLMENT AMOUNT','ASTP IN MULTIPLIER AMOUNT','ASTP OUT MINIMUM INSTALLMENT AMOUNT','ASTP OUT MAXIMUM INSTALLMENT AMOUNT','ASTP OUT MULTIPLIER AMOUNT','ASTP MINIMUM INSTALLMENT UNITS','ASTP MAXIMUM INSTALLMENT UNITS','ASTP MULTIPLIER UNITS','ASTP MINIMUM INSTALLMENT NUMBERS','ASTP MAXIMUM INSTALLMENT NUMBERS','ASTP REG IN','ASTP REG OUT','ASTP FREQUENCY','ASTP DATES','ASTP MINIMUM GAP','ASTP MAXIMUM GAP','ASTP INSTALLMENT GAP','ASTP STATUS']
 WHEN 'SWP' THEN ARRAY['AMC CODE','AMC NAME','NSE SCHEME CODE','SCHEME NAME','SCHEME ISIN','SCHEME TYPE','SWP TRANSACTION MODE','SWP MINIMUM INSTALLMENT AMOUNT','SWP MAXIMUM INSTALLMENT AMOUNT','SWP MULTIPLIER AMOUNT','SWP MINIMUM INSTALLMENT UNITS','SWP MAXIMUM INSTALLMENT UNITS','SWP MULTIPLIER UNITS','SWP MINIMUM INSTALLMENT NUMBERS','SWP MAXIMUM INSTALLMENT NUMBERS','SWP FREQUENCY','SWP DATES','SWP MINIMUM GAP','SWP MAXIMUM GAP','SWP INSTALLMENT GAP','SWP STATUS']
 ELSE NULL END $$;
CREATE FUNCTION nse_reference.systematic_text(value text, max_length integer) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
BEGIN
  IF value IS NULL OR char_length(value) NOT BETWEEN 1 AND max_length OR value<>btrim(value) THEN
    RAISE EXCEPTION 'nse_systematic_field_invalid'; END IF;
  RETURN value;
END $$;
CREATE FUNCTION nse_reference.systematic_number(value text, digits integer, scale integer DEFAULT 0) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
BEGIN
  IF value IS NULL OR value !~ ('^[0-9]{1,'||digits::text||'}'||
    CASE WHEN scale=0 THEN '' ELSE '(\.[0-9]{1,'||scale::text||'})?' END||'$') THEN
    RAISE EXCEPTION 'nse_systematic_number_invalid'; END IF;
  RETURN value::numeric;
END $$;
CREATE FUNCTION nse_reference.systematic_reserved(value text, expected text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
BEGIN
  IF value IS DISTINCT FROM expected THEN RAISE EXCEPTION 'nse_systematic_reserved_field'; END IF;
  RETURN value;
END $$;
CREATE FUNCTION nse_reference.systematic_receipt(p_snapshot uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT pg_catalog.jsonb_build_object('snapshot_id',v.snapshot_id,'workspace_id',v.workspace_id,
    'connection_id',v.connection_id,'file_type',v.file_type,'version',s.version,
    'download_id',s.download_id,'parser_version',v.parser_version,'layout_id',v.layout_id,
    'source_sha256',encode(v.source_sha256,'hex'),'source_bytes',v.source_bytes,
    'header_sha256',encode(v.header_sha256,'hex'),'row_count',v.row_count,
    'rejected_rows',v.rejected_rows,'authority',v.authority,
    'eligibility','UNINTERPRETED','reason','PRODUCT_SEMANTICS_UNCOMMISSIONED')
  FROM nse_reference.systematic_validations v JOIN nse_reference.snapshots s ON s.id=v.snapshot_id
  WHERE v.snapshot_id=p_snapshot
$$;
CREATE FUNCTION nse_reference.validate_systematic(p_workspace uuid,p_snapshot uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; r nse_reference.results; b bytea; body text; lines text[]; c text[];
  headers text[]; line text; row_hash bytea;
BEGIN
  SELECT * INTO s FROM nse_reference.snapshots WHERE id=p_snapshot AND workspace_id=p_workspace;
  IF s.id IS NULL THEN RAISE EXCEPTION 'nse_reference_snapshot_unavailable'; END IF;
  PERFORM nse_reference.lock_download(p_workspace,s.download_id);
  IF s.file_type NOT IN ('SIP','STP','SWP') THEN RAISE EXCEPTION 'nse_systematic_variant_invalid'; END IF;
  SELECT * INTO r FROM nse_reference.results WHERE download_id=s.download_id;
  IF r.capture_kind IS DISTINCT FROM 'COMPLETE' OR r.http_status IS DISTINCT FROM 200 OR
    r.media_type NOT IN ('TEXT','OCTET_STREAM') THEN RAISE EXCEPTION 'nse_reference_not_stageable'; END IF;
  b:=nse_reference.body(s.download_id);
  IF extensions.digest(b,'sha256')<>r.response_sha256 OR octet_length(b)<>r.captured_bytes THEN
    RAISE EXCEPTION 'nse_reference_integrity_mismatch'; END IF;
  IF EXISTS(SELECT 1 FROM nse_reference.systematic_validations WHERE snapshot_id=s.id) THEN
    RETURN nse_reference.systematic_receipt(s.id); END IF;
  BEGIN body:=pg_catalog.convert_from(b,'UTF8'); EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'nse_systematic_encoding_invalid'; END;
  IF left(body,1)=chr(65279) THEN body:=substr(body,2); END IF;
  body:=replace(body,E'\r\n',E'\n');
  IF body ~ E'[\x01-\x09\x0b-\x1f\x7f]' OR strpos(body,chr(65279))>0 THEN RAISE EXCEPTION 'nse_systematic_framing_invalid'; END IF;
  IF right(body,1)=E'\n' THEN body:=left(body,length(body)-1); END IF;
  lines:=string_to_array(body,E'\n'); headers:=nse_reference.systematic_headers(s.file_type::text);
  IF lines[1] IS DISTINCT FROM array_to_string(headers,'|') THEN RAISE EXCEPTION 'nse_systematic_layout_unknown'; END IF;
  IF cardinality(lines) NOT BETWEEN 2 AND 100001 THEN RAISE EXCEPTION 'nse_systematic_row_count_invalid'; END IF;
  INSERT INTO nse_reference.systematic_validations(snapshot_id,parser_version,workspace_id,connection_id,file_type,layout_id,
    source_sha256,header_sha256,source_bytes,row_count)
  VALUES(s.id,'nse-systematic-web-v1',s.workspace_id,s.connection_id,s.file_type,'NSE_WEB_'||s.file_type::text||'_V1',
    r.response_sha256,extensions.digest(lines[1],'sha256'),r.captured_bytes,cardinality(lines)-1);
  FOR i IN 2..cardinality(lines) LOOP
    line:=lines[i]; c:=string_to_array(line,'|'); row_hash:=extensions.digest(line,'sha256');
    IF char_length(line) NOT BETWEEN 1 AND 4096 THEN RAISE EXCEPTION 'nse_systematic_row_invalid'; END IF;
    IF cardinality(c)<>cardinality(headers) THEN RAISE EXCEPTION 'nse_systematic_column_count'; END IF;
    BEGIN
    IF s.file_type='SIP' THEN
      INSERT INTO nse_reference.sip_products(
        snapshot_id,parser_version,workspace_id,connection_id,source_line,
        source_row_sha256,amc_code,amc_name,scheme_code,scheme_name,
        transaction_mode,frequency,dates,minimum_gap,maximum_gap,
        installment_gap,status,minimum_installment_amount,maximum_installment_amount,multiplier_amount,
        minimum_installments,maximum_installments,scheme_isin,scheme_type,pause_flag,
        pause_minimum_installments,pause_maximum_installments,pause_modification_count,filler1,filler2,
        filler3,filler4,filler5)
      VALUES(
        s.id,'nse-systematic-web-v1',s.workspace_id,
        s.connection_id,i,row_hash,
        nse_reference.systematic_text(c[1],100),nse_reference.systematic_text(c[2],255),nse_reference.systematic_text(c[3],30),
        nse_reference.systematic_text(c[4],200),nse_reference.systematic_text(c[5],1),nse_reference.systematic_text(c[6],15),
        nse_reference.systematic_text(c[7],100),nse_reference.systematic_number(c[8],5),nse_reference.systematic_number(c[9],5),
        nse_reference.systematic_number(c[10],5),nse_reference.systematic_text(c[11],1),nse_reference.systematic_number(c[12],10,2),
        nse_reference.systematic_number(c[13],10,2),nse_reference.systematic_number(c[14],5),nse_reference.systematic_number(c[15],5),
        nse_reference.systematic_number(c[16],5),nse_reference.systematic_text(c[17],12),nse_reference.systematic_text(c[18],25),
        nse_reference.systematic_reserved(c[19],'N'),nse_reference.systematic_reserved(c[20],''),nse_reference.systematic_reserved(c[21],''),
        nse_reference.systematic_reserved(c[22],''),nse_reference.systematic_reserved(c[23],''),nse_reference.systematic_reserved(c[24],''),
        nse_reference.systematic_reserved(c[25],''),nse_reference.systematic_reserved(c[26],''),nse_reference.systematic_reserved(c[27],''));
    ELSIF s.file_type='STP' THEN
      INSERT INTO nse_reference.stp_products(
        snapshot_id,parser_version,workspace_id,connection_id,source_line,
        source_row_sha256,amc_code,amc_name,scheme_code,scheme_name,
        scheme_isin,scheme_type,transaction_mode,in_minimum_installment_amount,in_maximum_installment_amount,
        in_multiplier_amount,out_minimum_installment_amount,out_maximum_installment_amount,out_multiplier_amount,minimum_installment_units,
        maximum_installment_units,multiplier_units,minimum_installments,maximum_installments,registration_in,
        registration_out,frequency,dates,minimum_gap,maximum_gap,
        installment_gap,status)
      VALUES(
        s.id,'nse-systematic-web-v1',s.workspace_id,
        s.connection_id,i,row_hash,
        nse_reference.systematic_text(c[1],100),nse_reference.systematic_text(c[2],255),nse_reference.systematic_text(c[3],30),
        nse_reference.systematic_text(c[4],200),nse_reference.systematic_text(c[5],12),nse_reference.systematic_text(c[6],25),
        nse_reference.systematic_text(c[7],2),nse_reference.systematic_number(c[8],10,2),nse_reference.systematic_number(c[9],10,2),
        nse_reference.systematic_number(c[10],5),nse_reference.systematic_number(c[11],10,2),nse_reference.systematic_number(c[12],10,2),
        nse_reference.systematic_number(c[13],5),nse_reference.systematic_number(c[14],10,2),nse_reference.systematic_number(c[15],10,2),
        nse_reference.systematic_number(c[16],5),nse_reference.systematic_number(c[17],5),nse_reference.systematic_number(c[18],5),
        nse_reference.systematic_number(c[19],1),nse_reference.systematic_number(c[20],1),nse_reference.systematic_text(c[21],15),
        nse_reference.systematic_text(c[22],100),nse_reference.systematic_number(c[23],5),nse_reference.systematic_number(c[24],5),
        nse_reference.systematic_number(c[25],5),nse_reference.systematic_text(c[26],1));
    ELSIF s.file_type='SWP' THEN
      INSERT INTO nse_reference.swp_products(
        snapshot_id,parser_version,workspace_id,connection_id,source_line,
        source_row_sha256,amc_code,amc_name,scheme_code,scheme_name,
        scheme_isin,scheme_type,transaction_mode,minimum_installment_amount,maximum_installment_amount,
        multiplier_amount,minimum_installment_units,maximum_installment_units,multiplier_units,minimum_installments,
        maximum_installments,frequency,dates,minimum_gap,maximum_gap,
        installment_gap,status)
      VALUES(
        s.id,'nse-systematic-web-v1',s.workspace_id,
        s.connection_id,i,row_hash,
        nse_reference.systematic_text(c[1],100),nse_reference.systematic_text(c[2],255),nse_reference.systematic_text(c[3],30),
        nse_reference.systematic_text(c[4],200),nse_reference.systematic_text(c[5],12),nse_reference.systematic_text(c[6],25),
        nse_reference.systematic_text(c[7],2),nse_reference.systematic_number(c[8],10,2),nse_reference.systematic_number(c[9],10,2),
        nse_reference.systematic_number(c[10],5),nse_reference.systematic_number(c[11],9,3),nse_reference.systematic_number(c[12],9,3),
        nse_reference.systematic_number(c[13],5),nse_reference.systematic_number(c[14],5),nse_reference.systematic_number(c[15],5),
        nse_reference.systematic_text(c[16],15),nse_reference.systematic_text(c[17],100),nse_reference.systematic_number(c[18],5),
        nse_reference.systematic_number(c[19],5),nse_reference.systematic_number(c[20],5),nse_reference.systematic_text(c[21],1));
    END IF;
    EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'nse_systematic_duplicate_row'; END;
  END LOOP;
  RETURN nse_reference.systematic_receipt(s.id);
END $$;
CREATE FUNCTION public.validate_nse_systematic_snapshot(p_workspace_id uuid,p_snapshot_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN RETURN nse_reference.validate_systematic(p_workspace_id,p_snapshot_id); END $$;

CREATE FUNCTION public.publish_nse_systematic_snapshot(p_workspace_id uuid,p_snapshot_id uuid,p_expected_current_snapshot_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; prior nse_reference.systematic_publications; old nse_reference.systematic_publications; receipt jsonb;
BEGIN
  SELECT * INTO s FROM nse_reference.snapshots WHERE id=p_snapshot_id AND workspace_id=p_workspace_id;
  IF s.id IS NULL THEN RAISE EXCEPTION 'nse_reference_snapshot_unavailable'; END IF;
  PERFORM nse_reference.lock_connection(p_workspace_id,s.connection_id);
  IF s.file_type NOT IN ('SIP','STP','SWP') THEN RAISE EXCEPTION 'nse_systematic_variant_invalid'; END IF;
  SELECT * INTO prior FROM nse_reference.systematic_publications WHERE connection_id=s.connection_id AND file_type=s.file_type ORDER BY version DESC LIMIT 1;
  SELECT * INTO old FROM nse_reference.systematic_publications WHERE snapshot_id=s.id;
  IF old.snapshot_id IS NOT NULL THEN
    IF old.previous_snapshot_id IS DISTINCT FROM p_expected_current_snapshot_id THEN RAISE EXCEPTION 'nse_systematic_publication_conflict'; END IF;
    RETURN nse_reference.systematic_receipt(s.id)||pg_catalog.jsonb_build_object('is_current',prior.snapshot_id=s.id);
  END IF;
  IF prior.snapshot_id IS DISTINCT FROM p_expected_current_snapshot_id THEN RAISE EXCEPTION 'nse_systematic_publication_conflict'; END IF;
  IF s.version<=prior.version THEN RAISE EXCEPTION 'nse_systematic_version_regression'; END IF;
  IF EXISTS(SELECT 1 FROM nse_reference.downloads incoming
    JOIN nse_reference.snapshots previous ON previous.id=prior.snapshot_id
    JOIN nse_reference.downloads previous_download ON previous_download.id=previous.download_id
    WHERE incoming.id=s.download_id AND incoming.started_at<previous_download.started_at) THEN
    RAISE EXCEPTION 'nse_systematic_capture_regression'; END IF;
  -- Validation, all typed rows, publication and audit are one atomic transaction.
  receipt:=nse_reference.validate_systematic(p_workspace_id,p_snapshot_id);
  INSERT INTO nse_reference.systematic_publications(snapshot_id,parser_version,workspace_id,connection_id,file_type,version,previous_snapshot_id)
  VALUES(s.id,'nse-systematic-web-v1',s.workspace_id,s.connection_id,s.file_type,s.version,prior.snapshot_id);
  INSERT INTO public.workspace_audit_logs(workspace_id,action,event_type,target_type,entity_type,target_id,entity_id,actor_type,reason,payload)
  VALUES(s.workspace_id,'nse.reference.systematic_publish','nse.reference.systematic_publish','nse_reference','nse_reference',s.id,s.id,
    'system','Publish validated product reference',pg_catalog.jsonb_build_object('file_type',s.file_type,'previous_snapshot_id',prior.snapshot_id,
    'snapshot_id',s.id,'version',s.version,'parser_version','nse-systematic-web-v1','authority','REFERENCE_ONLY'));
  RETURN receipt||pg_catalog.jsonb_build_object('is_current',true);
END $$;
CREATE FUNCTION public.get_nse_systematic_current(p_workspace_id uuid,p_connection_id uuid,p_file_type text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE snapshot uuid;
BEGIN
  PERFORM nse_reference.lock_connection(p_workspace_id,p_connection_id);
  IF p_file_type IS NULL OR p_file_type NOT IN ('SIP','STP','SWP') THEN RAISE EXCEPTION 'nse_systematic_variant_invalid'; END IF;
  SELECT snapshot_id INTO snapshot FROM nse_reference.systematic_publications
    WHERE connection_id=p_connection_id AND file_type::text=p_file_type ORDER BY version DESC LIMIT 1;
  RETURN nse_reference.systematic_receipt(snapshot);
END $$;
-- Resolve current once, then pin snapshot_id across all pages/decisions. NSE codes
-- stay in their source namespace; no equality join to mutual_funds is implied.
CREATE FUNCTION public.get_nse_systematic_products(p_workspace_id uuid,p_snapshot_id uuid,p_scheme_code text,
  p_after_line integer DEFAULT 1,p_limit integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.systematic_publications; rows jsonb;
BEGIN
  SELECT * INTO s FROM nse_reference.systematic_publications WHERE snapshot_id=p_snapshot_id AND workspace_id=p_workspace_id;
  IF s.snapshot_id IS NULL THEN RAISE EXCEPTION 'nse_systematic_publication_unavailable'; END IF;
  PERFORM nse_reference.lock_connection(p_workspace_id,s.connection_id);
  IF p_after_line IS NULL OR p_after_line NOT BETWEEN 1 AND 100001 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500
    OR p_scheme_code IS NULL OR char_length(p_scheme_code) NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'nse_systematic_query_invalid'; END IF;
  SELECT COALESCE(jsonb_agg(x.row_data ORDER BY x.source_line),'[]'::jsonb) INTO rows FROM (
    SELECT source_line,to_jsonb(p)-'source_row_sha256'||jsonb_build_object('source_row_sha256',encode(p.source_row_sha256,'hex'))||jsonb_build_object('minimum_installment_amount',p.minimum_installment_amount::text,'maximum_installment_amount',p.maximum_installment_amount::text) AS row_data
      FROM nse_reference.sip_products p WHERE s.file_type='SIP' AND p.snapshot_id=s.snapshot_id AND p.scheme_code=p_scheme_code AND p.source_line>p_after_line
    UNION ALL
    SELECT source_line,to_jsonb(p)-'source_row_sha256'||jsonb_build_object('source_row_sha256',encode(p.source_row_sha256,'hex'))||jsonb_build_object('in_minimum_installment_amount',p.in_minimum_installment_amount::text,'in_maximum_installment_amount',p.in_maximum_installment_amount::text,'out_minimum_installment_amount',p.out_minimum_installment_amount::text,'out_maximum_installment_amount',p.out_maximum_installment_amount::text,'minimum_installment_units',p.minimum_installment_units::text,'maximum_installment_units',p.maximum_installment_units::text)
      FROM nse_reference.stp_products p WHERE s.file_type='STP' AND p.snapshot_id=s.snapshot_id AND p.scheme_code=p_scheme_code AND p.source_line>p_after_line
    UNION ALL
    SELECT source_line,to_jsonb(p)-'source_row_sha256'||jsonb_build_object('source_row_sha256',encode(p.source_row_sha256,'hex'))||jsonb_build_object('minimum_installment_amount',p.minimum_installment_amount::text,'maximum_installment_amount',p.maximum_installment_amount::text,'minimum_installment_units',p.minimum_installment_units::text,'maximum_installment_units',p.maximum_installment_units::text)
      FROM nse_reference.swp_products p WHERE s.file_type='SWP' AND p.snapshot_id=s.snapshot_id AND p.scheme_code=p_scheme_code AND p.source_line>p_after_line
    ORDER BY source_line LIMIT p_limit
  ) x;
  RETURN nse_reference.systematic_receipt(s.snapshot_id)||pg_catalog.jsonb_build_object('rows',rows,
    'scheme_namespace','NSE','eligibility','UNINTERPRETED','reason','PRODUCT_SEMANTICS_UNCOMMISSIONED');
END $$;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['systematic_validations','sip_products','stp_products','swp_products','systematic_publications'] LOOP
    EXECUTE format('ALTER TABLE nse_reference.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON TABLE nse_reference.%I FROM PUBLIC,anon,authenticated,service_role',t);
    EXECUTE format('CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON nse_reference.%I FOR EACH ROW EXECUTE FUNCTION nse_reference.immutable()',t);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION nse_reference.systematic_headers(text),nse_reference.systematic_text(text,integer),
  nse_reference.systematic_number(text,integer,integer),nse_reference.systematic_reserved(text,text),
  nse_reference.systematic_receipt(uuid),nse_reference.validate_systematic(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.validate_nse_systematic_snapshot(uuid,uuid),public.publish_nse_systematic_snapshot(uuid,uuid,uuid),
  public.get_nse_systematic_current(uuid,uuid,text),public.get_nse_systematic_products(uuid,uuid,text,integer,integer)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.validate_nse_systematic_snapshot(uuid,uuid),public.publish_nse_systematic_snapshot(uuid,uuid,uuid),
  public.get_nse_systematic_current(uuid,uuid,text),public.get_nse_systematic_products(uuid,uuid,text,integer,integer) TO service_role;
-- The shared worker stages only. Reference publication remains an explicit CAS RPC.
-- Catch only parser rejections, in a subtransaction that removes every partial row
-- and typed receipt. Integrity, ownership, audit and unexpected errors propagate.
CREATE FUNCTION nse_reference.systematic_runtime_validation(p_snapshot uuid,p_file_type text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s nse_reference.snapshots; receipt jsonb;
BEGIN
  SELECT * INTO s FROM nse_reference.snapshots WHERE id=p_snapshot AND file_type::text=p_file_type;
  IF s.id IS NULL OR p_file_type NOT IN ('SIP','STP','SWP') THEN
    RAISE EXCEPTION 'nse_systematic_variant_invalid'; END IF;
  BEGIN
    receipt:=nse_reference.validate_systematic(s.workspace_id,s.id);
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT IN ('nse_systematic_encoding_invalid','nse_systematic_framing_invalid',
      'nse_systematic_layout_unknown','nse_systematic_row_count_invalid','nse_systematic_row_invalid',
      'nse_systematic_column_count','nse_systematic_field_invalid','nse_systematic_number_invalid',
      'nse_systematic_reserved_field','nse_systematic_duplicate_row') THEN RAISE; END IF;
    RETURN pg_catalog.jsonb_build_object('status','REJECTED','category','nse_reference_systematic_layout_invalid',
      'row_count',0,'rejected_rows',0,'validation_scope','STRUCTURE_ONLY_REFERENCE_ONLY');
  END;
  RETURN pg_catalog.jsonb_build_object('status','STAGED_VALIDATED','category','nse_reference_systematic_layout_valid',
    'row_count',(receipt->>'row_count')::integer,'rejected_rows',0,'validation_scope','STRUCTURE_ONLY_REFERENCE_ONLY');
END $$;
CREATE FUNCTION nse_reference.validate_sip_v1(p_snapshot uuid) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT nse_reference.systematic_runtime_validation(p_snapshot,'SIP')
$$;
CREATE FUNCTION nse_reference.validate_stp_v1(p_snapshot uuid) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT nse_reference.systematic_runtime_validation(p_snapshot,'STP')
$$;
CREATE FUNCTION nse_reference.validate_swp_v1(p_snapshot uuid) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT nse_reference.systematic_runtime_validation(p_snapshot,'SWP')
$$;
INSERT INTO nse_reference.validators(file_type,parser_version,function_name) VALUES
  ('SIP','NSE_WEB_SIP_V1','validate_sip_v1'),
  ('STP','NSE_WEB_STP_V1','validate_stp_v1'),
  ('SWP','NSE_WEB_SWP_V1','validate_swp_v1');
REVOKE ALL ON FUNCTION nse_reference.systematic_runtime_validation(uuid,text),
  nse_reference.validate_sip_v1(uuid),nse_reference.validate_stp_v1(uuid),nse_reference.validate_swp_v1(uuid)
  FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
