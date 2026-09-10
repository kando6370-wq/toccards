#!/bin/sh
set -eu

postgres_bin_dir=$(find /usr/lib/postgresql -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)/bin
PATH="$postgres_bin_dir:$PATH"
export PATH

if [ "${1:-}" != "postgres" ]; then
  exec "$@"
fi

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${PGDATA:=/var/lib/postgresql/data}"

mkdir -p "$PGDATA"
chown -R postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  password_file=$(mktemp)
  trap 'rm -f "$password_file"' EXIT INT TERM
  printf '%s\n' "$POSTGRES_PASSWORD" > "$password_file"
  chown postgres:postgres "$password_file"
  chmod 600 "$password_file"

  runuser -u postgres -- initdb \
    -D "$PGDATA" \
    --username="$POSTGRES_USER" \
    --pwfile="$password_file" \
    --auth-local=trust \
    --auth-host=scram-sha-256
  rm -f "$password_file"
  trap - EXIT INT TERM

  printf "listen_addresses = '*'\n" >> "$PGDATA/postgresql.conf"
fi

hba_rule="host all all all scram-sha-256"
grep -Fqx "$hba_rule" "$PGDATA/pg_hba.conf" || printf '%s\n' "$hba_rule" >> "$PGDATA/pg_hba.conf"

runuser -u postgres -- pg_ctl -D "$PGDATA" -o "-c listen_addresses=localhost" -w start
database_exists=$(runuser -u postgres -- psql \
  --username="$POSTGRES_USER" \
  --dbname=postgres \
  --tuples-only \
  --no-align \
  --command="SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'")
if [ "$database_exists" != "1" ]; then
  runuser -u postgres -- createdb \
    --username="$POSTGRES_USER" \
    --owner="$POSTGRES_USER" \
    "$POSTGRES_DB"
fi
runuser -u postgres -- pg_ctl -D "$PGDATA" -m fast -w stop

exec runuser -u postgres -- postgres -D "$PGDATA"
