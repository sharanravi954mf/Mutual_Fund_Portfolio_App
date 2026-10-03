BEGIN;
-- NSE-T002 correction 003 regression: synthetic, self-contained and rolled back.
-- The fixture uses an already-registered synthetic NSE account supplied by the
-- test harness; this file deliberately contains no hosted or NSE interaction.
DO $$
DECLARE
  v_account public.integration_accounts; v_operation public.integration_operations;
  v_event public.event_outbox; v_claim record; v_request public.integration_api_interactions;
  v_result public.integration_api_interactions; v_headers pg_catalog.jsonb := '{"content_type":"application/json","accept":"application/json","user_agent":"MoneyBowl-Test"}';
  v_result_headers pg_catalog.jsonb := '{"content_type":"application/json"}';
  v_call pg_catalog.uuid := pg_catalog.gen_random_uuid();
BEGIN
  SELECT * INTO v_account FROM public.integration_accounts
  WHERE integration_key='NSE_INVEST' AND integration_environment='UAT' AND state='REGISTERED'
    AND external_account_id IS NOT NULL LIMIT 1;
  IF v_account.id IS NULL THEN RAISE EXCEPTION 'nse_order_status_synthetic_account_missing'; END IF;
  BEGIN
    PERFORM public.prepare_nse_order_status_read(v_account.id,'2026-09-01','2026-09-01','[]'::pg_catalog.jsonb,NULL);
    RAISE EXCEPTION 'order_id_filter_created_operation';
  EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'nse_order_status_read_filter_invalid')=0 THEN RAISE; END IF; END;
  SELECT * INTO v_operation FROM public.prepare_nse_order_status_read(v_account.id,'2026-09-01','2026-09-07',NULL,NULL);
  IF v_operation.category <> 'RECONCILIATION' OR v_operation.safety_class <> 'READ_ONLY' OR v_operation.operation_type <> 'ORDER_STATUS_REPORT' OR v_operation.api_key <> 'ORDER_STATUS' OR v_operation.contract_version <> 'NNF_1.9.7' OR v_operation.operation_purpose IS NOT NULL OR v_operation.reconciliation_target_operation_id IS NOT NULL OR v_operation.reconciliation_resolution_operation_id IS NOT NULL THEN RAISE EXCEPTION 'order_status_identity_invalid'; END IF;
  SELECT * INTO v_event FROM public.event_outbox WHERE entity_id=v_operation.id AND event_type='integration.nse.order_status_requested';
  SELECT * INTO v_claim FROM public.claim_nse_order_status_event(v_event.id,3,120);
  SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id;
  IF v_operation.state <> 'QUEUED' THEN RAISE EXCEPTION 'claim_changed_operation_state'; END IF;
  SELECT * INTO v_request FROM public.start_nse_order_status_read(v_event.id,v_claim.claim_token,v_call,pg_catalog.jsonb_build_object('client_code',v_account.external_account_id,'from_date','2026-09-01','to_date','2026-09-07')::pg_catalog.text,v_headers,'2026-09-07T00:00:00Z');
  IF (SELECT state FROM public.integration_operations WHERE id=v_operation.id) <> 'SUBMITTING' THEN RAISE EXCEPTION 'request_did_not_submit'; END IF;
  IF (public.start_nse_order_status_read(v_event.id,v_claim.claim_token,v_call,pg_catalog.jsonb_build_object('client_code',v_account.external_account_id,'from_date','2026-09-01','to_date','2026-09-07')::pg_catalog.text,v_headers,'2026-09-07T00:00:00Z')).id <> v_request.id THEN RAISE EXCEPTION 'request_replay_not_stable'; END IF;
  BEGIN PERFORM public.start_nse_order_status_read(v_event.id,v_claim.claim_token,v_call,'{}',v_headers,'2026-09-07T00:00:00Z'); RAISE EXCEPTION 'request_conflict_allowed'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_request_idempotency_conflict')=0 THEN RAISE; END IF; END;
  SELECT * INTO v_result FROM public.finish_nse_order_status_read(v_event.id,v_claim.claim_token,v_call,'{"response_status":"S"}','application/json',v_result_headers,200,'S','synthetic','SUCCESS',NULL,false,false,'2026-09-07T00:00:01Z',1);
  IF (SELECT state FROM public.integration_operations WHERE id=v_operation.id) <> 'SUCCESS' OR (SELECT count(*) FROM public.integration_api_interactions WHERE integration_operation_id=v_operation.id) <> 2 THEN RAISE EXCEPTION 'result_not_finalized'; END IF;
  IF (public.finish_nse_order_status_read(v_event.id,v_claim.claim_token,v_call,'{"response_status":"S"}','application/json',v_result_headers,200,'S','synthetic','SUCCESS',NULL,false,false,'2026-09-07T00:00:01Z',1)).id <> v_result.id OR (SELECT count(*) FROM public.integration_api_interactions WHERE integration_operation_id=v_operation.id) <> 2 THEN RAISE EXCEPTION 'result_replay_duplicated'; END IF;
  BEGIN PERFORM public.finish_nse_order_status_read(v_event.id,v_claim.claim_token,v_call,'{}','application/json',v_result_headers,200,'S','synthetic','SUCCESS',NULL,false,false,'2026-09-07T00:00:01Z',1); RAISE EXCEPTION 'result_conflict_allowed'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_result_idempotency_conflict')=0 THEN RAISE; END IF; END;
  IF pg_catalog.has_function_privilege('authenticated','public.prepare_nse_order_status_read(pg_catalog.uuid,pg_catalog.date,pg_catalog.date,pg_catalog.jsonb,pg_catalog.jsonb)','EXECUTE') OR pg_catalog.has_function_privilege('anon','public.start_nse_order_status_read(pg_catalog.uuid,pg_catalog.uuid,pg_catalog.uuid,pg_catalog.text,pg_catalog.jsonb,pg_catalog.timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'order_status_privilege_broadened'; END IF;
  BEGIN UPDATE public.integration_api_interactions SET created_at=pg_catalog.now() WHERE id=v_request.id; RAISE EXCEPTION 'order_status_evidence_mutable'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_api_interactions_append_only')=0 THEN RAISE; END IF; END;
END $$;
DO $$
DECLARE
  v_account public.integration_accounts; v_operation public.integration_operations;
  v_event public.event_outbox; v_claim record;
BEGIN
  SELECT * INTO v_account FROM public.integration_accounts
  WHERE integration_key='NSE_INVEST' AND integration_environment='UAT' AND state='REGISTERED'
    AND external_account_id IS NOT NULL LIMIT 1;
  SELECT * INTO v_operation FROM public.prepare_nse_order_status_read(v_account.id,'2026-09-08','2026-09-08',NULL,NULL);
  SELECT * INTO v_event FROM public.event_outbox WHERE entity_id=v_operation.id AND event_type='integration.nse.order_status_requested';
  SELECT * INTO v_claim FROM public.claim_nse_order_status_event(v_event.id,3,120);
  UPDATE public.event_outbox SET claim_expires_at=pg_catalog.now()-interval '1 second' WHERE id=v_event.id;
  IF public.recover_expired_nse_order_status_event(v_event.id) <> 'safe_read_retry_available' THEN RAISE EXCEPTION 'expired_claim_retry_missing'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id;
  IF v_operation.state <> 'SUBMISSION_FAILED' OR NOT v_operation.retry_allowed THEN RAISE EXCEPTION 'expired_claim_state_invalid'; END IF;
  SELECT * INTO v_claim FROM public.claim_nse_order_status_event(v_event.id,3,120);
  UPDATE public.event_outbox SET claim_expires_at=pg_catalog.now()-interval '1 second' WHERE id=v_event.id;
  PERFORM public.recover_expired_nse_order_status_event(v_event.id);
  SELECT * INTO v_claim FROM public.claim_nse_order_status_event(v_event.id,3,120);
  UPDATE public.event_outbox SET claim_expires_at=pg_catalog.now()-interval '1 second' WHERE id=v_event.id;
  IF public.recover_expired_nse_order_status_event(v_event.id) <> 'read_attempts_exhausted' THEN RAISE EXCEPTION 'expired_claim_exhaustion_missing'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id;
  IF v_operation.state <> 'SUBMISSION_FAILED' OR v_operation.retry_allowed OR (SELECT claim_token FROM public.event_outbox WHERE id=v_event.id) IS NOT NULL THEN RAISE EXCEPTION 'expired_claim_stranded'; END IF;
END $$;
ROLLBACK;
