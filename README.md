# mac-phone-link

A native macOS companion for an Android phone — screen mirroring, per-app
windows, notifications, media control, "ring my phone", battery and clipboard —
built to fill the gap where Windows has **Phone Link** and the Mac has nothing
good.

It is **not** a Phone Link clone and does **not** talk to Microsoft. See
[Why not Microsoft / Link to Windows](#why-not-microsoft--link-to-windows).

> Status: **early scaffold.** The architecture, the protocol layer, and the
> headless build pipeline are in place and unit-tested. The end-to-end
> streaming path and the companion (notifications/media/ring) transport are
> partially implemented — see [What works today](#what-works-today) for an
> honest breakdown. Nothing here has been compiled on macOS yet in this repo's
> history; the GitHub Actions build on `macos-latest` is the first real
> compile. Expect to fix build errors as CI surfaces them.

## The idea in one picture

mac-phone-link is **two independent planes** talking to the same phone:

```
                 ┌──────────────────────── macOS app (this repo) ───────────────────────┐
                 │                                                                        │
  ┌─────────┐    │   Display plane (Streaming + VideoPipeline)                            │
  │ Android │◄───┼── adb ──► scrcpy-server ──► H.264 over TCP ──► VideoToolbox ──► window  │
  │  phone  │    │   mouse/keyboard ◄── scrcpy control protocol ◄── AppKit events         │
  │         │    │                                                                        │
  │         │◄───┼── Companion plane (Companion) ─────────────────────────────────────┐   │
  └─────────┘    │   KDE Connect protocol over TLS: notifications, media, ring,        │   │
                 │   battery, clipboard, calls/SMS                                     │   │
                 └────────────────────────────────────────────────────────────────────┴───┘
```

- **Display plane** reuses [scrcpy](https://github.com/Genymobile/scrcpy)'s
  server (Apache-2.0) over `adb`. scrcpy already solves screen capture, H.264
  encoding, **per-app virtual displays**, and input injection. We replace
  scrcpy's SDL desktop client with a native macOS one (VideoToolbox decode,
  AppKit windows) — which is where a smoother, more reliable experience than the
  stock scrcpy app comes from.
- **Companion plane** speaks the
  [KDE Connect](https://github.com/KDE/kdeconnect-kde) protocol to the KDE
  Connect Android app, which already implements notifications, media control,
  find-my-phone, battery, clipboard and telephony. We reimplement the desktop
  side of that protocol (the protocol is not copyrightable; **no GPL code is
  copied** — see [NOTICE.md](NOTICE.md)).

Full design: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Feature-by-feature mapping of the Phone Link UI: [docs/FEATURES.md](docs/FEATURES.md).

## Why not Microsoft / Link to Windows

Link to Windows pairs your phone to a Microsoft account and registers a signed
Windows host client against Microsoft's cloud. Making a Mac masquerade as that
host would mean reverse-engineering and impersonating Microsoft's first-party
client against Microsoft's own authentication servers. This project
deliberately does not do that:

1. It is client-impersonation / auth-circumvention against a third party's
   infrastructure.
2. It is also a practical dead end — that stack is built to resist exactly this
   and breaks on every update.

Everything Phone Link does that you actually want (mirror, apps-in-windows,
notifications, media, ring, battery, clipboard) is achievable through Android's
own APIs (`adb` + virtual displays) and an open device-sync protocol, with **no
cloud and no Microsoft dependency** — which is also why it is more durable.

## What works today

| Area | State |
| --- | --- |
| scrcpy control-message & video-frame wire format | ✅ implemented + unit-tested (`ScrcpyProtocol`) |
| KDE Connect packet models (ring, notification, media, battery, clipboard, telephony) | ✅ implemented + unit-tested (`Companion`) |
| `adb` discovery, server push, tunnel, launch (incl. `--new-display`/`--start-app`) | ✅ implemented (`AdbBridge`), not yet run against a device |
| VideoToolbox H.264 decode | ✅ implemented (`VideoPipeline`), needs on-device validation |
| TCP transport + session orchestration | ✅ implemented (`Streaming`), handshake ordering to verify vs. scrcpy 3.1 |
| Menu-bar app + mirror windows + input mapping | ✅ implemented (`PhoneLink`) |
| Companion encrypted transport (mDNS discovery + TLS 1716 + pairing) | ⬜ **next milestone** — protocol is ready, transport is not |
| Metal zero-copy renderer (the real latency win) | ⬜ roadmap |
| Notarized/signed distribution | ⬜ unsigned only for now |

See [docs/ROADMAP.md](docs/ROADMAP.md).

## Building

No Xcode project — this is a Swift Package built from the command line.

```bash
swift build -c release      # compile
swift test                  # run the protocol unit tests
./scripts/package-app.sh    # produce build/PhoneLink.app and build/mac-phone-link.dmg
```

CI does all of this on every push via
[`.github/workflows/build.yml`](.github/workflows/build.yml) and uploads the
`.app` and `.dmg` as downloadable artifacts.

## Running

1. **Install `adb`** (`brew install android-platform-tools`) and enable USB
   debugging on the phone.
2. **Get `scrcpy-server`** matching the pinned version
   (`ScrcpyProtocol.ScrcpyServer.pinnedVersion`) from scrcpy's releases, and put
   it at `~/Library/Application Support/mac-phone-link/scrcpy-server` (or set
   `PHONELINK_SCRCPY_SERVER`). We do not vendor it — it is separately licensed
   (Apache-2.0).
3. **For companion features**, install the KDE Connect app on the phone.
   (Pairing transport is the next milestone.)
4. Launch the app; use the menu-bar icon → *Mirror Phone Screen* or *Open App in
   Its Own Window…*.

### Installing an unsigned build

Builds are unsigned and not notarized, so Gatekeeper will block the first launch.
After copying the app to `/Applications`:

```bash
xattr -dr com.apple.quarantine /Applications/PhoneLink.app
```

…or right-click the app → *Open* → *Open*.

## Credits & licensing

This project is MIT (see [LICENSE](LICENSE)). It stands on the shoulders of
other projects without copying their code — full attribution and the licensing
rationale are in [NOTICE.md](NOTICE.md). In short:

- **scrcpy** (Apache-2.0) — the Android-side server we drive over `adb`.
- **KDE Connect** (GPL-2.0+) — the protocol we reimplement on the desktop side,
  and the Android app that speaks it. No KDE Connect source is used here.
