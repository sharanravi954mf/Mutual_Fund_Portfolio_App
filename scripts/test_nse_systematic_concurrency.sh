#!/usr/bin/env bash
# Only a network-isolated disposable container created by the B06.3 test runner.
set -euo pipefail
container=${1:?disposable test container required}
case "$container" in moneybowl-systematic-test-*) ;; *) exit 2 ;; esac
test "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container")" = none
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
python3 - "$repo_root/supabase/tests/nse_systematic_product_masters_test.sql" > "$test_dir/setup.sql" <<'PY'
import sys
print(open(sys.argv[1]).read().split('-- FIXTURE_END')[0])
print("CREATE TABLE public.b063_race_targets(label text PRIMARY KEY,snapshot_id uuid);")
for label in ['a','b','c']:
    print("INSERT INTO public.b063_race_targets VALUES('%s',pg_temp.snapshot('SIP',pg_temp.file('SIP')));" % label)
print("CREATE TABLE public.b063_runtime_bodies AS SELECT kind,pg_temp.file(kind) AS body FROM unnest(ARRAY['SIP','STP','SWP']) kind;")
print('COMMIT;')
PY
psql_local < "$test_dir/setup.sql" > "$test_dir/setup.log"
a=$(psql_local -Atqc "SELECT snapshot_id FROM public.b063_race_targets WHERE label='a'")
b=$(psql_local -Atqc "SELECT snapshot_id FROM public.b063_race_targets WHERE label='b'")
c=$(psql_local -Atqc "SELECT snapshot_id FROM public.b063_race_targets WHERE label='c'")
run_publish() {
  psql_local <<SQL
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.publish_nse_systematic_snapshot('b0630000-0000-4000-8001-000000000001','$1',$2);
SELECT pg_sleep(0.5);
COMMIT;
SQL
}
run_publish "$a" NULL > "$test_dir/a.log" 2>&1 &
first=$!
run_publish "$b" NULL > "$test_dir/b.log" 2>&1 &
second=$!
first_status=0; wait "$first" || first_status=$?
second_status=0; wait "$second" || second_status=$?
if [[ "$first_status" == 0 && "$second_status" != 0 ]]; then
  grep -q 'nse_systematic_publication_conflict' "$test_dir/b.log"
elif [[ "$second_status" == 0 && "$first_status" != 0 ]]; then
  grep -q 'nse_systematic_publication_conflict' "$test_dir/a.log"
else
  cat "$test_dir/a.log" "$test_dir/b.log"
  exit 1
fi
current=$(psql_local -Atqc 'SELECT snapshot_id FROM nse_reference.systematic_publications')
# Two acknowledgements for the same frozen CAS request must produce one publication.
run_publish "$c" "'$current'" > "$test_dir/c1.log" 2>&1 &
first=$!
run_publish "$c" "'$current'" > "$test_dir/c2.log" 2>&1 &
second=$!
wait "$first"
wait "$second"
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM nse_reference.systematic_publications)<>2
 OR (SELECT count(*) FROM nse_reference.systematic_validations)<>2
 OR (SELECT count(*) FROM nse_reference.sip_products)<>2
 OR (SELECT count(*) FROM public.workspace_audit_logs WHERE action='nse.reference.systematic_publish')<>2
 OR NOT EXISTS(SELECT 1 FROM nse_reference.systematic_publications a
   JOIN nse_reference.systematic_publications b ON b.previous_snapshot_id=a.snapshot_id AND b.version>a.version)
 THEN RAISE EXCEPTION 'b063_publication_race_failed'; END IF;
END $$;
SQL
printf 'B06.3 publication race: one CAS winner; concurrent acknowledgement replay is idempotent\n'

# The same shared B06.2 route must serialize preparation, claims and finalization
# for each systematic variant while leaving explicit reference publication alone.
race() {
  psql_local < "$test_dir/$1.sql" > "$test_dir/first.log" 2>&1 & first=$!
  psql_local < "$test_dir/$2.sql" > "$test_dir/second.log" 2>&1 & second=$!
  wait "$first"
  wait "$second"
}
for variant in SIP STP SWP; do
  key=$(psql_local -Atqc 'SELECT gen_random_uuid()')
  for n in 1 2; do
    cat > "$test_dir/prepare$n.sql" <<SQL
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.prepare_nse_master_download('b0630000-0000-4000-8001-000000000001','b0630000-0000-4000-8002-000000000001','$variant','$key');
SELECT pg_sleep(0.3);
COMMIT;
SQL
  done
  race prepare1 prepare2
  event_id=$(psql_local -Atqc "SELECT event_id FROM nse_reference.jobs WHERE file_type='$variant'")
  for n in 1 2; do
    cat > "$test_dir/claim$n.sql" <<SQL
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.claim_nse_master_download('$event_id','b0630000-0000-4000-8003-00000000000$n');
SELECT pg_sleep(0.3);
COMMIT;
SQL
  done
  race claim1 claim2
  psql_local <<SQL
DO \$\$ DECLARE e public.event_outbox; body text; BEGIN
 SELECT * INTO STRICT e FROM public.event_outbox WHERE id='$event_id';
 IF e.status<>'processing' OR e.retry_count<>1 THEN RAISE EXCEPTION 'b063_claim_not_exclusive'; END IF;
 SELECT b.body INTO STRICT body FROM public.b063_runtime_bodies b WHERE kind='$variant';
 PERFORM public.begin_nse_master_job_capture(e.id,e.claim_token,gen_random_uuid(),'UAT','05418','https://nse.example.test');
 PERFORM public.append_nse_master_job_chunk(e.id,e.claim_token,0,replace(encode(convert_to(body,'UTF8'),'base64'),E'\n',''),encode(extensions.digest(body,'sha256'),'hex'));
 PERFORM public.finish_nse_master_job_capture(e.id,e.claim_token,'COMPLETE',200,'TEXT',octet_length(body),true,true,encode(extensions.digest(body,'sha256'),'hex'));
END \$\$;
SQL
  token=$(psql_local -Atqc "SELECT claim_token FROM public.event_outbox WHERE id='$event_id'")
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
  psql_local <<SQL
DO \$\$ BEGIN
 IF (SELECT count(*) FROM nse_reference.jobs WHERE file_type='$variant')<>1
 OR (SELECT count(*) FROM nse_reference.completions c JOIN nse_reference.jobs j ON j.id=c.id WHERE j.file_type='$variant' AND c.outcome='STAGED_VALIDATED')<>1
 OR (SELECT count(*) FROM nse_reference.validations WHERE file_type='$variant' AND row_count=1)<>1
 OR (SELECT count(*) FROM nse_reference.systematic_validations typed JOIN nse_reference.validations shared USING(snapshot_id) WHERE typed.file_type='$variant')<>1
 OR EXISTS(SELECT 1 FROM nse_reference.systematic_publications p JOIN nse_reference.validations v USING(snapshot_id))
 OR (SELECT count(*) FROM nse_reference.systematic_publications)<>2
 THEN RAISE EXCEPTION 'b063_runtime_race_failed'; END IF;
END \$\$;
SQL
  printf 'B06.3 %s shared runtime race: one job, claim and validation; no automatic publication\n' "$variant"
done
