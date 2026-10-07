#!/usr/bin/env bash
# Full composed migrations in a disposable PostgreSQL container with no network.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
container="moneybowl-authz-regression-platform-mfd-$$"
trap 'docker rm --force "$container" >/dev/null' EXIT
docker run --detach --name "$container" --network none --tmpfs /var/lib/postgresql/data:rw \
  -e POSTGRES_PASSWORD=local_disposable_only public.ecr.aws/supabase/postgres:17.6.1.155 >/dev/null
for attempt in {1..60}; do
  if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
docker exec -i "$container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < "$repo_root/supabase/tests/fixtures/nse_local_platform.sql"
for migration in "$repo_root"/supabase/migrations/*.sql; do
  if [[ "${migration##*/}" == 20261003233928_authorization_workspace_containment.sql ]]; then
    psql_local < "$repo_root/supabase/tests/fixtures/authorization_containment_history_before.sql"
  fi
  echo "Applying ${migration##*/}"
  psql_local < "$migration"
done
for test in onboarding_kyc_test.sql nse_order_status_vertical_slice_test.sql nse_prov_orders_vertical_slice_test.sql nse_order_funding_vertical_slice_test.sql nse_settlement_redemption_vertical_slice_test.sql nse_sip_xsip_reports_vertical_slice_test.sql nse_stp_swp_reports_vertical_slice_test.sql nse_response_diagnostics_test.sql nse_master_reference_foundation_test.sql nse_master_sch_test.sql nse_systematic_product_masters_test.sql nse_nav_set_test.sql nse_nav_set_runtime_test.sql generic_outbox_dispatcher_test.sql mfd_led_investor_onboarding_test.sql nse_ucc_vertical_slice_test.sql nse_client_readiness_vertical_slice_test.sql nse_bank_mandate_test.sql nse_bank_mandate_write_test.sql mfd_application_approval_v1_test.sql platform_admin_authority_v1_test.sql fixtures/authorization_containment_history_after.sql authorization_containment_test.sql email_signup_identity_test.sql nse_frontend_integration_v1_test.sql issue_114_workspace_authorization_rpc_test.sql issue_114_gmail_oauth_provisioning_test.sql issue_30_order_requests_rls_test.sql issue_89_sell_switch_order_intent_test.sql issue_95_order_folio_projection_rpc_test.sql; do
  echo "Testing $test"
  psql_local < "$repo_root/supabase/tests/$test"
done
psql_local <<'SQL'
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
DO $$ DECLARE fn record; finding record; BEGIN
 FOR fn IN SELECT p.oid,p.prorettype,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 JOIN pg_language l ON l.oid=p.prolang WHERE l.lanname='plpgsql' AND (n.nspname='moneybowl_onboarding' OR
 (n.nspname='public' AND (p.proname LIKE '%onboarding%' OR p.proname IN ('bootstrap_identity','prepare_onboarded_investor_ucc')))) LOOP
 FOR finding IN SELECT * FROM extensions.plpgsql_check_function_tb(fn.oid::regprocedure,
 CASE WHEN fn.prorettype='trigger'::regtype THEN (SELECT tgrelid FROM pg_trigger WHERE tgfoid=fn.oid LIMIT 1) ELSE 0::oid END,fatal_errors:=false) LOOP
 IF finding.level='error' THEN RAISE EXCEPTION 'onboarding_lint:%:%',fn.proname,finding.message; END IF;
 RAISE NOTICE 'onboarding_lint:%:%:line %:%',fn.proname,finding.level,finding.lineno,finding.message||coalesce(' detail: '||finding.detail,'')||coalesce(' hint: '||finding.hint,'');
 END LOOP; END LOOP;
END $$;
SQL
bash "$repo_root/scripts/test_email_signup_concurrency.sh" "$container"
bash "$repo_root/scripts/test_authorization_containment_concurrency.sh" "$container"
bash "$repo_root/scripts/test_platform_admin_authority_concurrency.sh" "$container"
bash "$repo_root/scripts/test_mfd_application_concurrency.sh" "$container"
python3 "$repo_root/scripts/test_platform_mfa_commissioning.py" "$container"
bash "$repo_root/scripts/test_investor_onboarding_concurrency.sh" "$container"
bash "$repo_root/scripts/test_onboarding_kyc_concurrency.sh" "$container"
echo 'Investor onboarding, NSE, MFD, platform authority and containment full-schema regressions: PASS'
