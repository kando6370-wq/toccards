#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

deploy_root=${TOCCARDS_DEPLOY_ROOT:-$HOME/apps/toccards-test}
watcher_dir=${TOCCARDS_WATCHER_DIR:-$deploy_root/watcher}
config_file=${TOCCARDS_WATCHER_CONFIG:-$watcher_dir/watcher.env}

if [[ -f "$config_file" ]]; then
  set -a
  source "$config_file"
  set +a
fi

repository_url=${TOCCARDS_REPOSITORY_URL:-https://github.com/kando6370-wq/toccards.git}
deploy_branch=${TOCCARDS_DEPLOY_BRANCH:-dev}
retry_cooldown_seconds=${TOCCARDS_RETRY_COOLDOWN_SECONDS:-900}
source_dir="$watcher_dir/source"
state_dir="$watcher_dir/state"
log_dir="$watcher_dir/logs"
pnpm_store_dir="$watcher_dir/pnpm-store"
pnpm_tools_dir="$watcher_dir/tools"
pnpm_bin="$pnpm_tools_dir/node_modules/.bin/pnpm"
artifact_dir="$watcher_dir/artifact"
lock_file="$watcher_dir/watch.lock"

mkdir -p "$state_dir" "$log_dir" "$pnpm_store_dir" "$pnpm_tools_dir"
chmod 700 "$watcher_dir" "$state_dir" "$log_dir" "$pnpm_store_dir" "$pnpm_tools_dir"

log_file="$log_dir/watch.log"
if [[ -f "$log_file" && $(wc -c < "$log_file") -gt 10485760 ]]; then
  mv -f "$log_file" "$log_file.1"
fi
exec >> "$log_file" 2>&1

echo "[$(date -Iseconds)] Checking $repository_url branch $deploy_branch"

exec 9> "$lock_file"
if ! flock -n 9; then
  echo "Another branch check is already running."
  exit 0
fi

if [[ ! -d "$source_dir/.git" ]]; then
  rm -rf "$source_dir"
  git clone --no-tags --single-branch --branch "$deploy_branch" "$repository_url" "$source_dir"
fi

git -C "$source_dir" remote set-url origin "$repository_url"
git -C "$source_dir" fetch --no-tags --prune origin \
  "+refs/heads/$deploy_branch:refs/remotes/origin/$deploy_branch"
target_sha=$(git -C "$source_dir" rev-parse "refs/remotes/origin/$deploy_branch")
last_seen_sha=$(cat "$state_dir/last-seen-sha" 2>/dev/null || true)

if [[ "$target_sha" == "$last_seen_sha" && "${TOCCARDS_FORCE_DEPLOY:-0}" != "1" ]]; then
  echo "No new commit. Current branch SHA: $target_sha"
  exit 0
fi

failed_sha=$(cat "$state_dir/failed-sha" 2>/dev/null || true)
failed_at=$(cat "$state_dir/failed-at" 2>/dev/null || echo 0)
now=$(date +%s)
if [[ "$target_sha" == "$failed_sha" \
  && "${TOCCARDS_FORCE_DEPLOY:-0}" != "1" \
  && $((now - failed_at)) -lt "$retry_cooldown_seconds" ]]; then
  echo "Commit $target_sha is in retry cooldown."
  exit 0
fi

if [[ -n "$last_seen_sha" ]] && git -C "$source_dir" cat-file -e "$last_seen_sha^{commit}" 2>/dev/null; then
  mapfile -t changed_paths < <(git -C "$source_dir" diff --name-only "$last_seen_sha" "$target_sha")
  relevant_change=0
  for changed_path in "${changed_paths[@]}"; do
    case "$changed_path" in
      .dockerignore|package.json|pnpm-lock.yaml|pnpm-workspace.yaml|tsconfig.base.json|turbo.json|.github/workflows/linux-test-deploy.yml|apps/admin-web/*|apps/workers-api/*|deploy/linux/*|packages/*)
        relevant_change=1
        break
        ;;
    esac
  done
  if [[ $relevant_change -eq 0 && "${TOCCARDS_FORCE_DEPLOY:-0}" != "1" ]]; then
    printf '%s\n' "$target_sha" > "$state_dir/last-seen-sha"
    echo "Commit $target_sha has no Linux deployment impact; baseline advanced."
    exit 0
  fi
fi

git -C "$source_dir" checkout --detach "$target_sha"
git -C "$source_dir" reset --hard "$target_sha"
git -C "$source_dir" clean -fdx

if [[ ! -x "$source_dir/deploy/linux/ci/deploy-release.sh" ]]; then
  printf '%s\n' "$target_sha" > "$state_dir/last-seen-sha"
  echo "Commit $target_sha does not contain Linux auto-deployment assets; baseline advanced without deployment."
  exit 0
fi

record_failure() {
  local exit_status=$?
  trap - ERR
  printf '%s\n' "$target_sha" > "$state_dir/failed-sha"
  date +%s > "$state_dir/failed-at"
  echo "Deployment attempt failed for $target_sha with exit status $exit_status."
  exit "$exit_status"
}
trap record_failure ERR

cd "$source_dir"
if [[ ! -x "$pnpm_bin" || "$($pnpm_bin --version 2>/dev/null || true)" != "11.9.0" ]]; then
  rm -rf "$pnpm_tools_dir/node_modules"
  npm install \
    --prefix "$pnpm_tools_dir" \
    --no-save \
    --no-package-lock \
    pnpm@11.9.0
fi
export PATH="$pnpm_tools_dir/node_modules/.bin:$PATH"
"$pnpm_bin" install --frozen-lockfile --store-dir "$pnpm_store_dir"
"$pnpm_bin" --filter @kando/auth-core build
"$pnpm_bin" --filter @kando/workers-api type-check
"$pnpm_bin" --filter @kando/workers-api exec vitest run \
  src/db/postgres-database.test.ts \
  src/linux/in-memory-kv.test.ts \
  src/linux/filesystem-r2.test.ts \
  src/linux/execution-context.test.ts \
  src/cors.test.ts \
  src/index-postgres-runtime.test.ts
node --test apps/admin-web/test/api-environment-intent.test.mjs
"$pnpm_bin" --filter @kando/workers-api build:linux

rm -rf "$artifact_dir"
mkdir -p \
  "$artifact_dir/apps/workers-api/dist/linux" \
  "$artifact_dir/apps/workers-api/src/db/postgres/migrations" \
  "$artifact_dir/apps/admin-web/dist"
cp .dockerignore "$artifact_dir/.dockerignore"
cp -R deploy "$artifact_dir/deploy"
cp -R apps/workers-api/dist/linux/. "$artifact_dir/apps/workers-api/dist/linux/"
cp -R apps/workers-api/src/db/postgres/migrations/. \
  "$artifact_dir/apps/workers-api/src/db/postgres/migrations/"
cp -R apps/admin-web/dist/. "$artifact_dir/apps/admin-web/dist/"
cat > "$artifact_dir/release-manifest.txt" <<EOF
repository=$repository_url
branch=$deploy_branch
sha=$target_sha
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
source=kd201-branch-watcher
EOF

TOCCARDS_RELEASE_ID="branch-$deploy_branch-${target_sha:0:12}-$(date +%Y%m%d%H%M%S)" \
  bash "$artifact_dir/deploy/linux/ci/deploy-release.sh" "$artifact_dir"

printf '%s\n' "$target_sha" > "$state_dir/last-seen-sha"
printf '%s\n' "$target_sha" > "$state_dir/last-deployed-sha"
rm -f "$state_dir/failed-sha" "$state_dir/failed-at"
trap - ERR
echo "Deployment completed for $target_sha."
