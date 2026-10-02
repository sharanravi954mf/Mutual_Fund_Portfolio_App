#!/usr/bin/env bash
# Network-isolated, disposable current-schema regression; no hosted connections.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
container="moneybowl-systematic-test-$$"
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
psql_local <<'SQL'
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
DO $$ DECLARE fn record; finding record; BEGIN
  FOR fn IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_language l ON l.oid=p.prolang WHERE l.lanname='plpgsql' AND
      ((n.nspname='nse_reference' AND (p.proname LIKE 'systematic_%' OR p.proname='validate_systematic')) OR
       (n.nspname='public' AND p.proname IN ('validate_nse_systematic_snapshot','publish_nse_systematic_snapshot',
         'get_nse_systematic_current','get_nse_systematic_products'))) LOOP
    FOR finding IN SELECT * FROM extensions.plpgsql_check_function_tb(fn.oid::regprocedure,fatal_errors:=false) LOOP
      RAISE EXCEPTION 'b063_lint:%:%:%',fn.oid::regprocedure,finding.level,finding.message;
    END LOOP;
  END LOOP;
END $$;
SQL
for pass in 1 2; do
  psql_local < "$repo_root/supabase/tests/nse_systematic_product_masters_test.sql"
done
psql_local -c "DO \$\$ BEGIN
 IF EXISTS(SELECT 1 FROM nse_reference.systematic_validations) OR EXISTS(SELECT 1 FROM nse_reference.connections)
 OR EXISTS(SELECT 1 FROM nse_reference.systematic_publications)
 OR EXISTS(SELECT 1 FROM vault.decrypted_secrets WHERE name='integration_payload_encryption_key_v1')
 THEN RAISE EXCEPTION 'b063_test_did_not_rollback'; END IF;
END \$\$;"
bash "$repo_root/scripts/test_nse_systematic_concurrency.sh" "$container"
