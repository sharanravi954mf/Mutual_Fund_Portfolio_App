#!/usr/bin/env sh
set -eu

DB_CONTAINER="${SUPABASE_DB_CONTAINER:-$(docker ps --filter "name=supabase_db_" --format "{{.Names}}" | head -n 1)}"

if [ -z "${DB_CONTAINER}" ]; then
  echo "No local Supabase database container found" >&2
  exit 1
fi

PSQL="docker exec -i ${DB_CONTAINER} psql -v ON_ERROR_STOP=1 -U postgres -d postgres"
WORKDIR="$(mktemp -d)"
PAYMENT_ID="issue39-concurrent-payment-001"
SUBSCRIPTION_ID="39c00000-0000-4000-8000-000000000201"
PROFILE_ID="39c00000-0000-4000-8000-000000000101"
PLAN_ID="39c00000-0000-4000-8000-000000000301"
USER_ID="39c00000-0000-4000-8000-000000000001"

cleanup_db() {
  ${PSQL} <<SQL >/dev/null 2>&1 || true
DELETE FROM public.investor_subscription_audit_logs
WHERE investor_subscription_id = '${SUBSCRIPTION_ID}';
DELETE FROM public.payment_events
WHERE investor_subscription_id = '${SUBSCRIPTION_ID}' OR payment_id = '${PAYMENT_ID}';
DELETE FROM public.investor_subscriptions WHERE id = '${SUBSCRIPTION_ID}';
DELETE FROM public.investor_account_links WHERE profile_id = '${PROFILE_ID}';
DELETE FROM public.subscription_plans WHERE id = '${PLAN_ID}';
DELETE FROM auth.users WHERE id = '${USER_ID}';
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
) VALUES (
  '${USER_ID}', 'authenticated', 'authenticated',
  'issue39-concurrency-investor@moneybowl.test', '{}', '{"role":"user"}', now(), now()
);

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id = '${USER_ID}';

UPDATE public.profiles
SET id = '${PROFILE_ID}', role = 'investor', full_name = 'Issue 39 Concurrency Investor'
WHERE user_id = '${USER_ID}';

INSERT INTO public.investor_account_links (
  user_id, profile_id, verification_method, verified_at, link_status
) VALUES ('${USER_ID}', '${PROFILE_ID}', 'verified_email', now(), 'active');

INSERT INTO public.subscription_plans (id, name, client_limit, monthly_price)
VALUES ('${PLAN_ID}', 'Issue 39 Concurrency Plan', 1, 199.00);

INSERT INTO public.investor_subscriptions (
  id, investor_profile_id, plan_id
) VALUES ('${SUBSCRIPTION_ID}', '${PROFILE_ID}', '${PLAN_ID}');
SQL

cat > "${WORKDIR}/holder.sql" <<SQL
SET statement_timeout = '15s';
BEGIN;
SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('${PAYMENT_ID}', 0)
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
SET ROLE service_role;
SELECT replayed::text
FROM public.process_investor_subscription_payment(
  '${SUBSCRIPTION_ID}',
  '${PAYMENT_ID}',
  199.00,
  'succeeded',
  'active',
  'concurrent payment capture'
);
SQL
}

write_delivery "${WORKDIR}/left.sql"
write_delivery "${WORKDIR}/right.sql"

# Hold the processor's advisory key, start two independent deliveries while
# both are blocked behind it, then release them into the same lock race.
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
  echo "Issue #39 concurrency: expected one first application and one replay" >&2
  cat "${WORKDIR}/left.out" >&2
  cat "${WORKDIR}/right.out" >&2
  exit 1
fi

COUNTS="$(${PSQL} <<SQL | grep -E '^[0-9]+:[0-9]+:active$' | head -n 1
\pset tuples_only on
\pset format unaligned
SELECT
  (SELECT count(*) FROM public.payment_events WHERE payment_id = '${PAYMENT_ID}')::text
  || ':' ||
  (SELECT count(*) FROM public.investor_subscription_audit_logs WHERE investor_subscription_id = '${SUBSCRIPTION_ID}')::text
  || ':' ||
  (SELECT status FROM public.investor_subscriptions WHERE id = '${SUBSCRIPTION_ID}');
SQL
)"

if [ "${COUNTS}" != "1:1:active" ]; then
  echo "Issue #39 concurrency: expected one payment, one audit, and one lifecycle transition; got ${COUNTS}" >&2
  exit 1
fi

echo "Issue #39 concurrent duplicate payment protection passed"
