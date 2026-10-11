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
the zip to GitHub Releases.

**Packaging does three things that matter (`scripts/package-app.sh`):**
1. Embeds dynamic frameworks (`MSAL.framework`) into `Contents/Frameworks/` and
   adds rpath `@executable_path/../Frameworks`. Without this the app crashes at
   launch: `Library not loaded: @rpath/MSAL.framework` (the v0.1.0 bug).
2. `chmod 755` on `Contents/MacOS/PhoneLink`.
3. Ad-hoc code-signs (`codesign --force --deep --sign -`), frameworks first.

**Gatekeeper (un-notarized):** downloaded copies are quarantined → "is damaged".
Testers: right-click → Open, or `xattr -dr com.apple.quarantine PhoneLink.app`.
**Proper signing (WIRED in CI, needs secrets):** `scripts/PhoneLink.entitlements`
(keychain-access-groups incl. MSAL's `com.microsoft.adalcache` — required or MSAL
token-cache hits `errSecMissingEntitlement -34018`). `package-app.sh` honors
`CODESIGN_IDENTITY`/`CODESIGN_ENTITLEMENTS` (hardened runtime + entitlements for a
real identity; ad-hoc otherwise). `build-app.yml` imports the cert and runs
`codesign` + `xcrun notarytool submit --wait` + `stapler staple`, gated on repo
secrets: `MACOS_CERTIFICATE` (base64 Developer ID .p12), `MACOS_CERTIFICATE_PWD`,
`MACOS_SIGN_IDENTITY`, plus notarization `AC_API_KEY_ID`/`AC_API_ISSUER_ID`/
`AC_API_KEY_P8`. Absent secrets → ad-hoc fallback. Setup: `docs/MICROSOFT_SIGNIN.md`.

**Releases:** `v0.1.0` asset is BROKEN (pre-embed, crashes on missing MSAL).
**`v0.1.1`** is the first launchable asset (framework embedded + ad-hoc signed).

## Onboarding / pairing (PhoneLinkUI)
`AppRootView` gates on `@AppStorage("didCompleteOnboarding")`: shows
`OnboardingView` until the flow hits `.done`, then `PhoneLinkRootView`.
- `OnboardingViewModel` steps: welcome → permissions → signIn → pairing → done. Sign-in is optional ("Skip for now" link) since DCG is first-party-gated.
- `PermissionsManager` (@MainActor): `requestNotifications()` (UserNotifications),
  `requestLocalNetwork()` (NWBrowser Bonjour → macOS prompt).
- Sign-in is **wired** (`Sources/PhoneLinkApp/MicrosoftSignIn.swift`):
  `App.init()` sets `onboarding.signInAction = MicrosoftSignIn.makeSignInAction()`,
  which builds a `DCGAuthenticator` (redirect `msauth.com.maclink.phonelink://auth`)
  and runs a real MSAL interactive sign-in with diagnostic scopes. Client id is
  caller-supplied (env `PHONELINK_MSAL_CLIENT_ID` → onboarding text field →
  Info.plist `PhoneLinkMSALClientId`), never embedded. `package-app.sh` now
  registers the `msauth.com.maclink.phonelink` URL scheme + local-network
  (Bonjour `_maclink._tcp`) Info.plist keys. Setup + the keychain/signing caveat:
  `docs/MICROSOFT_SIGNIN.md`.
- `QRCode.image(from:)` renders the pairing payload (CoreImage). Payload is a
  **placeholder** until the real DCG pairing handshake exists — that's the next
  protocol task (study pairing-proxy + the QR the Windows app shows).
- `@main` app (`Sources/PhoneLinkApp/App.swift`) builds `connection` +
  `onboarding` StateObjects and hosts `AppRootView`.

## Nano/QUIC transport (`NanoTransport` target)
The direct high-bandwidth path. Scaffolded:
- `NanoFraming` — 4-byte big-endian length prefix per message; `NanoFrameDecoder`
  reassembles split/coalesced chunks. Pure + unit-tested.
- `NanoTransport` protocol (`state`/`onFrame`/`onStateChange`/`send`/`cancel`) +
  `LoopbackNanoTransport` for tests/wiring.
