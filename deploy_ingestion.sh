#!/bin/bash
set -euo pipefail

echo "ERROR: deploy_ingestion.sh is retired and must not be used." >&2
echo "Hosted Dev deploys from develop; use services/ingestion-support/compose.yaml locally." >&2
echo "Direct IMAP credentials and manual Supabase deployment are intentionally unsupported." >&2
exit 1
