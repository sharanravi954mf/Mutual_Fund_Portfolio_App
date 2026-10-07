-- NSE UAT MASTER_DOWNLOAD transport characterization: 2026-10-07.
-- HTTP 200 text/plain with identity encoding was observed without Content-Length.
-- Permit bounded EOF completion while retaining the 16 MiB cap, exact digest,
-- identity-encoding requirement and malformed/compressed framing rejection.
BEGIN;

ALTER TABLE nse_reference.results DROP CONSTRAINT results_check1;
ALTER TABLE nse_reference.results ADD CONSTRAINT results_check1 CHECK (
  capture_kind<>'COMPLETE' OR (
    eof AND identity_encoding AND http_status IS NOT NULL
    AND (declared_bytes IS NULL OR declared_bytes=captured_bytes)
    AND response_sha256=captured_sha256
  )
);

CREATE OR REPLACE FUNCTION public.finish_nse_master_download(p_workspace_id uuid,p_download_id uuid,p_capture_kind text,
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
    (p_declared_bytes IS NOT NULL AND p_declared_bytes<>octet_length(b)) OR p_sha256 IS NULL OR p_sha256<>encode(h,'hex')) THEN
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

COMMIT;
