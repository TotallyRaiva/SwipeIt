#!/usr/bin/env bash
set -euo pipefail

# SwipeIt — DMG Packaging Script
# Builds SwipeIt.app in Release configuration and packages it into a compressed .dmg with an /Applications symlink.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="SwipeIt"
SCHEME_NAME="SwipeIt"
CONFIGURATION="Release"
BUILD_DIR="${PROJECT_ROOT}/build"
DIST_DIR="${PROJECT_ROOT}/dist"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
STAGING_DIR="${BUILD_DIR}/dmg_staging"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"

echo "==========================================="
echo " Building ${APP_NAME} (${CONFIGURATION})"
echo "==========================================="

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# 1. Build the Release application bundle
echo "==> Compiling Release binary with xcodebuild..."
xcodebuild \
    -project "${PROJECT_ROOT}/${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration "${CONFIGURATION}" \
    -destination "platform=macOS" \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

BUILT_APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"

if [ ! -d "${BUILT_APP}" ]; then
    echo "Warning: Not found at ${BUILT_APP}, searching DerivedData..."
    FOUND_APP=$(find "${DERIVED_DATA}" -name "${APP_NAME}.app" -type d | head -n 1)
    if [ -n "${FOUND_APP}" ] && [ -d "${FOUND_APP}" ]; then
        BUILT_APP="${FOUND_APP}"
        echo "Found at: ${BUILT_APP}"
    else
        echo "ERROR: Built application not found in ${DERIVED_DATA}"
        exit 1
    fi
fi

# 2. Stage the app and /Applications symlink
echo "==> Staging ${APP_NAME}.app and /Applications symlink..."
cp -R "${BUILT_APP}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# 3. Create compressed DMG using hdiutil
echo "==> Creating compressed DMG package..."
rm -f "${DMG_PATH}"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

# 4. Generate SHA-256 checksum
echo "==> Generating SHA-256 checksum..."
cd "${DIST_DIR}"
shasum -a 256 "${APP_NAME}.dmg" > "${APP_NAME}.dmg.sha256"

DMG_SIZE=$(du -h "${DMG_PATH}" | cut -f1)
DMG_HASH=$(cat "${APP_NAME}.dmg.sha256")

echo "==========================================="
echo " SUCCESS! DMG created:"
echo " File:   ${DMG_PATH}"
echo " Size:   ${DMG_SIZE}"
echo " SHA256: ${DMG_HASH}"
echo "==========================================="
