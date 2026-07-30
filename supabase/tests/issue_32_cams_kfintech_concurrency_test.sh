#!/usr/bin/env sh
set -eu

SCENARIOS=18
DB_CONTAINER="${SUPABASE_DB_CONTAINER:-$(docker ps --filter "name=supabase_db_" --format "{{.Names}}" | head -n 1)}"

if [ -z "${DB_CONTAINER}" ]; then
  echo "No local Supabase database container found" >&2
  exit 1
fi

PSQL="docker exec -i ${DB_CONTAINER} psql -v ON_ERROR_STOP=1 -U postgres -d postgres"
WORKDIR="$(mktemp -d)"
cleanup() {
  docker exec -i "${DB_CONTAINER}" psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL' >/dev/null 2>&1 || true
DROP TRIGGER IF EXISTS issue32_concurrency_sleep_before_document_insert ON public.ingested_documents;
DROP FUNCTION IF EXISTS public.issue32_concurrency_sleep_trigger();
SQL
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

run_psql() {
  ${PSQL}
}

write_persist_sql() {
  file="$1"
  correlation_id="$2"
  message_id="$3"
  attachment_id="$4"
  attempt_key="$5"
  sha_char="$6"
  folio="$7"
  registrar_txn_id="$8"
  source_row="$9"
  run_id="${10:-94900000-0000-0000-0000-000000000001}"
  cat > "${file}" <<SQL
\\pset tuples_only on
\\pset format unaligned
SET statement_timeout = '10s';
SET lock_timeout = '5s';
SET ROLE service_role;
BEGIN;
SET LOCAL moneybowl.issue32_concurrency_sleep = 'on';
SELECT public.claim_cams_kfintech_ingestion_run(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '${run_id}',
  'CAMS'
);
SELECT idempotent
FROM public.persist_cams_kfintech_statement_ingestion(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '${run_id}',
  '${correlation_id}',
  '${message_id}',
  '${attachment_id}',
  '${attempt_key}',
  'CAMS',
  repeat('${sha_char}', 64),
  'ingested-documents',
  'concurrency/${sha_char}',
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
    'registrar', 'CAMS',
    'clientPan', 'ABCDE1234F',
    'investorName', 'Issue 32 Concurrent Investor',
    'folioNumber', '${folio}',
    'schemeCode', 'MF32CON',
    'schemeName', 'Issue 32 Concurrency Fund',
    'fundHouse', 'Money Bowl AMC',
    'category', 'Equity',
    'transactionType', 'BUY',
    'transactionDirection', 'INFLOW',
    'registrarTransactionCode', 'BUY',
    'units', 1,
    'nav', 10,
    'amount', 10,
    'date', '2026-07-29',
    'sourceRowNumber', ${source_row},
    'registrarTransactionId', '${registrar_txn_id}'
  ))
);
COMMIT;
SQL
}

write_failure_sql() {
  file="$1"
  correlation_id="$2"
  cat > "${file}" <<SQL
\\pset tuples_only on
\\pset format unaligned
SET statement_timeout = '10s';
SET lock_timeout = '5s';
SET ROLE service_role;
BEGIN;
SET LOCAL moneybowl.issue32_concurrency_sleep = 'on';
SELECT public.claim_cams_kfintech_ingestion_run(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '94900000-0000-0000-0000-000000000001',
  'CAMS'
);
SELECT public.record_cams_kfintech_ingestion_failure(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '94900000-0000-0000-0000-000000000001',
  '${correlation_id}',
  'concurrent-failure-message',
  'concurrent-failure-attachment',
  'concurrent-failure-attempt',
  'CAMS',
  'malware_detected',
  repeat('f', 64),
  'ingested-documents',
  'concurrency/failure',
  'application/x-dbase',
  'DBF',
  1024
);
COMMIT;
SQL
}

write_custom_failure_sql() {
  file="$1"
  run_id="$2"
  correlation_id="$3"
  message_id="$4"
  attachment_id="$5"
  attempt_key="$6"
  sha_char="$7"
  failure_code="$8"
  cat > "${file}" <<SQL
\\pset tuples_only on
\\pset format unaligned
SET statement_timeout = '10s';
SET lock_timeout = '5s';
SET ROLE service_role;
BEGIN;
SET LOCAL moneybowl.issue32_concurrency_sleep = 'on';
SELECT public.claim_cams_kfintech_ingestion_run(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '${run_id}',
  'CAMS'
);
SELECT public.record_cams_kfintech_ingestion_failure(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '${run_id}',
  '${correlation_id}',
  '${message_id}',
  '${attachment_id}',
  '${attempt_key}',
  'CAMS',
  '${failure_code}',
  repeat('${sha_char}', 64),
  'ingested-documents',
  'concurrency/${sha_char}',
  'application/x-dbase',
  'DBF',
  1024
);
COMMIT;
SQL
}

