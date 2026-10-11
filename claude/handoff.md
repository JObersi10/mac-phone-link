# handoff.md — technical continuation summary

Precise state for picking up `mac-phone-link` in a fresh session.

## Repo & branches
- GitHub: `jobersi10/mac-phone-link` (public), default branch `main`.
- **PR #2 merged to `main`** (squash) — the clean-room foundation is now on main.
- **PR #1** (old scrcpy/companion prototype) was moved to
  `jobersi10/mac-phone-link-old` (its code is on that repo's `main`) and closed.
- **PR #3** `feature/screen-mirroring` → `main` (retargeted; CI green). **Current
  branch.** Adds screen-mirroring protos, `PhoneLinkVideo`, `PhoneLinkApp`, and
  `build-app.yml`. Ready to merge (user merges — agent can't merge-without-review).
- Tag **`v0.1.0`** pushed from the PR #3 tip to exercise the Release workflow.

## Toolchain
- Build locally: `swift build` (works with Swift 6.1 CommandLineTools).
- `swift test` needs full Xcode (XCTest) — **not available locally**; runs in CI.
  Before pushing test changes, grep generated names in
  `Sources/PhoneLinkProtos/Generated/*.pb.swift` to avoid typos.
- Regenerate protos (also what CI does):
  ```bash
  export PATH="/opt/homebrew/bin:$PATH"
  OUT=Sources/PhoneLinkProtos/Generated; rm -rf "$OUT"; mkdir -p "$OUT"
  find Protos -name '*.proto' -print0 | xargs -0 protoc --proto_path=Protos \
    --plugin=protoc-gen-swift="$(which protoc-gen-swift)" \
    --swift_opt=Visibility=Public,FileNaming=PathToUnderscores --swift_out="$OUT"
  ```
  Requires `brew install protobuf swift-protobuf`.

## Package layout (`Package.swift`, tools 5.9, macOS v13)
Products / targets:
- `PhoneLinkProtos` (lib) — SwiftProtobuf models from `Protos/` + committed
  `Generated/`. Marker: `Sources/PhoneLinkProtos/Version.swift`.
- `DCGAuth` (lib) — MSAL + device trust. Files: `DCGAuth.swift` (MSAL),
  `DeviceTrustJWT.swift`, `CertThumbprint.swift`, `DRSNonce.swift`,
  `DRSDiscovery.swift`. Deps: MSAL (AzureAD SPM).
- `DCGTransport` (lib) — `DCGFraming.swift`, `DCGConnection.swift`,
  `SignalRDCGChannel.swift`, `SideChannelAuth.swift`, `DCGSession.swift`.
  Deps: `PhoneLinkProtos`, `DCGAuth`, SignalRClient (moozzyk SPM).
- `PhoneLinkUI` (lib) — `ConnectionViewModel.swift`, `PhoneLinkRootView.swift`,
  `PhoneLinkApp.swift` (SwiftUI `Scene`, no `@main`). Deps: `PhoneLinkProtos`,
  `DCGTransport`.
- `PhoneLinkVideo` (lib) — `NALUnit.swift`, `VideoDecoder.swift`
  (format desc + `VTVideoDecoder`), `VideoDisplayView.swift`
  (`AVSampleBufferDisplayLayer`), `VideoStreamController.swift`. System
  frameworks only (VideoToolbox/CoreMedia/AVFoundation/AppKit).
- `PhoneLinkApp` (exe) — `@main` SwiftUI app hosting `PhoneLinkRootView`. This is
  what `build-app.yml` packages into `PhoneLink.app`.
- `ProtoCheck` (exe) — sanity entry.
- `PhoneLinkProtosTests` (tests) — serialization + framing + auth + DRS +
  session + UI VM + mirroring.

Third-party deps: `apple/swift-protobuf` ≥1.28.2,
`AzureAD/microsoft-authentication-library-for-objc` ≥1.5.0,
`moozzyk/SignalR-Client-Swift` ≥1.0.0.

## Key types & entry points
- Generated names: `Maclink_<Package>_V1_<Message>` (e.g.
  `Maclink_Sidechannel_V1_Authorization`, `Maclink_Platform_V1_DcgFragmentMessage`,
  `Maclink_Mirroring_V1_ConfigMessage`). Note `has_more` → `hasMore_p`.
- Auth: `DCGAuthenticator(config:)` → MSA token for scope
  `https://dcg.microsoft.com/DCG.ReadWrite` (caller supplies `clientId`).
- Device trust: `DeviceTrustJWT.sign(claims:with:)`; `SecKeyRS256Signer`;
  `CertThumbprint.kid(certificate:variant:)`.
- DRS: `DRSDiscoveryClient.discover(tenant:)` → `DRSMetadata.nonceURL()`;
  `DRSNonceClient.requestNonce(discoveringFor:discovery:)`.
- Transport: `DCGConnection(channel:sessionID:)` with `onPayload`/`onStateChange`;
  `send(payload:handlerType:)`. `DCGChannel` protocol (SignalR impl +
  `MockChannel` in tests).
- Unified: `DCGSession(config:accessTokenProvider:deviceTrust:…)` →
  `start()` opens connection; `currentAuthorization()` = discover nonce → sign →
  wrap. `channelFactory` injectable for tests.
- UI: `ConnectionViewModel.bind(to: DCGConnection)`; decodes `handlerType ==
  "notification"` payloads (`Maclink_Notification_V1_ResponseMessage`).

## How to wire a live attempt (end-to-end sketch)
1. Register your own Entra app; set `DCGAuthConfig.clientId`.
2. `DCGAuthenticator.acquireToken…` for DCG scope (expect possible first-party
   consent refusal — that's a finding).
3. Build `DeviceTrustAuthorizer(signer: SecKeyRS256Signer(privateKey:certificate:),
   dcgClientId:)`.
4. `DCGSession(config: .init(hubURL:tenant:), accessTokenProvider: { try await
   authenticator… }, deviceTrust:)` → `start()`.
5. `session.currentAuthorization()` for each side-channel request; attach to
   `Maclink_Sidechannel_V1_ClientRequest.authorization`.

## Build the .app locally
```bash
swift build -c release --product PhoneLinkApp
BIN="$(swift build -c release --product PhoneLinkApp --show-bin-path)/PhoneLinkApp"
scripts/package-app.sh "$BIN" dist 0.1.0   # -> dist/PhoneLink.app
```
CI (`build-app.yml`) does the same, zips with `ditto`, and on a `v*` tag uploads
the zip to GitHub Releases. App is **unsigned** (Gatekeeper prompt until a
Developer ID cert is wired into CI secrets).

## Next work (priority order)
1. **Merge #3** to `main` (user action).
2. **Nano/QUIC transport** — the direct path screen-mirroring video actually
   flows over. Needs: QUIC (Network.framework `NWConnection` w/ QUIC, or msquic),
   the `context_source` identity-challenge handshake, Wi-Fi Direct/instant-
   hotspot negotiation via side-channel. Biggest remaining piece; it feeds frame
   bytes into `VideoStreamController.feed(frame:)`.
3. **Device-trust provisioning** — pairing-proxy cert issuance (we can sign but
   assume a key/cert already exists). Study `pairingproxyclient`.
4. **Wire video to a real screen** — connect `VideoStreamController` →
   `SampleBufferDisplayNSView` in the UI; confirm the stream's actual frame
   container (Annex B vs AVCC, SPS/PPS signaling) against live bytes.
5. **App signing/notarization** — Developer ID in CI secrets, codesign +
   notarytool in `build-app.yml`.

## Guardrails to preserve
- Keep everything **clean-room**: no vendor source text, headers, namespaces, or
  binaries in git. New protos → `maclink.*`, own header, field numbers only.
- Never commit the vendor MSIX/APK/DLLs (`.gitignore` already blocks them).
- Do not embed Microsoft first-party client ids / impersonate the app.
- Validate `swift build` locally before each push; rely on CI for `swift test`.
- Commit footer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
