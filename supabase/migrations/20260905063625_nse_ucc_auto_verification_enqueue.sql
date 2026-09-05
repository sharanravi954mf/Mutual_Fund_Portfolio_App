-- Preserve the proven registration-result implementation as a private
-- service helper. The public RPC name below wraps it to enqueue the one
-- post-registration Client Master verification in the same transaction.
ALTER FUNCTION public.finish_nse_ucc_submission(
  pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text,
  pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.timestamptz,
  pg_catalog.int8, pg_catalog.text, pg_catalog.text, pg_catalog.text,
  pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.text,
  pg_catalog.text, pg_catalog.int4
) RENAME TO finish_nse_ucc_submission_base;

-- Enforce lifetime idempotency for post-registration verification even if a
-- future privileged code path bypasses prepare_nse_ucc_verification().
CREATE UNIQUE INDEX integration_operations_one_post_reg_verification_idx
  ON public.integration_operations (reconciliation_target_operation_id)
  WHERE operation_type = 'UCC_VERIFICATION'
    AND operation_purpose = 'POST_REGISTRATION_VERIFICATION';

-- A verification operation owns one outbox request event for its lifetime.
-- READ_ONLY retries reuse this row and advance its retry/claim state.
CREATE UNIQUE INDEX event_outbox_one_ucc_verification_requested_idx
  ON public.event_outbox (entity_type, entity_id, event_type)
  WHERE entity_type = 'integration_operation'
    AND event_type = 'integration.nse.ucc_verification_requested';

CREATE OR REPLACE FUNCTION public.prepare_nse_ucc_verification(
  p_target_operation_id pg_catalog.uuid,
  p_verification_purpose pg_catalog.text
)
RETURNS public.integration_operations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_target public.integration_operations;
  v_verification public.integration_operations;
