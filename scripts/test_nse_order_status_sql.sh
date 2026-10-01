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
printf 'Existing generic dispatcher SQL regression\n'
psql_local < "$repo_root/supabase/tests/generic_outbox_dispatcher_test.sql"
printf 'Existing NSE UCC SQL regression\n'
psql_local < "$repo_root/supabase/tests/nse_ucc_vertical_slice_test.sql"
for pass in 1 2; do
  printf 'ORDER_STATUS regression pass %s (must rollback)\n' "$pass"
  psql_local < "$repo_root/supabase/tests/nse_order_status_vertical_slice_test.sql"
done
psql_local -c "DO \$\$ BEGIN
  IF EXISTS (SELECT 1 FROM public.integration_operations WHERE operation_type='ORDER_STATUS')
    OR EXISTS (SELECT 1 FROM public.nse_order_status_queries)
    OR EXISTS (SELECT 1 FROM public.nse_order_status_observations)
    OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'order-status-%@moneybowl.invalid')
    OR EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name='integration_payload_encryption_key_v1')
  THEN RAISE EXCEPTION 'order_status_test_did_not_rollback'; END IF;
END \$\$;"
