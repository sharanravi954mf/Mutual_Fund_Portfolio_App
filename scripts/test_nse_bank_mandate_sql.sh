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
psql_local < "$repo_root/supabase/tests/nse_bank_mandate_test.sql"
psql_local < "$repo_root/supabase/tests/nse_bank_mandate_write_test.sql"
psql_local <<'SQL'
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
DO $$ DECLARE fn record; finding record; BEGIN
 FOR fn IN SELECT p.oid,p.prorettype,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 JOIN pg_language l ON l.oid=p.prolang WHERE l.lanname='plpgsql' AND (n.nspname='nse_bank_mandate' OR (n.nspname='public' AND (p.proname LIKE '%nse_mandate_status%' OR p.proname LIKE '%nse_bank_mandate%' OR p.proname='request_nse_bank_mandate_review'))) LOOP
 FOR finding IN SELECT * FROM extensions.plpgsql_check_function_tb(fn.oid::regprocedure,
 CASE WHEN fn.prorettype<>'trigger'::regtype THEN 0::regclass WHEN fn.proname='immutable_intent' THEN 'nse_bank_mandate.intents'::regclass WHEN fn.proname='audit_authority' THEN 'nse_bank_mandate.write_intents'::regclass ELSE 'public.event_outbox'::regclass END,fatal_errors:=false) LOOP
 IF finding.level='error' THEN RAISE EXCEPTION 'b07_lint:%:%',fn.proname,finding.message; END IF;
 RAISE NOTICE 'b07_lint:%:%:line %:%',fn.proname,finding.level,finding.lineno,finding.message;
 END LOOP; END LOOP;
END $$;
SQL
bash "$repo_root/scripts/test_nse_bank_mandate_concurrency.sh" "$container"
bash "$repo_root/scripts/test_nse_bank_mandate_write_concurrency.sh" "$container"
