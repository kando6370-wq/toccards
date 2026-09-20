#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$APP_DIR/build/ios/Debug-test-iphonesimulator/Runner.app"
DEVICE_ID=""

arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
  case "${arguments[$index]}" in
    -d|--device-id)
      if ((index + 1 < ${#arguments[@]})); then
        DEVICE_ID="${arguments[$((index + 1))]}"
      fi
      ;;
    --device-id=*)
      DEVICE_ID="${arguments[$index]#*=}"
      ;;
  esac
done

cd "$APP_DIR"

build_started_at="$(date +%s)"

if flutter run \
  --flavor test \
  --dart-define-from-file=config/test.json \
  "$@"; then
  exit 0
fi

if [[ -z "$DEVICE_ID" || ! -d "$APP_PATH" ]]; then
  exit 1
fi

app_built_at="$(stat -f '%m' "$APP_PATH")"
if ((app_built_at < build_started_at)); then
  exit 1
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
printf '[ios-simulator] Flutter post-processing failed; installing the completed Xcode build.\n' >&2
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$bundle_id"
