#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"

until pg_isready -d "$DATABASE_URL" >/dev/null 2>&1; do
  sleep 2
done

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  filename text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
SQL

for migration in /migrations/*.sql; do
  filename=$(basename "$migration")
  applied=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc \
    "SELECT 1 FROM schema_migrations WHERE filename = '$filename'")
  if [ "$applied" = "1" ]; then
    echo "Skipping applied migration $filename"
    continue
  fi

  echo "Applying migration $filename"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -v migration_filename="$filename" <<SQL
BEGIN;
\i '$migration'
INSERT INTO schema_migrations (filename) VALUES (:'migration_filename');
COMMIT;
SQL
done
