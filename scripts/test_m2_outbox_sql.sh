#!/usr/bin/env bash
# Rebuild every migration in a new network-disabled database; never touches a running stack.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
container="moneybowl-m2-test-$$"
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
  printf 'Applying %s\n' "${migration##*/}"
  if [[ "$migration" == *m2_native_outbox_dispatcher.sql ]]; then
    # Capture the actual composed feed before M2, independent of M2's implementation.
    psql_local <<'SQL'
CREATE SCHEMA m2_baseline;
DO $$ BEGIN
 EXECUTE replace(pg_get_functiondef('public.list_dispatchable_outbox_events(text[],integer,integer)'::regprocedure),
   'public.list_dispatchable_outbox_events(', 'm2_baseline.original_feed(');
END $$;
REVOKE ALL ON SCHEMA m2_baseline FROM PUBLIC,anon,authenticated,service_role;
SQL
  fi
  psql_local < "$migration"
done
psql_local < "$repo_root/supabase/tests/fixtures/m2_feed_parity.sql"
for test in "$repo_root"/supabase/tests/generic_outbox_dispatcher_test.sql \
  "$repo_root"/supabase/tests/m2_native_outbox_dispatcher_test.sql \
  "$repo_root"/supabase/tests/m2a_commissioning_test.sql \
  "$repo_root"/supabase/tests/nse*_test.sql "$repo_root"/supabase/tests/onboarding_kyc_test.sql; do
  printf 'Testing %s\n' "${test##*/}"
  if [[ "$test" == *m2_native_outbox_dispatcher_test.sql ]]; then
    # pg_net is now installed: only its extension owner can replace the test transport.
    # The regression retains its explicit SET ROLE checks for actual API roles.
    docker exec -i "$container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < "$test"
  else
    psql_local < "$test"
  fi
done
bash "$repo_root/scripts/test_m2_outbox_concurrency.sh" "$container"
