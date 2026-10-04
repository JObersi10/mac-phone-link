# claude.md — working guide for mac-phone-link

This file is for any Claude (or human) session picking up this project. Read it
and `claude/handoff.md` before doing anything. `handoff.md` is the living state;
this file is the stable context.

## What this project is

An open, no-Microsoft, no-cloud equivalent of **AirSync**: Android ⇄ macOS
mirroring and sync. A **native windowed SwiftUI macOS app** (+ menu-bar extra)
and a **custom Android app** (the APK). Screen/app mirroring, notifications,
media, ring, battery, clipboard, files — over Bluetooth / Wi-Fi / USB, E2E
encrypted. **The full plan lives in `ROADMAP.md`** (read it first after this).

Current status: PR #1, CI green on macOS. Mac display + UI largely built
(mirroring via scrcpy/adb, per-app windows, apps grid, menu bar, logging). The
companion half needs the Android app + transport (next milestones).

## Hard constraints (do not cross these)

1. **No Microsoft.** Do not reverse-engineer, impersonate, or connect to
   Microsoft Link to Windows / Phone Link cloud, OAuth, Device Graph, or WNS.
   Do not decompile or incorporate the Samsung MDX ("Link to Windows") APK.
2. **No cloud.** Everything is Bluetooth + Wi-Fi + USB. No WNS/cloud fallback.
3. Deliver the *experience* of AirSync/Phone Link through open means.

Reality limits (don't chase loopholes — all explained to the owner):
- Mirroring needs adb today (USB/wireless); the **custom APK removes adb** via
  MediaProjection + AccessibilityService.
- Bluetooth can't carry video (H.264 bandwidth); BT = companion/control/fallback.
- True Wi-Fi Direct P2P isn't exposed on macOS → phone hotspot / Internet Sharing.

These are product constraints the owner set; honor them.

## Architecture — two planes (see docs/ARCHITECTURE.md)

- **Display plane**: drive `scrcpy-server` over `adb`. Screen capture, per-app
  **virtual displays** (`new_display` + `start_app`), input injection. Native
  VideoToolbox decode + AppKit windows replace scrcpy's SDL client.
- **Companion plane**: notifications, media, ring, battery, clipboard, files.
  Phone side is the **custom Android app** (NOT KDE Connect — that was the
  earlier plan, dropped because it's Wi-Fi-only and we want Bluetooth + no-adb).
  The Mac-side `Companion` module's JSON packet shapes (modeled on KDE Connect)
  are reused as our transport-agnostic protocol for the custom app. See
  `docs/ANDROID_APP.md`.

## Module map (SwiftPM targets)

| Target | Role | Platform |
| --- | --- | --- |
| `ScrcpyProtocol` | scrcpy wire format (control/video/device msgs). Pure, tested. | portable |
| `AdbBridge` | drive `adb`, push + launch scrcpy-server | Foundation |
| `VideoPipeline` | Annex-B + VideoToolbox H.264 decode | VideoToolbox |
| `Streaming` | `DeviceSession`, sockets, de-framing | Network |
| `Companion` | Companion packets + client (KDE-Connect-shaped JSON; our protocol). Pure, tested. | portable |
| `PhoneLink` | **SwiftUI windowed app** + menu-bar extra, mirror windows, apps grid, Now Playing bridge, AppLog | SwiftUI/AppKit, MediaPlayer |

Key `PhoneLink` files: `PhoneLinkApp.swift` (@main, MenuBarExtra, app-window
WindowGroup), `AppModel.swift` (+ `SessionBox`, `MainTab`), `MainWindow.swift`
(sidebar + tabs + apps grid + `AppMirrorWindow`), `OnboardingView.swift`,
`FrameRenderView.swift` (+ `InteractiveFrameView`: input + scroll-as-drag),
`NowPlayingBridge.swift`, `SessionManager.swift`, `AppLog.swift`.

## Pinned protocol versions

- scrcpy server: `ScrcpyProtocol.ScrcpyServer.pinnedVersion` = **4.1**, bundled
  at `vendor/scrcpy-server` and copied into the app. 4.1 gives resizable virtual
  displays, so the aspect-ratio button's live device-side resize works. The
  version string MUST match the bundled server exactly (scrcpy-server validates
  it).
- `adb`: bundled at `vendor/adb` (universal binary from scrcpy macOS v4.1),
  copied into the app; `AdbBridge` prefers it.
- KDE Connect: protocol v7.

Protocol byte/JSON layouts are version-specific — re-verify against upstream
when bumping, and keep the unit tests in `Tests/` green.

## Seamless-UX targets (what "all-in-one" means here)

- **Now Playing on macOS Control Center**: phone's media state → Apple's
  `MPNowPlayingInfoCenter`; Control Center / media keys → `MPRemoteCommandCenter`
  → forwarded to the phone via KDE Connect MPRIS. (Use the native MediaPlayer
  framework, NOT the private MediaRemote framework.)
- **Notification → screen mirror of that app**: clicking a mirrored notification
  opens a per-app virtual-display window for the originating app.
- **Mirror window aspect-ratio button**: toggles native phone ratio ↔ 16:9,
  updating live (no close/reopen). Client-side framing always works; true
  device-resolution change uses scrcpy RESIZE_DISPLAY (needs scrcpy ≥ 4.0).

## Suggested libraries and where they fit (add at the right milestone, not before base compiles)

- **sparkle-project/Sparkle** — auto-update for the `.dmg`. Milestone 6
  (distribution), after signing/notarization exists.
- **dagronf/QRCode** — render/scan the pairing QR for the companion TLS pairing.
  Milestone 3 (companion transport).
- **httpswift/swifter** — tiny local HTTP server, if we expose a local control
  API or serve photo thumbnails. Optional; only if a feature needs it.
- **tfmart/LottieUI** — onboarding / empty-state animation polish. Cosmetic;
  late.
- **ungive/media-control** — NOT used. It reads others' now-playing via private
  MediaRemote; we publish via public MediaPlayer instead. Keep only if we ever
  need to *mirror Mac playback to the phone*.

## Build / test / run

```bash
swift build -c release
swift test
./scripts/package-app.sh    # build/PhoneLink.app + build/mac-phone-link.dmg
```

No Xcode project. CI (`.github/workflows/build.yml`, macos-latest) is the real
compile gate — there is no local Swift toolchain in the cloud dev environment.

## Conventions

- Keep protocol correctness in the pure targets (`ScrcpyProtocol`, `Companion`)
  with unit tests asserting exact layout.
- Don't fabricate protocol details. If a byte layout is uncertain, pin a version,
  cite the upstream file, and mark it to verify — don't guess silently.
- Commit messages: clear subject + body. Attribution footer per session rules.

## Where to look first

- **The plan (everything): `ROADMAP.md`** (top level) + `docs/PRODUCT.md`
  (full feature matrix).
- Current state & next steps: `claude/handoff.md`
- The Android app: `docs/ANDROID_APP.md`
- Design: `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md`
- Credits/licensing: `NOTICE.md`
