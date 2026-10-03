#!/usr/bin/env bash
# Fresh full schema, no network or hosted Supabase access, no email delivery.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
container="moneybowl-email-signup-$$"
trap 'docker rm --force "$container" >/dev/null' EXIT
docker run --detach --name "$container" --network none --tmpfs /var/lib/postgresql/data:rw \
 -e POSTGRES_PASSWORD=local_disposable_only public.ecr.aws/supabase/postgres:17.6.1.155 >/dev/null
for attempt in {1..60}; do
 if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
 sleep 1
done
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
docker exec -i "$container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < "$repo_root/supabase/tests/fixtures/nse_local_platform.sql"
for migration in "$repo_root"/supabase/migrations/*.sql; do
 echo "Applying ${migration##*/}"
 psql_local < "$migration"
done
for test in email_signup_identity_test.sql core_auth_rbac_test.sql user_management_workspace_test.sql browser_api_privilege_contract_test.sql issue_40_referral_claim_lifecycle_test.sql issue_40_referral_signup_provenance_test.sql issue_40_referral_mechanics_test.sql issue_40_referral_entitlement_bridge_test.sql; do
 echo "Testing $test"
 psql_local < "$repo_root/supabase/tests/$test"
done
psql_local <<'SQL'
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
DO $$ DECLARE fn record; finding record; BEGIN
 FOR fn IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('handle_new_user','bootstrap_identity','complete_onboarding_choice','accept_workspace_invitation') LOOP
 FOR finding IN SELECT * FROM extensions.plpgsql_check_function_tb(fn.oid::regprocedure,
 CASE WHEN fn.proname='handle_new_user' THEN 'auth.users'::regclass ELSE 0::regclass END,fatal_errors:=false) LOOP
  IF finding.level='error' THEN RAISE EXCEPTION 'signup_lint:%:%',fn.proname,finding.message; END IF;
  RAISE NOTICE 'signup_lint:%:%:%',fn.proname,finding.level,finding.message;
 END LOOP;
 END LOOP;
END $$;
SQL
bash "$repo_root/scripts/test_email_signup_concurrency.sh" "$container"
SUPABASE_DB_CONTAINER="$container" sh "$repo_root/supabase/tests/issue_40_referral_conversion_concurrency_test.sh"
echo 'Email signup full-schema regressions: PASS'
