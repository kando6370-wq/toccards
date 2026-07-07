#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)/.."
cd "$ROOT"

verify_task_completion() {
  pnpm build || return $?
  pnpm --filter @kando/workers-api test || return $?
  pnpm --filter @kando/auth-core test || return $?

  if [ -f "apps/admin-web/package.json" ]; then
    pnpm --filter @kando/admin-web build || return $?
  fi

  if [ -f "pubspec.yaml" ]; then
    if command -v flutter >/dev/null 2>&1; then
      flutter pub get || return $?
      dart run melos run test || return $?
    else
      printf '%s\n' 'Skipping Flutter verification: flutter command is not available in this environment.' >&2
    fi
  fi
}

if verify_task_completion; then
  python3 .claude/hooks/task_status.py stop
else
  python3 .claude/hooks/task_status.py fail || true
  exit 1
fi
