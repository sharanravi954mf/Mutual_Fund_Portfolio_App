#!/usr/bin/env bash
# Only the disposable network-none regression container; no deployed worker.
set -euo pipefail
container=${1:?disposable test container required}
case "$container" in moneybowl-order-status-test-*) ;; *) exit 2 ;; esac
test "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container")" = none
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
python3 - "$repo_root/supabase/tests/nse_master_reference_foundation_test.sql" > "$test_dir/fixture.sql" <<'PY'
import sys
print(open(sys.argv[1]).read().split('CREATE TEMP TABLE b061_assertions')[0])
print('COMMIT;')
PY
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_dir/fixture.sql" > "$test_dir/fixture.log"
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 > "$test_dir/seed.log" <<'SQL'
DO $$ DECLARE d uuid; n integer; BEGIN
 FOR n IN 1..2 LOOP
  d:=('b0610000-0000-4000-8003-00000000000'||n)::uuid;
  PERFORM public.begin_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001','SCH',d,'UAT','05418','https://nse.example.test',gen_random_uuid());
  PERFORM public.append_nse_master_chunk('b0610000-0000-4000-8001-000000000001',d,0,'YXxiCg==',encode(extensions.digest(E'a|b\n','sha256'),'hex'));
  PERFORM public.finish_nse_master_download('b0610000-0000-4000-8001-000000000001',d,'COMPLETE',200,'TEXT',4,true,true,encode(extensions.digest(E'a|b\n','sha256'),'hex'));
 END LOOP;
END $$;
SQL
for n in 1 2; do
  cat > "$test_dir/stage$n.sql" <<SQL
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.stage_nse_reference_snapshot('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8003-00000000000$n');
SELECT pg_sleep(0.5);
COMMIT;
SQL
done
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_dir/stage1.sql" > "$test_dir/first.log" &
first=$!
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_dir/stage2.sql" > "$test_dir/second.log" &
second=$!
wait "$first"
wait "$second"
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM nse_reference.snapshots)<>2 OR NOT EXISTS(
  SELECT 1 FROM nse_reference.snapshots a JOIN nse_reference.snapshots b ON b.previous_snapshot_id=a.id
  WHERE a.version=1 AND b.version=2 AND a.connection_id=b.connection_id AND a.file_type=b.file_type
 ) THEN RAISE EXCEPTION 'b061_concurrent_version_lineage_failed'; END IF;
END $$;
-- Only the disposable container contains these committed synthetic fixtures.
DELETE FROM vault.secrets WHERE name='integration_payload_encryption_key_v1';
SQL
printf 'B06.1 concurrent snapshots: unique sequential versions and intact predecessor lineage\n'
