#!/usr/bin/env bash
# Only the disposable container created by the containment harness is accepted.
set -euo pipefail
container=${1:?disposable container required}
[[ "$container" == moneybowl-authz-regression-* ]] || exit 2
race_dir=$(mktemp -d)
trap 'rm -rf "$race_dir"' EXIT
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
psql_local <<'SQL'
INSERT INTO auth.users(id,email,email_confirmed_at) SELECT ('ac000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'race-'||n||'@example.test',now() FROM generate_series(1,3) n;
INSERT INTO public.profiles(id,user_id,role) SELECT id,id,CASE WHEN right(id::text,1)='1' THEN 'admin' ELSE 'investor' END FROM auth.users WHERE id::text LIKE 'ac000000%' AND right(id::text,1)<>'3';
INSERT INTO public.workspaces(id,name,slug,owner_profile_id) VALUES('ac100000-0000-0000-0000-000000000001','Authz race','authz-race','ac000000-0000-0000-0000-000000000001');
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role) VALUES
('ac100000-0000-0000-0000-000000000001','ac000000-0000-0000-0000-000000000001','admin'),
('ac100000-0000-0000-0000-000000000001','ac000000-0000-0000-0000-000000000002','investor');
INSERT INTO public.order_requests(id,workspace_id,investor_profile_id,scheme_code,type,amount,initiated_by_profile_id,initiated_by_role,initiation_channel)
VALUES('ac200000-0000-0000-0000-000000000001','ac100000-0000-0000-0000-000000000001','ac000000-0000-0000-0000-000000000002','TEST','buy',100,'ac000000-0000-0000-0000-000000000001','advisor','advisor_portal');
SQL
# Cancellation waits for a locked order while the actor is suspended. It must
# re-evaluate live authority after waiting, not use authority read beforehand.
psql_local > "$race_dir/holder.log" <<'SQL' &
BEGIN;
SELECT 1 FROM public.order_requests WHERE id='ac200000-0000-0000-0000-000000000001' FOR UPDATE;
SELECT pg_sleep(2);
COMMIT;
SQL
holder=$!
sleep 0.3
psql_local > "$race_dir/cancel.log" 2>&1 <<'SQL' &
SET statement_timeout='10s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ac000000-0000-0000-0000-000000000001',false);
DO $$ BEGIN
 BEGIN PERFORM public.cancel_order('ac200000-0000-0000-0000-000000000001','race'); RAISE EXCEPTION 'revocation_race_bypass';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'not_authorized' THEN RAISE; END IF; END;
END $$;
SQL
caller=$!
sleep 0.3
psql_local <<'SQL'
UPDATE public.workspace_memberships SET status='suspended' WHERE workspace_id='ac100000-0000-0000-0000-000000000001' AND profile_id='ac000000-0000-0000-0000-000000000001';
SQL
wait "$holder"
wait "$caller" || { cat "$race_dir/cancel.log"; exit 1; }
psql_local <<'SQL'
DO $$ BEGIN IF (SELECT status FROM public.order_requests WHERE id='ac200000-0000-0000-0000-000000000001')<>'pending_qualification' THEN RAISE EXCEPTION 'revoked_actor_changed_order'; END IF; END $$;
UPDATE public.workspace_memberships SET status='active' WHERE workspace_id='ac100000-0000-0000-0000-000000000001' AND profile_id='ac000000-0000-0000-0000-000000000001';
INSERT INTO public.workspace_invitations(workspace_id,email,role,invited_by,token_hash,expires_at)
VALUES('ac100000-0000-0000-0000-000000000001','race-3@example.test','advisor','ac000000-0000-0000-0000-000000000001',encode(extensions.digest('race-token','sha256'),'hex'),now()+interval '1 day');
SQL
pids=()
for n in 1 2; do
 psql_local > "$race_dir/invite-$n.log" 2>&1 <<'SQL' &
SET statement_timeout='10s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','ac000000-0000-0000-0000-000000000003',false);
DO $$ BEGIN
 BEGIN PERFORM public.accept_workspace_invitation('race-token');
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'invitation_unavailable' THEN RAISE; END IF; END;
END $$;
SQL
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || { cat "$race_dir"/invite-*.log; exit 1; }; done
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM public.workspace_memberships m JOIN public.profiles p ON p.id=m.profile_id WHERE p.user_id='ac000000-0000-0000-0000-000000000003')<>1 THEN RAISE EXCEPTION 'concurrent_invitation_duplicate'; END IF;
 IF (SELECT count(*) FROM public.workspace_audit_logs WHERE workspace_id='ac100000-0000-0000-0000-000000000001' AND action='invitation_accepted')<>1 THEN RAISE EXCEPTION 'concurrent_invitation_audit_duplicate'; END IF;
END $$;
SQL
echo 'Concurrent membership revocation and invitation acceptance: PASS'
