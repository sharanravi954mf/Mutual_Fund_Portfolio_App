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
for test in mfd_application_approval_v1_test.sql platform_admin_authority_v1_test.sql fixtures/authorization_containment_history_after.sql authorization_containment_test.sql email_signup_identity_test.sql nse_frontend_integration_v1_test.sql issue_114_workspace_authorization_rpc_test.sql issue_114_gmail_oauth_provisioning_test.sql issue_30_order_requests_rls_test.sql issue_89_sell_switch_order_intent_test.sql issue_95_order_folio_projection_rpc_test.sql; do
  echo "Testing $test"
  psql_local < "$repo_root/supabase/tests/$test"
done
bash "$repo_root/scripts/test_email_signup_concurrency.sh" "$container"
bash "$repo_root/scripts/test_authorization_containment_concurrency.sh" "$container"
bash "$repo_root/scripts/test_platform_admin_authority_concurrency.sh" "$container"
bash "$repo_root/scripts/test_mfd_application_concurrency.sh" "$container"
python3 "$repo_root/scripts/test_platform_mfa_commissioning.py" "$container"
echo 'MFD application, platform authority and containment full-schema regressions: PASS'