- `QUICNanoConnection` — Network.framework QUIC (`NWProtocolQUIC.Options(alpn:)`,
  one bidirectional stream), `@available(macOS 12)`, `#if canImport(Network)`.
  Insecure-cert verify block by default (direct peer uses a device-trust cert,
  not web PKI) — pin the expected cert there for production.
- `NanoHandshake` — context_source exchange (Initialize → IdentityResponse →
  OpenDeviceConnectionRequest) over the clean-room `ContextSourceMessage`.
- **Wire to video**: `transport.onFrame = { try? controller.feed(frame: $0) }`
  (`VideoStreamController.feed(frame:) throws -> CMSampleBuffer?`).
Still TODO: confirm the real frame container (Annex B vs AVCC, SPS/PPS
signaling) against live bytes, Wi-Fi Direct/instant-hotspot negotiation via the
side channel, cert pinning, and multi-stream (control vs media) if needed.

## Screen mirroring UI (wired)
`PhoneLinkRootView` is now a `TabView`: **Notifications** (DCG connection) +
**Screen Mirroring**. `MirroringViewModel` (PhoneLinkUI) drives a `NanoTransport`
— `connect(host:port:)` builds a `QUICNanoConnection` (empty host → loopback
self-test), routes `onFrame` into `VideoStreamController.feed` → the
`AVSampleBufferDisplayLayer` in `MirroringView`, and publishes `state` +
`framesReceived`. So there's a runnable Connect action end to end.

## Remote control + clipboard + input proto (PhoneLinkUI)
- **Cursor/keyboard control** of the mirror: `RemoteControl` maps a view point →
  normalized [0,1] of the aspect-fit video content (`videoContentRect`,
  `normalize` returns nil in letterbox bars → event dropped), `MoveCoalescer`
  rate-limits moves. `RemoteInputNSView`/`RemoteInputView` overlay the video,
  flip AppKit's bottom-left Y, and emit `Maclink_Mirroring_V1_InputEventMessage`
  (new `Protos/maclink/mirroring/v1/input.proto`: kind/x/y/button/scroll/key/
  meta/ts). `MirroringViewModel.sendInput` serializes + sends over the transport
  only while connected. This is what keeps control stable ("doesn't go crazy"):
  clamped, letterbox-correct, coalesced. Default `videoSize` 1080×2400 until a
  real stream reports dimensions.
- **Clipboard**: `ClipboardSync` polls `NSPasteboard.changeCount` → serializes a
  `Maclink_Clipboard_V1_ResponseMessage` (textPlain item) to a sink; inbound
  `handleIncoming` writes remote text back (suppressing the echo). `ClipboardCodec`
  is the pure, tested proto<->value mapping. Not yet attached to a live channel.
- **Notifications** already decode (`ConnectionViewModel.decodeNotifications`).

## QR diagnosis (confirmed first-party wall; grammar is correct)
The URL grammar is right and `dcg.microsoft.com` IS an `autoVerify` App Link in
the APK manifest — but scanning in-app still just "opened the link" because the
pairing parser (`FreParseDynamicLinkManager.validateDynamicLink`) only treats it
as a real pairing link when backed by cloud session params (`cpsi`, a Microsoft-
minted `uaid`); ours isn't, so it degrades to opening the raw URL, which hits
dcg's API host and returns a generic MS error page. No client-side fix exists —
it needs a real cloud PinSession (first-party gated). QR work is done.

## QR payload (fixed — was rejected as "invalid")
The phone's `DeeplinkResolver.validateUri` rejects any string without a scheme +
host, so the old bare `uaid=...` was invalid. `QRPairingPayload` now emits the
real **HTTPS DCG dynamic link** (`https://dcg.microsoft.com/?vm=5&uaid=…&ti=…&r=5&
apn=com.microsoft.appmanager`). The phone will now accept the scan; it still
can't complete pairing (the `uaid`/session isn't a real cloud PinSession — the
first-party gate). See `docs/PAIRING_PROTOCOL.md`.

## Next work (priority order)
1. **Nano transport live bring-up** — verify framing + handshake against real
   traffic; the UI Connect action already routes frames to the display layer.
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
