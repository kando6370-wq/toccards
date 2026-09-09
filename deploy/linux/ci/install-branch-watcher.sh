#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

script_source=${1:-}
if [[ -z "$script_source" || ! -f "$script_source" ]]; then
  echo "Usage: $0 <watch-branch.sh> [initial-branch-sha]" >&2
  exit 2
fi

initial_branch_sha=${2:-}
deploy_root=${TOCCARDS_DEPLOY_ROOT:-$HOME/apps/toccards-test}
watcher_dir=${TOCCARDS_WATCHER_DIR:-$deploy_root/watcher}
watcher_script="$watcher_dir/watch-branch.sh"
config_file="$watcher_dir/watcher.env"
state_dir="$watcher_dir/state"
repository_url=${TOCCARDS_REPOSITORY_URL:-https://github.com/kando6370-wq/toccards.git}
deploy_branch=${TOCCARDS_DEPLOY_BRANCH:-dev}

mkdir -p "$watcher_dir" "$state_dir" "$watcher_dir/logs"
chmod 700 "$watcher_dir" "$state_dir" "$watcher_dir/logs"
install -m 700 "$script_source" "$watcher_script"

cat > "$config_file" <<EOF
TOCCARDS_REPOSITORY_URL=$repository_url
TOCCARDS_DEPLOY_BRANCH=$deploy_branch
TOCCARDS_DEPLOY_ROOT=$deploy_root
TOCCARDS_WATCHER_DIR=$watcher_dir
TOCCARDS_RETRY_COOLDOWN_SECONDS=900
EOF
chmod 600 "$config_file"

if [[ -z "$initial_branch_sha" ]]; then
  initial_branch_sha=$(git ls-remote "$repository_url" "refs/heads/$deploy_branch" | awk '{print $1}')
fi
if [[ ! "$initial_branch_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Unable to resolve the initial branch SHA for $deploy_branch." >&2
  exit 3
fi
printf '%s\n' "$initial_branch_sha" > "$state_dir/last-seen-sha"

cron_begin="# BEGIN TOCCARDS LINUX TEST WATCHER"
cron_end="# END TOCCARDS LINUX TEST WATCHER"
temporary_crontab=$(mktemp)
trap 'rm -f "$temporary_crontab"' EXIT INT TERM
crontab -l 2>/dev/null \
  | awk -v begin="$cron_begin" -v end="$cron_end" '
      $0 == begin { skipping = 1; next }
      $0 == end { skipping = 0; next }
      !skipping { print }
    ' > "$temporary_crontab" || true
cat >> "$temporary_crontab" <<EOF
$cron_begin
*/2 * * * * $watcher_script
$cron_end
EOF
crontab "$temporary_crontab"

echo "Installed Linux test branch watcher."
echo "Branch: $deploy_branch"
echo "Initial baseline: $initial_branch_sha"
echo "Script: $watcher_script"
echo "Log: $watcher_dir/logs/watch.log"
