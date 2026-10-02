#!/usr/bin/env bash
# Runs after B06.1 concurrency in the same disposable, network-none test container.
set -euo pipefail
container=${1:?disposable test container required}
case "$container" in moneybowl-order-status-test-*) ;; *) exit 2 ;; esac
test "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container")" = none
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
for n in 1 2; do
 cat > "$test_dir/prepare$n.sql" <<'SQL'
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.prepare_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001','SCH','b0620000-0000-4000-8000-000000000001');
SELECT pg_sleep(0.3);
COMMIT;
SQL
done
race() {
 psql_local < "$test_dir/$1.sql" > "$test_dir/first.log" & first=$!
 psql_local < "$test_dir/$2.sql" > "$test_dir/second.log" & second=$!
 wait "$first"
 wait "$second"
}
race prepare1 prepare2
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM nse_reference.jobs)<>1 THEN RAISE EXCEPTION 'b062_duplicate_preparation'; END IF;
END $$;
SQL
event_id=$(psql_local -Atc 'SELECT event_id FROM nse_reference.jobs')
for n in 1 2; do
 cat > "$test_dir/claim$n.sql" <<SQL
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.claim_nse_master_download('$event_id','b0620000-0000-4000-8001-00000000000$n');
SELECT pg_sleep(0.3);
COMMIT;
SQL
done
race claim1 claim2
psql_local <<'SQL'
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','B06.2 disposable synthetic');
DO $$ DECLARE e public.event_outbox; fields text[]:=string_to_array(repeat('|',43),'|'); body text; BEGIN
 SELECT event.* INTO STRICT e FROM public.event_outbox event JOIN nse_reference.jobs j ON j.event_id=event.id;
 IF e.status<>'processing' OR e.retry_count<>1 THEN RAISE EXCEPTION 'b062_claim_not_exclusive'; END IF;
 fields[1]:='1';fields[2]:='CONCURRENT';fields[6]:='SYNTHETIC-AMC';fields[9]:='Synthetic Scheme';
 body:=nse_reference.sch_header_v1()||E'\n'||array_to_string(fields,'|')||E'\n';
 PERFORM public.begin_nse_master_job_capture(e.id,e.claim_token,gen_random_uuid(),'UAT','05418','https://nse.example.test');
 PERFORM public.append_nse_master_job_chunk(e.id,e.claim_token,0,replace(encode(convert_to(body,'UTF8'),'base64'),E'\n',''),encode(extensions.digest(body,'sha256'),'hex'));
 PERFORM public.finish_nse_master_job_capture(e.id,e.claim_token,'COMPLETE',200,'TEXT',octet_length(body),true,true,encode(extensions.digest(body,'sha256'),'hex'));
END $$;
SQL
token=$(psql_local -Atc "SELECT claim_token FROM public.event_outbox WHERE id='$event_id'")
for n in 1 2; do
 cat > "$test_dir/finalize$n.sql" <<SQL
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.finalize_nse_master_download('$event_id','$token');
SELECT pg_sleep(0.3);
COMMIT;
SQL
done
race finalize1 finalize2
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM nse_reference.completions WHERE outcome='STAGED_VALIDATED')<>1
  OR (SELECT count(*) FROM nse_reference.validations WHERE status='STAGED_VALIDATED')<>1
  OR (SELECT count(*) FROM nse_reference.sch_rows)<>1
  OR (SELECT count(*) FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.master_download_requested']))<>0 THEN
  RAISE EXCEPTION 'b062_concurrent_finalization_not_atomic'; END IF;
END $$;
DELETE FROM vault.secrets WHERE name='integration_payload_encryption_key_v1';
SQL
printf 'B06.2 concurrent prepare/claim/finalize: one job, claim, staged snapshot and receipt\n'
