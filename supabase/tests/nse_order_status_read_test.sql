-- Self-contained ORDER_STATUS regression fixture. It creates its own local
-- secret and identities and always leaves the database unchanged.
BEGIN;

SELECT 1 FROM vault.create_secret(repeat('o', 40), 'integration_payload_encryption_key_v1', 'synthetic ORDER_STATUS local test key');

DO $$
DECLARE
  v_profile uuid := gen_random_uuid(); v_workspace uuid := gen_random_uuid(); v_account uuid := gen_random_uuid();
  v_operation public.integration_operations; v_event public.event_outbox; v_claim record; v_source jsonb;
  v_call_id uuid := gen_random_uuid();
  v_request_text text := '{"client_code":"MBUAT0001","from_date":"2026-09-01","to_date":"2026-09-01","order_status":"ALL","transaction_type":"ALL"}';
  v_response_text text := '{"response_status":"S","report_data":[]}';
  v_headers jsonb := '{"content_type":"application/json","x_test":"order-status"}';
  v_recovery public.integration_operations; v_recovery_event public.event_outbox; v_recovery_claim record; v_attempt integer;
BEGIN
  INSERT INTO auth.users(id,aud,role,email) VALUES(v_profile,'authenticated','authenticated',v_profile::text||'@test.invalid');
  INSERT INTO public.profiles(id,email,role) VALUES(v_profile,v_profile::text||'@test.invalid','investor');
  INSERT INTO public.workspaces(id,name) VALUES(v_workspace,'ORDER STATUS regression');
  INSERT INTO public.workspace_memberships(workspace_id,profile_id,role,status) VALUES(v_workspace,v_profile,'owner','active');
  INSERT INTO public.integration_accounts(id,workspace_id,investor_profile_id,integration_key,integration_environment,state,external_account_id) VALUES(v_account,v_workspace,v_profile,'NSE_INVEST','UAT','REGISTERED','MBUAT0001');

  -- Identifier filters must fail before an operation or outbox row exists.
  BEGIN PERFORM public.prepare_nse_order_status(v_workspace,v_profile,'{"from_date":"2026-09-01","to_date":"2026-09-01","order_status":"ALL","transaction_type":"ALL","order_ids":["forbidden"]}'::jsonb); RAISE EXCEPTION 'order_identifier_rejection_missing'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'nse_order_status_identifiers_forbidden')=0 THEN RAISE; END IF; END;
  BEGIN PERFORM public.prepare_nse_order_status(v_workspace,v_profile,'{"from_date":"2026-09-01","to_date":"2026-09-01","order_status":"ALL","transaction_type":"ALL","member_unique_ids":["forbidden"]}'::jsonb); RAISE EXCEPTION 'member_identifier_rejection_missing'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'nse_order_status_identifiers_forbidden')=0 THEN RAISE; END IF; END;
  IF EXISTS (SELECT 1 FROM public.integration_operations WHERE workspace_id=v_workspace) THEN RAISE EXCEPTION 'identifier_rejection_created_operation'; END IF;

  SELECT * INTO v_operation FROM public.prepare_nse_order_status(v_workspace,v_profile,'{"from_date":"2026-09-01","to_date":"2026-09-01","order_status":"ALL","transaction_type":"ALL"}'::jsonb);
  IF v_operation.category<>'RECONCILIATION' OR v_operation.safety_class<>'READ_ONLY' OR v_operation.operation_type<>'ORDER_STATUS_REPORT' OR v_operation.api_key<>'ORDER_STATUS' OR v_operation.contract_version<>'NNF_1.9.7' OR v_operation.operation_purpose IS NOT NULL OR v_operation.reconciliation_target_operation_id IS NOT NULL OR v_operation.reconciliation_resolution_operation_id IS NOT NULL OR v_operation.state<>'QUEUED' THEN RAISE EXCEPTION 'order_status_identity_invalid'; END IF;
  v_source:=public.get_nse_order_status_source(v_operation.id);
  IF v_source->>'client_code'<>'MBUAT0001' THEN RAISE EXCEPTION 'order_status_client_code_not_derived'; END IF;

  -- Private evidence has RLS, no policies or API table grants, and service-only RPCs.
  IF NOT (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid='private.nse_order_status_requests'::regclass) OR NOT (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid='private.nse_order_status_observations'::regclass) OR EXISTS(SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname='private' AND tablename IN ('nse_order_status_requests','nse_order_status_observations')) OR has_table_privilege('anon','private.nse_order_status_requests','SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated','private.nse_order_status_requests','SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('service_role','private.nse_order_status_requests','SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon','private.nse_order_status_observations','SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated','private.nse_order_status_observations','SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('service_role','private.nse_order_status_observations','SELECT,INSERT,UPDATE,DELETE') OR has_function_privilege('authenticated','public.prepare_nse_order_status(uuid,uuid,jsonb)','EXECUTE') OR NOT has_function_privilege('service_role','public.prepare_nse_order_status(uuid,uuid,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'order_status_privilege_or_rls_invalid'; END IF;

  SELECT * INTO v_event FROM public.event_outbox WHERE entity_id=v_operation.id AND event_type='integration.nse.order_status_requested';
  SELECT * INTO v_claim FROM public.claim_nse_order_status_event(v_event.id,3,120);
  SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id;
  IF v_claim.claim_state<>'claimed' OR v_claim.attempt<>1 OR v_operation.state<>'QUEUED' THEN RAISE EXCEPTION 'claim_changed_queued_operation'; END IF;

  -- Exact REQUEST replay is harmless; changed payload for the same call fails.
  PERFORM public.start_nse_order_status(v_event.id,v_claim.claim_token,v_call_id,v_request_text,'application/json',v_headers,'2026-09-01T12:00:00Z');
  PERFORM public.start_nse_order_status(v_event.id,v_claim.claim_token,v_call_id,v_request_text,'application/json',v_headers,'2026-09-01T12:00:00Z');
  BEGIN PERFORM public.start_nse_order_status(v_event.id,v_claim.claim_token,v_call_id,v_request_text||' ','application/json',v_headers,'2026-09-01T12:00:00Z'); RAISE EXCEPTION 'request_replay_conflict_missing'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_request_idempotency_conflict')=0 THEN RAISE; END IF; END;
  IF (SELECT count(*) FROM private.nse_order_status_requests WHERE integration_operation_id=v_operation.id AND phase='REQUEST')<>1 OR (SELECT extensions.pgp_sym_decrypt(payload_ciphertext,public.integration_payload_encryption_key('integration_payload_encryption_key_v1')) FROM private.nse_order_status_requests WHERE call_id=v_call_id AND phase='REQUEST')<>v_request_text THEN RAISE EXCEPTION 'request_evidence_invalid'; END IF;

  PERFORM public.finish_nse_order_status(v_event.id,v_claim.claim_token,v_call_id,v_response_text,'application/json',v_headers,200,'2026-09-01T12:00:01Z',1,'S',0,0,'SUCCESS',NULL,false,false,3);
  -- Completed-event exact replay needs no live lease; a changed RESULT conflicts.
  PERFORM public.finish_nse_order_status(v_event.id,v_claim.claim_token,v_call_id,v_response_text,'application/json',v_headers,200,'2026-09-01T12:00:01Z',1,'S',0,0,'SUCCESS',NULL,false,false,3);
  BEGIN PERFORM public.finish_nse_order_status(v_event.id,v_claim.claim_token,v_call_id,'{"response_status":"S","report_data":[{}]}','application/json',v_headers,200,'2026-09-01T12:00:01Z',1,'S',1,0,'SUCCESS',NULL,false,false,3); RAISE EXCEPTION 'result_replay_conflict_missing'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'integration_result_idempotency_conflict')=0 THEN RAISE; END IF; END;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id=v_operation.id;
  IF v_operation.state<>'SUCCESS' OR (SELECT count(*) FROM private.nse_order_status_requests WHERE integration_operation_id=v_operation.id)<>2 OR (SELECT count(*) FROM private.nse_order_status_observations WHERE integration_operation_id=v_operation.id)<>1 OR (SELECT extensions.pgp_sym_decrypt(payload_ciphertext,public.integration_payload_encryption_key('integration_payload_encryption_key_v1')) FROM private.nse_order_status_requests WHERE call_id=v_call_id AND phase='RESULT')<>v_response_text THEN RAISE EXCEPTION 'result_evidence_or_observation_invalid'; END IF;

  -- Both evidence tables are append-only after lifecycle persistence.
  BEGIN UPDATE private.nse_order_status_requests SET content_type='text/plain' WHERE call_id=v_call_id; RAISE EXCEPTION 'request_update_allowed'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'nse_order_status_evidence_append_only')=0 THEN RAISE; END IF; END;
  BEGIN DELETE FROM private.nse_order_status_requests WHERE call_id=v_call_id; RAISE EXCEPTION 'request_delete_allowed'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'nse_order_status_evidence_append_only')=0 THEN RAISE; END IF; END;
  BEGIN UPDATE private.nse_order_status_observations SET observation_count=1 WHERE integration_operation_id=v_operation.id; RAISE EXCEPTION 'observation_update_allowed'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'nse_order_status_evidence_append_only')=0 THEN RAISE; END IF; END;
  BEGIN DELETE FROM private.nse_order_status_observations WHERE integration_operation_id=v_operation.id; RAISE EXCEPTION 'observation_delete_allowed'; EXCEPTION WHEN OTHERS THEN IF strpos(SQLERRM,'nse_order_status_evidence_append_only')=0 THEN RAISE; END IF; END;

  -- Three expired claims are bounded; the third recovery leaves no further claim.
  SELECT * INTO v_recovery FROM public.prepare_nse_order_status(v_workspace,v_profile,'{"from_date":"2026-09-02","to_date":"2026-09-02","order_status":"ALL","transaction_type":"ALL"}'::jsonb);
  SELECT * INTO v_recovery_event FROM public.event_outbox WHERE entity_id=v_recovery.id AND event_type='integration.nse.order_status_requested';
  FOR v_attempt IN 1..3 LOOP
    SELECT * INTO v_recovery_claim FROM public.claim_nse_order_status_event(v_recovery_event.id,3,120);
    IF v_recovery_claim.claim_state<>'claimed' OR v_recovery_claim.attempt<>v_attempt THEN RAISE EXCEPTION 'recovery_claim_attempt_invalid:%',v_attempt; END IF;
    UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=v_recovery_event.id;
    IF public.recover_expired_nse_order_status_events(3)<>1 THEN RAISE EXCEPTION 'recovery_count_invalid:%',v_attempt; END IF;
    SELECT * INTO v_recovery FROM public.integration_operations WHERE id=v_recovery.id;
    SELECT * INTO v_recovery_event FROM public.event_outbox WHERE id=v_recovery_event.id;
    IF v_recovery.state<>'SUBMISSION_FAILED' OR v_recovery.retry_allowed<>(v_attempt<3) OR v_recovery_event.status<>'failed' OR v_recovery_event.claim_token IS NOT NULL OR v_recovery_event.claim_expires_at IS NOT NULL THEN RAISE EXCEPTION 'recovery_state_invalid:%',v_attempt; END IF;
  END LOOP;
  SELECT * INTO v_recovery_claim FROM public.claim_nse_order_status_event(v_recovery_event.id,3,120);
  IF v_recovery_claim.claim_state<>'no_event' THEN RAISE EXCEPTION 'recovery_attempt_three_not_exhausted'; END IF;
END $$;

ROLLBACK;
