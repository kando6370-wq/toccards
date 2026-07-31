#!/bin/sh

set -eu

if [ -z "${FIREBASE_ENVIRONMENT:-}" ]; then
  echo "error: FIREBASE_ENVIRONMENT is not configured."
  exit 1
fi

source_plist="${PROJECT_DIR}/Runner/Firebase/${FIREBASE_ENVIRONMENT}/GoogleService-Info.plist"
destination_plist="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"

if [ ! -f "${source_plist}" ]; then
  echo "error: Firebase configuration not found: ${source_plist}"
  exit 1
fi

firebase_bundle_id=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "${source_plist}")
if [ "${firebase_bundle_id}" != "${PRODUCT_BUNDLE_IDENTIFIER}" ]; then
  echo "error: Firebase BUNDLE_ID ${firebase_bundle_id} does not match ${PRODUCT_BUNDLE_IDENTIFIER}."
  exit 1
fi

/bin/cp "${source_plist}" "${destination_plist}"
echo "Selected ${FIREBASE_ENVIRONMENT} Firebase configuration for ${PRODUCT_BUNDLE_IDENTIFIER}."
