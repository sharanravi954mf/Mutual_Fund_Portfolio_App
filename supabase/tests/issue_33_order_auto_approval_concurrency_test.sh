#!/usr/bin/env sh
set -eu

DB_CONTAINER="${SUPABASE_DB_CONTAINER:-$(docker ps --filter "name=supabase_db_" --format "{{.Names}}" | head -n 1)}"

if [ -z "${DB_CONTAINER}" ]; then
  echo "No local Supabase database container found" >&2
  exit 1
fi

PSQL="docker exec -i ${DB_CONTAINER} psql -v ON_ERROR_STOP=1 -U postgres -d postgres"
WORKDIR="$(mktemp -d)"

cleanup_db() {
  ${PSQL} <<'SQL' >/dev/null 2>&1 || true
DELETE FROM public.event_outbox WHERE entity_id = 'a33c0000-0000-4000-8000-000000000201';
DELETE FROM public.order_requests WHERE id = 'a33c0000-0000-4000-8000-000000000201';
SQL
}

cleanup() {
  cleanup_db
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

cleanup_db

${PSQL} <<'SQL' >/dev/null
INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('a33c0000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'issue33-concurrency-owner@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('a33c0000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'issue33-concurrency-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;

UPDATE public.user_accounts SET account_state = 'advisor'
WHERE user_id = 'a33c0000-0000-4000-8000-000000000001';
UPDATE public.user_accounts SET account_state = 'linked_investor'
WHERE user_id = 'a33c0000-0000-4000-8000-000000000002';

UPDATE public.profiles
SET id = 'a33c0000-0000-4000-8000-000000000101',
    role = 'advisor',
    full_name = 'Issue 33 Concurrency Owner'
WHERE user_id = 'a33c0000-0000-4000-8000-000000000001';

UPDATE public.profiles
SET id = 'a33c0000-0000-4000-8000-000000000102',
    role = 'investor',
    full_name = 'Issue 33 Concurrency Investor'
WHERE user_id = 'a33c0000-0000-4000-8000-000000000002';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES ('a33c0000-0000-4000-8000-000000000301', 'Issue 33 Concurrency Workspace', 'issue-33-concurrency-workspace', 'a33c0000-0000-4000-8000-000000000101', 'active')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    slug = EXCLUDED.slug,
    owner_profile_id = EXCLUDED.owner_profile_id,
    workspace_status = EXCLUDED.workspace_status;

DELETE FROM public.workspace_memberships
WHERE workspace_id = 'a33c0000-0000-4000-8000-000000000301';

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('a33c0000-0000-4000-8000-000000000301', 'a33c0000-0000-4000-8000-000000000101', 'admin', 'active'),
  ('a33c0000-0000-4000-8000-000000000301', 'a33c0000-0000-4000-8000-000000000102', 'investor', 'active');

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES ('a33c0000-0000-4000-8000-000000000002', 'a33c0000-0000-4000-8000-000000000102', 'verified_email', now(), 'active')
ON CONFLICT DO NOTHING;

INSERT INTO public.order_requests (
  id,
  workspace_id,
  investor_profile_id,
  initiated_by_profile_id,
  initiated_by_role,
  initiation_channel,
  scheme_code,
  type,
  amount,
  status
) VALUES (
  'a33c0000-0000-4000-8000-000000000201',
  'a33c0000-0000-4000-8000-000000000301',
  'a33c0000-0000-4000-8000-000000000102',
  'a33c0000-0000-4000-8000-000000000102',
  'investor',
  'investor_portal',
  'SCH33-CONCURRENT',
  'buy',
  1000.00,
  'pending_qualification'
);
SQL

EVENT_ID="$(${PSQL} <<'SQL' | grep -Eo '[0-9a-f-]{36}' | head -n 1
\pset tuples_only on
\pset format unaligned
SELECT id FROM public.event_outbox WHERE entity_id = 'a33c0000-0000-4000-8000-000000000201';
SQL
)"

cat > "${WORKDIR}/left.sql" <<SQL
\\pset tuples_only on
\\pset format unaligned
SET statement_timeout = '10s';
SET lock_timeout = '5s';
SET ROLE service_role;
BEGIN;
SELECT claim_state || ':' || event_outbox_id::text || ':' || attempt::text
FROM public.claim_order_auto_approval_event(
  'a33c0000-0000-4000-8000-000000000401',
  '${EVENT_ID}',
  3
);
SELECT pg_sleep(2);
COMMIT;
SQL

cat > "${WORKDIR}/right.sql" <<SQL
\\pset tuples_only on
\\pset format unaligned
SET statement_timeout = '10s';
SET lock_timeout = '5s';
SET ROLE service_role;
SELECT claim_state || ':' || event_outbox_id::text || ':' || attempt::text
FROM public.claim_order_auto_approval_event(
  'a33c0000-0000-4000-8000-000000000402',
  '${EVENT_ID}',
  3
);
SQL

${PSQL} < "${WORKDIR}/left.sql" > "${WORKDIR}/left.out" 2>&1 &
LEFT_PID=$!
sleep 0.2
${PSQL} < "${WORKDIR}/right.sql" > "${WORKDIR}/right.out" 2>&1 &
RIGHT_PID=$!

wait "${LEFT_PID}"
wait "${RIGHT_PID}"

if ! grep -q "newly_claimed:${EVENT_ID}:1" "${WORKDIR}/left.out" "${WORKDIR}/right.out"; then
  echo "Issue #33 concurrency: expected one newly_claimed result" >&2
  cat "${WORKDIR}/left.out" >&2
  cat "${WORKDIR}/right.out" >&2
  exit 1
fi

if ! grep -q "active_in_progress:${EVENT_ID}:1" "${WORKDIR}/left.out" "${WORKDIR}/right.out"; then
  echo "Issue #33 concurrency: expected one active_in_progress result" >&2
  cat "${WORKDIR}/left.out" >&2
  cat "${WORKDIR}/right.out" >&2
  exit 1
fi

COUNT="$(${PSQL} <<SQL | grep -E '^[0-9]+:(processing|pending|failed|completed)$' | head -n 1
\\pset tuples_only on
\\pset format unaligned
SELECT retry_count::text || ':' || status
FROM public.event_outbox
WHERE id = '${EVENT_ID}';
SQL
)"

if [ "${COUNT}" != "1:processing" ]; then
  echo "Issue #33 concurrency: expected one durable processing claim, got ${COUNT}" >&2
  exit 1
fi

echo "Issue #33 concurrency claim protection passed"
