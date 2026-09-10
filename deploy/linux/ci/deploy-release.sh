#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

artifact_root=${1:-}
if [[ -z "$artifact_root" || ! -d "$artifact_root" ]]; then
  echo "Usage: $0 <release-artifact-directory>" >&2
  exit 2
fi
artifact_root=$(cd "$artifact_root" && pwd -P)

deploy_root=${TOCCARDS_DEPLOY_ROOT:-$HOME/apps/toccards-test}
shared_dir="$deploy_root/shared"
releases_dir="$deploy_root/releases"
backups_dir="$deploy_root/backups"
env_file=${TOCCARDS_ENV_FILE:-$shared_dir/.env}

sha=${GITHUB_SHA:-manual}
release_id=${TOCCARDS_RELEASE_ID:-$(date +%Y%m%d-%H%M%S)-${sha:0:12}}
release_id=$(printf '%s' "$release_id" | tr -c 'A-Za-z0-9._-' '-')
release_dir="$releases_dir/$release_id"

required_paths=(
  ".dockerignore"
  "deploy/linux/docker-compose.yml"
  "deploy/linux/docker-compose.offline.yml"
  "deploy/linux/offline/prepare-node-runtime.sh"
  "apps/workers-api/dist/linux/server.mjs"
  "apps/workers-api/src/db/postgres/migrations"
  "apps/admin-web/dist/index.html"
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$artifact_root/$required_path" ]]; then
    echo "Release artifact is missing $required_path" >&2
    exit 3
  fi
done

if [[ ! -f "$env_file" ]]; then
  echo "Linux test environment file is missing: $env_file" >&2
  exit 4
fi

mkdir -p "$shared_dir" "$releases_dir" "$backups_dir"
chmod 700 "$deploy_root" "$shared_dir" "$releases_dir" "$backups_dir"

exec 9> "$shared_dir/deploy.lock"
if ! flock -n 9; then
  echo "Another Linux test deployment is already running." >&2
  exit 5
fi

if [[ -e "$release_dir" ]]; then
  echo "Release already exists: $release_dir" >&2
  exit 6
fi

previous_release=""
if [[ -L "$deploy_root/current" ]]; then
  previous_release=$(readlink -f "$deploy_root/current")
fi

compose_in() {
  local target_release=$1
  shift
  (
    cd "$target_release/deploy/linux"
    docker compose \
      --env-file .env \
      -f docker-compose.yml \
      -f docker-compose.offline.yml \
      "$@"
  )
}

backup_database() {
  if [[ -z "$previous_release" || ! -d "$previous_release/deploy/linux" ]]; then
    return
  fi
  if [[ "$(docker inspect toccards-linux-test-db-1 --format '{{.State.Running}}' 2>/dev/null || true)" != "true" ]]; then
    echo "Existing database container is not running; refusing deployment without backup." >&2
    exit 7
  fi

  local backup_file="$backups_dir/toccards-test-$(date +%Y%m%d-%H%M%S)-before-$release_id.dump"
  local temporary_backup="$backup_file.tmp"
  echo "Creating PostgreSQL backup: $backup_file"
  compose_in "$previous_release" exec -T db sh -c \
    'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
    > "$temporary_backup"
  test -s "$temporary_backup"
  mv "$temporary_backup" "$backup_file"
}

rollback_application() {
  local failed_status=$?
  trap - ERR
  set +e
  echo "Deployment failed for $release_id." >&2
  if [[ -n "$previous_release" && -d "$previous_release/deploy/linux" ]]; then
    echo "Rebuilding the previous application release: $previous_release" >&2
    compose_in "$previous_release" up -d --build
    rollback_status=$?
    if [[ $rollback_status -ne 0 ]]; then
      echo "Previous application release also failed to start; manual recovery is required." >&2
    fi
  else
    echo "No previous release is available for application rollback." >&2
  fi
  exit "$failed_status"
}

backup_database

mkdir -p "$release_dir"
cp -a "$artifact_root/." "$release_dir/"
ln -s "$env_file" "$release_dir/deploy/linux/.env"
chmod +x \
  "$release_dir/deploy/linux/ci/deploy-release.sh" \
  "$release_dir/deploy/linux/migrate.sh" \
  "$release_dir/deploy/linux/offline/postgres-entrypoint.sh" \
  "$release_dir/deploy/linux/offline/prepare-node-runtime.sh"

trap rollback_application ERR

echo "Preparing offline Node runtime for $release_id"
(
  cd "$release_dir/deploy/linux"
  sh offline/prepare-node-runtime.sh
)

echo "Starting release $release_id"
compose_in "$release_dir" up -d --build

attempts=0
until [[ "$(docker inspect toccards-linux-test-api-1 --format '{{.State.Health.Status}}' 2>/dev/null || true)" == "healthy" ]]; do
  attempts=$((attempts + 1))
  if [[ $attempts -ge 60 ]]; then
    echo "API did not become healthy within 120 seconds." >&2
    false
  fi
  sleep 2
done

if [[ "$(docker inspect toccards-linux-test-migrate-1 --format '{{.State.ExitCode}}')" != "0" ]]; then
  echo "Migration container did not exit successfully." >&2
  false
fi

migration_count=$(compose_in "$release_dir" exec -T db sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" --tuples-only --no-align --command="SELECT count(*) FROM schema_migrations"' \
  | tr -d '[:space:]')
if [[ ! "$migration_count" =~ ^[0-9]+$ || "$migration_count" -lt 1 ]]; then
  echo "Migration ledger is invalid: $migration_count" >&2
  false
fi

if [[ "$(curl -fsS http://127.0.0.1:8080/api/v1/health)" != '{"status":"ok"}' ]]; then
  echo "Linux test health endpoint returned an unexpected response." >&2
  false
fi
curl -fsS http://127.0.0.1:8080/ | grep -Fq '<title>Kando Admin</title>'

ln -sfn "$release_dir" "$deploy_root/current"
printf '%s\n' "$release_id" > "$shared_dir/current-release"
trap - ERR

echo "Linux test deployment completed."
echo "Release: $release_id"
echo "Previous release: ${previous_release:-none}"
echo "Migration count: $migration_count"
echo "URL: http://192.168.50.201:8080"
