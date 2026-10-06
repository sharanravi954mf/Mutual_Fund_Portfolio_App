#!/usr/bin/env bash
# Only the fresh disposable database owned by the parent harness is accepted.
set -euo pipefail
container=${1:?disposable container required}
[[ "$container" == moneybowl-authz-regression-platform-mfd-* ]] || exit 2
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
# Reuse explicit synthetic approval fixtures, not a service bypass in the API test.
python3 - "$repo_root/supabase/tests/mfd_led_investor_onboarding_test.sql" <<'PY' | psql_local >/dev/null
import sys
print(open(sys.argv[1]).read().split('SET LOCAL ROLE authenticated;')[0])
print('COMMIT;')
PY
race_dir=$(mktemp -d)
trap 'rm -rf "$race_dir"' EXIT
pids=()
for n in 1 2; do
 psql_local > "$race_dir/onboard-$n.log" 2>&1 <<SQL &
BEGIN;
SET LOCAL statement_timeout='20s';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
SELECT public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001','ab500000-0000-0000-0000-00000000000$n',0,
 '{"legal_name":"Concurrent Synthetic Investor","pan":"ZZZPZ0011Z","email":"onboarding-3@example.test","mobile":"919000000003"}') IS NOT NULL;
SELECT pg_sleep(0.3);
SELECT public.resolve_investor_onboarding('ab500000-0000-0000-0000-00000000000$n',1) IS NOT NULL;
COMMIT;
SQL
 pids+=("$!")
done
psql_local > "$race_dir/bootstrap.log" 2>&1 <<'SQL' &
SET statement_timeout='20s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000003',false);
SELECT account_state FROM public.bootstrap_identity();
SQL
pids+=("$!")
for pid in "${pids[@]}"; do
 if ! wait "$pid"; then cat "$race_dir"/*.log; exit 1; fi
done
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM public.profiles WHERE full_name='Concurrent Synthetic Investor')<>1 THEN RAISE EXCEPTION 'duplicate race investor'; END IF;
 IF (SELECT count(*) FROM public.investor_account_links WHERE user_id='ab000000-0000-0000-0000-000000000003' AND link_status='active')<>1 THEN RAISE EXCEPTION 'race link missing'; END IF;
 IF (SELECT count(*) FROM moneybowl_onboarding.cases WHERE superseded_by IS NULL)<>1 THEN RAISE EXCEPTION 'duplicate race case'; END IF;
 IF (SELECT count(*) FROM public.advisor_investor_assignments WHERE advisor_id='ab100000-0000-0000-0000-000000000001')<>1 THEN RAISE EXCEPTION 'duplicate race assignment'; END IF;
END $$;
SQL
# Revocation commits before a blocked onboarding RPC resumes. Retained token fails.
psql_local > "$race_dir/revoke.log" 2>&1 <<'SQL' &
BEGIN;
UPDATE public.workspace_memberships SET ended_at=now() WHERE id='ab300000-0000-0000-0000-000000000001';
SELECT pg_sleep(1);
COMMIT;
SQL
revoker=$!
sleep 0.3
psql_local > "$race_dir/denial.log" 2>&1 <<'SQL'
SET statement_timeout='10s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',false);
DO $$ BEGIN
 BEGIN PERFORM public.save_investor_onboarding('ab200000-0000-0000-0000-000000000001',gen_random_uuid(),0,'{}');
 RAISE EXCEPTION 'retained token accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SQL
wait "$revoker"
echo 'Onboarding concurrency: canonical identity/case/assignment, signup overlap, revocation fencing PASS'