write_unclaimed_persist_sql() {
  file="$1"
  cat > "${file}" <<SQL
\\pset tuples_only on
\\pset format unaligned
SET statement_timeout = '10s';
SET lock_timeout = '5s';
SET ROLE service_role;
BEGIN;
SELECT idempotent
FROM public.persist_cams_kfintech_statement_ingestion(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '94900000-0000-0000-0000-000000000911',
  '94900000-0000-0000-0000-000000000911',
  's11-message',
  's11-attachment',
  's11-attempt',
  'CAMS',
  repeat('e', 64),
  'ingested-documents',
  'concurrency/unclaimed',
  'application/x-dbase',
  'DBF',
  1024,
  '2026-07-29T00:00:00Z',
  pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
    'registrar', 'CAMS',
    'clientPan', 'ABCDE1234F',
    'investorName', 'Issue 32 Concurrent Investor',
    'folioNumber', 'CON-FOLIO-11',
    'schemeCode', 'MF32CON',
    'fundHouse', 'Money Bowl AMC',
    'transactionType', 'BUY',
    'transactionDirection', 'INFLOW',
    'registrarTransactionCode', 'BUY',
    'units', 1,
    'nav', 10,
    'amount', 10,
    'date', '2026-07-29',
    'sourceRowNumber', 1,
    'registrarTransactionId', 'CON-TXN-11'
  ))
);
COMMIT;
SQL
}

write_finalize_sql() {
  file="$1"
  run_id="$2"
  stopped_reason="$3"
  failure_code="$4"
  observed_count="${5:-NULL}"
  cat > "${file}" <<SQL
\\pset tuples_only on
\\pset format unaligned
SET statement_timeout = '10s';
SET lock_timeout = '5s';
SET ROLE service_role;
BEGIN;
SELECT status
FROM public.finalize_cams_kfintech_ingestion_run(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '${run_id}',
  'CAMS',
  ${stopped_reason},
  ${failure_code},
  ${observed_count}
);
COMMIT;
SQL
}

run_pair() {
  name="$1"
  left_sql="$2"
  right_sql="$3"
  left_out="${WORKDIR}/${name}.left.out"
  right_out="${WORKDIR}/${name}.right.out"

  set +e
  docker exec -i "${DB_CONTAINER}" psql -v ON_ERROR_STOP=1 -U postgres -d postgres < "${left_sql}" > "${left_out}" 2>&1 &
  left_pid="$!"
  docker exec -i "${DB_CONTAINER}" psql -v ON_ERROR_STOP=1 -U postgres -d postgres < "${right_sql}" > "${right_out}" 2>&1 &
  right_pid="$!"
  (sleep 20; kill "${left_pid}" "${right_pid}" 2>/dev/null || true) &
  watchdog_pid="$!"
  wait "${left_pid}"
  left_status="$?"
  wait "${right_pid}"
  right_status="$?"
  kill "${watchdog_pid}" 2>/dev/null || true
  wait "${watchdog_pid}" 2>/dev/null || true
  set -e

  echo "${left_status}" > "${WORKDIR}/${name}.left.status"
  echo "${right_status}" > "${WORKDIR}/${name}.right.status"
}

one_success_one_conflict() {
  name="$1"
  left_status="$(cat "${WORKDIR}/${name}.left.status")"
  right_status="$(cat "${WORKDIR}/${name}.right.status")"
  if [ "${left_status}:${right_status}" = "0:0" ] || [ "${left_status}:${right_status}" != "0:3" ] && [ "${left_status}:${right_status}" != "3:0" ]; then
    echo "${name}: expected exactly one successful psql session and one conflict" >&2
    cat "${WORKDIR}/${name}.left.out" >&2
    cat "${WORKDIR}/${name}.right.out" >&2
    exit 1
  fi
  if ! grep -qE "attachment_hash_mismatch|correlation_conflict|duplicate_attachment|persistence_conflict|ingestion_run_finalized" "${WORKDIR}/${name}.left.out" "${WORKDIR}/${name}.right.out"; then
    echo "${name}: expected stable conflict code" >&2
    exit 1
  fi
}

success_or_processing_incomplete() {
  name="$1"
  for side in left right; do
    status="$(cat "${WORKDIR}/${name}.${side}.status")"
    if [ "${status}" != "0" ] && ! grep -q "processing_incomplete" "${WORKDIR}/${name}.${side}.out"; then
      echo "${name}: ${side} session failed without processing_incomplete" >&2
      cat "${WORKDIR}/${name}.left.out" >&2
      cat "${WORKDIR}/${name}.right.out" >&2
      exit 1
    fi
  done
  if [ "$(cat "${WORKDIR}/${name}.left.status")" != "0" ] && [ "$(cat "${WORKDIR}/${name}.right.status")" != "0" ]; then
    echo "${name}: expected at least one session to succeed" >&2
    cat "${WORKDIR}/${name}.left.out" >&2
    cat "${WORKDIR}/${name}.right.out" >&2
    exit 1
  fi
}

