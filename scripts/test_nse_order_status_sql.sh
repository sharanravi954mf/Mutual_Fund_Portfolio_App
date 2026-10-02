#!/usr/bin/env bash
# Network-isolated, disposable current-schema regression; no hosted connections.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
container="moneybowl-order-status-test-$$"
image="public.ecr.aws/supabase/postgres:17.6.1.155"
cleanup() { docker rm --force "$container" >/dev/null; }
trap cleanup EXIT
docker run --detach --name "$container" --network none \
  --tmpfs /var/lib/postgresql/data:rw \
  -e POSTGRES_PASSWORD=local_disposable_only "$image" >/dev/null
for attempt in {1..60}; do
  if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
docker exec -i "$container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < "$repo_root/supabase/tests/fixtures/nse_local_platform.sql"
for migration in "$repo_root"/supabase/migrations/*.sql; do
  printf 'Applying %s\n' "${migration##*/}"
  psql_local < "$migration"
done
printf 'NSE application facade and reference foundation PL/pgSQL lint\n'
psql_local <<'SQL'
BEGIN;
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
DO $$ DECLARE fn record; finding record; BEGIN
  FOR fn IN SELECT p.oid, p.prorettype FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_catalog.pg_language l ON l.oid=p.prolang
    WHERE l.lanname='plpgsql' AND (n.nspname IN ('nse_app','nse_reference','nse_nav','nse_set') OR
      (n.nspname='public' AND p.proname IN ('list_nse_read_targets_v1','get_nse_read_context_v1',
        'list_nse_settlement_candidates_v1','submit_nse_read_v1','list_nse_read_operations_v1','get_nse_read_operation_v1',
        'begin_nse_master_download','append_nse_master_chunk','finish_nse_master_download','read_nse_master_chunk','stage_nse_reference_snapshot','get_nse_reference_snapshot','prepare_nse_master_download','claim_nse_master_download','begin_nse_master_job_capture','append_nse_master_job_chunk','finish_nse_master_job_capture','finalize_nse_master_download','get_nse_master_download_job','validate_nse_systematic_snapshot','publish_nse_systematic_snapshot','get_nse_systematic_current','get_nse_systematic_products',
        'validate_nse_nav_snapshot','read_nse_nav_observations','assess_nse_set_snapshot')))
  LOOP
    FOR finding IN SELECT * FROM extensions.plpgsql_check_function_tb(fn.oid::regprocedure,
      CASE WHEN fn.prorettype<>'trigger'::regtype THEN 0::regclass
        WHEN fn.oid::regprocedure::text LIKE 'nse_reference.guard_job_event%' THEN 'public.event_outbox'::regclass
        WHEN fn.oid::regprocedure::text LIKE 'nse_reference.guard_job_download%' THEN 'nse_reference.downloads'::regclass
        WHEN fn.oid::regprocedure::text LIKE 'nse_nav.%' THEN 'nse_nav.validations'::regclass
        WHEN fn.oid::regprocedure::text LIKE 'nse_reference.audit_evidence%' THEN 'nse_reference.downloads'::regclass
        WHEN fn.oid::regprocedure::text LIKE 'nse_reference.%' THEN 'nse_reference.connections'::regclass
        ELSE 'nse_app.dev_access'::regclass END,
      fatal_errors := false)
    LOOP
      IF finding.level='error' THEN
        RAISE EXCEPTION 'facade_lint_failed:%:%',fn.oid::regprocedure,finding.message;
      END IF;
      RAISE NOTICE 'facade_lint:%:%:line %:%',fn.oid::regprocedure,finding.level,finding.lineno,finding.message;
    END LOOP;
  END LOOP;
END $$;
ROLLBACK;
SQL
printf 'Existing generic dispatcher SQL regression\n'
psql_local < "$repo_root/supabase/tests/generic_outbox_dispatcher_test.sql"
printf 'Existing NSE UCC SQL regression\n'
psql_local < "$repo_root/supabase/tests/nse_ucc_vertical_slice_test.sql"
for pass in 1 2; do
  printf 'ORDER_STATUS regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_order_status_vertical_slice_test.sql"
  printf 'PROV_ORDERS regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_prov_orders_vertical_slice_test.sql"
  printf 'B01 readiness regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_client_readiness_vertical_slice_test.sql"
  printf 'B02 order/funding regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_order_funding_vertical_slice_test.sql"
  printf 'B03 settlement/redemption regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_settlement_redemption_vertical_slice_test.sql"
  printf 'B04 SIP/XSIP regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_sip_xsip_reports_vertical_slice_test.sql"
  printf 'B05 STP/SWP/AMC regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_stp_swp_reports_vertical_slice_test.sql"
  psql_local < "$repo_root/supabase/tests/nse_response_diagnostics_test.sql"
  printf 'B06.1 reference foundation regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_master_reference_foundation_test.sql"
  printf 'B06.2 SCH regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_master_sch_test.sql"
  printf 'B06.3 systematic reference/runtime regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_systematic_product_masters_test.sql"
  printf 'B06.4 NAV/SET regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_nav_set_test.sql"
  printf 'NSE frontend application facade regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_frontend_integration_v1_test.sql"
done
psql_local -c "DO \$\$ BEGIN
  IF EXISTS (SELECT 1 FROM public.integration_operations WHERE operation_type IN ('ORDER_STATUS','PROV_ORDERS','CLIENT_READINESS','ORDER_FUNDING','SETTLEMENT_REDEMPTION','SIP_XSIP_REPORTS','STP_SWP_REPORTS'))
    OR EXISTS (SELECT 1 FROM public.event_outbox WHERE event_type IN ('integration.nse.prov_orders_requested','integration.nse.client_readiness_requested','integration.nse.order_funding_requested','integration.nse.settlement_redemption_requested','integration.nse.sip_xsip_reports_requested','integration.nse.stp_swp_reports_requested'))
    OR EXISTS (SELECT 1 FROM public.nse_order_status_queries)
    OR EXISTS (SELECT 1 FROM public.nse_order_status_observations)
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'order-status-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'prov-orders-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'client-readiness-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'order-funding-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'settlement-redemption-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgname LIKE 'b03_no_%' OR tgname LIKE 'b04_no_%' OR tgname LIKE 'b05_no_%' OR tgname LIKE 'b061_no_%')
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'sip-xsip-reports-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'stp-swp-reports-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM nse_nav.validations)
    OR EXISTS (SELECT 1 FROM nse_nav.observations)
    OR EXISTS (SELECT 1 FROM nse_set.assessments)
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'b064-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgname LIKE 'b064_no_%')
    OR EXISTS (SELECT 1 FROM nse_reference.connections)
    OR EXISTS (SELECT 1 FROM nse_reference.downloads)
    OR EXISTS (SELECT 1 FROM nse_reference.snapshots)
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'b061-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM nse_app.submission_receipts)
    OR EXISTS (SELECT 1 FROM nse_app.dev_access)
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'nse-app-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name='integration_payload_encryption_key_v1')
  THEN RAISE EXCEPTION 'order_status_test_did_not_rollback'; END IF;
END \$\$;"
bash "$repo_root/scripts/test_nse_reference_concurrency.sh" "$container"
bash "$repo_root/scripts/test_nse_master_concurrency.sh" "$container"
bash "$repo_root/scripts/test_nse_nav_set_concurrency.sh" "$container"
bash "$repo_root/scripts/test_nse_frontend_concurrency.sh" "$container"
