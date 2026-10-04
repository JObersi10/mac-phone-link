# Product spec — the full feature set

The target is an open, no-Microsoft, no-cloud equivalent of AirSync: Android ⇄
macOS sync and mirroring. This file is the master checklist. Every feature the
owner has asked for is here with its plane, the milestone that delivers it, and
an honest feasibility note. Status: ✅ done · 🟡 in progress · ⬜ planned.

## Planes
- **Display** — screen/app mirroring + input. Today: scrcpy over adb. Future:
  the custom Android app via MediaProjection (capture) + AccessibilityService
  (input), removing adb. See `docs/ANDROID_APP.md`.
- **Companion** — everything else (notifications, media, battery, clipboard,
  files…). Custom Android app over Bluetooth + Wi-Fi + USB, AES E2E. KDE Connect
  is no longer the plan (the custom app is).

## Feature checklist

| # | Feature | Plane | Milestone | Status | Notes |
|---|---------|-------|-----------|--------|-------|
| 1 | Android screen mirroring | Display | now (scrcpy) → APK | 🟡 | Works via scrcpy/adb; APK will use MediaProjection |
| 2 | App mirroring (app in its own window) | Display | now | 🟡 | Per-app virtual display; opens in its own macOS window; `no_vd_system_decorations` to avoid DeX |
| 3 | Desktop mode | Display | later | ⬜ | Virtual display at desktop resolution + launcher |
| 4 | Click notification → open that app (mirror) | Both | after transport | ⬜ | Notification carries package → open app window |
| 5 | Notification sync + dismissals | Companion | transport | ⬜ | NotificationListenerService; dismiss both ways |
| 6 | Android now-playing + media controls (→ Mac) | Companion | transport | 🟡 | Protocol + `NowPlayingBridge` ready; needs transport |
| 7 | Control **Mac** playback from phone (reverse) | Companion | transport | ⬜ | Inject system media keys on Mac (CGEvent NX_KEYTYPE_PLAY) |
| 8 | Android battery + volume on Mac | Companion | transport | 🟡 | Battery modeled; volume to add |
| 9 | **Mac** battery % in a persistent phone notification | Companion | transport | ⬜ | Mac sends battery (IOPowerSources) → APK ongoing notification |
| 10 | Clipboard sync + text sharing | Companion/Display | transport | 🟡 | scrcpy clipboard now; full sync via companion |
| 11 | File share | Companion | transport | ⬜ | Chunked transfer over the companion channel |
| 12 | Android wallpaper + album art on Mac | Companion | transport | ⬜ | Fetch wallpaper + art bytes over companion |
| 13 | Ring my phone | Companion | transport | 🟡 | Protocol ready; needs transport |
| 14 | "Keep phone away, control from Mac" | Both | APK | ⬜ | No-adb control via AccessibilityService + BT |
| 15 | End-to-end encryption (AES) | Transport | transport | ⬜ | AES-GCM session keys from pairing |
| 16 | Scan QR to authenticate | Both | transport | ⬜ | Mac shows QR (dagronf/QRCode); phone scans to pair |
| 17 | Quick-Settings tile to re-connect | APK | APK | ⬜ | Android QS tile toggles the connection |
| 18 | Widgets on Android | APK | APK | ⬜ | Home-screen widgets (now playing, connect) |
| 19 | Material 3 UI (Android app) | APK | APK | ⬜ | Jetpack Compose + Material 3 |
| 20 | Native macOS UI | Mac | now | 🟡 | SwiftUI windowed app + menu-bar extra |
| 21 | Menu-bar icon + quick actions | Mac | now | ✅ | MenuBarExtra |
| 22 | Startup log + Developer menu (save log) | Mac | now | ✅ | `AppLog` + Developer menu |
| 23 | Device auto-select (hide adb) | Mac | now | ✅ | Auto-picks a device; picker only when several |
| 24 | Scroll = touch-drag (natural) | Display | now | 🟡 | Scroll emulates a finger swipe |
| 25 | "Phone apps" folder of launchers | Mac | next | ⬜ | Folder next to the app with per-app launchers (URL scheme) |
| 26 | App icons + labels (not package names) | Mac | next | ⬜ | Pull real icons/labels from device |

## Transport options for mirroring (no shared router)
- **USB** — works offline today, carries everything.
- **Wi-Fi (same LAN)** — works today.
- **Wi-Fi Direct / hotspot** — the owner's preference for no-router. True Wi-Fi
  Direct P2P is **not exposed on macOS** (no public API; AWDL is AirDrop-only),
  so the practical equivalent is **phone-hosted hotspot** (or Mac Internet
  Sharing): the two devices form a direct Wi-Fi link with no router, at Wi-Fi
  bandwidth. To implement in the APK milestone.
- **Bluetooth** — companion/control only; cannot carry H.264 video.

## Honest scope note
This is a large, multi-milestone product (an open AirSync). It will be built
incrementally: the Mac display/UI first (in progress), then the custom Android
app + encrypted transport (the bulk of the companion features), which unlocks
most rows above at once.
