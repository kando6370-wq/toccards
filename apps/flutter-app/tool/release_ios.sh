#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PUBSPEC="$APP_DIR/pubspec.yaml"
BUILD_ROOT="$APP_DIR/build/ios"
ARCHIVE_PATH="$BUILD_ROOT/archive/Runner.xcarchive"
APP_STORE_IPA_DIR="$BUILD_ROOT/ipa"
DEVICE_IPA_DIR="$BUILD_ROOT/device-ipa"

TEAM_ID="${TEAM_ID:-B95U3272HR}"
BUNDLE_ID="${BUNDLE_ID:-com.cardai.tcg}"
ENVIRONMENT="production"
ENV_CONFIG=""
API_BASE_URL=""
FIREBASE_CONFIG_SOURCE=""
FIREBASE_PROJECT_ID=""

BUILD_NUMBER=""
INSTALL_DEVICE=""
SHOULD_UPLOAD=0
SKIP_ANALYZE=0
# Bash 3.2 treats an empty array as unset under `set -u`; the empty sentinel
# keeps cleanup safe before the first temporary directory is created.
TEMP_DIRS=("")
NEW_TEMP_DIR=""
LAST_APP_PATH=""
LAST_PROFILE_PATH=""

log() {
  printf '[release-ios] %s\n' "$*"
}

die() {
  printf '[release-ios] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./tool/release_ios.sh [options]

Build a clean iOS Release archive and App Store-signed IPA.
The build number is incremented automatically unless --build-number is used.

Options:
  --env ENV          Build test or production (default: production).
  --build-number N   Use N instead of incrementing the current build number.
  --install DEVICE   Export a release-testing IPA and install it on DEVICE.
                     DEVICE may be a CoreDevice ID, hardware UDID, or unique name.
  --upload           Upload the App Store build to App Store Connect.
  --skip-analyze     Skip flutter analyze.
  --list-devices     List paired devices and exit.
  -h, --help         Show this help.

Examples:
  ./tool/release_ios.sh
  ./tool/release_ios.sh --env test
  ./tool/release_ios.sh --list-devices
  ./tool/release_ios.sh --install ABBA554A-D3A7-5651-827D-3754EB085751
  ./tool/release_ios.sh --upload
  ./tool/release_ios.sh --install 00008101-00111DCE3668001E --upload
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ "$actual" == "$expected" ]] || die "$label: expected '$expected', got '$actual'"
}

make_temp_dir() {
  NEW_TEMP_DIR="$(mktemp -d /tmp/card-ai-ios-release.XXXXXX)"
  TEMP_DIRS+=("$NEW_TEMP_DIR")
}

cleanup() {
  local temp_dir
  for temp_dir in "${TEMP_DIRS[@]}"; do
    case "$temp_dir" in
      /tmp/card-ai-ios-release.*) rm -rf -- "$temp_dir" ;;
    esac
  done
}

write_export_options() {
  local output_path="$1"
  local method="$2"
  local destination="$3"

  cat >"$output_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>$destination</string>
  <key>method</key>
  <string>$method</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>uploadSymbols</key>
  <true/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
EOF
}

