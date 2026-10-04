# handoff.md — living state

> Update this after any big implementation step and before compaction, so the
> next session loses nothing crucial. Newest status at top.

## 2026-10-04 — Windowed SwiftUI UI + onboarding

### Done
- Replaced the menu-bar-only AppKit app with a **windowed SwiftUI app** (Phone
  Link-style). Deleted `main.swift`, `AppController.swift`,
  `MirrorWindowController.swift`; removed `LSUIElement`.
- New files: `PhoneLinkApp.swift` (@main + onboarding gate), `AppModel.swift`
  (ObservableObject + `SessionBox`), `OnboardingView.swift`, `MainWindow.swift`
  (NavigationSplitView: sidebar with device header / quick actions / now-playing
  / notifications; detail with Phone Screen / Apps / Messages / Calls / Photos
  tabs; `MirrorRepresentable` embeds the decode view). `InteractiveFrameView`
  moved into `FrameRenderView.swift`.
- Mirroring (full screen + per-app windows) renders inside the window. Companion
  panels (media, notifications, battery) are wired to `AppModel` and fill in once
  the transport lands.

### Committed transport decision (user)
- Build a **custom Android companion app** (own repo/dir) doing **Bluetooth +
  Wi-Fi with USB fallback**. This is the next big milestone and includes the
  Mac-side CoreBluetooth transport. KDE Connect is Wi-Fi-only so we're rolling
  our own phone app (this is the APK the user wanted; build it in CI).

### Next
1. Get this UI rewrite green on CI (first SwiftUI build — expect a few fixes).
2. Custom Android app + Mac BT/Wi-Fi/USB transport.

## 2026-10-04 — Bundle tools (v4.1) + transport reality

### Done
- **Bundled scrcpy-server v4.1 and adb** (user-provided) at `vendor/scrcpy-server`
  and `vendor/adb` (committed; adb is a 19MB universal binary). `package-app.sh`
  copies both + `vendor/scrcpy-LICENSE` into `PhoneLink.app/Contents/Resources`.
  `SessionManager` and `AdbBridge` prefer the bundled copies. This fixes the
  "scrcpy-server jar not found" error the user hit.
- Bumped `ScrcpyServer.pinnedVersion` → **4.1** (enables resizable virtual
  displays → aspect-ratio button's live resize). Version string must match the
  bundled server exactly.
- NOTICE updated for bundling (Apache-2.0: scrcpy-server + adb).

### HARD REALITY CONSTRAINTS (do not chase these; told the user)
- **Mirroring requires adb** (USB cable or wireless debugging) — no loophole on
  non-rooted Android. Phone Link skips it only because Samsung's phone app is a
  privileged OEM system app; we can't be one. Capture + input injection need
  shell/root privilege.
- **Bluetooth cannot carry mirroring** — H.264 needs multi-Mbps; BT/BLE can't.
  Even Phone Link uses Wi-Fi for mirroring; BT only for call audio + signaling.
- **Offline / not-same-network**: the real answer is **USB cable** (carries
  everything, no network, works offline). Wi-Fi needs same LAN. BT would need a
  custom phone app (KDE Connect is Wi-Fi only) and still couldn't mirror.
- Companion features (notifications/media/ring/battery) need NO debugging — Wi-Fi
  via KDE Connect, or tunnel over USB for offline.

### Next (user's chosen order: both → windowed UI → companion transport)
1. [this commit] bundling — DONE, verify CI green.
2. Windowed Phone Link-style UI (NavigationSplitView) + onboarding (replace the
   menu-bar-only app). Onboarding should offer `adb install` of KDE Connect and
   explain USB-vs-Wi-Fi honestly.
3. Companion transport (mDNS + TLS pairing) — unlocks the no-debug features.

## 2026-10-04 — Seamless-UX pass + claude/ folder

**Branch:** `ccr-151fd929-grpp95` · **PR:** JObersi10/mac-phone-link#1 (draft)

### Done
- Two-plane scaffold committed (display: scrcpy over adb + VideoToolbox;
  companion: KDE Connect protocol). ~2k LOC Swift, SwiftPM, CI on macos-latest.
- Protocol unit tests for control-message byte layout and KDE Connect packets.
- This pass added:
  - `claude/claude.md` + `claude/handoff.md` (this file), and a root `CLAUDE.md`
    pointer so guidance auto-loads.
  - `RESIZE_DISPLAY` control message (`ScrcpyProtocol`) + test.
  - Mirror-window **aspect-ratio toggle button** (native phone ratio ↔ 16:9),
    live via `window.contentAspectRatio` (client-side, always works) and, for
    virtual-display sessions, a device-side RESIZE_DISPLAY send (needs scrcpy
    ≥ 4.0 to actually relayout).
  - `NowPlayingBridge` (`PhoneLink`, MediaPlayer framework): publishes phone
    media to macOS Control Center and routes remote commands back to the phone.
  - Notification → open-app-mirror hook (clicking a companion notification asks
    AppController to open a per-app mirror window).
  - Docs updated (FEATURES, ROADMAP, ARCHITECTURE) + libraries recorded in
    claude.md.

### Build status
- **CI is GREEN on macOS** as of commit `216533b` (runs #7/#8). It compiles on
  the macOS 26 / Swift 6.3 runner, `swift test` passes, and the workflow
  packages `PhoneLink.app` + `mac-phone-link.dmg` and uploads them as artifacts.
- Two first-build errors were found and fixed: `FrameRenderView` was `final`
  while being subclassed (`cfe6470`), and `sizeToFit()` was called on `NSView`
  instead of `NSControl` (`216533b`).
- Green means it *builds and unit-tests pass* — NOT that end-to-end mirroring
  works. That still needs a real device + scrcpy-server + the companion
  transport.

### Not done / still true from before
- Companion **encrypted transport** (mDNS + TLS pairing on :1716) not
  implemented. Until it is, `companion` is nil, Now Playing has no data source,
  notifications don't arrive, and companion menu items show a setup notice.
- On-device validation of the whole streaming path still pending.

### Next steps (in order)
1. Get CI green — fix whatever the macos-latest build surfaces first.
2. Milestone 1 (docs/ROADMAP.md): first on-device mirror; verify scrcpy 3.1
   handshake/video framing against a real device.
3. Milestone 3: companion transport — this unlocks notifications, Now Playing,
   ring, battery all at once.

### Open decisions
- **Bump scrcpy pin to 4.x?** The aspect-ratio button's *live device resize* and
  resizable virtual displays need scrcpy ≥ 4.0. Core control-message layouts are
  largely stable 3.x→4.x, but re-verify before bumping. Recommendation: bump at
  Milestone 2 and re-run the protocol tests. Until then the button does
  client-side framing only.
- appName→package resolution for notification→mirror: KDE Connect notifications
  carry `appName`, not the Android package. Need a lookup (e.g.
  `adb shell pm list packages` + label match, or a user-editable map). Hook is in
  place; resolution is a TODO.

### Known risks / gotchas
- `NWEndpoint.Host(host)` with a String variable — RESOLVED: compiles fine on
  Swift 6.3.
- `MPNowPlayingInfoCenter.playbackState` — RESOLVED: compiles fine on macOS 26.
- VideoToolbox async decode: block buffers must OWN their memory (fixed in
  `H264Decoder.decodeAVCC` — copies into an assured block buffer).
- `MPNowPlayingInfoCenter` from an `LSUIElement` accessory app: compiles, but
  whether it registers as a Now Playing source at runtime is unverified (no
  device/runtime test yet).
