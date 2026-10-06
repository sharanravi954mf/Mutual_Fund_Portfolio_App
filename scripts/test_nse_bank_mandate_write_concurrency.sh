#!/usr/bin/env bash
# Only synthetic records in the existing network-isolated disposable database.
set -euo pipefail
container=${1:?disposable test container required}
case "$container" in moneybowl-order-status-test-*) ;; *) exit 2 ;; esac
test "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container")" = none
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
python3 - "$repo_root" > "$test_dir/seed.sql" <<'PY'
from pathlib import Path
import sys
import re
s=(Path(sys.argv[1])/'supabase/tests/nse_bank_mandate_write_test.sql').read_text()
s=s[:s.index('CREATE FUNCTION pg_temp.begin_write')]
s=s.replace('e0010000','da010000').replace('e0030000','da030000').replace('e0040000','da040000').replace('e0060000','da060000').replace('b0710000','da710000')
s=s.replace('client-readiness-','b07-write-concurrency-').replace('SYNTHETIC','RACETEST')
s=re.sub(r"^SELECT 1 FROM vault.create_secret[^\n]+\n",'',s,flags=re.M)
s=s.replace('NOT EXISTS(SELECT 1 FROM public.integration_operations)',"NOT EXISTS(SELECT 1 FROM public.integration_operations WHERE integration_account_id='da060000-0000-4000-8000-000000000001')")
print(s)
print('COMMIT;')
PY
psql_local < "$test_dir/seed.sql" > "$test_dir/seed.log"
cat > "$test_dir/prepare.sql" <<'SQL'
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.prepare_nse_bank_mandate_write('da710000-0000-4000-8000-000000000001');
SELECT pg_sleep(0.3);
COMMIT;
SQL
race() {
 psql_local < "$test_dir/$1.sql" > "$test_dir/first.log" & first=$!
 psql_local < "$test_dir/$1.sql" > "$test_dir/second.log" & second=$!
 wait "$first"
 wait "$second"
}
race prepare
event=$(psql_local -Atc "SELECT id FROM public.event_outbox WHERE entity_id='da710000-0000-4000-8000-000000000001'")
cat > "$test_dir/claim.sql" <<SQL
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.claim_nse_bank_mandate_write('$event');
SELECT pg_sleep(0.3);
COMMIT;
SQL
race claim
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM public.event_outbox WHERE entity_id='da710000-0000-4000-8000-000000000001')<>1
 OR NOT EXISTS(SELECT 1 FROM public.event_outbox WHERE entity_id='da710000-0000-4000-8000-000000000001' AND status='processing' AND retry_count=1)
 THEN RAISE EXCEPTION 'b07_write_concurrency_failed'; END IF;
END $$;
SQL
printf 'B07 approved write concurrent prepare/claim: one operation, event and exclusive claim\n'
