#!/usr/bin/env sh
# Run every persistent SQL regression after `supabase db reset`.
set -eu

db_container=$(docker ps --filter 'name=^/supabase_db_' --format '{{.Names}}' | head -n 1)
if [ -z "$db_container" ]; then
  echo 'No local Supabase database container is running.' >&2
  exit 1
fi

for sql_file in supabase/tests/*.sql; do
  container_file="/tmp/$(basename "$sql_file")"
  docker cp "$sql_file" "$db_container:$container_file"
  docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f "$container_file"
done