both_fail_with_code() {
  name="$1"
  code="$2"
  if [ "$(cat "${WORKDIR}/${name}.left.status")" = "0" ] || [ "$(cat "${WORKDIR}/${name}.right.status")" = "0" ]; then
    echo "${name}: expected both psql sessions to fail" >&2
    cat "${WORKDIR}/${name}.left.out" >&2
    cat "${WORKDIR}/${name}.right.out" >&2
    exit 1
  fi
  if ! grep -q "${code}" "${WORKDIR}/${name}.left.out" || ! grep -q "${code}" "${WORKDIR}/${name}.right.out"; then
    echo "${name}: expected both failures to include ${code}" >&2
    exit 1
  fi
}

both_success() {
  name="$1"
  if [ "$(cat "${WORKDIR}/${name}.left.status")" != "0" ] || [ "$(cat "${WORKDIR}/${name}.right.status")" != "0" ]; then
    echo "${name}: expected both psql sessions to succeed" >&2
    cat "${WORKDIR}/${name}.left.out" >&2
    cat "${WORKDIR}/${name}.right.out" >&2
    exit 1
  fi
}

assert_sql() {
  run_psql <<SQL
$1
SQL
}

write_claim_sql() {
  file="$1"
  workspace_id="$2"
  mailbox_id="$3"
  run_id="$4"
  registrar="$5"
  cat > "${file}" <<SQL
\\pset tuples_only on
\\pset format unaligned
SET ROLE service_role;
BEGIN;
SELECT public.claim_cams_kfintech_ingestion_run(
  '${workspace_id}',
  '${mailbox_id}',
  '${run_id}',
  '${registrar}'
);
COMMIT;
SQL
}

run_psql <<'SQL'
DROP TRIGGER IF EXISTS issue32_concurrency_sleep_before_document_insert ON public.ingested_documents;
DROP FUNCTION IF EXISTS public.issue32_concurrency_sleep_trigger();

ALTER TABLE public.ingestion_logs DISABLE TRIGGER enforce_ingestion_logs_immutability;
ALTER TABLE public.cams_kfintech_ingestion_attempts DISABLE TRIGGER enforce_cams_kfintech_ingestion_attempts_immutability;
DELETE FROM public.cams_kfintech_ingestion_attempts
WHERE workspace_id = '94400000-0000-0000-0000-000000000001';
DELETE FROM public.event_outbox AS event
USING public.ingested_documents AS document
WHERE event.entity_type = 'ingested_document'
  AND event.entity_id = document.id
  AND document.workspace_id = '94400000-0000-0000-0000-000000000001';
DELETE FROM public.transactions
WHERE registrar_transaction_id LIKE 'CON-TXN-%'
   OR source_document_id IN (
     SELECT id FROM public.ingested_documents
     WHERE workspace_id = '94400000-0000-0000-0000-000000000001'
   );
DELETE FROM public.ingestion_logs
WHERE workspace_id = '94400000-0000-0000-0000-000000000001';
DELETE FROM public.ingested_documents
WHERE workspace_id = '94400000-0000-0000-0000-000000000001';
DELETE FROM public.cams_kfintech_ingestion_runs
WHERE workspace_id = '94400000-0000-0000-0000-000000000001'
   OR ingestion_run_id IN (
     '94900000-0000-0000-0000-000000000901',
     '94900000-0000-0000-0000-000000000902'
   );
DELETE FROM public.portfolio_folio_references AS mapping
USING public.folio_references AS folio
WHERE folio.id = mapping.folio_reference_id
  AND folio.registrar = 'CAMS'
  AND folio.normalized_folio_number LIKE 'CONFOLIO%';
DELETE FROM public.folio_references
WHERE registrar = 'CAMS'
  AND normalized_folio_number LIKE 'CONFOLIO%';
