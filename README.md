# mac-phone-link

Open-source groundwork for a native **macOS** client that interoperates with
Microsoft **Phone Link / Link to Windows**.

> Clean-room project. See [`NOTICE.md`](NOTICE.md). Not affiliated with Microsoft.

## Status: research complete, interop blocked at the first-party wall
This project reverse-engineered the full Phone Link link (auth, pairing,
transport) and built the macOS client up to — but not through — Microsoft's
first-party identity gate. See the docs below for exactly where that line is.

- [`docs/FINDINGS.md`](docs/FINDINGS.md) — everything confirmed, incl. live
  captures: auth is an **MSA device/token-broker** flow (not Entra OAuth);
  pairing is a **cloud `cpsi` PinSession** (QR) or **account device-to-device**;
  media transport is **ICE/STUN/TURN, P2P over LAN** with Azure TURN fallback.
- [`docs/WINDOWS_COMPONENTS.md`](docs/WINDOWS_COMPONENTS.md) — which Windows DLL
  owns each part and how they connect, mapped to our Mac modules.
- [`docs/SETUP_CLIENT_ID.md`](docs/SETUP_CLIENT_ID.md) — the client is wired
  end-to-end (`AccountLinkCoordinator`) but needs a **caller-supplied client
  id**; DCG only issues to the first-party id, which this repo does not embed.
- [`docs/OWN_APP.md`](docs/OWN_APP.md) — the no-wall alternative (own protocol,
  LAN-direct), with the Mac engine reused and an `LANTransport` started.

**The wall:** completing a real link needs a Microsoft-minted device token /
first-party client id that a clean third-party client cannot reproduce. The code
is complete and runnable up to that point; it is not a working link on its own.

## What's here
- **`Protos/`** — clean-room protobuf schemas (`maclink.*`) mirroring the
  observed wire interface (clipboard, notifications, platform channel &
  session/channel validation, side channel wake/hotspot/auth, auth tokens).
- **`Sources/PhoneLinkProtos/`** — Swift package target; generated
  `*.pb.swift` live in `Generated/`.
- **`Sources/ProtoCheck/`** — tiny executable that links the models and prints
  a sanity line, so CI can verify compilation without Xcode.
- **`.github/workflows/build-swift.yml`** — macOS CI: installs `protoc` +
  `swift-protobuf` via Homebrew, regenerates Swift from `Protos/`, then
  `swift build`.

## Build locally
```bash
brew install protobuf swift-protobuf
protoc --proto_path=Protos \
  --plugin=protoc-gen-swift="$(which protoc-gen-swift)" \
  --swift_opt=Visibility=Public,FileNaming=PathToUnderscores \
  --swift_out=Sources/PhoneLinkProtos/Generated \
  $(find Protos -name '*.proto')
swift build && swift run proto-check
```

## Protocol background
See [`PHONE_LINK_PROTOCOL_ANALYSIS.md`](PHONE_LINK_PROTOCOL_ANALYSIS.md) for the
transport/auth architecture (cloud-relayed SignalR via DCG, Nano/QUIC direct
transport, device-trust model) and [`poc/`](poc/) for an MSA OAuth proof of
concept.
