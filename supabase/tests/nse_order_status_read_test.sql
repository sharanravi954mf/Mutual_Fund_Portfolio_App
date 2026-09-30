BEGIN;
DO $$
DECLARE v_policy_count pg_catalog.int4; v_public pg_catalog.bool;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4 INTO v_policy_count FROM pg_catalog.pg_policies WHERE schemaname = 'public' AND tablename IN ('nse_order_status_requests', 'nse_order_status_observations');
  IF v_policy_count <> 0 THEN RAISE EXCEPTION 'order_status_private_tables_must_have_no_rls_policy'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid = 'public.nse_order_status_requests'::pg_catalog.regclass) OR NOT (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid = 'public.nse_order_status_observations'::pg_catalog.regclass) THEN RAISE EXCEPTION 'order_status_private_storage_requires_rls'; END IF;
  SELECT pg_catalog.has_table_privilege('anon', 'public.nse_order_status_requests', 'SELECT') OR pg_catalog.has_table_privilege('authenticated', 'public.nse_order_status_requests', 'SELECT') INTO v_public;
  IF v_public THEN RAISE EXCEPTION 'order_status_storage_is_not_private'; END IF;
  IF pg_catalog.has_function_privilege('anon', 'public.prepare_nse_order_status(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.date, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text[], pg_catalog.text[])', 'EXECUTE') OR pg_catalog.has_function_privilege('authenticated', 'public.prepare_nse_order_status(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.date, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text[], pg_catalog.text[])', 'EXECUTE') OR NOT pg_catalog.has_function_privilege('service_role', 'public.prepare_nse_order_status(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.date, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text[], pg_catalog.text[])', 'EXECUTE') THEN RAISE EXCEPTION 'order_status_prepare_service_role_only'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid = 'public.nse_order_status_observations'::pg_catalog.regclass AND tgname = 'nse_order_status_observations_append_only' AND NOT tgisinternal) THEN RAISE EXCEPTION 'order_status_observations_must_be_append_only'; END IF;
  BEGIN
    PERFORM public.prepare_nse_order_status('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', '2026-09-01', '2026-09-07', 'ALL', 'ALL', 'ALL', NULL, NULL, ARRAY['canonical-order']::pg_catalog.text[], NULL);
    RAISE EXCEPTION 'order_status_ids_must_be_rejected_before_operation';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'order_status_id_scope_not_supported' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.prepare_nse_order_status('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', '2026-09-01', '2026-09-08', 'ALL', 'ALL', 'ALL');
    RAISE EXCEPTION 'order_status_date_constraint_missing';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'order_status_date_range_invalid' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.prepare_nse_order_status('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', '2026-09-01', '2026-09-07', 'BAD', 'ALL', 'ALL');
    RAISE EXCEPTION 'order_status_enum_constraint_missing';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'order_status_filter_invalid' THEN RAISE; END IF; END;
END $$;
ROLLBACK;

