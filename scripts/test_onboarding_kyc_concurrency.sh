#!/usr/bin/env bash
# Runs only inside the parent's disposable, network-disabled regression database.
set -euo pipefail
container=${1:?disposable container required}
[[ "$container" == moneybowl-authz-regression-platform-mfd-* ]] || exit 2
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
psql_local() { docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
race_dir=$(mktemp -d)
trap 'rm -rf "$race_dir"' EXIT
python3 - "$repo_root/supabase/tests/mfd_led_investor_onboarding_test.sql" <<'PY' | psql_local >/dev/null
import sys
s=open(sys.argv[1]).read().split('SET LOCAL ROLE authenticated;')[0]
s='\n'.join(line for line in s.splitlines() if 'vault.create_secret' not in line)
print(s.replace('ab','e7').replace('onboarding-','kyc-race-'))
print("SELECT 1 FROM vault.create_secret(repeat('e',40),'integration_payload_encryption_key_v1','synthetic test') WHERE NOT EXISTS(SELECT 1 FROM vault.decrypted_secrets WHERE name='integration_payload_encryption_key_v1');")
print('COMMIT;')
PY
psql_local >/dev/null <<'SQL'
INSERT INTO moneybowl_onboarding.ekyc_amcs(code,label,source_reference) VALUES('TEST','Synthetic AMC','race fixture');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','e7000000-0000-0000-0000-000000000001',false);
SELECT public.start_onboarding_kyc('e7200000-0000-0000-0000-000000000001','e7400000-0000-0000-0000-000000000001','ZZZPZ0801Z') IS NOT NULL;
SQL
race() {
 local action=$1
 local pids=()
 for n in 1 2; do
 psql_local > "$race_dir/$action-$n.log" 2>&1 <<SQL &
BEGIN;
SET LOCAL statement_timeout='20s';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','e7000000-0000-0000-0000-000000000001',true);
SELECT public.request_onboarding_kyc('e7400000-0000-0000-0000-000000000001',gen_random_uuid(),'$action','fixture@example.test','9000000000','TEST') IS NOT NULL;
SELECT pg_sleep(0.3);
COMMIT;
SQL
 pids+=("$!")
 done
 for pid in "${pids[@]}"; do wait "$pid" || { cat "$race_dir"/*.log; exit 1; }; done
}
race CHECK
# Save and Check share the identity lock. The frozen PAN remains unchanged.
psql_local > "$race_dir/save.log" 2>&1 <<'SQL' &
BEGIN;
SET LOCAL statement_timeout='20s';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','e7000000-0000-0000-0000-000000000001',true);
SELECT public.save_investor_onboarding('e7200000-0000-0000-0000-000000000001','e7400000-0000-0000-0000-000000000001',1,'{"email":"fixture@example.test"}') IS NOT NULL;
SELECT pg_sleep(0.3);
COMMIT;
SQL
saver=$!
race CHECK
wait "$saver" || { cat "$race_dir/save.log"; exit 1; }
psql_local <<'SQL'
DO $$ DECLARE claim jsonb; e uuid; BEGIN
 IF (SELECT count(*) FROM moneybowl_onboarding.kyc_operations WHERE case_id='e7400000-0000-0000-0000-000000000001')<>1 THEN RAISE EXCEPTION 'duplicate check'; END IF;
 SELECT ev.id INTO e FROM public.event_outbox ev JOIN moneybowl_onboarding.kyc_operations o ON o.id=ev.entity_id WHERE o.case_id='e7400000-0000-0000-0000-000000000001';
 claim:=public.claim_onboarding_kyc(e);
 IF (claim->>'request')::jsonb<>'{"pan_no":"ZZZPZ0801Z"}'::jsonb THEN RAISE EXCEPTION 'PAN changed during race'; END IF;
 PERFORM public.start_onboarding_kyc_call((claim->>'operation_id')::uuid,(claim->>'claim_token')::uuid,(claim->>'call_id')::uuid);
 PERFORM public.finish_onboarding_kyc_call((claim->>'operation_id')::uuid,(claim->>'claim_token')::uuid,(claim->>'call_id')::uuid,
 encode(convert_to('{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":"No record(s) found."}','UTF8'),'base64'),200,'SENT_WITH_RESULT');
END $$;
SQL
race EKYC
# Refresh racing initiation cannot create a second provider operation.
psql_local > "$race_dir/refresh.log" 2>&1 <<'SQL' &
SET statement_timeout='20s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','e7000000-0000-0000-0000-000000000001',false);
SELECT public.request_onboarding_kyc('e7400000-0000-0000-0000-000000000001',gen_random_uuid(),'REFRESH') IS NOT NULL;
SQL
refresher=$!
race EKYC
wait "$refresher" || { cat "$race_dir/refresh.log"; exit 1; }
psql_local <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM moneybowl_onboarding.kyc_operations WHERE case_id='e7400000-0000-0000-0000-000000000001' AND api='EKYCREG')<>1 THEN RAISE EXCEPTION 'duplicate eKYC'; END IF;
 IF (SELECT count(*) FROM moneybowl_onboarding.kyc_operations WHERE case_id='e7400000-0000-0000-0000-000000000001')<>2 THEN RAISE EXCEPTION 'refresh initiation overlap'; END IF;
END $$;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','e7000000-0000-0000-0000-000000000001',false);
SELECT public.save_investor_onboarding('e7200000-0000-0000-0000-000000000001','e7400000-0000-0000-0000-000000000002',0,'{"legal_name":"Race existing","pan":"ZZZPZ0802Z"}') IS NOT NULL;
SELECT public.resolve_investor_onboarding('e7400000-0000-0000-0000-000000000002',1) IS NOT NULL;
SELECT public.start_onboarding_kyc('e7200000-0000-0000-0000-000000000001',gen_random_uuid(),'ZZZPZ0802Z') IS NOT NULL;
SQL
psql_local > "$race_dir/revoke.log" 2>&1 <<'SQL' &
BEGIN;
UPDATE public.advisor_investor_assignments SET status='ended',ended_at=now() WHERE workspace_id='e7200000-0000-0000-0000-000000000001';
SELECT pg_sleep(1);
COMMIT;
SQL
revoker=$!
sleep 0.3
psql_local > "$race_dir/denied.log" 2>&1 <<'SQL'
SET statement_timeout='10s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','e7000000-0000-0000-0000-000000000001',false);
DO $$ BEGIN
 BEGIN
 PERFORM public.request_onboarding_kyc('e7400000-0000-0000-0000-000000000002',gen_random_uuid(),'CHECK');
 RAISE EXCEPTION 'revocation bypass'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SQL
wait "$revoker" || { cat "$race_dir/revoke.log"; exit 1; }
psql_local <<'SQL'
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM moneybowl_onboarding.kyc_operations WHERE case_id='e7400000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'revoked operation prepared'; END IF;
END $$;
SQL
echo 'KYC concurrency: check/check, save/check, initiate/initiate, refresh/initiate, assignment revocation PASS'
