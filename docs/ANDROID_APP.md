# Android companion app (the APK)

The custom Android app is the project's second codebase and the thing that
removes adb and unlocks the companion features. It will live in `android/` with
its own Gradle build and a CI job that produces an APK artifact.

## Why a custom app (not KDE Connect)
KDE Connect is Wi-Fi only and we want Bluetooth + no-adb mirroring. A purpose-built
app gets us: no-adb capture/input, Bluetooth transport, AES E2E, QR pairing, a
QS tile, widgets, and a Material 3 UI.

## No adb — how
- **Screen capture**: `MediaProjection` (one-time system consent dialog). Encode
  with `MediaCodec` (H.264), stream frames. No debugging required.
- **Input injection**: an `AccessibilityService` dispatches taps/swipes
  (`dispatchGesture`). One toggle in settings; no adb, no root. (Limited vs. adb
  HID, but covers tap/scroll/swipe/back/home.)
- **Companion data**: `NotificationListenerService` (notifications),
  `MediaSessionManager` (now playing + controls), `BatteryManager`/intents,
  `ClipboardManager`, `AudioManager` (volume).
- Result: "keep your phone away and control it from the Mac" with only two
  user-granted permissions, no cable, no adb.

## Transports (priority + fallback)
1. **Wi-Fi (LAN or phone hotspot / Mac Internet Sharing)** — for mirroring video
   (needs multi-Mbps). True Wi-Fi Direct P2P isn't exposed on macOS; a
   phone-hosted hotspot is the no-router equivalent.
2. **USB** — phone listens on localhost; Mac reaches it over an adb-free USB
   tunnel if available, or we keep adb only as an optional USB path. Offline.
3. **Bluetooth (RFCOMM/BLE)** — always-available companion + control channel and
   the fallback when Wi-Fi isn't present. Not for video.

The app advertises over all available transports; the Mac picks the best one for
each stream (Wi-Fi for video, Bluetooth for companion/control), and falls back to
Bluetooth when Wi-Fi drops.

## Pairing & security
- **AES-GCM** end-to-end. Session keys established at pairing.
- **QR pairing**: the Mac shows a QR (contains device id + public key +
  connection hints); the phone scans it. A **QS tile** re-connects to a known
  Mac without re-pairing.

## Companion protocol
Reuse the JSON-line packet model already implemented on the Mac
(`Sources/Companion`): `{id, type, body}` newline-delimited, transport-agnostic
(works over Bluetooth RFCOMM, Wi-Fi TCP, or USB). Add packet types as features
land (volume, wallpaper, album art, file-share chunks, Mac-battery).

## Bidirectional media
- Phone → Mac now-playing: already bridged to macOS Control Center
  (`NowPlayingBridge`).
- Mac → phone control: `mpris.request` (implemented).
- **Phone → Mac control** (new): phone sends a media command; the Mac injects a
  system media key (`CGEvent` posting `NX_KEYTYPE_PLAY/NEXT/PREVIOUS`) so it
  controls whatever Mac app is playing.

## Mac-battery notification
The Mac reports its battery (`IOPSCopyPowerSourcesInfo`) over the companion
channel; the app shows an **ongoing** foreground-service notification with the
Mac's battery % while connected.

## Android app stack
- Kotlin, Gradle, min SDK 26, Jetpack Compose + **Material 3**.
- Foreground service for the connection; `MediaProjection` + `MediaCodec`;
  `AccessibilityService`; `NotificationListenerService`; Bluetooth + sockets.
- **Widgets** (now playing, connect/disconnect), **QS tile**.
- CI: Gradle `assembleDebug` on ubuntu-latest → APK uploaded as an artifact.

## Build order (APK milestone)
1. Project skeleton + CI that builds an APK artifact.
2. Companion over Bluetooth + Wi-Fi (notifications, media, battery, clipboard,
   ring) with QR/AES pairing — unlocks most of `docs/PRODUCT.md`.
3. MediaProjection mirroring + AccessibilityService input (no-adb display).
4. File share, wallpaper/album art, widgets, QS tile, desktop mode, Mac-battery
   notification, reverse media control.
