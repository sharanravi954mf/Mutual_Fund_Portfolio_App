BEGIN;

ALTER TABLE public.cams_kfintech_ingestion_runs
  ADD COLUMN mailbox_outcome pg_catalog.text;

ALTER TABLE public.cams_kfintech_ingestion_runs
  ADD CONSTRAINT cams_kfintech_ingestion_runs_mailbox_outcome_check
  CHECK (
    mailbox_outcome IS NULL
    OR (
      mailbox_outcome = 'no_data'
      AND status = 'completed'
      AND attempted_attachment_count = 0
      AND successful_attachment_count = 0
      AND failed_attachment_count = 0
      AND duplicate_attachment_count = 0
      AND stopped_attachment_count = 0
      AND observed_attachment_count = 0
      AND durable_attempt_count = 0
      AND lineage_gap_count = 0
      AND stopped_reason IS NULL
      AND run_failure_code IS NULL
    )
  );

CREATE OR REPLACE FUNCTION public.finalize_cams_kfintech_no_data_run(
  p_workspace_id pg_catalog.uuid,
  p_mailbox_connection_id pg_catalog.uuid,
  p_ingestion_run_id pg_catalog.uuid,
  p_registrar pg_catalog.text
)
RETURNS TABLE (
  ingestion_run_id pg_catalog.uuid,
  status pg_catalog.text,
  attempted_attachment_count pg_catalog.int4,
  successful_attachment_count pg_catalog.int4,
  failed_attachment_count pg_catalog.int4,
  duplicate_attachment_count pg_catalog.int4,
  stopped_attachment_count pg_catalog.int4,
  observed_attachment_count pg_catalog.int4,
  durable_attempt_count pg_catalog.int4,
  lineage_gap_count pg_catalog.int4,
  stopped_reason pg_catalog.text,
  run_failure_code pg_catalog.text
) AS $$
DECLARE
  v_run public.cams_kfintech_ingestion_runs;
  v_attempt_count pg_catalog.int4;
BEGIN
  IF p_workspace_id IS NULL
     OR p_mailbox_connection_id IS NULL
     OR p_ingestion_run_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;
  IF p_registrar <> 'CAMS' THEN
    RAISE EXCEPTION 'unsupported_registrar';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_ingestion_run_id::pg_catalog.text, 0)
  );

  SELECT run.*
  INTO v_run
  FROM public.cams_kfintech_ingestion_runs AS run
  WHERE run.ingestion_run_id = p_ingestion_run_id
  FOR UPDATE;

  IF v_run.ingestion_run_id IS NULL THEN
    RAISE EXCEPTION 'correlation_conflict';
  END IF;
  IF v_run.workspace_id IS DISTINCT FROM p_workspace_id
     OR v_run.mailbox_connection_id IS DISTINCT FROM p_mailbox_connection_id
     OR v_run.registrar IS DISTINCT FROM p_registrar THEN
    RAISE EXCEPTION 'correlation_conflict';
  END IF;

  IF v_run.status <> 'claimed' THEN
    IF v_run.status = 'completed' AND v_run.mailbox_outcome = 'no_data' THEN
      RETURN QUERY SELECT
        v_run.ingestion_run_id,
        v_run.status,
        v_run.attempted_attachment_count,
        v_run.successful_attachment_count,
        v_run.failed_attachment_count,
        v_run.duplicate_attachment_count,
        v_run.stopped_attachment_count,
        v_run.observed_attachment_count,
        v_run.durable_attempt_count,
        v_run.lineage_gap_count,
        v_run.stopped_reason,
        v_run.run_failure_code;
      RETURN;
    END IF;
    RAISE EXCEPTION 'ingestion_run_finalized';
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_attempt_count
  FROM public.cams_kfintech_ingestion_attempts AS attempt
  WHERE attempt.ingestion_run_id = p_ingestion_run_id
    AND attempt.workspace_id = p_workspace_id
    AND attempt.mailbox_connection_id = p_mailbox_connection_id;

  IF COALESCE(v_attempt_count, 0) <> 0 THEN
    RAISE EXCEPTION 'processing_incomplete';
  END IF;

  UPDATE public.cams_kfintech_ingestion_runs AS run
  SET status = 'completed',
      completed_at = pg_catalog.now(),
      attempted_attachment_count = 0,
      successful_attachment_count = 0,
      failed_attachment_count = 0,
      duplicate_attachment_count = 0,
      stopped_attachment_count = 0,
      observed_attachment_count = 0,
      durable_attempt_count = 0,
      lineage_gap_count = 0,
      stopped_reason = NULL,
      run_failure_code = NULL,
      mailbox_outcome = 'no_data',
      updated_at = pg_catalog.now()
  WHERE run.ingestion_run_id = p_ingestion_run_id
  RETURNING run.* INTO v_run;

  RETURN QUERY SELECT
    v_run.ingestion_run_id,
    v_run.status,
    v_run.attempted_attachment_count,
    v_run.successful_attachment_count,
    v_run.failed_attachment_count,
    v_run.duplicate_attachment_count,
    v_run.stopped_attachment_count,
    v_run.observed_attachment_count,
    v_run.durable_attempt_count,
    v_run.lineage_gap_count,
    v_run.stopped_reason,
    v_run.run_failure_code;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.finalize_cams_kfintech_no_data_run(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.finalize_cams_kfintech_no_data_run(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text
) TO service_role;

COMMIT;
