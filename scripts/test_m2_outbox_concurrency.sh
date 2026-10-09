#!/usr/bin/env bash
# Only called with the disposable database owned by test_m2_outbox_sql.sh.
set -euo pipefail
container=${1:?isolated container required}
[[ "$container" == moneybowl-m2-test-* ]] || exit 2
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
sql() { docker exec -i "$container" psql -X -At -U postgres -d postgres -v ON_ERROR_STOP=1; }
sql <<'SQL'
UPDATE moneybowl_dispatch.control SET environment='DEV',project_url='https://synthetic-dev.supabase.co',mode='observe';
SQL
sql > "$scratch/first" <<'SQL' &
BEGIN;
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','observe',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',NULL,ARRAY['integration.nse.ucc_registration_requested'])->>'code';
SELECT pg_sleep(2);
COMMIT;
SQL
first_pid=$!
for attempt in {1..50}; do
  if grep -qx admitted "$scratch/first"; then break; fi
  sleep 0.1
done
grep -qx admitted "$scratch/first"
sql > "$scratch/second" <<'SQL'
BEGIN;
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT public.admit_outbox_dispatch('DEV','https://synthetic-dev.supabase.co','observe',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',NULL,ARRAY['integration.nse.ucc_registration_requested'])->>'code';
COMMIT;
SQL
wait "$first_pid"
grep -qx busy "$scratch/second"
sql <<'SQL'
UPDATE moneybowl_dispatch.control SET mode='disabled',environment=NULL,project_url=NULL,batch_token=NULL,lease_until=NULL;
DELETE FROM moneybowl_dispatch.receipts WHERE request_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SQL
printf 'Concurrent duplicate/recovery admission: 1 admitted, 1 busy\n'
# Concurrent routine reconciliation must converge on one inactive job.
sql > "$scratch/schedule-first" <<'SQL' &
BEGIN;
SELECT moneybowl_dispatch.provision_recovery();
SELECT pg_sleep(1);
COMMIT;
SQL
schedule_pid=$!
sql > "$scratch/schedule-second" <<'SQL'
SELECT moneybowl_dispatch.provision_recovery();
SQL
wait "$schedule_pid"
sql <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM cron.job WHERE jobname='moneybowl-outbox-recovery')<>1
  OR EXISTS(SELECT 1 FROM cron.job WHERE jobname='moneybowl-outbox-recovery' AND active) THEN
  RAISE EXCEPTION 'concurrent_schedule_not_idempotent';
 END IF;
 IF (SELECT mode FROM moneybowl_dispatch.control WHERE singleton)<>'disabled' THEN
  RAISE EXCEPTION 'schedule_activated_dispatch';
 END IF;
END $$;
SQL
printf 'Concurrent recovery provisioning: one inactive job; dispatcher disabled\n'
