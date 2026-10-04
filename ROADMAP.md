# mac-phone-link — Roadmap

Single source of truth for the plan. Detailed specs: `docs/PRODUCT.md` (feature
matrix), `docs/ANDROID_APP.md` (the APK), `docs/ARCHITECTURE.md`,
`docs/PROTOCOL.md`. Living build state: `claude/handoff.md`.

## Vision
An open, no-Microsoft, no-cloud equivalent of **AirSync**: Android ⇄ macOS
mirroring and sync. Native macOS app + a custom Android app. Everything over
Bluetooth / Wi-Fi / USB, end-to-end encrypted.

## Hard constraints (reality — don't chase around these)
- **Mirroring needs adb today** (USB or wireless). No loophole on non-rooted
  Android for a third-party tool. The **custom APK removes adb** via
  MediaProjection (capture) + AccessibilityService (input).
- **Bluetooth cannot carry video** (H.264 needs multi-Mbps). BT = companion +
  control + fallback only. Video goes over Wi-Fi or USB.
- **True Wi-Fi Direct P2P is not exposed on macOS.** The no-router equivalent is
  a phone-hosted hotspot (or Mac Internet Sharing).
- No Microsoft Link to Windows / Phone Link code, APIs, or cloud. No Samsung MDX
  APK decompilation.

## Status (2026-10-04)
- PR #1 (draft) on branch `ccr-151fd929-grpp95`, **CI green on macOS**.
- **Works / built (Mac):** windowed SwiftUI app + onboarding; menu-bar extra;
  screen mirroring (scrcpy v4.1 + adb, bundled); per-app windows (own macOS
  window, DeX-decorations off); apps grid from the phone; input (tap/drag);
  scroll-as-touch-drag; device auto-select; startup log + Developer menu (save
  log to Downloads); correct v4.1 handshake + captured server log.
- **Not yet working:** all companion features (need the Android app + transport);
  the current disconnect-on-device is being diagnosed via the saved log.

---

## Milestones (in order)

### M1 — Mirroring solid on-device  🟡 current
- [x] Bundle scrcpy-server v4.1 + adb into the app (no manual setup).
- [x] Correct v4.1 handshake; capture server output; connect retries.
- [x] Device auto-select (hide adb); logging + Developer menu.
- [ ] Confirm mirroring works on the user's phone (awaiting saved log).
- [ ] Real app **icons + labels** in the Apps grid (pull from device).
- [ ] **"Phone apps" folder** next to the .app: per-launchable-app launchers
      that open each app as a mirror (via a `phonelink://open?pkg=` URL scheme).
- [ ] Scroll direction verify/invert; touch-feel tuning.

### M2 — The Android app skeleton + CI  ⬜
- [ ] `android/` Gradle project (Kotlin, Material 3, min SDK 26).
- [ ] CI job builds a debug **APK** artifact (ubuntu-latest).
- [ ] Foreground service + connection lifecycle + QS tile + widgets scaffolding.

### M3 — Encrypted transport + pairing (unlocks most companion features)  ⬜
- [ ] Bluetooth (RFCOMM/BLE) + Wi-Fi (TCP) + USB transports; auto-select & fail
      over to Bluetooth.
- [ ] **QR pairing** (Mac shows QR via dagronf/QRCode; phone scans) + QS-tile
      re-connect.
- [ ] **AES-GCM end-to-end encryption**.
- [ ] Wire `Companion` (Mac) + the app over this transport.

### M4 — Companion features  ⬜ (each is a PRODUCT.md row)
- [ ] **Notifications sync**: receive, post as native macOS notifications.
- [ ] **Sync notification dismissals** (both directions).
- [ ] **Open app on notification click** (→ opens the app's mirror window). [beta]
- [ ] **System Notifications style** setting (how alerts surface on Mac:
      Default / banner / off).
- [ ] **Per-app notification toggles** with app icons + per-app settings (like
      the AirSync "App notifications" list).
- [ ] **Call Alerts**: call-alert style (Pop-up / banner), **Ring for calls**
      toggle.
- [ ] **Media**: Android now-playing + controls on macOS Control Center (bridge
      done); **control Mac playback from phone** (inject system media keys).
- [ ] **Battery + volume** (Android on Mac) and **Mac battery %** in a persistent
      phone notification.
- [ ] **Clipboard sync + text sharing** (both ways).
- [ ] **Ring my phone** (protocol done).
- [ ] **Wallpaper + now-playing album art** shown on Mac.

### M5 — File access  ⬜
- [ ] **File share** both directions.
- [ ] **Drag & drop files onto the window** → paste into the focused Android app,
      or save to a chosen location.
- [ ] **Mount phone storage as a Finder network location / volume** (browse +
      save, bidirectional).

### M6 — No-adb display (APK)  ⬜
- [ ] **MediaProjection** capture + `MediaCodec` H.264 over Wi-Fi/hotspot.
- [ ] **AccessibilityService** input (tap/swipe/back/home) — "keep phone away,
      control from Mac" with no adb.
- [ ] **Desktop mode** (virtual display at desktop resolution + launcher).
- [ ] Wi-Fi Direct via phone hotspot / Mac Internet Sharing for no-router links.

### M7 — Polish & distribution  ⬜
- [ ] Metal zero-copy renderer (latency win over scrcpy).
- [ ] Full keyboard via UHID; right-click / multi-touch / pinch.
- [ ] Developer ID signing + notarization in CI; Sparkle auto-update.
- [ ] Material 3 polish on Android; macOS UI polish (icons, empty states).

---

## Suggested libraries (add at the right milestone)
- **sparkle-project/Sparkle** — auto-update (M7).
- **dagronf/QRCode** — QR pairing (M3).
- **tfmart/LottieUI** — onboarding polish (M7, optional).
- **httpswift/swifter** — only if a local HTTP surface is needed.
- `ungive/media-control` — NOT used (private framework; we publish via public
  MediaPlayer). Only if we ever mirror Mac playback metadata to the phone.

## Credits / licensing
MIT. scrcpy (Apache-2.0, bundled), adb (Apache-2.0, bundled), KDE Connect
protocol shapes reimplemented (no GPL code). See `NOTICE.md`.