ALTER TABLE public.cams_kfintech_ingestion_attempts ENABLE TRIGGER enforce_cams_kfintech_ingestion_attempts_immutability;
ALTER TABLE public.ingestion_logs ENABLE TRIGGER enforce_ingestion_logs_immutability;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('94200000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue32-concurrency-owner@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('94200000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue32-concurrency-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;

UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id = '94200000-0000-0000-0000-000000000001';
UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id = '94200000-0000-0000-0000-000000000002';
UPDATE public.profiles
SET id = '94300000-0000-0000-0000-000000000001', role = 'advisor', full_name = 'Issue 32 Concurrency Owner'
WHERE user_id = '94200000-0000-0000-0000-000000000001';
UPDATE public.profiles
SET id = '94300000-0000-0000-0000-000000000002', role = 'investor', full_name = 'Issue 32 Concurrency Investor'
WHERE user_id = '94200000-0000-0000-0000-000000000002';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES ('94400000-0000-0000-0000-000000000001', 'Issue 32 Concurrency Workspace', 'issue-32-concurrency-workspace', '94300000-0000-0000-0000-000000000001', 'active')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES ('94400000-0000-0000-0000-000000000002', 'Issue 32 Concurrency Workspace B', 'issue-32-concurrency-workspace-b', '94300000-0000-0000-0000-000000000001', 'active')
ON CONFLICT (id) DO NOTHING;

DELETE FROM public.workspace_memberships
WHERE profile_id IN ('94300000-0000-0000-0000-000000000001', '94300000-0000-0000-0000-000000000002');
INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('94400000-0000-0000-0000-000000000001', '94300000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('94400000-0000-0000-0000-000000000001', '94300000-0000-0000-0000-000000000002', 'investor', 'active');

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES ('94200000-0000-0000-0000-000000000002', '94300000-0000-0000-0000-000000000002', 'verified_email', now(), 'active')
ON CONFLICT DO NOTHING;

INSERT INTO public.profile_pan_records (
  id,
  profile_id,
  pan_ciphertext,
  pan_lookup_hmac,
  masked_pan,
  source,
  source_system,
  status,
  verified_at
) VALUES (
  '94210000-0000-0000-0000-000000000001',
  '94300000-0000-0000-0000-000000000002',
  extensions.pgp_sym_encrypt('ABCDE1234F', public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
  extensions.hmac('ABCDE1234F', public.pan_lookup_hmac_key(), 'sha256'),
  public.mask_pan('ABCDE1234F'),
  'INVESTOR',
  'MANUAL',
  'VERIFIED',
  now()
) ON CONFLICT (id) DO NOTHING;

UPDATE public.profiles
SET canonical_pan_record_id = '94210000-0000-0000-0000-000000000001'
WHERE id = '94300000-0000-0000-0000-000000000002';

INSERT INTO public.registrar_configs (
  id,
  workspace_id,
  registrar,
  allowed_sender_addresses,
  max_attachment_bytes,
  max_messages_per_poll,
  max_attachments_per_message,
  max_attachments_per_run,
  total_bytes_per_run,
  supported_file_types,
  is_active
) VALUES (
  '94600000-0000-0000-0000-000000000001',
  '94400000-0000-0000-0000-000000000001',
  'CAMS',
  ARRAY['concurrency@camsonline.com'],
  1024,
  10,
  2,
  10,
  4096,
  ARRAY['DBF'],
  true
) ON CONFLICT (workspace_id, registrar) DO NOTHING;

INSERT INTO public.mailbox_connections (
  id,
  workspace_id,
  registrar,
  mailbox_address,
  connector_ref,
  oauth_provider,
  allowed_sender_addresses,
  status
) VALUES (
  '94700000-0000-0000-0000-000000000001',
  '94400000-0000-0000-0000-000000000001',
  'CAMS',
  'concurrency-owner@moneybowl.test',
  'issue-32-concurrency-connector',
  'gmail',
  ARRAY['concurrency@camsonline.com'],
  'active'
) ON CONFLICT (workspace_id, connector_ref) DO NOTHING;

INSERT INTO public.mailbox_connections (
  id,
  workspace_id,
  registrar,
  mailbox_address,
  connector_ref,
  oauth_provider,
  allowed_sender_addresses,
  status
) VALUES (
  '94700000-0000-0000-0000-000000000002',
  '94400000-0000-0000-0000-000000000002',
  'CAMS',
  'concurrency-owner-b@moneybowl.test',
  'issue-32-concurrency-connector-b',
  'gmail',
  ARRAY['concurrency@camsonline.com'],
  'active'
) ON CONFLICT (workspace_id, connector_ref) DO NOTHING;

INSERT INTO public.mailbox_oauth_credentials (
  id,
  mailbox_connection_id,
  workspace_id,
  credential_ciphertext,
  credential_nonce,
  key_version,
  expires_at
) VALUES (
  '94800000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '94400000-0000-0000-0000-000000000001',
  encode('ciphertext-concurrency'::bytea, 'base64'),
  encode(repeat('q', 12)::bytea, 'base64'),
  1,
  now() + interval '1 hour'
) ON CONFLICT (mailbox_connection_id) DO NOTHING;

INSERT INTO public.mutual_funds (scheme_code, scheme_name, fund_house, category, current_nav, nav_date)
VALUES ('MF32CON', 'Issue 32 Concurrency Fund', 'Money Bowl AMC', 'Equity', 50.0000, '2026-07-29')
ON CONFLICT (scheme_code) DO UPDATE SET scheme_name = EXCLUDED.scheme_name;

CREATE OR REPLACE FUNCTION public.issue32_concurrency_sleep_trigger()
RETURNS pg_catalog.trigger AS $$
BEGIN
  IF current_setting('moneybowl.issue32_concurrency_sleep', true) = 'on' THEN
    PERFORM pg_catalog.pg_sleep(0.75);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS issue32_concurrency_sleep_before_document_insert ON public.ingested_documents;
CREATE TRIGGER issue32_concurrency_sleep_before_document_insert
  BEFORE INSERT ON public.ingested_documents
  FOR EACH ROW EXECUTE FUNCTION public.issue32_concurrency_sleep_trigger();
SQL

write_persist_sql "${WORKDIR}/s1a.sql" "94900000-0000-0000-0000-000000000101" "s1-message" "s1-attachment" "s1-attempt" "1" "CON-FOLIO-1" "CON-TXN-1" 1
write_persist_sql "${WORKDIR}/s1b.sql" "94900000-0000-0000-0000-000000000101" "s1-message" "s1-attachment" "s1-attempt" "1" "CON-FOLIO-1" "CON-TXN-1" 1
run_pair "scenario1_identical_attachment" "${WORKDIR}/s1a.sql" "${WORKDIR}/s1b.sql"
both_success "scenario1_identical_attachment"
if ! grep -q '^t$' "${WORKDIR}/scenario1_identical_attachment.left.out" "${WORKDIR}/scenario1_identical_attachment.right.out"; then
  echo "scenario1_identical_attachment: expected one idempotent retry result" >&2
  exit 1
fi
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.ingested_documents WHERE correlation_id = '94900000-0000-0000-0000-000000000101' AND processing_status = 'completed';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario1 document count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.transactions WHERE registrar_transaction_id = 'CON-TXN-1';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario1 transaction count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.ingestion_logs WHERE correlation_id = '94900000-0000-0000-0000-000000000101' AND status = 'SUCCESS';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario1 success log count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.event_outbox e JOIN public.ingested_documents d ON d.id = e.entity_id WHERE d.correlation_id = '94900000-0000-0000-0000-000000000101' AND e.event_type = 'statement.imported';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario1 event count %', v_count; END IF;
END \$\$;"

write_persist_sql "${WORKDIR}/s2a.sql" "94900000-0000-0000-0000-000000000201" "s2-message-a" "s2-attachment-a" "s2-attempt-a" "2" "CON-FOLIO-2" "CON-TXN-2A" 1
write_persist_sql "${WORKDIR}/s2b.sql" "94900000-0000-0000-0000-000000000201" "s2-message-b" "s2-attachment-b" "s2-attempt-b" "3" "CON-FOLIO-2" "CON-TXN-2B" 1
run_pair "scenario2_conflicting_binding" "${WORKDIR}/s2a.sql" "${WORKDIR}/s2b.sql"
one_success_one_conflict "scenario2_conflicting_binding"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.ingested_documents WHERE correlation_id = '94900000-0000-0000-0000-000000000201';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario2 document count %', v_count; END IF;
END \$\$;"

write_failure_sql "${WORKDIR}/s3a.sql" "94900000-0000-0000-0000-000000000301"
write_failure_sql "${WORKDIR}/s3b.sql" "94900000-0000-0000-0000-000000000301"
run_pair "scenario3_identical_failure" "${WORKDIR}/s3a.sql" "${WORKDIR}/s3b.sql"
both_success "scenario3_identical_failure"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.ingestion_logs WHERE attachment_attempt_key = 'concurrent-failure-attempt' AND failure_code = 'malware_detected';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario3 failure log count %', v_count; END IF;
END \$\$;"

write_persist_sql "${WORKDIR}/s4a.sql" "94900000-0000-0000-0000-000000000401" "s4-message-a" "s4-attachment-a" "s4-attempt-a" "4" "CON-FOLIO-4A" "CON-TXN-4A" 1
write_persist_sql "${WORKDIR}/s4b.sql" "94900000-0000-0000-0000-000000000402" "s4-message-b" "s4-attachment-b" "s4-attempt-b" "5" "CON-FOLIO-4B" "CON-TXN-4B" 1
run_pair "scenario4_two_new_folios" "${WORKDIR}/s4a.sql" "${WORKDIR}/s4b.sql"
both_success "scenario4_two_new_folios"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.portfolios WHERE workspace_id = '94400000-0000-0000-0000-000000000001' AND client_id = '94300000-0000-0000-0000-000000000002';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario4 portfolio count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.portfolio_folio_references m JOIN public.folio_references f ON f.id = m.folio_reference_id WHERE f.normalized_folio_number IN ('CONFOLIO4A','CONFOLIO4B');
  IF v_count <> 2 THEN RAISE EXCEPTION 'scenario4 folio mapping count %', v_count; END IF;
END \$\$;"

write_persist_sql "${WORKDIR}/s5a.sql" "94900000-0000-0000-0000-000000000501" "s5-message-a" "s5-attachment-a" "s5-attempt-a" "6" "CON-FOLIO-5" "CON-TXN-5" 1
write_persist_sql "${WORKDIR}/s5b.sql" "94900000-0000-0000-0000-000000000502" "s5-message-b" "s5-attachment-b" "s5-attempt-b" "7" "CON-FOLIO-5" "CON-TXN-5" 1
run_pair "scenario5_duplicate_registrar_txn" "${WORKDIR}/s5a.sql" "${WORKDIR}/s5b.sql"
one_success_one_conflict "scenario5_duplicate_registrar_txn"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.transactions WHERE registrar_transaction_id = 'CON-TXN-5';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario5 transaction identity count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.ingested_documents WHERE provider_message_id IN ('s5-message-a','s5-message-b') AND processing_status = 'completed';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario5 completed document count %', v_count; END IF;
END \$\$;"

write_persist_sql "${WORKDIR}/s6a.sql" "94900000-0000-0000-0000-000000000601" "s6-message-a" "s6-attachment-a" "s6-attempt-a" "8" "CON-FOLIO-6" "CON-TXN-6A" 1
write_persist_sql "${WORKDIR}/s6b.sql" "94900000-0000-0000-0000-000000000602" "s6-message-b" "s6-attachment-b" "s6-attempt-b" "9" "CON-FOLIO-6" "CON-TXN-6B" 1
run_pair "scenario6_one_folio_reference" "${WORKDIR}/s6a.sql" "${WORKDIR}/s6b.sql"
both_success "scenario6_one_folio_reference"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.folio_references WHERE registrar = 'CAMS' AND normalized_folio_number = 'CONFOLIO6';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario6 folio reference count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.portfolio_folio_references m JOIN public.folio_references f ON f.id = m.folio_reference_id WHERE f.registrar = 'CAMS' AND f.normalized_folio_number = 'CONFOLIO6';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario6 folio mapping count %', v_count; END IF;
END \$\$;"

write_persist_sql "${WORKDIR}/s7a.sql" "94900000-0000-0000-0000-000000000701" "s7-message" "s7-attachment" "s7-attempt-a" "a" "CON-FOLIO-7" "CON-TXN-7A" 1
write_persist_sql "${WORKDIR}/s7b.sql" "94900000-0000-0000-0000-000000000701" "s7-message" "s7-attachment" "s7-attempt-b" "b" "CON-FOLIO-7" "CON-TXN-7B" 1
run_pair "scenario7_provider_identity_changed_digest" "${WORKDIR}/s7a.sql" "${WORKDIR}/s7b.sql"
one_success_one_conflict "scenario7_provider_identity_changed_digest"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.ingested_documents WHERE provider_message_id = 's7-message' AND provider_attachment_id = 's7-attachment';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario7 document count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.transactions WHERE registrar_transaction_id IN ('CON-TXN-7A','CON-TXN-7B');
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario7 transaction count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.ingestion_logs WHERE provider_message_id = 's7-message' AND status = 'SUCCESS';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario7 success log count %', v_count; END IF;
END \$\$;"

write_persist_sql "${WORKDIR}/s8a.sql" "94900000-0000-0000-0000-000000000801" "s8-message-a" "s8-attachment-a" "s8-attempt-a" "c" "CON-FOLIO-8A" "CON-TXN-8A" 1
write_persist_sql "${WORKDIR}/s8b.sql" "94900000-0000-0000-0000-000000000802" "s8-message-b" "s8-attachment-b" "s8-attempt-b" "c" "CON-FOLIO-8B" "CON-TXN-8B" 1
run_pair "scenario8_same_digest_different_provider_identity" "${WORKDIR}/s8a.sql" "${WORKDIR}/s8b.sql"
both_success "scenario8_same_digest_different_provider_identity"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.ingested_documents WHERE provider_message_id IN ('s8-message-a','s8-message-b');
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario8 document count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.transactions WHERE registrar_transaction_id IN ('CON-TXN-8A','CON-TXN-8B');
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario8 transaction count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.event_outbox e JOIN public.ingested_documents d ON d.id = e.entity_id WHERE d.provider_message_id IN ('s8-message-a','s8-message-b') AND e.event_type = 'statement.imported';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario8 event count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_attempts WHERE provider_message_id IN ('s8-message-a','s8-message-b') AND outcome = 'duplicate' AND failure_code = 'duplicate_attachment';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario8 duplicate attempt count %', v_count; END IF;
  SELECT count(*)::int INTO v_count FROM public.ingestion_logs WHERE provider_message_id IN ('s8-message-a','s8-message-b') AND failure_code = 'duplicate_attachment';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario8 duplicate log count %', v_count; END IF;
END \$\$;"

write_claim_sql "${WORKDIR}/s9a.sql" "94400000-0000-0000-0000-000000000001" "94700000-0000-0000-0000-000000000001" "94900000-0000-0000-0000-000000000901" "CAMS"
write_claim_sql "${WORKDIR}/s9b.sql" "94400000-0000-0000-0000-000000000001" "94700000-0000-0000-0000-000000000001" "94900000-0000-0000-0000-000000000901" "CAMS"
run_pair "scenario9_identical_run_claim" "${WORKDIR}/s9a.sql" "${WORKDIR}/s9b.sql"
both_success "scenario9_identical_run_claim"
if ! grep -q "active_in_progress" "${WORKDIR}/scenario9_identical_run_claim.left.out" "${WORKDIR}/scenario9_identical_run_claim.right.out"; then
  echo "scenario9_identical_run_claim: expected one active_in_progress replay" >&2
  cat "${WORKDIR}/scenario9_identical_run_claim.left.out" >&2
  cat "${WORKDIR}/scenario9_identical_run_claim.right.out" >&2
  exit 1
fi
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_runs WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000901';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario9 run count %', v_count; END IF;
END \$\$;"

write_claim_sql "${WORKDIR}/s10a.sql" "94400000-0000-0000-0000-000000000001" "94700000-0000-0000-0000-000000000001" "94900000-0000-0000-0000-000000000902" "CAMS"
write_claim_sql "${WORKDIR}/s10b.sql" "94400000-0000-0000-0000-000000000002" "94700000-0000-0000-0000-000000000002" "94900000-0000-0000-0000-000000000902" "CAMS"
run_pair "scenario10_conflicting_run_claim" "${WORKDIR}/s10a.sql" "${WORKDIR}/s10b.sql"
one_success_one_conflict "scenario10_conflicting_run_claim"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_runs WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000902';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario10 run count %', v_count; END IF;
END \$\$;"

write_unclaimed_persist_sql "${WORKDIR}/s11a.sql"
write_unclaimed_persist_sql "${WORKDIR}/s11b.sql"
run_pair "scenario11_unclaimed_persistence" "${WORKDIR}/s11a.sql" "${WORKDIR}/s11b.sql"
both_fail_with_code "scenario11_unclaimed_persistence" "ingestion_run_not_claimed"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_attempts WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000911';
  IF v_count <> 0 THEN RAISE EXCEPTION 'scenario11 attempt count %', v_count; END IF;
END \$\$;"

assert_sql "SET ROLE service_role;
SELECT public.claim_cams_kfintech_ingestion_run('94400000-0000-0000-0000-000000000001','94700000-0000-0000-0000-000000000001','94900000-0000-0000-0000-000000000912','CAMS');
SELECT * FROM public.finalize_cams_kfintech_ingestion_run('94400000-0000-0000-0000-000000000001','94700000-0000-0000-0000-000000000001','94900000-0000-0000-0000-000000000912','CAMS', NULL, 'mailbox_poll_failed', 0);"
write_persist_sql "${WORKDIR}/s12a.sql" "94900000-0000-0000-0000-000000000912" "s12-message" "s12-attachment-a" "s12-attempt-a" "d" "CON-FOLIO-12A" "CON-TXN-12A" 1 "94900000-0000-0000-0000-000000000912"
write_persist_sql "${WORKDIR}/s12b.sql" "94900000-0000-0000-0000-000000000912" "s12-message" "s12-attachment-b" "s12-attempt-b" "e" "CON-FOLIO-12B" "CON-TXN-12B" 1 "94900000-0000-0000-0000-000000000912"
run_pair "scenario12_persistence_after_terminal" "${WORKDIR}/s12a.sql" "${WORKDIR}/s12b.sql"
both_fail_with_code "scenario12_persistence_after_terminal" "ingestion_run_finalized"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_attempts WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000912';
  IF v_count <> 0 THEN RAISE EXCEPTION 'scenario12 attempt count %', v_count; END IF;
END \$\$;"

assert_sql "SET ROLE service_role;
SELECT public.claim_cams_kfintech_ingestion_run('94400000-0000-0000-0000-000000000001','94700000-0000-0000-0000-000000000001','94900000-0000-0000-0000-000000000913','CAMS');
SELECT public.record_cams_kfintech_ingestion_failure(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '94900000-0000-0000-0000-000000000913',
  '94900000-0000-0000-0000-000000000913',
  's13-message',
  's13-attachment',
  's13-attempt',
  'CAMS',
  'malware_detected',
  repeat('f', 64),
  'ingested-documents',
  'concurrency/s13-failure',
  'application/x-dbase',
  'DBF',
  1024
);"
write_finalize_sql "${WORKDIR}/s13a.sql" "94900000-0000-0000-0000-000000000913" "NULL" "NULL"
write_finalize_sql "${WORKDIR}/s13b.sql" "94900000-0000-0000-0000-000000000913" "NULL" "NULL"
run_pair "scenario13_identical_terminal_finalization" "${WORKDIR}/s13a.sql" "${WORKDIR}/s13b.sql"
both_success "scenario13_identical_terminal_finalization"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_runs WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000913' AND status = 'failed';
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario13 failed run count %', v_count; END IF;
END \$\$;"

assert_sql "SET ROLE service_role;
SELECT public.claim_cams_kfintech_ingestion_run('94400000-0000-0000-0000-000000000001','94700000-0000-0000-0000-000000000001','94900000-0000-0000-0000-000000000914','CAMS');"
write_finalize_sql "${WORKDIR}/s14a.sql" "94900000-0000-0000-0000-000000000914" "'attachment_limit_exceeded'" "NULL"
write_finalize_sql "${WORKDIR}/s14b.sql" "94900000-0000-0000-0000-000000000914" "NULL" "'mailbox_poll_failed'"
run_pair "scenario14_conflicting_terminal_finalization" "${WORKDIR}/s14a.sql" "${WORKDIR}/s14b.sql"
one_success_one_conflict "scenario14_conflicting_terminal_finalization"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_runs WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000914' AND status IN ('failed','stopped');
  IF v_count <> 1 THEN RAISE EXCEPTION 'scenario14 terminal run count %', v_count; END IF;
END \$\$;"

write_persist_sql "${WORKDIR}/s15a.sql" "94900000-0000-0000-0000-000000000915" "s15-message" "s15-attachment" "s15-attempt" "1" "CON-FOLIO-15" "CON-TXN-15" 1 "94900000-0000-0000-0000-000000000915"
write_custom_failure_sql "${WORKDIR}/s15b.sql" "94900000-0000-0000-0000-000000000915" "94900000-0000-0000-0000-000000000915" "s15-message" "s15-attachment" "s15-attempt" "1" "parse_failed"
run_pair "scenario15_persist_failure_same_attachment" "${WORKDIR}/s15a.sql" "${WORKDIR}/s15b.sql"
one_success_one_conflict "scenario15_persist_failure_same_attachment"
assert_sql "DO \$\$ DECLARE v_count int; v_success int; v_failed int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_attempts WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000915' AND provider_message_id = 's15-message' AND provider_attachment_id = 's15-attachment';
  SELECT count(*)::int INTO v_success FROM public.cams_kfintech_ingestion_attempts WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000915' AND outcome = 'succeeded';
  SELECT count(*)::int INTO v_failed FROM public.cams_kfintech_ingestion_attempts WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000915' AND outcome = 'failed';
  IF v_count <> 1 OR (v_success > 0 AND v_failed > 0) THEN RAISE EXCEPTION 'scenario15 contradictory attempts survived: %, %, %', v_count, v_success, v_failed; END IF;
END \$\$;"

assert_sql "SET ROLE service_role;
SELECT public.claim_cams_kfintech_ingestion_run('94400000-0000-0000-0000-000000000001','94700000-0000-0000-0000-000000000001','94900000-0000-0000-0000-000000000916','CAMS');"
write_persist_sql "${WORKDIR}/s16a.sql" "94900000-0000-0000-0000-000000000916" "s16-message" "s16-attachment" "s16-attempt" "2" "CON-FOLIO-16" "CON-TXN-16" 1 "94900000-0000-0000-0000-000000000916"
write_finalize_sql "${WORKDIR}/s16b.sql" "94900000-0000-0000-0000-000000000916" "NULL" "NULL"
run_pair "scenario16_persist_races_finalization" "${WORKDIR}/s16a.sql" "${WORKDIR}/s16b.sql"
success_or_processing_incomplete "scenario16_persist_races_finalization"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_attempts WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000916';
  IF v_count > 1 THEN RAISE EXCEPTION 'scenario16 attempt count %', v_count; END IF;
END \$\$;"

assert_sql "SET ROLE service_role;
SELECT public.claim_cams_kfintech_ingestion_run('94400000-0000-0000-0000-000000000001','94700000-0000-0000-0000-000000000001','94900000-0000-0000-0000-000000000917','CAMS');"
write_custom_failure_sql "${WORKDIR}/s17a.sql" "94900000-0000-0000-0000-000000000917" "94900000-0000-0000-0000-000000000917" "s17-message" "s17-attachment" "s17-attempt" "3" "malware_detected"
write_finalize_sql "${WORKDIR}/s17b.sql" "94900000-0000-0000-0000-000000000917" "NULL" "NULL"
run_pair "scenario17_failure_races_finalization" "${WORKDIR}/s17a.sql" "${WORKDIR}/s17b.sql"
success_or_processing_incomplete "scenario17_failure_races_finalization"
assert_sql "DO \$\$ DECLARE v_count int; BEGIN
  SELECT count(*)::int INTO v_count FROM public.cams_kfintech_ingestion_attempts WHERE ingestion_run_id = '94900000-0000-0000-0000-000000000917';
  IF v_count > 1 THEN RAISE EXCEPTION 'scenario17 attempt count %', v_count; END IF;
END \$\$;"

write_claim_sql "${WORKDIR}/s18a.sql" "94400000-0000-0000-0000-000000000001" "94700000-0000-0000-0000-000000000001" "94900000-0000-0000-0000-000000000918" "CAMS"
write_claim_sql "${WORKDIR}/s18b.sql" "94400000-0000-0000-0000-000000000001" "94700000-0000-0000-0000-000000000001" "94900000-0000-0000-0000-000000000918" "CAMS"
run_pair "scenario18_active_duplicate_claim_contract" "${WORKDIR}/s18a.sql" "${WORKDIR}/s18b.sql"
both_success "scenario18_active_duplicate_claim_contract"
if ! grep -q "active_in_progress" "${WORKDIR}/scenario18_active_duplicate_claim_contract.left.out" "${WORKDIR}/scenario18_active_duplicate_claim_contract.right.out"; then
  echo "scenario18_active_duplicate_claim_contract: expected active_in_progress" >&2
  cat "${WORKDIR}/scenario18_active_duplicate_claim_contract.left.out" >&2
  cat "${WORKDIR}/scenario18_active_duplicate_claim_contract.right.out" >&2
  exit 1
fi

run_psql <<'SQL'
DROP TRIGGER IF EXISTS issue32_concurrency_sleep_before_document_insert ON public.ingested_documents;
DROP FUNCTION IF EXISTS public.issue32_concurrency_sleep_trigger();
SQL

echo "Issue #32 concurrency harness passed: ${SCENARIOS} scenarios"