validate_common_ipa() {
  local ipa_path="$1"
  local expected_version="$2"
  local expected_build="$3"
  local label="$4"
  local verify_dir app_path entitlements_path profile_path signature_details

  [[ -f "$ipa_path" ]] || die "$label IPA not found: $ipa_path"

  make_temp_dir
  verify_dir="$NEW_TEMP_DIR"
  unzip -q "$ipa_path" -d "$verify_dir"
  app_path="$(find "$verify_dir/Payload" -maxdepth 1 -name '*.app' -print -quit)"
  [[ -n "$app_path" ]] || die "$label IPA does not contain an app bundle"

  assert_equal "$BUNDLE_ID" "$(plist_value "$app_path/Info.plist" CFBundleIdentifier)" "$label bundle ID"
  assert_equal "$expected_version" "$(plist_value "$app_path/Info.plist" CFBundleShortVersionString)" "$label version"
  assert_equal "$expected_build" "$(plist_value "$app_path/Info.plist" CFBundleVersion)" "$label build number"

  codesign --verify --deep --strict --verbose=2 "$app_path"

  entitlements_path="$verify_dir/entitlements.plist"
  codesign -d --entitlements :- "$app_path" >"$entitlements_path" 2>/dev/null
  assert_equal "false" "$(plist_value "$entitlements_path" get-task-allow)" "$label get-task-allow"
  assert_equal "$TEAM_ID" "$(plist_value "$entitlements_path" com.apple.developer.team-identifier)" "$label team ID"
  assert_equal "$TEAM_ID.$BUNDLE_ID" "$(plist_value "$entitlements_path" application-identifier)" "$label application identifier"
  signature_details="$(codesign -dvvv "$app_path" 2>&1)"
  grep -Fq 'Authority=Apple Distribution:' <<<"$signature_details" \
    || die "$label is not signed with Apple Distribution"

  profile_path="$verify_dir/profile.plist"
  security cms -D -i "$app_path/embedded.mobileprovision" >"$profile_path"
  assert_equal "false" "$(plist_value "$profile_path" Entitlements:get-task-allow)" "$label profile get-task-allow"

  assert_equal "$FIREBASE_PROJECT_ID" "$(plist_value "$app_path/GoogleService-Info.plist" PROJECT_ID)" "$label Firebase project"
  assert_equal "$BUNDLE_ID" "$(plist_value "$app_path/GoogleService-Info.plist" BUNDLE_ID)" "$label Firebase bundle ID"
  cmp -s "$FIREBASE_CONFIG_SOURCE" "$app_path/GoogleService-Info.plist" || die "$label contains the wrong Firebase configuration"
  grep -aFq "$API_BASE_URL" "$app_path/Frameworks/App.framework/App" || die "$label does not contain the $ENVIRONMENT API URL"

  LAST_APP_PATH="$app_path"
  LAST_PROFILE_PATH="$profile_path"
  log "$label validation passed"
}

verify_dsym_coverage() {
  local app_path="$1"
  local work_dir app_uuids dsym_uuids missing_uuids binary uuid

  make_temp_dir
  work_dir="$NEW_TEMP_DIR"
  app_uuids="$work_dir/app-uuids.txt"
  dsym_uuids="$work_dir/dsym-uuids.txt"
  missing_uuids="$work_dir/missing-uuids.txt"

  : >"$app_uuids"
  while IFS= read -r -d '' binary; do
    if file "$binary" | grep -q 'Mach-O'; then
      xcrun dwarfdump --uuid "$binary" | awk '{print $2}' >>"$app_uuids"
    fi
  done < <(find "$app_path" -type f -print0)
  sort -u "$app_uuids" -o "$app_uuids"

  find "$ARCHIVE_PATH/dSYMs" -type f -path '*/Contents/Resources/DWARF/*' -print0 \
    | xargs -0 xcrun dwarfdump --uuid \
    | awk '{print $2}' \
    | sort -u >"$dsym_uuids"

  [[ -s "$app_uuids" ]] || die "No Mach-O UUIDs found in the exported app"
  [[ -s "$dsym_uuids" ]] || die "No dSYM UUIDs found in the archive"

  : >"$missing_uuids"
  while IFS= read -r uuid; do
    grep -Fxq "$uuid" "$dsym_uuids" || printf '%s\n' "$uuid" >>"$missing_uuids"
  done <"$app_uuids"

  if [[ -s "$missing_uuids" ]]; then
    cat "$missing_uuids" >&2
    die "One or more embedded Mach-O binaries do not have matching dSYMs"
  fi

  log "dSYM coverage passed ($(wc -l <"$app_uuids" | tr -d ' ') Mach-O UUIDs)"
}

find_single_ipa() {
  local directory="$1"
  local ipa_path

  ipa_path="$(find "$directory" -maxdepth 1 -name '*.ipa' -print -quit)"
  [[ -n "$ipa_path" ]] || die "No IPA found in $directory"
  printf '%s\n' "$ipa_path"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || die "--env requires test or production"
      ENVIRONMENT="$2"
      shift 2
      ;;
    --build-number)
      [[ $# -ge 2 ]] || die "--build-number requires a value"
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --install)
      [[ $# -ge 2 ]] || die "--install requires a device selector"
      INSTALL_DEVICE="$2"
      shift 2
      ;;
    --upload)
      SHOULD_UPLOAD=1
      shift
      ;;
    --skip-analyze)
      SKIP_ANALYZE=1
      shift
      ;;
    --list-devices)
      xcrun devicectl list devices
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "This script must run on macOS"
require_command flutter
require_command xcodebuild
require_command xcrun
require_command codesign
require_command security
require_command unzip
require_command shasum
require_command perl
require_command file
require_command awk
require_command cmp

[[ -f "$PUBSPEC" ]] || die "pubspec.yaml not found: $PUBSPEC"

