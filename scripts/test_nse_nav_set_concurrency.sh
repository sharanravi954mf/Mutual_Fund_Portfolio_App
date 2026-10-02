#!/usr/bin/env bash
# Runs after test_nse_reference_concurrency.sh in its disposable synthetic fixture.
set -euo pipefail
container=${1:?disposable test container required}
case "$container" in moneybowl-order-status-test-*) ;; *) exit 2 ;; esac
test "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container")" = none
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
psql_local > "$test_dir/seed.log" <<'SQL'
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','B06.4 synthetic concurrency');
DO $$ DECLARE d uuid; b bytea; k text; BEGIN
 FOREACH k IN ARRAY ARRAY['NAV','SET'] LOOP
  d:=CASE k WHEN 'NAV' THEN 'b0640000-0000-4000-8003-000000000001'::uuid ELSE 'b0640000-0000-4000-8003-000000000002'::uuid END;
  b:=convert_to(CASE k WHEN 'NAV' THEN '2026-09-30|NSE-A|Synthetic Growth|RTA-A|Z|INF000000001|123.4500|CAMS' ELSE 'unknown|SET|format' END,'UTF8');
  PERFORM public.begin_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001',k,d,'UAT','05418','https://nse.example.test',gen_random_uuid());
  PERFORM public.append_nse_master_chunk('b0610000-0000-4000-8001-000000000001',d,0,replace(encode(b,'base64'),E'\n',''),encode(extensions.digest(b,'sha256'),'hex'));
  PERFORM public.finish_nse_master_download('b0610000-0000-4000-8001-000000000001',d,'COMPLETE',200,'TEXT',octet_length(b),true,true,encode(extensions.digest(b,'sha256'),'hex'));
  PERFORM public.stage_nse_reference_snapshot('b0610000-0000-4000-8001-000000000001',d);
 END LOOP;
END $$;
SQL
cat > "$test_dir/validate.sql" <<'SQL'
BEGIN;
SELECT set_config('b064.nav_id',(SELECT id::text FROM nse_reference.snapshots WHERE download_id='b0640000-0000-4000-8003-000000000001'),true);
SELECT set_config('b064.set_id',(SELECT id::text FROM nse_reference.snapshots WHERE download_id='b0640000-0000-4000-8003-000000000002'),true);
SET LOCAL ROLE service_role;
SELECT public.validate_nse_nav_snapshot('b0610000-0000-4000-8001-000000000001',current_setting('b064.nav_id')::uuid);
SELECT pg_sleep(0.5);
SELECT public.assess_nse_set_snapshot('b0610000-0000-4000-8001-000000000001',current_setting('b064.set_id')::uuid);
COMMIT;
SQL
psql_local < "$test_dir/validate.sql" > "$test_dir/first.log" &
first=$!
psql_local < "$test_dir/validate.sql" > "$test_dir/second.log" &
second=$!
wait "$first"
wait "$second"
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM nse_nav.validations)<>1 OR (SELECT count(*) FROM nse_nav.observations)<>1
  OR (SELECT count(*) FROM nse_set.assessments)<>1 OR
  (SELECT count(*) FROM public.workspace_audit_logs WHERE action IN ('nse.nav.assessment','nse.set.assessment'))<>2
 THEN RAISE EXCEPTION 'b064_concurrent_assessment_replay_failed'; END IF;
END $$;
DELETE FROM vault.secrets WHERE name='integration_payload_encryption_key_v1';
SQL
printf 'B06.4 concurrent replay: one NAV receipt/row, one blocked SET receipt, two audits\n'
