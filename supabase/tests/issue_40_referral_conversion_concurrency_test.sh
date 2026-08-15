#!/usr/bin/env sh
set -eu

DB_CONTAINER="${SUPABASE_DB_CONTAINER:-$(docker ps --filter "name=supabase_db_" --format "{{.Names}}" | head -n 1)}"

if [ -z "${DB_CONTAINER}" ]; then
  echo "No local Supabase database container found" >&2
  exit 1
fi

PSQL="docker exec -i ${DB_CONTAINER} psql -v ON_ERROR_STOP=1 -U postgres -d postgres"
WORKDIR="$(mktemp -d)"
REFERRER_USER_ID="40c00000-0000-4000-8000-000000000001"
REFEREE_USER_ID="40c00000-0000-4000-8000-000000000002"
REFERRER_PROFILE_ID="40c00000-0000-4000-8000-000000000101"
REFEREE_PROFILE_ID="40c00000-0000-4000-8000-000000000102"

cleanup_db() {
  ${PSQL} <<SQL >/dev/null 2>&1 || true
BEGIN;
-- The production audit trigger is deliberately immutable. The local test
-- harness is a database superuser and temporarily disables only that trigger
-- inside this cleanup transaction so repeated test runs leave no fixtures.
ALTER TABLE public.referral_reward_audit_logs
  DISABLE TRIGGER referral_reward_audit_immutable;
DELETE FROM public.referral_reward_audit_logs
WHERE profile_id IN ('${REFERRER_PROFILE_ID}', '${REFEREE_PROFILE_ID}');
ALTER TABLE public.referral_reward_audit_logs
  ENABLE TRIGGER referral_reward_audit_immutable;
DELETE FROM public.referral_rewards
WHERE profile_id IN ('${REFERRER_PROFILE_ID}', '${REFEREE_PROFILE_ID}');
DELETE FROM public.referral_onboarding_claims
WHERE bound_user_id = '${REFEREE_USER_ID}'
   OR referral_id IN (
     SELECT id FROM public.investor_referrals
     WHERE referrer_profile_id = '${REFERRER_PROFILE_ID}'
   );
DELETE FROM public.referral_conversions
WHERE referee_profile_id = '${REFEREE_PROFILE_ID}';
DELETE FROM public.investor_referrals
WHERE referrer_profile_id = '${REFERRER_PROFILE_ID}';
DELETE FROM public.investor_account_links
WHERE profile_id IN ('${REFERRER_PROFILE_ID}', '${REFEREE_PROFILE_ID}');
DELETE FROM public.workspaces
WHERE owner_profile_id IN ('${REFERRER_PROFILE_ID}', '${REFEREE_PROFILE_ID}');
DELETE FROM auth.users
WHERE id IN ('${REFERRER_USER_ID}', '${REFEREE_USER_ID}');
COMMIT;
SQL
}

cleanup() {
  cleanup_db
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

cleanup_db

${PSQL} <<SQL >/dev/null
INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('${REFERRER_USER_ID}', 'authenticated', 'authenticated', 'issue40-concurrent-referrer@moneybowl.test', '{}', '{"role":"user"}', now(), now());

UPDATE public.user_accounts SET account_state = 'linked_investor'
WHERE user_id = '${REFERRER_USER_ID}';
UPDATE public.profiles SET id = '${REFERRER_PROFILE_ID}', role = 'investor', account_status = 'active'
WHERE user_id = '${REFERRER_USER_ID}';

INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES
  ('${REFERRER_USER_ID}', '${REFERRER_PROFILE_ID}', 'verified_email', now(), 'active');
SQL

REFERRAL_CODE="$(${PSQL} <<SQL | grep -E '^[0-9a-f]{48}$' | head -n 1
\pset tuples_only on
\pset format unaligned
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"${REFERRER_USER_ID}","role":"authenticated"}',
  false
);
SET ROLE authenticated;
SELECT referral_code FROM public.get_or_create_investor_referral();
SQL
)"

if [ -z "${REFERRAL_CODE}" ]; then
  echo "Issue #40 concurrency: failed to create referral code" >&2
  exit 1
fi

CLAIM_TOKEN="$(${PSQL} <<SQL | grep -E '^[0-9a-f]{64}$' | head -n 1
\pset tuples_only on
\pset format unaligned
SET ROLE anon;
SELECT claim_token
FROM public.create_referral_onboarding_claim('${REFERRAL_CODE}');
SQL
)"

if [ -z "${CLAIM_TOKEN}" ]; then
  echo "Issue #40 concurrency: failed to create pre-auth onboarding claim" >&2
  exit 1
fi

