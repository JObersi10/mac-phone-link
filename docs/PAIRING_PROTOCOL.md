# Phone Link pairing & QR payload — reverse-engineering notes + plan

Status: **investigation / plan**. Goal: replace the placeholder pairing payload
(`ms-phone-link://pair?v=1`) in `PhoneLinkUI` with the real handshake so the
official **Link to Windows** Android app can pair with our macOS host.

Everything below is from static analysis of the APK's Dalvik strings
(`com.microsoft.mmx.agents.ypp.pairing.*` / `...pairingproxyclient.*`) — class
and REST-path names, not decompiled bodies. Treat specifics as hypotheses to
confirm by decompiling the named classes (jadx) and by observing live traffic.

## Direction of the QR
The **host (PC / our Mac) displays the QR; the phone scans it.** Android side is
a *scanner* (zxing: `QrCodeScanScreen`, `OnboardingScanResultHandler`,
`screenMirroringQrCodeResultActivity`), never a generator. So to interoperate we
must **emit a QR the Android scanner accepts** — the exact payload is the thing
to nail down.

## Two cloud sessions (Device Pairing Proxy)
REST paths observed (relative; base host is an env-configured pairing-proxy /
DCG-adjacent service — still to confirm):

QR / PIN path (**this is the QR flow**):
- `POST /DevicePairingProxy/PinSessions/{pin_session_id}` (create)
- `GET  /DevicePairingProxy/PinSessions/{pin_session_id}/State`
- `.../PinSessions/{pin_session_id}/QRScanned`
- `.../PinSessions/{pin_session_id}/PINTyped`
- `.../PinSessions/{pin_session_id}/ValidateTrustInfo`
- `.../PinSessions/{pin_session_id}/AccountTransferred`
- `.../PhoneSessions/{phone_session_id}/State` + `/PhoneState`

Crypto-trust ceremony:
- `.../PairingSessions/{pairing_session_id}` + `/Complete`
- `CreatePairingSessionRequestBody`, enums `PairingSessionState`,
  `ProxyPairingFlowType`, `PairingProtocol`, `ProxyAccountInfo`.

Auth to the proxy: MSA token via `PairingProxyMsaTokenHeaderInterceptor`
(note: "Request pairing proxy service with dcg token unauthorized" → it rejects
a plain DCG token; the pairing proxy wants an MSA/pairing-scoped token).

## Pairing ceremony messages (over a netty `PairingChannel`)
`com.microsoft.mmx.agents.ypp.pairing.protocol.*`:
- `JoinChannelWithMsaRequestMessage { msaToken=… }` → `JoinChannelResponseMessage
  { channelExpireTime=… }`
- `DeviceInfoExchangeMessage` / `DeviceInfoExchangeMessageWrapper`
- `CryptoInfoExchangeMessage`  (device public-key / cert exchange → crypto trust)
- `NonceMessage`, `PingMessage`, `PairingResponseMessage`
  (`PairingResponseStatus`/`Type`), `ExitChannel*`, `PartnerExitedMessage`
Driven by `PairingStateMachine` with processors incl. `CheckPermission`,
`CommitCryptoTrust`, `Failed`. Result: `PairingResult` / `PairingCeremonyData`.

## Account transfer (what the QR flow accomplishes)
- `TransferToken` (see repo `maclink.auth.v1.TransferToken`): an MSA
  **transfer token** moves the account onto the paired device
  (`generateAndSaveTransferTokenAsync`, `AccountTransferred`,
  `MsaTransferTokenLoginViewModel`).
- A **session key** (AES-GCM, kept in Android KeyStore:
  `SessionKeyUtil:extractSessionKey`, `getSessionKeyBasedDecryptorAesGcm`)
  encrypts the exchange — **very likely carried in / derived from the QR**.

## Working hypothesis for the QR payload
The QR encodes enough for the phone to (a) find the cloud PinSession and (b)
derive the session key:
  { pin_session_id, session_key (or seed), environment/ring, host/device name,
    protocol version }
probably as a compact string or base64 blob. **Unconfirmed** — exact format is
the #1 thing to extract.

## Plan to replace the placeholder
1. **Decompile the exact parsers** (jadx on the APK), in priority order:
   - `OnboardingScanResultHandler` + `QrCodeScanScreen` result handling → the
     QR string grammar the phone accepts.
   - `pairingproxyclient` service models (`CreatePairingSessionRequestBody`,
     PinSession create/response) → request/response JSON shape + base host.
   - `SessionKeyUtil` → how the session key is encoded/derived from the QR.
   - `pairing.protocol.*` message wire formats (netty codec) → ceremony framing.
2. **Confirm the base host + MSA scope** the pairing proxy requires (separate
   from `dcg.microsoft.com/DCG.ReadWrite`).
3. **Model it clean-room** in Swift under `DCGAuth`/a new `Pairing` module:
   `PinSessionClient` (create/poll/complete against the proxy), `QRPayload`
   (encode to the confirmed grammar), `PairingCeremony` (device/crypto-info
   exchange → commit crypto trust, feeding the existing `DeviceTrustAuthorizer`
   / `CryptoManager`-equivalent).
4. **Wire into onboarding**: `OnboardingViewModel.pairingPayload` ← real
   `QRPayload`; drive the PinSession state machine while the QR is shown; advance
   to `.done` on `AccountTransferred` + `CommitCryptoTrust`.

## Honest caveats
- The QR/PIN flow is **MSA-first-party**: the pairing proxy likely gates on a
  first-party identity (as with DCG). A third-party client may be refused —
  confirm early (same risk already documented for DCG).
- Nothing here is byte-confirmed yet; these are names + REST paths. Do step 1
  before writing the clean-room encoder, or the QR will be rejected.