case "$ENVIRONMENT" in
  production)
    API_BASE_URL="https://api.tcgcard.fun/api/v1"
    ;;
  test)
    API_BASE_URL="https://api-dev.tcgcard.fun/api/v1"
    ;;
  *)
    die "Unsupported environment '$ENVIRONMENT'. Use test or production."
    ;;
esac

ENV_CONFIG="$APP_DIR/config/$ENVIRONMENT.json"
FIREBASE_CONFIG_SOURCE="$APP_DIR/ios/Runner/Firebase/$ENVIRONMENT/GoogleService-Info.plist"
[[ -f "$ENV_CONFIG" ]] || die "Environment config not found: $ENV_CONFIG"
[[ -f "$FIREBASE_CONFIG_SOURCE" ]] || die "Firebase config not found: $FIREBASE_CONFIG_SOURCE"
grep -Eq "\"APP_ENV\"[[:space:]]*:[[:space:]]*\"$ENVIRONMENT\"" "$ENV_CONFIG" \
  || die "$ENV_CONFIG does not select APP_ENV=$ENVIRONMENT"
FIREBASE_PROJECT_ID="$(plist_value "$FIREBASE_CONFIG_SOURCE" PROJECT_ID)"
assert_equal "$BUNDLE_ID" "$(plist_value "$FIREBASE_CONFIG_SOURCE" BUNDLE_ID)" "$ENVIRONMENT Firebase bundle ID"

trap cleanup EXIT

log "Environment: $ENVIRONMENT"

device_udid=""
device_model=""
if [[ -n "$INSTALL_DEVICE" ]]; then
  make_temp_dir
  device_info_dir="$NEW_TEMP_DIR"
  device_info_path="$device_info_dir/device-info.txt"
  xcrun devicectl device info details --device "$INSTALL_DEVICE" >"$device_info_path"
  device_udid="$(awk -F'udid: ' '/udid: / {print $2; exit}' "$device_info_path" | tr -d '\r')"
  device_model="$(awk -F'marketingName: ' '/marketingName: / {print $2; exit}' "$device_info_path" | tr -d '\r')"
  [[ -n "$device_udid" ]] || die "Could not determine the hardware UDID for device: $INSTALL_DEVICE"
  [[ -n "$device_model" ]] || die "Could not determine the model for device: $INSTALL_DEVICE"
  log "Install target: $device_model ($device_udid)"
fi

