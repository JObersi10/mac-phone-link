# mac-phone-link

Open-source groundwork for a native **macOS** client that interoperates with
Microsoft **Phone Link / Link to Windows**.

> Clean-room project. See [`NOTICE.md`](NOTICE.md). Not affiliated with Microsoft.

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
