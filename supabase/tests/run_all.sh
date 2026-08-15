#!/usr/bin/env sh
# Run every persistent SQL regression after `supabase db reset`.
set -eu

db_container="${SUPABASE_DB_CONTAINER:-$(docker ps --filter "name=supabase_db_" --format "{{.Names}}" | head -n 1)}"
if [ -z "$db_container" ]; then
  echo 'No local Supabase database container is running.' >&2
  exit 1
fi

for sql_file in supabase/tests/*.sql; do
  echo "Running $sql_file..."
  docker exec -i "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres < "$sql_file"
done

sh supabase/tests/issue_40_referral_conversion_concurrency_test.sh
