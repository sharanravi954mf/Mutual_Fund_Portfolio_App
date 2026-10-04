#!/usr/bin/env bash
# Only the network-disabled disposable container created by the MFD harness.
set -euo pipefail
container=${1:?disposable MFD container required}
[[ "$container" == moneybowl-authz-regression-platform-mfd-* ]] || exit 2
[[ $(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container") == none ]] || exit 2
race_dir=$(mktemp -d)
trap 'rm -rf "$race_dir"' EXIT
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
wait_activity() {
 for attempt in {1..60}; do
  if [[ $(psql_local -Atc "SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE $1)") == t ]]; then return; fi
  sleep 0.1
 done
 cat "$race_dir"/*.log
 echo 'Expected MFD race overlap not observed' >&2
 return 1
}
psql_local <<'SQL'
CREATE SCHEMA mfd_race;
CREATE FUNCTION mfd_race.id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT md5('mfd-race-'||n)::uuid $$;
CREATE FUNCTION mfd_race.login(n integer) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',jsonb_build_object('sub',mfd_race.id(n),'role','authenticated','aal','aal2','session_id',mfd_race.id(300+n))::text,false)::void
$$;
CREATE FUNCTION mfd_race.app(n integer) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$ SELECT id FROM public.mfd_applications WHERE applicant_user_id=mfd_race.id(n) ORDER BY submitted_at DESC LIMIT 1 $$;
GRANT USAGE ON SCHEMA mfd_race TO authenticated;
INSERT INTO auth.users(id,email,email_confirmed_at) SELECT mfd_race.id(n),'mfd-race-'||n||'@example.test',now() FROM generate_series(1,10) n;
SELECT platform_authority.grant_authority(mfd_race.id(1),'platform_admin',mfd_race.id(101),'synthetic race reviewer');
SELECT platform_authority.grant_authority(mfd_race.id(1),'mfd_applications.review',mfd_race.id(102),'synthetic race review capability');
SELECT platform_authority.grant_authority(mfd_race.id(2),'platform_admin',mfd_race.id(103),'synthetic second race reviewer');
SELECT platform_authority.grant_authority(mfd_race.id(2),'mfd_applications.review',mfd_race.id(104),'synthetic second review capability');
INSERT INTO auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) SELECT mfd_race.id(200+n),mfd_race.id(n),'totp','verified',now(),now() FROM generate_series(1,2) n;
INSERT INTO auth.sessions(id,user_id,factor_id,aal) SELECT mfd_race.id(300+n),mfd_race.id(n),mfd_race.id(200+n),'aal2' FROM generate_series(1,2) n;
SET ROLE authenticated;
DO $$ DECLARE n integer; BEGIN
 FOR n IN 3..7 LOOP
  PERFORM mfd_race.login(n); PERFORM public.submit_mfd_application(mfd_race.id(400+n),'Race business','ARN',NULL);
  PERFORM mfd_race.login(1); PERFORM public.start_mfd_application_review(mfd_race.app(n),1,mfd_race.id(500+n));
 END LOOP;
END $$;
SQL
# Hold applicant first so both decision sessions demonstrably overlap.
race_decisions() {
 local applicant=$1 second=$2 same=$3
 psql_local > "$race_dir/holder-$applicant.log" 2>&1 <<SQL &
SET application_name='mfd_holder_$applicant';
BEGIN;
SELECT 1 FROM auth.users WHERE id=mfd_race.id($applicant) FOR UPDATE;
SELECT pg_sleep(3);
COMMIT;
SQL
 local holder=$!
 wait_activity "application_name='mfd_holder_$applicant' AND wait_event='PgSleep'"
 local pids=()
 for side in 1 2; do
  local action=approve actor=$side request=$((600+applicant*10+side))
  if [[ $side == 2 ]]; then action=$second; fi
  if [[ $same == yes ]]; then actor=1; request=$((600+applicant*10+1)); fi
  psql_local > "$race_dir/decision-$applicant-$side.log" 2>&1 <<SQL &
SET statement_timeout='12s';
SET application_name='mfd_decision_${applicant}_$side';
SET ROLE authenticated;
SELECT mfd_race.login($actor);
DO \$\$ BEGIN
 BEGIN PERFORM public.${action}_mfd_application(mfd_race.app($applicant),2,mfd_race.id($request),'manual race review');
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'mfd_application_decided' THEN RAISE; END IF; END;
END \$\$;
SQL
  pids+=("$!")
 done
 wait_activity "application_name LIKE 'mfd_decision_${applicant}_%' AND wait_event_type='Lock'"
 wait "$holder"
 for pid in "${pids[@]}"; do wait "$pid" || { cat "$race_dir"/decision-*.log; exit 1; }; done
 psql_local -c "DO \$\$ DECLARE a public.mfd_applications; BEGIN SELECT * INTO a FROM public.mfd_applications WHERE id=mfd_race.app($applicant); IF a.status NOT IN ('approved','rejected') OR (SELECT count(*) FROM public.mfd_application_events WHERE application_id=a.id AND event_type IN ('approved','rejected'))<>1 THEN RAISE EXCEPTION 'terminal_race_failed'; END IF; IF a.status='approved' AND ((SELECT count(*) FROM public.profiles WHERE user_id=a.applicant_user_id)<>1 OR (SELECT count(*) FROM public.workspaces WHERE owner_profile_id=a.profile_id)<>1 OR (SELECT count(*) FROM public.workspace_memberships WHERE profile_id=a.profile_id)<>1) THEN RAISE EXCEPTION 'duplicate_provisioning'; END IF; IF a.status='rejected' AND EXISTS(SELECT 1 FROM public.profiles WHERE user_id=a.applicant_user_id) THEN RAISE EXCEPTION 'rejection_provisioned'; END IF; END \$\$;"
}
race_decisions 3 approve no
race_decisions 4 reject no
race_decisions 5 approve yes
# Same applicant, simultaneous distinct submission requests: only one open application.
psql_local > "$race_dir/submit-holder.log" 2>&1 <<'SQL' &
SET application_name='mfd_submit_holder';
BEGIN;
SELECT 1 FROM auth.users WHERE id=mfd_race.id(8) FOR UPDATE;
SELECT pg_sleep(3);
COMMIT;
SQL
holder=$!
wait_activity "application_name='mfd_submit_holder' AND wait_event='PgSleep'"
pids=()
for side in 1 2; do
 psql_local > "$race_dir/submit-$side.log" 2>&1 <<SQL &
SET statement_timeout='12s';
SET ROLE authenticated;
SET application_name='mfd_submit_racer';
SELECT mfd_race.login(8);
DO \$\$ BEGIN BEGIN PERFORM public.submit_mfd_application(mfd_race.id($((800+side))),'Concurrent submission','ARN',NULL);
EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'mfd_application_open' THEN RAISE; END IF; END; END \$\$;
SQL
 pids+=("$!")
done
wait_activity "application_name='mfd_submit_racer' AND wait_event_type='Lock'"
wait "$holder"
for pid in "${pids[@]}"; do wait "$pid" || { cat "$race_dir"/submit-*.log; exit 1; }; done
psql_local -c "DO \$\$ BEGIN IF (SELECT count(*) FROM public.mfd_applications WHERE applicant_user_id=mfd_race.id(8))<>1 THEN RAISE EXCEPTION 'duplicate_submission'; END IF; END \$\$;"
# Same globally bound UUID used for two different applications cannot commit twice.
psql_local <<'SQL'
SET ROLE authenticated;
DO $$ DECLARE n integer; BEGIN FOR n IN 9..10 LOOP
 PERFORM mfd_race.login(n); PERFORM public.submit_mfd_application(mfd_race.id(400+n),'UUID race','ARN',NULL);
 PERFORM mfd_race.login(1); PERFORM public.start_mfd_application_review(mfd_race.app(n),1,mfd_race.id(500+n));
END LOOP; END $$;
SQL
psql_local > "$race_dir/uuid-holder.log" 2>&1 <<'SQL' &
SET application_name='mfd_uuid_holder';
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('mfd-request:'||mfd_race.id(899)::text,0));
SELECT pg_sleep(3);
COMMIT;
SQL
holder=$!
wait_activity "application_name='mfd_uuid_holder' AND wait_event='PgSleep'"
pids=()
for applicant in 9 10; do
 psql_local > "$race_dir/uuid-$applicant.log" 2>&1 <<SQL &
SET application_name='mfd_uuid_racer';
SET statement_timeout='12s';
SET ROLE authenticated;
SELECT mfd_race.login(1);
DO \$\$ BEGIN BEGIN PERFORM public.approve_mfd_application(mfd_race.app($applicant),2,mfd_race.id(899),'same evidence');
EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'mfd_request_conflict' THEN RAISE; END IF; END; END \$\$;
SQL
 pids+=("$!")
done
wait_activity "application_name='mfd_uuid_racer' AND wait_event_type='Lock'"
wait "$holder"
for pid in "${pids[@]}"; do wait "$pid" || { cat "$race_dir"/uuid-*.log; exit 1; }; done
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM public.mfd_applications WHERE applicant_user_id IN (mfd_race.id(9),mfd_race.id(10)) AND status='approved')<>1
 OR (SELECT count(*) FROM public.profiles WHERE user_id IN (mfd_race.id(9),mfd_race.id(10)))<>1 THEN RAISE EXCEPTION 'cross_target_uuid_race'; END IF;
END $$;
SQL
# Revocation wins a held authority lock before a waiting decision can proceed.
for kind in capability session; do
 if [[ $kind == capability ]]; then
  actor=1; applicant=6; expected=platform_capability_required
  change="SELECT platform_authority.revoke_authority((SELECT id FROM platform_authority.grants WHERE user_id=mfd_race.id(1) AND grant_key='mfd_applications.review' AND revoked_at IS NULL),mfd_race.id(901),'race capability revoked');"
 else
  actor=2; applicant=7; expected=platform_admin_step_up_required
  change="UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id=mfd_race.id(302);"
 fi
 psql_local > "$race_dir/revoke-$kind.log" 2>&1 <<SQL &
SET application_name='mfd_loss_$kind';
BEGIN;
$change
SELECT pg_sleep(3);
COMMIT;
SQL
 revoker=$!
 wait_activity "application_name='mfd_loss_$kind' AND wait_event='PgSleep'"
 psql_local > "$race_dir/loss-$kind.log" 2>&1 <<SQL &
SET statement_timeout='12s';
SET application_name='mfd_wait_$kind';
SET ROLE authenticated;
SELECT mfd_race.login($actor);
DO \$\$ BEGIN
 BEGIN PERFORM public.approve_mfd_application(mfd_race.app($applicant),2,mfd_race.id($((950+applicant))),'manual reviewed evidence'); RAISE EXCEPTION 'revocation_bypass';
 EXCEPTION WHEN insufficient_privilege THEN IF SQLERRM<>'$expected' THEN RAISE; END IF; END;
END \$\$;
SQL
 caller=$!
 wait_activity "application_name='mfd_wait_$kind' AND wait_event_type='Lock'"
 wait "$revoker"
 wait "$caller" || { cat "$race_dir/loss-$kind.log"; exit 1; }
done
psql_local <<'SQL'
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.profiles WHERE user_id IN (mfd_race.id(6),mfd_race.id(7))) THEN RAISE EXCEPTION 'revoked_decision_created_authority'; END IF;
 IF (SELECT count(*) FROM public.mfd_applications WHERE applicant_user_id IN (mfd_race.id(6),mfd_race.id(7)) AND status='under_review')<>2 THEN RAISE EXCEPTION 'revoked_decision_changed_application'; END IF;
END $$;
SQL
echo 'MFD concurrency: approve/approve, approve/reject, exact replay, duplicate submission, cross-target UUID, capability/session loss PASS'
