# claude.md — working notes & architectural decisions

Project: **mac-phone-link** — an open-source, clean-room native macOS client that
interoperates with Microsoft **Phone Link / Link to Windows**.

Repo: `jobersi10/mac-phone-link` (public). Primary language: Swift (SwiftPM).

---

## Where the knowledge came from
Two local vendor artifacts (used for analysis only, **never committed** — see
`.gitignore`):
- `YourPhone.Package_1.26082.117.0_arm64` — the Windows MSIX (.NET 10, WinUI/WPF,
  `PhoneExperienceHost.exe` + `YourPhoneAppProxy.exe`).
- `com.microsoft.appmanager_1.26082.130.0…apk` — the Android "Link to Windows"
  app. **Ships uncompiled `.proto` files**, which were the richest source. Code
  is in `classes*.dex` (11 dex); analyzed via `strings` dumps, not full decompile.

`PHONE_LINK_PROTOCOL_ANALYSIS.md` (committed) is the architecture writeup.

---

## Core architectural findings (drive every decision)
1. **Not LAN/P2P by default.** Baseline transport is a **cloud relay** —
   Microsoft "Device Connectivity Gateway" (DCG, `dcg.microsoft.com`) over
   **SignalR**. No mDNS/Bonjour/SSDP discovery exists.
2. **Shared protocol = "YPP".** Android `com.microsoft.mmx.agents.ypp.*` and
   Windows `YourPhone.YPP.*` generate from one protobuf schema → regenerating
   clients from the `.proto` files is the interop strategy.
3. **Two auth layers, independent:**
   - MSA/Entra access token (audience `dcg.microsoft.com/DCG.ReadWrite`) → SignalR
     hub bearer.
   - **Device-to-device crypto trust**: an RS256 JWT (per-message) carrying a
     DRS-issued `nonce` + `dcgClientId`, wrapped in `SideChannelAuthorization`.
4. **Framing:** app payloads are fragmented into `DcgFragmentMessage`s (shared
   `message_id`, ordered `fragment_id`, `sequence_number`), ack'd via
   `DcgAckMessage`.
5. **Direct/high-bandwidth = "Nano" transport** (QUIC / Wi-Fi Direct) for screen
   mirroring & streaming — **not yet implemented** here.

---

## Decisions made (and why)
- **Clean-room protos.** Repo is public. The vendor feature `.proto`s are
  "Copyright … All rights reserved." We re-authored them under `maclink.*`
  packages with our own headers/comments; only **field numbers + wire types** are
  preserved (interface facts). Vendor package/namespace names are NOT used. The
  original vendor `.proto`s never entered git history (fresh `git init`).
- **`FileNaming=PathToUnderscores`** on `protoc` — two `trace_context.proto`
  collided on object-file basename under SwiftPM; this flattens names
  (`maclink_platform_v1_trace_context.pb.swift`). **Load-bearing.**
- **Dropped `swift_prefix`** so generated type names derive from package
  (`Maclink_Platform_V1_*`), matching hand-written code.
- **MSAL wrapper takes a caller-supplied `clientId`.** We deliberately do NOT
  embed Microsoft's first-party client id (that would impersonate the official
  app). The DCG scope is first-party-protected; a 3rd-party app will likely be
  refused consent — documented, not hidden.
- **Signer is abstracted (`JWTSigner`).** Native `Security.framework`
  `SecKeyRS256Signer` provided (no extra dep). CryptoKit for thumbprints.
- **UI is a library target, not an `.app`.** A SwiftUI `@main` executable in SPM
  is CI-fragile (no bundle/signing on runners); shipping a real app wants an
  Xcode project. `PhoneLinkScene` has no `@main`; a one-line host wrapper is
  documented.
- **Generated `*.pb.swift` are committed** so clones build without `protoc`; CI
  still regenerates them as verification.
- **Local validation before every push.** `swift build` runs locally (Swift 6.1
  CommandLineTools). `swift test` cannot run locally (no full Xcode) → it runs in
  CI; generated property/enum names are grep-verified before pushing.

---

## Current implementation status

| Area | Target | Status |
|---|---|---|
| Clean-room protos (35) | `Protos/` → `PhoneLinkProtos` | ✅ clipboard, notification, messaging, contacts, files, side_channel, platform/DCG framing, mirroring, streaming, auth tokens |
| MSA/Entra OAuth | `DCGAuth` | ✅ `DCGAuthenticator` (MSAL) silent+interactive; `poc/msa_dcg_token.py` |
| Device-trust JWT | `DCGAuth` | ✅ `DeviceTrustJWT` (RS256), `JWTSigner`, `SecKeyRS256Signer` |
| Cert thumbprint → kid | `DCGAuth` | ✅ `CertThumbprint` (SHA-1/256 × hex/b64url) |
| DRS nonce + discovery | `DCGAuth` | ✅ `DRSNonceClient`, `DRSDiscoveryClient` (contract → RegistrationEndpoint → nonce URL) |
| DCG framing | `DCGTransport` | ✅ `DCGFragmenter`/`DCGReassembler`/`DCGAck` |
| Routing | `DCGTransport` | ✅ `DCGConnection` (fragment-on-send, reassemble+auto-ack) over `DCGChannel` |
| SignalR channel | `DCGTransport` | ✅ `SignalRDCGChannel` (configurable hub method names) |
| Auth↔transport bridge | `DCGTransport` | ✅ `DeviceTrustAuthorizer`, `SideChannelAuth`, `DCGSession` |
| macOS UI | `PhoneLinkUI` | ✅ `ConnectionViewModel`, `PhoneLinkRootView`, `PhoneLinkScene` (library) |
| Screen-mirroring protos | `PhoneLinkProtos` | ✅ message layer (PR #3) |
| Nano/QUIC transport | — | ❌ not started |
| Device-trust provisioning (pairing-proxy cert issuance) | — | ❌ not started |
| Runnable `.app` bundle | — | ❌ (Xcode project needed) |

---

## Known uncertainties (verify against live traffic)
- SignalR **hub method names** for DCG send/receive — placeholders (`SendMessage`/
  `ReceiveMessage`), configurable.
- DRS **nonce URL / discovery contract** field names — standard Workplace-Join
  shape, case-tolerant parse, but not byte-confirmed.
- JWT **`kid` hash variant** — default base64url SHA-256; switchable.
- Exact **claim set** DCG validates beyond nonce/dcgClientId/validity.
- First-party DCG consent likely blocked for third-party apps (expected finding).

---

## CI / workflow
- `.github/workflows/build-swift.yml`: `macos-latest` → brew `protobuf` +
  `swift-protobuf` → regenerate → `swift build` → `swift test` → `proto-check`.
- PR #2 (`feature/swift-protobuf-ci`) = foundation; **merge blocked pending user
  review** (auto-mode classifier denies merge-without-review).
- PR #3 (`feature/screen-mirroring`) = this branch, **stacked on #2**. Retarget to
  `main` after #2 merges.
- Commit attribution footer: `Co-Authored-By: Claude Opus 4.8`.
