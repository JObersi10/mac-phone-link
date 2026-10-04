# claude.md — working guide for mac-phone-link

This file is for any Claude (or human) session picking up this project. Read it
and `claude/handoff.md` before doing anything. `handoff.md` is the living state;
this file is the stable context.

## What this project is

A native macOS menu-bar companion for an Android phone: screen mirroring,
per-app windows, notifications, media control, ring-my-phone, battery, clipboard,
calls. The goal is the *seamless, all-in-one* experience Windows Phone Link
gives — but native to macOS, and without its clunk.

## Hard constraints (do not cross these)

1. **No Microsoft.** Do not reverse-engineer, impersonate, or connect to
   Microsoft Link to Windows / Phone Link cloud, OAuth, Device Graph, or WNS.
   Do not decompile or incorporate the Samsung MDX ("Link to Windows") APK.
2. **No cloud at all, for now.** Everything is LAN + USB + (later) BLE. The role
   Microsoft's cloud played (WNS fallback) is intentionally dropped; proximity /
   fallback becomes BLE later.
3. Deliver the *experience* of Phone Link through open means, not its protocol.

These are product constraints the owner set; honor them.

## Architecture — two planes (see docs/ARCHITECTURE.md)

- **Display plane**: drive `scrcpy-server` over `adb`. Screen capture, per-app
  **virtual displays** (`new_display` + `start_app`), input injection. Native
  VideoToolbox decode + AppKit windows replace scrcpy's SDL client.
- **Companion plane**: reimplement the **KDE Connect** desktop protocol (no GPL
  code copied) for notifications, media (MPRIS), ring (findmyphone), battery,
  clipboard, telephony. Phone side = the KDE Connect Android app.

## Module map (SwiftPM targets)

| Target | Role | Platform |
| --- | --- | --- |
| `ScrcpyProtocol` | scrcpy wire format (control/video/device msgs). Pure, tested. | portable |
| `AdbBridge` | drive `adb`, push + launch scrcpy-server | Foundation |
| `VideoPipeline` | Annex-B + VideoToolbox H.264 decode | VideoToolbox |
| `Streaming` | `DeviceSession`, sockets, de-framing | Network |
| `Companion` | KDE Connect packets + client. Pure, tested. | portable |
| `PhoneLink` | AppKit menu-bar app, mirror windows, Now Playing bridge | AppKit, MediaPlayer |

## Pinned protocol versions

- scrcpy server: `ScrcpyProtocol.ScrcpyServer.pinnedVersion` (currently 3.1).
  NOTE: live virtual-display resize (the aspect-ratio button's device-side path)
  needs scrcpy **≥ 4.0** (resizable virtual display). See handoff "Open
  decisions".
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

- Current state & next steps: `claude/handoff.md`
- Design: `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md`
- Feature parity map: `docs/FEATURES.md`
- Plan: `docs/ROADMAP.md`
- Credits/licensing: `NOTICE.md`
