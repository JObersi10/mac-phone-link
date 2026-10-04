#!/usr/bin/env bash
#
# Build PhoneLink in release mode and assemble a .app bundle (and, if hdiutil is
# available, a .dmg). Runs headlessly — no Xcode project, just the Swift
# toolchain. Produces:
#   build/PhoneLink.app
#   build/mac-phone-link.dmg   (macOS only)
#
set -euo pipefail

APP_NAME="PhoneLink"
BUNDLE="${APP_NAME}.app"
BUILD_DIR="build"
CONFIG="release"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"

echo "==> Assembling ${BUNDLE}"
rm -rf "${BUILD_DIR}/${BUNDLE}"
mkdir -p "${BUILD_DIR}/${BUNDLE}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${BUNDLE}/Contents/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${BUILD_DIR}/${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${BUILD_DIR}/${BUNDLE}/Contents/Info.plist"

# Bundle any SwiftPM resource bundles that were produced (if any).
if ls "${BIN_PATH}"/*.bundle >/dev/null 2>&1; then
  cp -R "${BIN_PATH}"/*.bundle "${BUILD_DIR}/${BUNDLE}/Contents/Resources/" || true
fi

echo "==> Ad-hoc code signature (unsigned distribution)"
# Ad-hoc signing lets the app run locally after the quarantine attribute is
# cleared; it is NOT notarized. See README "Installing an unsigned build".
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${BUILD_DIR}/${BUNDLE}" || \
    echo "    (codesign failed; the .app is still usable after clearing quarantine)"
fi

if command -v hdiutil >/dev/null 2>&1; then
  echo "==> Creating DMG"
  rm -f "${BUILD_DIR}/mac-phone-link.dmg"
  STAGING="$(mktemp -d)"
  cp -R "${BUILD_DIR}/${BUNDLE}" "${STAGING}/"
  ln -s /Applications "${STAGING}/Applications"
  hdiutil create -volname "mac-phone-link" -srcfolder "${STAGING}" \
    -ov -format UDZO "${BUILD_DIR}/mac-phone-link.dmg"
  rm -rf "${STAGING}"
  echo "==> build/mac-phone-link.dmg"
else
  echo "==> hdiutil not available (non-macOS host); skipping DMG"
fi

echo "==> Done: ${BUILD_DIR}/${BUNDLE}"
