#!/usr/bin/env bash
# Called only by the disposable network-none NSE SQL harness, after rollback tests.
set -euo pipefail
container=${1:?disposable test container required}
case "$container" in moneybowl-order-status-test-*) ;; *) exit 2 ;; esac
test "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container")" = none
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
python3 - "$repo_root/supabase/tests/nse_frontend_integration_v1_test.sql" > "$test_dir/fixture.sql" <<'PY'
import sys
print(open(sys.argv[1]).read().split('-- Catalog assertions')[0])
print("INSERT INTO nse_app.dev_access VALUES('aa020000-0000-4000-8000-000000000001','UAT',true,repeat('a',40),now()); COMMIT;")
PY
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_dir/fixture.sql" > "$test_dir/fixture.log"
cat > "$test_dir/submit.sql" <<'SQL'
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aa010000-0000-4000-8000-000000000002',true);
SELECT public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004','aa060000-0000-4000-8000-000000000099',
 '{"kind":"read_order_status","options":{"from":"2026-10-01","to":"2026-10-02"}}');
SELECT pg_sleep(0.5);
COMMIT;
SQL
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_dir/submit.sql" > "$test_dir/first.log" &
first=$!
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_dir/submit.sql" > "$test_dir/second.log" &
second=$!
wait "$first"
wait "$second"
python3 - "$test_dir/first.log" "$test_dir/second.log" <<'PY'
import json,sys
results=[]
for name in sys.argv[1:]:
    for line in open(name):
        if line.strip().startswith('{'):
            results.append(json.loads(line)['data'])
assert len(results)==2
assert {r['acceptance'] for r in results}=={'ACCEPTED','REPLAYED'}
assert results[0]['operation_id']==results[1]['operation_id']
PY
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM nse_app.submission_receipts)<>1
 OR (SELECT count(*) FROM public.integration_operations WHERE workspace_id='aa020000-0000-4000-8000-000000000001')<>1
 OR (SELECT count(*) FROM public.event_outbox e JOIN nse_app.submission_receipts r ON r.operation_id=e.entity_id)<>1
 OR (SELECT count(*) FROM public.workspace_audit_logs WHERE event_type='nse.read_accepted')<>1
 THEN RAISE EXCEPTION 'concurrent_submission_duplicated'; END IF;
END $$;
SQL
printf 'NSE frontend concurrent replay: one operation, event, receipt and audit\n'