BEGIN
  IF p_verification_purpose NOT IN (
    'POST_REGISTRATION_VERIFICATION', 'AMBIGUOUS_WRITE_RECONCILIATION'
  ) THEN
    RAISE EXCEPTION 'ucc_verification_purpose_invalid';
  END IF;

  -- This lock serializes preparation for the same registration target.
  SELECT * INTO v_target
  FROM public.integration_operations operation
  WHERE operation.id = p_target_operation_id
  FOR UPDATE;
  IF v_target.id IS NULL OR v_target.integration_key <> 'NSE_INVEST'
     OR v_target.integration_environment <> 'UAT'
     OR v_target.operation_type <> 'UCC_REGISTRATION'
     OR v_target.api_key <> 'CLIENTCOMMON183' THEN
    RAISE EXCEPTION 'ucc_verification_target_invalid';
  END IF;
  IF p_verification_purpose = 'POST_REGISTRATION_VERIFICATION'
     AND (v_target.state <> 'SUCCESS' OR v_target.reconciliation_required) THEN
    RAISE EXCEPTION 'ucc_post_registration_verification_target_invalid';
  END IF;
  IF p_verification_purpose = 'AMBIGUOUS_WRITE_RECONCILIATION'
     AND (v_target.state <> 'RECONCILIATION_REQUIRED' OR NOT v_target.reconciliation_required) THEN
    RAISE EXCEPTION 'ucc_reconciliation_target_invalid';
  END IF;

  SELECT * INTO v_verification
  FROM public.integration_operations verification
  WHERE verification.reconciliation_target_operation_id = v_target.id
    AND verification.operation_purpose = p_verification_purpose
    AND (
      p_verification_purpose = 'POST_REGISTRATION_VERIFICATION'
      OR verification.state IN ('PREPARED', 'QUEUED', 'SUBMITTING')
      OR (verification.state = 'SUBMISSION_FAILED' AND verification.retry_allowed)
    )
  ORDER BY verification.created_at, verification.id
  LIMIT 1
  FOR UPDATE;
  IF v_verification.id IS NOT NULL THEN
    IF v_verification.integration_key <> 'NSE_INVEST'
       OR v_verification.integration_environment <> 'UAT'
       OR v_verification.category <> 'RECONCILIATION'
       OR v_verification.safety_class <> 'READ_ONLY'
       OR v_verification.operation_type <> 'UCC_VERIFICATION'
       OR v_verification.api_key <> 'CLIENT_MASTER_REPORT' THEN
      RAISE EXCEPTION 'ucc_verification_existing_operation_invalid';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM public.event_outbox event
      WHERE event.entity_id = v_verification.id
        AND event.entity_type = 'integration_operation'
        AND event.event_type = 'integration.nse.ucc_verification_requested'
    ) THEN
      RAISE EXCEPTION 'ucc_verification_event_missing';
    END IF;
    RETURN v_verification;
  END IF;

  INSERT INTO public.integration_operations (
    workspace_id, integration_account_id, integration_key, integration_environment,
    category, safety_class, operation_type, operation_purpose, api_key, contract_version,
    state, reconciliation_target_operation_id
  ) VALUES (
    v_target.workspace_id, v_target.integration_account_id, 'NSE_INVEST', 'UAT',
    'RECONCILIATION', 'READ_ONLY', 'UCC_VERIFICATION', p_verification_purpose,
    'CLIENT_MASTER_REPORT', 'NNF_1.9.7', 'PREPARED', v_target.id
  ) RETURNING * INTO v_verification;
  UPDATE public.integration_operations
  SET state = 'QUEUED'
  WHERE id = v_verification.id
  RETURNING * INTO v_verification;
  INSERT INTO public.event_outbox (event_type, payload, status, entity_id, entity_type)
  VALUES (
    'integration.nse.ucc_verification_requested',
    pg_catalog.jsonb_build_object(
      'integration_operation_id', v_verification.id,
      'reconciliation_target_operation_id', v_target.id,
      'verification_purpose', p_verification_purpose,
      'integration_account_id', v_target.integration_account_id,
      'integration_key', 'NSE_INVEST'
    ),
    'pending', v_verification.id, 'integration_operation'
  );
  RETURN v_verification;
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_nse_ucc_submission(
  p_event_outbox_id pg_catalog.uuid,
  p_claim_token pg_catalog.uuid,
  p_call_id pg_catalog.uuid,
  p_response_payload pg_catalog.text,
  p_response_content_type pg_catalog.text,
  p_response_header_metadata pg_catalog.jsonb,
  p_http_status pg_catalog.int4,
  p_completed_at pg_catalog.timestamptz,
  p_elapsed_ms pg_catalog.int8,
  p_native_status_value pg_catalog.text,
  p_native_remark_category pg_catalog.text,
  p_normalized_outcome pg_catalog.text,
  p_error_category pg_catalog.text DEFAULT NULL,
  p_timeout_occurred pg_catalog.bool DEFAULT false,
  p_network_failure pg_catalog.bool DEFAULT false,
  p_external_account_id pg_catalog.text DEFAULT NULL,
  p_registration_reference pg_catalog.text DEFAULT NULL,
  p_max_attempts pg_catalog.int4 DEFAULT 2
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_result public.integration_api_interactions;
  v_operation public.integration_operations;
  v_account public.integration_accounts;
BEGIN
  SELECT * INTO v_result
  FROM public.finish_nse_ucc_submission_base(
    p_event_outbox_id, p_claim_token, p_call_id, p_response_payload,
    p_response_content_type, p_response_header_metadata, p_http_status,
    p_completed_at, p_elapsed_ms, p_native_status_value,
    p_native_remark_category, p_normalized_outcome, p_error_category,
    p_timeout_occurred, p_network_failure, p_external_account_id,
    p_registration_reference, p_max_attempts
  );

  IF v_result.normalized_outcome = 'SUCCESS'
     AND v_result.native_status_value = 'REG_SUCCESS'
     AND v_result.http_success THEN
    SELECT * INTO v_operation
    FROM public.integration_operations operation
    WHERE operation.id = v_result.integration_operation_id
    FOR UPDATE;
    SELECT * INTO v_account
    FROM public.integration_accounts account
    WHERE account.id = v_operation.integration_account_id;
    IF v_operation.integration_key = 'NSE_INVEST'
       AND v_operation.integration_environment = 'UAT'
       AND v_operation.operation_type = 'UCC_REGISTRATION'
       AND v_operation.api_key = 'CLIENTCOMMON183'
       AND v_operation.state = 'SUCCESS'
       AND NOT v_operation.ambiguous_outcome
       AND NOT v_operation.reconciliation_required
       AND v_account.state = 'REGISTERED'
       AND v_account.current_registration_status = 'REG_SUCCESS'
       AND NULLIF(pg_catalog.btrim(v_account.external_account_id), '') IS NOT NULL THEN
      PERFORM public.prepare_nse_ucc_verification(
        v_operation.id, 'POST_REGISTRATION_VERIFICATION'
      );
    ELSE
      RAISE EXCEPTION 'ucc_post_registration_verification_invariant_failed';
    END IF;
  END IF;
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.finish_nse_ucc_submission_base(
  pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text,
  pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.timestamptz,
  pg_catalog.int8, pg_catalog.text, pg_catalog.text, pg_catalog.text,
  pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.text,
  pg_catalog.text, pg_catalog.int4
) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.finish_nse_ucc_submission(
  pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text,
  pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.timestamptz,
  pg_catalog.int8, pg_catalog.text, pg_catalog.text, pg_catalog.text,
  pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.text,
  pg_catalog.text, pg_catalog.int4
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finish_nse_ucc_submission(
  pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text,
  pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.timestamptz,
  pg_catalog.int8, pg_catalog.text, pg_catalog.text, pg_catalog.text,
  pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.text,
  pg_catalog.text, pg_catalog.int4
) TO service_role;
