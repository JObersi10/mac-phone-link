# handoff.md — technical continuation summary

Precise state for picking up `mac-phone-link` in a fresh session.

## Repo & branches
- GitHub: `jobersi10/mac-phone-link` (public), default branch `main`.
- **PR #2** `feature/swift-protobuf-ci` → `main`: the foundation. CI green.
  **Awaiting user merge** (merge-without-review is blocked for the agent).
- **PR #3** `feature/screen-mirroring` → base `feature/swift-protobuf-ci`
  (stacked): screen-mirroring protocol layer. **This is the current branch.**
  After #2 merges to `main`, retarget #3 to `main` (`gh pr edit 3 --base main`)
  and rebase if needed.

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
  `PhoneLinkApp.swift` (SwiftUI). Deps: `PhoneLinkProtos`, `DCGTransport`.
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

## Next work (priority order)
1. **Merge #2**, retarget #3 to `main`.
2. **Nano/QUIC transport** — the direct path for screen mirroring/streaming.
   Needs: QUIC (Network.framework `NWConnection` w/ QUIC, or msquic), the
   `context_source` identity-challenge handshake, Wi-Fi Direct/instant-hotspot
   negotiation via side-channel. This is the biggest remaining piece.
3. **Device-trust provisioning** — pairing-proxy cert issuance (currently we can
   sign but assume a key/cert already exists). Study `pairingproxyclient`.
4. **Screen-mirroring runtime** — decode video frames over Nano, render in a
   SwiftUI/AppKit surface; input injection via `remote_control` + mirroring
   control messages.
5. **Runnable `.app`** — add an Xcode project (or xcodegen) host target that
   `import PhoneLinkUI` and marks `@main`. SPM alone won't produce a signed app.

## Guardrails to preserve
- Keep everything **clean-room**: no vendor source text, headers, namespaces, or
  binaries in git. New protos → `maclink.*`, own header, field numbers only.
- Never commit the vendor MSIX/APK/DLLs (`.gitignore` already blocks them).
- Do not embed Microsoft first-party client ids / impersonate the app.
- Validate `swift build` locally before each push; rely on CI for `swift test`.
- Commit footer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
