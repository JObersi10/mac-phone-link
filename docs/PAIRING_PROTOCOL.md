# Phone Link pairing & QR payload — reverse-engineering notes

Status: **QR grammar + proxy surface CONFIRMED by decompilation**; live traffic
and first-party gating still unverified. Goal: replace the placeholder pairing
payload in `PhoneLinkUI` with the real handshake so the official **Link to
Windows** Android app can interoperate with our macOS host.

Decompiled (jadx, single-class) sources that pin the grammar down:
`FreQrCodeManager` (QR parsing), `MsaA2DPairingManager` (account-to-device
flow). Class / REST-path names also come from Dalvik strings. The clean-room
Swift model of the confirmed facts lives in `Sources/PhoneLinkPairing/`
(`QRPairingPayload`, `PairingProxyEndpoints`, `PairingCeremony`), tested in
`Tests/PhoneLinkProtosTests/PairingTests.swift`.

## Direction of the QR
The **host (PC / our Mac) displays the QR; the phone scans it** (Android is a
zxing scanner — `QrCodeScanScreenKt`, `QrCodeImageDecoder`,
`OnboardingBaseViewModel.handleQrCodeScanResult`). To interoperate our Mac must
**emit a QR the Android scanner accepts.**

## CONFIRMED — the QR payload grammar
`FreQrCodeManager` parses the scanned string as a **query string** with two keys:
```
uaid=<prefix><16-char YPP pairing code>   &   code=<MSA authorization code>
```
- The **YPP pairing code is the last 16 characters of `uaid`**
  (`getYPPPairingCode` = `extractUaidFromScanResult(scan).substring(len - 16)`).
- The leading prefix is a zero-paddable field; a non-all-zeros prefix drives the
  telemetry result code to 1 (i.e. "a real session is encoded").
- `code=` is read by `extractMSACodeFromScanResult` (value terminated by `&`),
  the MSA auth code that moves the account onto the paired device.

Modeled in `QRPairingPayload` — parses a full URI or a bare query and exposes
`yppPairingCode` (the last-16 slice) and `hasMeaningfulPrefix`.

## CONFIRMED — pairing proxy base host + paths
The Device Pairing Proxy is hosted under the **DCG domain**; the REST path root
is `/DevicePairingProxy/`. Hosts observed: `dcg.microsoft.com` (prod),
`dcg-df.microsoft.com` (dogfood), `dcg-beta.microsoft.com` (beta).

QR / PIN flow (**the QR flow**), a PinSession advanced through states:
`created → QRScanned → PINTyped → ValidateTrustInfo → AccountTransferred`
(`updatePinSessionStateAsync`; bodies `UpdatePinSessionStateRequestBody`,
`ValidateTrustInfoRequestBody`, `CryptoTrustInfo`):
- `POST /DevicePairingProxy/PinSessions/{id}` (create)
- `GET  /DevicePairingProxy/PinSessions/{id}/State`
- `.../PinSessions/{id}/QRScanned` · `/PINTyped` · `/ValidateTrustInfo`
  · `/AccountTransferred`
- `.../PhoneSessions/{id}/State` + `/PhoneState`

Crypto-trust ceremony: `.../PairingSessions/{id}/Complete`.

Modeled in `PairingProxyEndpoints` + `PinSessionState`.

Auth to the proxy: an **MSA token** (`PairingProxyMsaTokenHeaderInterceptor`);
a plain DCG access token is rejected ("Request pairing proxy service with dcg
token unauthorized").

## CONFIRMED — pairing-channel ceremony order
From the ordered state processors
(`com.microsoft.mmx.agents.ypp.pairing.statemachine.processor.*`):
```
CheckPermission → GetChannelInfo → OpenConnection → JoinChannel(WithMsa)
  → SendDeviceInfo → SendCryptoInfo → SendNonce → WaitForPing
  → CommitCryptoTrust → Succeed | Failed
```
Message kinds (`pairing.protocol.*`): `JoinChannelWithMsaRequestMessage {msaToken}`
→ `JoinChannelResponseMessage {channelExpireTime}`, `DeviceInfoExchangeMessage`,
`CryptoInfoExchangeMessage` (public key / cert → crypto trust), `NonceMessage`,
`PingMessage`, `PairingResponseMessage`, `ExitChannel*`, `PartnerExitedMessage`.
Modeled in `PairingCeremony` (`PairingCeremonyState`, `PairingMessageKind`).

## Account transfer + session key
- `MsaA2DPairingManager.handleDynamicLink` turns the scanned link into a
  `pinSessionId`, then `reportQRCodeScannedAsync` → `reportChallengePinAsync`
  → `reportAccountTransferredAsync` → device enroll (`DeviceEnrollResult`).
- `TransferToken` (MSA) moves the account; an AES-GCM **session key**
  (`SessionKeyUtil`, `SessionKeyBasedDecryptorAesGcm`, Android KeyStore)
  encrypts the exchange — very likely derived from / carried alongside the QR
  session. Exact derivation still to confirm.

## Honest caveats / what's still blocking a full pair
- **First-party gating.** Creating the cloud PinSession and calling the pairing
  proxy both require an **MSA token**, and the proxy is expected to be gated to
  first-party identities (same risk as DCG). A third-party client — and a QR
  not backed by a real, cloud-created PinSession — will be refused. So the QR we
  now render is *structurally valid* (correct grammar) but **not yet backed by a
  real session**, and a phone scanning it will not complete pairing until the
  PinSession-create path is solved.
- **Not byte-confirmed on the wire.** Grammar and endpoints are from
  decompiled parsers, not captured traffic. The netty codec framing of the
  ceremony messages and the session-key derivation remain to be verified live.

## Next steps
1. Decompile `MsaA2DPairingManager.handleDynamicLink` + `PinSessionManager`
   fully to confirm the PinSession-create request/response JSON and how the
   `uaid` prefix maps to a `pinSessionId`.
2. Confirm the exact MSA scope the pairing proxy requires (vs
   `dcg.microsoft.com/DCG.ReadWrite`).
3. `SessionKeyUtil` — how the AES-GCM session key is derived/encoded.
4. Build `PinSessionClient` (create/poll/report against `PairingProxyEndpoints`)
   once an MSA token is available, and feed `CryptoInfoExchange` into the
   existing `DeviceTrustAuthorizer`.
