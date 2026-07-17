#!/bin/bash
set -e

# Sharan Fincorp Ingestion Deployment Script
# Automatically downloads Supabase CLI and deploys the ingestion function.

echo "===================================================="
echo "   Sharan Fincorp Ingestion Deployment Helper"
echo "===================================================="

# 1. Detect Architecture and Download Supabase CLI
ARCH=$(uname -m)
CLI_VER="1.178.2"

if [ "$ARCH" = "arm64" ]; then
  TAR_NAME="supabase_darwin_arm64.tar.gz"
else
  TAR_NAME="supabase_darwin_amd64.tar.gz"
fi

URL="https://github.com/supabase/cli/releases/download/v${CLI_VER}/${TAR_NAME}"

if [ ! -f "./supabase-cli/supabase" ]; then
  echo "Downloading Supabase CLI v${CLI_VER} for macOS ($ARCH)..."
  mkdir -p supabase-cli
  curl -sSL "$URL" -o "supabase-cli/${TAR_NAME}"
  tar -xzf "supabase-cli/${TAR_NAME}" -C supabase-cli
  rm "supabase-cli/${TAR_NAME}"
  echo "Supabase CLI downloaded successfully."
else
  echo "Supabase CLI already present."
fi

CLI="./supabase-cli/supabase"

# 2. Collect Inputs
echo ""
read -p "Enter your Supabase Personal Access Token (from https://supabase.com/dashboard/account/tokens): " ACCESS_TOKEN
read -p "Enter your IMAP Email User (e.g. your-email@gmail.com): " IMAP_USER
read -sp "Enter your IMAP Email Password (or Google App Password): " IMAP_PASS
echo ""
read -p "Enter your RTA Decryption Password (if statements are encrypted, else leave empty): " RTA_DECRYPT

export SUPABASE_ACCESS_TOKEN="$ACCESS_TOKEN"
PROJECT_REF="auxbbotbcvrgzvynyrgg"

# 3. Set Ingestion Secrets on Supabase
echo ""
echo "Configuring IMAP and Decryption secrets in Supabase project ($PROJECT_REF)..."
$CLI secrets set --project-ref "$PROJECT_REF" \
  IMAP_HOST="imap.gmail.com" \
  IMAP_PORT="993" \
  IMAP_USER="$IMAP_USER" \
  IMAP_PASSWORD="$IMAP_PASS" \
  RTA_DECRYPTION_PASSWORD="$RTA_DECRYPT"

# 4. Deploy the Edge Function
echo ""
echo "Deploying Edge Function: cams-kfintech-ingestion..."
$CLI functions deploy cams-kfintech-ingestion --project-ref "$PROJECT_REF" --no-verify-jwt

echo ""
echo "===================================================="
echo "   Deployment Complete!"
echo "   You can now test the sync in your Admin Dashboard."
echo "===================================================="
