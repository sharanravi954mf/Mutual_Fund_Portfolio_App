#!/usr/bin/env sh
set -eu

SCENARIOS=6
DB_CONTAINER="${SUPABASE_DB_CONTAINER:-$(docker ps --filter "name=supabase_db_" --format "{{.Names}}" | head -n 1)}"

if [ -z "${DB_CONTAINER}" ]; then
  echo "No local Supabase database container found" >&2
  exit 1
fi

PSQL="docker exec -i ${DB_CONTAINER} psql -v ON_ERROR_STOP=1 -U postgres -d postgres"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

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
  cat > "${file}" <<SQL
\\pset tuples_only on
\\pset format unaligned
SET ROLE service_role;
BEGIN;
SET LOCAL moneybowl.issue32_concurrency_sleep = 'on';
SELECT idempotent
FROM public.persist_cams_kfintech_statement_ingestion(
  '94400000-0000-0000-0000-000000000001',
  '94700000-0000-0000-0000-000000000001',
  '94900000-0000-0000-0000-000000000001',
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
SET ROLE service_role;
BEGIN;
SET LOCAL moneybowl.issue32_concurrency_sleep = 'on';
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
  wait "${left_pid}"
  left_status="$?"
  wait "${right_pid}"
  right_status="$?"
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
  if ! grep -qE "correlation_conflict|persistence_conflict" "${WORKDIR}/${name}.left.out" "${WORKDIR}/${name}.right.out"; then
    echo "${name}: expected correlation_conflict or persistence_conflict" >&2
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

run_psql <<'SQL'
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

run_psql <<'SQL'
DROP TRIGGER IF EXISTS issue32_concurrency_sleep_before_document_insert ON public.ingested_documents;
DROP FUNCTION IF EXISTS public.issue32_concurrency_sleep_trigger();
SQL

echo "Issue #32 concurrency harness passed: ${SCENARIOS} scenarios"
