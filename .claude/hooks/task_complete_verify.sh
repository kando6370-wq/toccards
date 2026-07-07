#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)/.."
cd "$ROOT"

pnpm build
pnpm --filter @kando/workers-api test
pnpm --filter @kando/auth-core test

if [ -f "apps/admin-web/package.json" ]; then
  pnpm --filter @kando/admin-web build
fi

if [ -f "pubspec.yaml" ]; then
  if command -v flutter >/dev/null 2>&1; then
    flutter pub get
    dart run melos run test
  else
    printf '%s\n' 'Skipping Flutter verification: flutter command is not available in this environment.' >&2
  fi
fi
