#!/usr/bin/env bash
# Assemble a PhoneLink.app bundle around the built executable.
# Usage: scripts/package-app.sh <binary-path> <output-dir> [version]
set -euo pipefail

BIN="${1:?usage: package-app.sh <binary-path> <output-dir> [version]}"
OUT_DIR="${2:?missing output dir}"
VERSION="${3:-0.0.0}"

APP="$OUT_DIR/PhoneLink.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp "$BIN" "$MACOS/PhoneLink"
# Executable bit required inside the bundle (755), else Launch Services rejects it.
chmod 755 "$MACOS/PhoneLink"

# Embed dynamic frameworks the binary links via @rpath (e.g. MSAL.framework).
# Without this the app aborts at launch: "Library not loaded: @rpath/…".
BIN_DIR="$(cd "$(dirname "$BIN")" && pwd)"
FRAMEWORKS="$APP/Contents/Frameworks"
shopt -s nullglob 2>/dev/null || true
embedded=0
for fw in "$BIN_DIR"/*.framework; do
  mkdir -p "$FRAMEWORKS"
  cp -R "$fw" "$FRAMEWORKS/"
  embedded=$((embedded+1))
  echo "embedded framework: $(basename "$fw")"
done
if [ "$embedded" -gt 0 ]; then
  # Make sure dyld looks inside the bundle for the embedded frameworks.
  if ! otool -l "$MACOS/PhoneLink" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/PhoneLink"
  fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Phone Link</string>
  <key>CFBundleDisplayName</key><string>Phone Link</string>
  <key>CFBundleIdentifier</key><string>com.maclink.phonelink</string>
  <key>CFBundleExecutable</key><string>PhoneLink</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <!-- MSAL redirect: ASWebAuthenticationSession returns to this custom scheme. -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.maclink.phonelink.msauth</string>
      <key>CFBundleURLSchemes</key>
      <array><string>msauth.com.maclink.phonelink</string></array>
    </dict>
  </array>
  <!-- Local-network (Bonjour) discovery prompt used by onboarding permissions. -->
  <key>NSLocalNetworkUsageDescription</key>
  <string>Phone Link discovers and connects to your phone over the local network.</string>
  <key>NSBonjourServices</key>
  <array><string>_maclink._tcp</string></array>
</dict>
</plist>
PLIST

# Ad-hoc code sign so Launch Services sees a (self-)signed bundle. This does NOT
# notarize — downloaded copies still carry the com.apple.quarantine attribute,
# but an ad-hoc signature turns the fatal "is damaged and can't be opened" into
# the recoverable "unidentified developer" (right-click → Open). Proper Developer
# ID signing/notarization is wired in CI when the secrets are present (see
# claude/claude.md). `codesign` only runs on macOS; skip gracefully elsewhere.
if command -v codesign >/dev/null 2>&1; then
  # Sign embedded frameworks first, then the app bundle (deep as a backstop).
  if [ -d "$FRAMEWORKS" ]; then
    for fw in "$FRAMEWORKS"/*.framework; do
      codesign --force --sign - --timestamp=none "$fw"
    done
  fi
  codesign --force --deep --sign - --timestamp=none "$APP"
  codesign --verify --deep --strict "$APP" && echo "ad-hoc signed: $APP"
else
  echo "warning: codesign not found; bundle left unsigned" >&2
fi

echo "Built: $APP"
