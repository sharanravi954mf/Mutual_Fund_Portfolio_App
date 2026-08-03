#!/usr/bin/env sh
set -eu

WORKDIR="$(mktemp -d)"
TOKEN="issue-33-gateway-token"
EVENT_ID="a33d0000-0000-4000-8000-000000000404"
SERVE_PID=""

cleanup() {
  if [ -n "${SERVE_PID}" ]; then
    kill "${SERVE_PID}" >/dev/null 2>&1 || true
    wait "${SERVE_PID}" >/dev/null 2>&1 || true
  fi
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

supabase status -o env > "${WORKDIR}/status.env"

API_URL="$(sed -n 's/^API_URL="\([^"]*\)"/\1/p' "${WORKDIR}/status.env")"
SERVICE_ROLE_KEY="$(sed -n 's/^SERVICE_ROLE_KEY="\([^"]*\)"/\1/p' "${WORKDIR}/status.env")"

if [ -z "${API_URL}" ] || [ -z "${SERVICE_ROLE_KEY}" ]; then
  echo "Issue #33 gateway: local Supabase API_URL or SERVICE_ROLE_KEY unavailable" >&2
  exit 1
fi

cat > "${WORKDIR}/worker.env" <<EOF
SUPABASE_URL=${API_URL}
SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
ORDER_AUTO_APPROVAL_WORKER_TOKEN=${TOKEN}
ORDER_AUTO_APPROVAL_MAX_ATTEMPTS=3
ORDER_AUTO_APPROVAL_LEASE_SECONDS=120
EOF

supabase functions serve order-auto-approval-worker --env-file "${WORKDIR}/worker.env" > "${WORKDIR}/serve.log" 2>&1 &
SERVE_PID="$!"

FUNCTION_URL="${API_URL}/functions/v1/order-auto-approval-worker"
REQUEST_BODY="{\"event_outbox_id\":\"${EVENT_ID}\"}"

request_status() {
  output_path="$1"
  shift
  curl -sS -o "${output_path}" -w "%{http_code}" -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    "$@" \
    -d "${REQUEST_BODY}"
}

ready="false"
for _ in $(seq 1 30); do
  status="$(request_status "${WORKDIR}/ready.json" || true)"
  if [ "${status}" = "403" ] && grep -q '"not_authorized"' "${WORKDIR}/ready.json"; then
    ready="true"
    break
  fi
  sleep 1
done

if [ "${ready}" != "true" ]; then
  echo "Issue #33 gateway: function server did not become ready" >&2
  cat "${WORKDIR}/serve.log" >&2 || true
  cat "${WORKDIR}/ready.json" >&2 || true
  exit 1
fi

missing_status="$(request_status "${WORKDIR}/missing.json")"
if [ "${missing_status}" != "403" ] || ! grep -q '"not_authorized"' "${WORKDIR}/missing.json"; then
  echo "Issue #33 gateway: missing token was not rejected by handler" >&2
  cat "${WORKDIR}/missing.json" >&2
  exit 1
fi

wrong_status="$(request_status "${WORKDIR}/wrong.json" -H "Authorization: Bearer wrong-token")"
if [ "${wrong_status}" != "403" ] || ! grep -q '"not_authorized"' "${WORKDIR}/wrong.json"; then
  echo "Issue #33 gateway: wrong token was not rejected by handler" >&2
  cat "${WORKDIR}/wrong.json" >&2
  exit 1
fi

correct_status="$(request_status "${WORKDIR}/correct.json" -H "Authorization: Bearer ${TOKEN}")"
if [ "${correct_status}" != "404" ] || ! grep -q '"event_not_found"' "${WORKDIR}/correct.json"; then
  echo "Issue #33 gateway: correct token did not reach the worker handler" >&2
  cat "${WORKDIR}/correct.json" >&2
  cat "${WORKDIR}/serve.log" >&2 || true
  exit 1
fi

echo "Issue #33 gateway authentication passed"
