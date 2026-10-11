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
chmod +x "$MACOS/PhoneLink"

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
</dict>
</plist>
PLIST

echo "Built: $APP"
