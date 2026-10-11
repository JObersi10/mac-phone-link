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
| macOS UI | `PhoneLinkUI` | ✅ `ConnectionViewModel`, `PhoneLinkRootView`; onboarding/pairing flow (`OnboardingView(Model)`, `PermissionsManager`, `QRCode`, `AppRootView` gate) |
| Screen-mirroring protos | `PhoneLinkProtos` | ✅ message layer (PR #3) |
| Screen-mirroring video | `PhoneLinkVideo` | ✅ VideoToolbox decode (`VTVideoDecoder`) + `AVSampleBufferDisplayLayer` render + `VideoStreamController` (NAL/AVCC framing) |
| Runnable `.app` bundle | `PhoneLinkApp` | ✅ `@main` SwiftUI app; `scripts/package-app.sh` assembles `PhoneLink.app` |
| Release packaging | CI | ✅ `build-app.yml` → `.app` → ditto zip → GitHub Releases on `v*` tags (no DMG) |
| Nano/QUIC transport | — | ❌ not started (the direct path video actually flows over) |
| Device-trust provisioning (pairing-proxy cert issuance) | — | ❌ not started |
| App signing / notarization | — | ❌ unsigned (Gatekeeper prompt); needs Developer ID in CI secrets |

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
- `.github/workflows/build-app.yml`: `macos-latest`, on `v*` tags +
  `workflow_dispatch` → `swift build -c release --product PhoneLinkApp` →
  `scripts/package-app.sh` → `ditto` zip (no DMG) → `upload-artifact` + publish
  the zip to **GitHub Releases** on tags (`contents: write`). Single-arch
  (arm64); universal is a one-flag opt-in (needs full-Xcode xcbuild on runner).
- **PR #2 merged to `main`** (squash). PR #1 (old scrcpy/companion prototype)
  moved to `jobersi10/mac-phone-link-old` and closed.
- PR #3 (`feature/screen-mirroring`) now **based on `main`**, CI green: screen-
  mirroring protos + `PhoneLinkVideo` + `PhoneLinkApp` + `build-app.yml`.
- `v0.1.0` tagged from the PR #3 tip to exercise the Release upload — its asset
  is the **broken pre-embed build** (crashes: missing MSAL.framework).
- **`v0.1.1`** tagged after the framework-embedding fix → first launchable
  release asset (`PhoneLink.app.zip`, ad-hoc signed, arm64). Use this one.
- **PR #3 merged to `main`** (squash) — onboarding + VideoToolbox + app bundle +
  release workflow are now the baseline on `main`. `feature/screen-mirroring`
  retired.
- Commit attribution footer: `Co-Authored-By: Claude Opus 4.8`.

## Pairing protocol (next big work) — see `docs/PAIRING_PROTOCOL.md`
Placeholder QR payload must be replaced with the real handshake. Findings so far:
- **Host shows the QR; the phone scans it** (Android is a zxing scanner only).
  So we must emit a QR the official app accepts — exact payload is TBD (#1 to
  extract via jadx on `OnboardingScanResultHandler`).
- Cloud **Device Pairing Proxy**: QR path uses `PinSessions`
  (`/QRScanned`,`/PINTyped`,`/ValidateTrustInfo`,`/AccountTransferred`); crypto
  ceremony uses `PairingSessions/{id}/Complete`. MSA-token auth (not plain DCG).
- Ceremony over a netty `PairingChannel`: JoinChannelWithMsa → DeviceInfoExchange
  → CryptoInfoExchange → Nonce → commit crypto trust (`PairingStateMachine`).
- QR likely carries `{pin_session_id, session_key/seed, env, name, version}`
  (session key = AES-GCM, Android KeyStore). Account moves via MSA `TransferToken`.
- Likely first-party-gated (confirm early). Full plan in the doc.

## Onboarding / pairing (PhoneLinkUI)
First-run flow gated by `@AppStorage("didCompleteOnboarding")` in `AppRootView`
(onboarding → else `PhoneLinkRootView`). Steps: welcome → permissions → sign-in
→ pairing → done.
- **Permissions** (`PermissionsManager`): Notifications via
  `UNUserNotificationCenter.requestAuthorization`; Local Network via an
  `NWBrowser` Bonjour browse that triggers the macOS prompt.
- **Microsoft sign-in**: injected `signInAction: () async throws -> String`
  (keeps PhoneLinkUI decoupled from MSAL UI). **Now wired** in the app layer:
  `Sources/PhoneLinkApp/MicrosoftSignIn.swift` builds a `DCGAuthenticator`
  (redirect `msauth.com.maclink.phonelink://auth`, scheme registered in the
  bundle's `Info.plist`) and runs a real MSAL interactive sign-in with diagnostic
  scopes. Client id is caller-supplied — env `PHONELINK_MSAL_CLIENT_ID`, the
  onboarding text field (`PhoneLinkMSALClientId` UserDefaults), or Info.plist —
  never embedded. Setup + keychain/signing caveat: `docs/MICROSOFT_SIGNIN.md`.
- **Pairing**: `QRCode.image(from:)` (CoreImage, no dep) renders the pairing
  payload. Payload is a **placeholder** (`ms-phone-link://pair?v=1`) until the
  real DCG pairing handshake is reverse-engineered/wired.

---

## Packaging, signing & Gatekeeper
- **Embed dynamic frameworks.** `PhoneLinkApp` links **MSAL as a dynamic
  framework** (`@rpath/MSAL.framework`). v0.1.0's hand-rolled bundle shipped only
  the executable → it aborted at launch: `Library not loaded:
  @rpath/MSAL.framework` (DYLD, Code 1). Fix in `scripts/package-app.sh`: copy
  every `*.framework` from the SwiftPM products dir into
  `PhoneLink.app/Contents/Frameworks/` and
  `install_name_tool -add_rpath "@executable_path/../Frameworks"` on the binary.
  Any future dynamic dep is picked up automatically by the same glob.
- **Perms:** `Contents/MacOS/PhoneLink` is `chmod 755` before zipping.
- **Ad-hoc signing:** `codesign --force --deep --sign -` signs embedded
  frameworks first, then the bundle; `--verify --deep --strict` gates it. Ad-hoc
  is NOT notarization.
- **Gatekeeper on un-notarized downloads:** a downloaded ad-hoc/unsigned app
  carries `com.apple.quarantine`, so macOS shows *"is damaged and can't be
  opened"*. Workaround for testers:
  - right-click the app → **Open** (then Open in the dialog), or
  - `xattr -dr com.apple.quarantine /path/to/PhoneLink.app`
  Ad-hoc signing downgrades the hard "damaged" failure toward the recoverable
  "unidentified developer" path; it does not remove the quarantine prompt.
- **Proper Developer ID signing/notarization (CI, TODO).** Add repo secrets and
  a signing step in `build-app.yml`:
  - `APPLE_DEVELOPER_ID` — "Developer ID Application: …" identity (and the signing
    cert/key imported into a CI keychain).
  - `PROVISIONING_PROFILE` — base64 provisioning profile, decoded at build time.
  - (also needed for notarization: an App Store Connect API key or
    `notarytool` creds.) Then `codesign` with the real identity + `xcrun
    notarytool submit --wait` + `xcrun stapler staple` — which removes the
    Gatekeeper prompt entirely.
- **Actions:** `actions/checkout@v5` (Node 24). `upload-artifact@v4` and
  `softprops/action-gh-release@v2` are the latest majors (GitHub's Node-20
  deprecation notice is upstream; runner force-runs them on Node 24).