# The referred Auth account is created only after the server captured the
# claim, matching the production /join -> signup lifecycle.
${PSQL} <<SQL >/dev/null
INSERT INTO auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES (
  '${REFEREE_USER_ID}', 'authenticated', 'authenticated',
  'issue40-concurrent-referee@moneybowl.test', '{}', '{"role":"user"}', now(), now()
);
UPDATE public.user_accounts SET account_state = 'linked_investor'
WHERE user_id = '${REFEREE_USER_ID}';
UPDATE public.profiles SET id = '${REFEREE_PROFILE_ID}', role = 'investor', account_status = 'active'
WHERE user_id = '${REFEREE_USER_ID}';
INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES (
  '${REFEREE_USER_ID}', '${REFEREE_PROFILE_ID}', 'verified_email', now(), 'active'
);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"${REFEREE_USER_ID}","role":"authenticated"}',
  false
);
SET ROLE authenticated;
SELECT * FROM public.bind_referral_onboarding_claim('${CLAIM_TOKEN}');
SQL

cat > "${WORKDIR}/holder.sql" <<SQL
SET statement_timeout = '15s';
BEGIN;
SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended(
    'referral-claim:' || pg_catalog.encode(
      extensions.digest('${CLAIM_TOKEN}', 'sha256'), 'hex'
    ),
    0
  )
);
SELECT pg_catalog.pg_sleep(2);
COMMIT;
SQL

write_delivery() {
  output_file="$1"
  cat > "${output_file}" <<SQL
\pset tuples_only on
\pset format unaligned
SET statement_timeout = '15s';
SET lock_timeout = '10s';
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"${REFEREE_USER_ID}","role":"authenticated"}',
  false
);
SET ROLE authenticated;
SELECT replayed::text
FROM public.process_investor_referral_conversion('${CLAIM_TOKEN}');
SQL
}

write_delivery "${WORKDIR}/left.sql"
write_delivery "${WORKDIR}/right.sql"

# Hold the processor's server-claim-derived key. Two independent sessions queue
# behind it and enter the same race when the holder commits.
${PSQL} < "${WORKDIR}/holder.sql" > "${WORKDIR}/holder.out" 2>&1 &
HOLDER_PID=$!
sleep 0.3
${PSQL} < "${WORKDIR}/left.sql" > "${WORKDIR}/left.out" 2>&1 &
LEFT_PID=$!
${PSQL} < "${WORKDIR}/right.sql" > "${WORKDIR}/right.out" 2>&1 &
RIGHT_PID=$!

wait "${HOLDER_PID}"
wait "${LEFT_PID}"
wait "${RIGHT_PID}"

if [ "$(grep -hE '^(true|false)$' "${WORKDIR}/left.out" "${WORKDIR}/right.out" | sort | tr '\n' ':' )" != "false:true:" ]; then
  echo "Issue #40 concurrency: expected one application and one replay" >&2
  cat "${WORKDIR}/left.out" >&2
  cat "${WORKDIR}/right.out" >&2
  exit 1
fi

COUNTS="$(${PSQL} <<SQL | grep -E '^[0-9]+:[0-9]+:[0-9]+$' | head -n 1
\pset tuples_only on
\pset format unaligned
SELECT
  (SELECT count(*) FROM public.referral_conversions WHERE referee_profile_id = '${REFEREE_PROFILE_ID}')::text
  || ':' ||
  (SELECT count(*) FROM public.referral_rewards WHERE profile_id IN ('${REFERRER_PROFILE_ID}', '${REFEREE_PROFILE_ID}'))::text
  || ':' ||
  (SELECT count(*) FROM public.referral_reward_audit_logs WHERE profile_id IN ('${REFERRER_PROFILE_ID}', '${REFEREE_PROFILE_ID}'))::text;
SQL
)"

if [ "${COUNTS}" != "1:2:2" ]; then
  echo "Issue #40 concurrency: expected one conversion and one entitlement/audit per participant; got ${COUNTS}" >&2
  exit 1
fi

check_entitlement() {
  user_id="$1"
  result="$(${PSQL} <<SQL | grep -E '^(true|false)$' | head -n 1
\pset tuples_only on
\pset format unaligned
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"${user_id}","role":"authenticated"}',
  false
);
SET ROLE authenticated;
SELECT public.has_investor_entitlement('family_hub_enabled')::text;
SQL
)"
  if [ "${result}" != "true" ]; then
    echo "Issue #40 concurrency: reward did not authorize Premium entitlement for ${user_id}" >&2
    exit 1
  fi
}

check_entitlement "${REFERRER_USER_ID}"
check_entitlement "${REFEREE_USER_ID}"

echo "Issue #40 concurrent duplicate referral conversion protection passed"
