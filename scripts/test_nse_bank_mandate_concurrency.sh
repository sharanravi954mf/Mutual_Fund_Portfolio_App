#!/usr/bin/env bash
# Only a disposable, network-isolated database after rollback-only B07 tests.
set -euo pipefail
container=${1:?disposable test container required}
case "$container" in moneybowl-order-status-test-*) ;; *) exit 2 ;; esac
test "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container")" = none
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
# Reuse only the synthetic identity fixture, with a commit for parallel sessions.
python3 - "$repo_root" > "$test_dir/seed.sql" <<'PY'
from pathlib import Path
import sys
s=(Path(sys.argv[1])/'supabase/tests/nse_bank_mandate_test.sql').read_text()
print(s[:s.index('CREATE TEMP TABLE readiness_contracts')])
print('COMMIT;')
PY
psql_local < "$test_dir/seed.sql" > "$test_dir/seed.log"
psql_local > "$test_dir/bank.log" <<'SQL'
SELECT 1 FROM vault.create_secret(repeat('b',40),'bank_account_encryption_key_v1','synthetic');
SELECT 1 FROM vault.create_secret(repeat('h',40),'bank_account_lookup_hmac_key_v1','synthetic');
SELECT (public.set_investor_bank_account('e0030000-0000-4000-8000-000000000001',
 (SELECT id FROM public.profiles WHERE user_id='e0010000-0000-4000-8000-000000000001'),'savings','12345678902','SBIN0000018',NULL,NULL,'verified',false)).id;
SQL
bank=$(psql_local -Atc "SELECT id FROM public.investor_bank_accounts WHERE workspace_id='e0030000-0000-4000-8000-000000000001'")
cat > "$test_dir/review.sql" <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','e0010000-0000-4000-8000-000000000001',true);
SELECT public.request_nse_bank_mandate_review('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001','$bank','MANDATE','b0700000-0000-4000-8000-000000000001');
SELECT pg_sleep(0.3);
COMMIT;
SQL
race() {
 psql_local < "$test_dir/$1.sql" > "$test_dir/first.log" & first=$!
 psql_local < "$test_dir/$1.sql" > "$test_dir/second.log" & second=$!
 wait "$first"
 wait "$second"
}
race review
cat > "$test_dir/prepare.sql" <<'SQL'
BEGIN;
SET LOCAL ROLE service_role;
SELECT id FROM public.prepare_nse_mandate_status('e0030000-0000-4000-8000-000000000001','e0060000-0000-4000-8000-000000000001','MANDATE_STATUS','{"intent_id":"b0700000-0000-4000-8000-000000000001"}','b0700000-0000-4000-8001-000000000001');
SELECT pg_sleep(0.3);
COMMIT;
SQL
race prepare
event=$(psql_local -Atc "SELECT id FROM public.event_outbox WHERE entity_id='b0700000-0000-4000-8001-000000000001'")
cat > "$test_dir/claim.sql" <<SQL
BEGIN;
SET LOCAL ROLE service_role;
SELECT * FROM public.claim_nse_mandate_status_event('$event');
SELECT pg_sleep(0.3);
COMMIT;
SQL
race claim
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM nse_bank_mandate.intents)<>1 OR
    (SELECT count(*) FROM public.workspace_audit_logs WHERE action='nse.bank_mandate.review_requested')<>1 OR
    (SELECT count(*) FROM public.integration_operations WHERE operation_type='MANDATE_STATUS')<>1 OR
    (SELECT count(*) FROM public.event_outbox WHERE event_type='integration.nse.mandate_status_requested')<>1 OR
    NOT EXISTS(SELECT 1 FROM public.event_outbox WHERE entity_id='b0700000-0000-4000-8001-000000000001' AND status='processing' AND retry_count=1)
 THEN RAISE EXCEPTION 'b07_concurrency_failed'; END IF;
END $$;
SQL
printf 'B07 concurrent owner replay, read prepare and exclusive claim passed\n'