current_version="$(awk '/^version:[[:space:]]*/ {print $2; exit}' "$PUBSPEC")"
if [[ ! "$current_version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]]; then
  die "Unsupported pubspec version format: $current_version"
fi

marketing_version="${BASH_REMATCH[1]}"
current_build="${BASH_REMATCH[2]}"
current_build_number="$((10#$current_build))"

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$((current_build_number + 1))"
fi

[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "Build number must be a positive integer"
BUILD_NUMBER="$((10#$BUILD_NUMBER))"
(( BUILD_NUMBER > current_build_number )) || die "Build number must be greater than the current build ($current_build)"

new_version="$marketing_version+$BUILD_NUMBER"
log "Selected version: $new_version"

cd "$APP_DIR"

log "Resolving dependencies"
flutter pub get

if [[ "$SKIP_ANALYZE" -eq 0 ]]; then
  log "Running flutter analyze"
  flutter analyze
fi

log "Cleaning previous build products"
flutter clean
flutter pub get

log "Building $ENVIRONMENT App Store IPA"
flutter_build_args=(
  build
  ipa
  --release
  "--build-name=$marketing_version"
  "--build-number=$BUILD_NUMBER"
  "--dart-define-from-file=$ENV_CONFIG"
)
if [[ "$ENVIRONMENT" == "test" ]]; then
  flutter_build_args+=("--flavor=test")
fi
flutter "${flutter_build_args[@]}"

[[ -d "$ARCHIVE_PATH" ]] || die "Archive not found: $ARCHIVE_PATH"
archive_info="$ARCHIVE_PATH/Info.plist"
assert_equal "$BUNDLE_ID" "$(plist_value "$archive_info" ApplicationProperties:CFBundleIdentifier)" "archive bundle ID"
assert_equal "$marketing_version" "$(plist_value "$archive_info" ApplicationProperties:CFBundleShortVersionString)" "archive version"
assert_equal "$BUILD_NUMBER" "$(plist_value "$archive_info" ApplicationProperties:CFBundleVersion)" "archive build number"

app_store_ipa="$(find_single_ipa "$APP_STORE_IPA_DIR")"
validate_common_ipa "$app_store_ipa" "$marketing_version" "$BUILD_NUMBER" "App Store IPA"

app_store_entitlements="$(dirname "$LAST_PROFILE_PATH")/entitlements.plist"
assert_equal "true" "$(plist_value "$app_store_entitlements" beta-reports-active)" "App Store beta-reports-active"
if plist_value "$LAST_PROFILE_PATH" ProvisionedDevices >/dev/null 2>&1; then
  die "App Store profile unexpectedly contains provisioned devices"
fi

verify_dsym_coverage "$LAST_APP_PATH"

packaging_log="$APP_STORE_IPA_DIR/Packaging.log"
if [[ -f "$packaging_log" ]]; then
  grep -Eq '(^|[[:space:]])error:' "$packaging_log" && die "Packaging.log contains an error"
  grep -Eiq 'warning:.*dSYM|dSYM.*missing' "$packaging_log" && die "Packaging.log contains a dSYM warning"
fi

log "Updating pubspec version: $current_version -> $new_version"
NEW_VERSION="$new_version" perl -pi -e 's/^version:[ \t]*\S+[ \t]*$/version: $ENV{NEW_VERSION}/' "$PUBSPEC"
assert_equal "$new_version" "$(awk '/^version:[[:space:]]*/ {print $2; exit}' "$PUBSPEC")" "pubspec version"

log "App Store IPA: $app_store_ipa"
log "App Store IPA SHA-256: $(shasum -a 256 "$app_store_ipa" | awk '{print $1}')"

if [[ -n "$INSTALL_DEVICE" ]]; then
  release_options="$BUILD_ROOT/ReleaseTestingExportOptions.plist"
  write_export_options "$release_options" "release-testing" "export"

  log "Exporting Apple Distribution device IPA"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$DEVICE_IPA_DIR" \
    -exportOptionsPlist "$release_options" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration

  device_ipa="$(find_single_ipa "$DEVICE_IPA_DIR")"
  validate_common_ipa "$device_ipa" "$marketing_version" "$BUILD_NUMBER" "Device IPA"

  provisioned_devices="$(plist_value "$LAST_PROFILE_PATH" ProvisionedDevices)"
  grep -Fq "$device_udid" <<<"$provisioned_devices" \
    || die "Device profile does not include UDID $device_udid"

  log "Installing on $device_model ($device_udid)"
  xcrun devicectl device install app --device "$INSTALL_DEVICE" "$LAST_APP_PATH"

  make_temp_dir
  installed_apps_dir="$NEW_TEMP_DIR"
  installed_apps_path="$installed_apps_dir/installed-apps.txt"
  xcrun devicectl device info apps --device "$INSTALL_DEVICE" --include-all-apps >"$installed_apps_path"
  installed_line="$(grep -F "$BUNDLE_ID" "$installed_apps_path" | head -1 || true)"
  [[ -n "$installed_line" ]] || die "Installed app was not found on the device"
  printf '%s\n' "$installed_line" | grep -Eq "[[:space:]]${marketing_version//./\\.}[[:space:]]+${BUILD_NUMBER}([[:space:]]|$)" \
    || die "Installed app version does not match $marketing_version ($BUILD_NUMBER)"

  log "Device IPA: $device_ipa"
  log "Device IPA SHA-256: $(shasum -a 256 "$device_ipa" | awk '{print $1}')"
  log "Installed $marketing_version ($BUILD_NUMBER) on $device_model"
fi

if [[ "$SHOULD_UPLOAD" -eq 1 ]]; then
  upload_options="$BUILD_ROOT/UploadExportOptions.plist"
  upload_log="$BUILD_ROOT/upload.log"
  write_export_options "$upload_options" "app-store-connect" "upload"

  log "Uploading $marketing_version ($BUILD_NUMBER) to App Store Connect"
  set +e
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$BUILD_ROOT/upload" \
    -exportOptionsPlist "$upload_options" \
    -allowProvisioningUpdates 2>&1 | tee "$upload_log"
  upload_status="${PIPESTATUS[0]}"
  set -e

  [[ "$upload_status" -eq 0 ]] || die "App Store Connect upload failed"
  grep -Fq 'Upload succeeded.' "$upload_log" || die "Upload did not return an explicit success result"
  log "App Store Connect upload succeeded"
fi

log "$ENVIRONMENT release workflow completed for $marketing_version ($BUILD_NUMBER)"
log "pubspec.yaml remains modified; commit the build number when appropriate"
