#!/usr/bin/env bash
# Only run against the disposable container created by test_email_signup_sql.sh.
set -euo pipefail
container=${1:?disposable container required}
[[ "$container" == moneybowl-email-signup-* || "$container" == moneybowl-authz-regression-* ]] || exit 2
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
psql_local <<'SQL'
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
('ef300000-0000-0000-0000-000000000001','race@example.test',now()),
('ef300000-0000-0000-0000-000000000002','RACE@example.test',now());
INSERT INTO public.profiles(id,role,verified_email) VALUES
('ef400000-0000-0000-0000-000000000001','investor','race@example.test');
SQL
signup_race_dir=$(mktemp -d)
trap 'rm -rf "$signup_race_dir"' EXIT
# Lock the shared candidate so both accounts overlap in bootstrap.
psql_local > "$signup_race_dir/holder.log" <<'SQL' &
BEGIN;
SELECT id FROM public.profiles WHERE id='ef400000-0000-0000-0000-000000000001' FOR UPDATE;
SELECT pg_sleep(2);
COMMIT;
SQL
holder=$!
sleep 0.3
pids=()
for n in 1 1 2 2; do
 psql_local > "$signup_race_dir/$n-$RANDOM.log" <<SQL &
SET statement_timeout='10s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ef300000-0000-0000-0000-00000000000$n',false);
SELECT * FROM public.bootstrap_identity();
SQL
 pids+=("$!")
done
wait "$holder"
for pid in "${pids[@]}"; do wait "$pid"; done
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM public.investor_account_links WHERE profile_id='ef400000-0000-0000-0000-000000000001' AND link_status='active') <> 1 THEN
  RAISE EXCEPTION 'duplicate race link'; END IF;
 IF (SELECT count(*) FROM public.user_accounts WHERE user_id::text LIKE 'ef300000%' AND account_state='linked_investor') <> 1 THEN
  RAISE EXCEPTION 'race claimed twice'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.investor_account_links l JOIN public.profiles p ON p.id=l.profile_id WHERE p.id='ef400000-0000-0000-0000-000000000001' AND l.user_id=p.user_id) THEN
  RAISE EXCEPTION 'ownership diverged'; END IF;
END $$;
DELETE FROM public.investor_account_links WHERE profile_id='ef400000-0000-0000-0000-000000000001';
DELETE FROM public.profiles WHERE id='ef400000-0000-0000-0000-000000000001';
DELETE FROM auth.users WHERE id::text LIKE 'ef300000%';
SQL
echo 'Concurrent and repeated bootstrap: PASS'
