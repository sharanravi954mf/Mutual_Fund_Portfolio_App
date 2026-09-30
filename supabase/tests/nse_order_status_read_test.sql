BEGIN;
DO $$
BEGIN
  IF NOT pg_catalog.has_function_privilege('service_role', 'public.prepare_nse_order_status(uuid, uuid, date, date, text, text, text, text, text, text[], text[])', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'public.prepare_nse_order_status(uuid, uuid, date, date, text, text, text, text, text, text[], text[])', 'EXECUTE') THEN RAISE EXCEPTION 'order_status_rpc_privileges_invalid'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid='public.nse_order_status_requests'::pg_catalog.regclass)
     OR (SELECT has_table_privilege('authenticated','public.nse_order_status_requests','SELECT')) THEN RAISE EXCEPTION 'order_status_private_storage_exposed'; END IF;
END $$;
ROLLBACK;
