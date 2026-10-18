#!/usr/bin/env bash
# phonelink-logcat.sh — capture the Android "Link to Windows" pairing flow.
#
# Run it, do the pairing on the phone, press Enter. It stops, redacts, and writes
# the shareable file next to this script.
#
# Needs: adb on PATH, phone connected with USB debugging on.
# Usage:  ./phonelink-logcat.sh

set -euo pipefail
out_raw="phonelink_pairing_android.txt"
out_red="phonelink_pairing_android.redacted.txt"

command -v adb >/dev/null || { echo "adb not found on PATH"; exit 1; }

echo "Bumping logcat buffer and clearing it..."
adb logcat -G 16M >/dev/null 2>&1 || true
adb logcat -c

echo ">>> Do the pairing on the phone NOW. <<<"
echo "Capturing to $out_raw ..."
# Capture in the background; stop on Enter.
adb logcat -v threadtime -b all > "$out_raw" &
cap_pid=$!

read -r -p "When finished, press Enter to STOP..." _
kill "$cap_pid" 2>/dev/null || true
wait "$cap_pid" 2>/dev/null || true

echo "Redacting -> $out_red"
sed -E \
  -e 's/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9._-]+/<JWT>/g' \
  -e 's/([Bb]earer )[A-Za-z0-9._-]+/\1<REDACTED>/g' \
  -e 's/[A-Za-z0-9+/]{40,}={0,2}/<B64>/g' \
  -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<EMAIL>/g' \
  "$out_raw" > "$out_red"

echo ""
echo "===== DONE ====="
echo "SHARE this:  $out_red"
echo "RAW (keep local): $out_raw"
echo "Interesting lines mention: appmanager / ypp / nano / dcg / pairing / ice / stun / turn"
