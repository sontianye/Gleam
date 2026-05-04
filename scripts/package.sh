#!/bin/bash
set -euo pipefail

# ── Gleam Build & Package Script ─────────────────────────────────────────────
# Produces a signed .app bundle and .dmg for distribution.
#
# Usage:
#   ./scripts/package.sh              # build + sign + dmg
#   ./scripts/package.sh --skip-build # skip swift build, reuse existing binary

cd "$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Sources/Gleam/Info.plist)
APP_NAME="Gleam"
BUNDLE_ID="com.sontianye.Gleam"
BUILD_DIR=".build/release"
APP_BUNDLE="build/${APP_NAME}.app"
DMG_NAME="Gleam-${VERSION}.dmg"

echo "── Building ${APP_NAME} v${VERSION} ──"

# Step 1: Build
if [[ "${1:-}" != "--skip-build" ]]; then
    echo "[1/5] Building release binary..."
    swift build -c release
else
    echo "[1/5] Skipping build (reusing existing binary)"
fi

# Step 2: Assemble .app bundle
echo "[2/5] Assembling .app bundle..."
rm -rf build
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Sources/Gleam/Info.plist   "${APP_BUNDLE}/Contents/Info.plist"
cp Sources/Gleam/Resources/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Step 3: Code sign
echo "[3/5] Code signing..."
codesign --force --deep --sign - \
    --options runtime \
    --entitlements Sources/Gleam/Gleam.entitlements \
    "${APP_BUNDLE}"

# Verify
codesign --verify --deep --strict "${APP_BUNDLE}" 2>&1

# Step 4: Create DMG
echo "[4/5] Creating DMG..."
rm -f "build/${DMG_NAME}"

DMG_STAGING="build/dmg_staging"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING}" -ov -format UDZO "build/${DMG_NAME}"
rm -rf "${DMG_STAGING}"

# Step 5: Report
echo "[5/5] Done!"
echo ""
echo "  App:   ${APP_BUNDLE}"
echo "  DMG:   build/${DMG_NAME}"
echo "  Size:  $(du -h "build/${DMG_NAME}" | cut -f1)"
echo ""
echo "Upload to GitHub:"
echo "  gh release upload v${VERSION} build/${DMG_NAME}"
