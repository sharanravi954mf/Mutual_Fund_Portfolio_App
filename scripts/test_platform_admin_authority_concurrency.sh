#!/usr/bin/env bash
set -euo pipefail
container=${1:?disposable platform-authority container required}
[[ "$container" == moneybowl-authz-regression-platform-* ]] || exit 2
race_dir=$(mktemp -d)
trap 'rm -rf "$race_dir"' EXIT
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
wait_for_activity() {
 local predicate=$1
 for attempt in {1..50}; do
  if [[ $(psql_local -Atc "SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE $predicate)") == t ]]; then return; fi
  sleep 0.1
 done
 cat "$race_dir"/*.log
 echo 'Expected concurrent database activity was not observed' >&2
 return 1
}
psql_local <<'SQL'
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES('aa000000-0000-0000-0000-000000000001','platform-race@example.test',now());
SQL
pids=()
for attempt in 1 2; do
 psql_local > "$race_dir/bootstrap-$attempt.log" 2>&1 <<'SQL' &
SET statement_timeout='10s';
SELECT platform_authority.bootstrap_first_admin('aa000000-0000-0000-0000-000000000001','aa100000-0000-0000-0000-000000000001','aa100000-0000-0000-0000-000000000002','concurrent verified operator evidence');
SQL
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || { cat "$race_dir"/bootstrap-*.log; exit 1; }; done
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM platform_authority.grants)<>2 OR (SELECT count(*) FROM platform_authority.events)<>2 THEN RAISE EXCEPTION 'concurrent_bootstrap_duplicate'; END IF;
END $$;
SELECT platform_authority.grant_authority('aa000000-0000-0000-0000-000000000001','platform.catalog.manage','aa100000-0000-0000-0000-000000000003','concurrency catalogue capability');
INSERT INTO auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) VALUES('aa200000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','totp','verified',now(),now());
INSERT INTO auth.sessions(id,user_id,factor_id,aal) VALUES('aa300000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','aa200000-0000-0000-0000-000000000001','aal2');
INSERT INTO public.mutual_funds(id,scheme_code,scheme_name,current_nav) VALUES('aa400000-0000-0000-0000-000000000001','PLATFORM-RACE','Concurrency fixture',10);
SQL
psql_local > "$race_dir/revoke.log" 2>&1 <<'SQL' &
SET application_name='platform_v1_revoker';
BEGIN;
SELECT platform_authority.revoke_authority((SELECT id FROM platform_authority.grants WHERE grant_key='platform_admin'),'aa100000-0000-0000-0000-000000000004','concurrency authority revocation');
SELECT pg_sleep(4);
COMMIT;
SQL
revoker=$!
wait_for_activity "application_name='platform_v1_revoker' AND wait_event='PgSleep'"
psql_local > "$race_dir/mutation.log" 2>&1 <<'SQL' &
SET application_name='platform_v1_mutation';
SET statement_timeout='10s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"aa000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2","session_id":"aa300000-0000-0000-0000-000000000001"}',false);
DO $$ BEGIN
 BEGIN PERFORM public.platform_update_fund_nav('aa400000-0000-0000-0000-000000000001',20,current_date); RAISE EXCEPTION 'revocation_race_bypass';
 EXCEPTION WHEN insufficient_privilege THEN IF SQLERRM<>'platform_capability_required' THEN RAISE; END IF; END;
END $$;
SQL
caller=$!
wait_for_activity "application_name='platform_v1_mutation' AND wait_event_type='Lock'"
wait "$revoker" || { cat "$race_dir/revoke.log"; exit 1; }
wait "$caller" || { cat "$race_dir/mutation.log"; exit 1; }
psql_local <<'SQL'
DO $$ BEGIN IF (SELECT current_nav FROM public.mutual_funds WHERE id='aa400000-0000-0000-0000-000000000001')<>10 THEN RAISE EXCEPTION 'revoked_mutation_committed'; END IF; END $$;
SQL
echo 'Concurrent platform bootstrap and revocation: PASS'
