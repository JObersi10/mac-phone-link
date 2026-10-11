# Reverse-engineering findings

Consolidated facts from static analysis of the vendor artifacts (the Windows
MSIX and the Android `com.microsoft.appmanager` APK — never committed; see
`.gitignore`). Method: `strings` over the `.dex`, targeted `jadx --single-class`
decompiles, and the decoded `AndroidManifest.xml`. These are **interface facts**
(names, grammar, endpoints) re-expressed clean-room under `maclink.*`; no vendor
source text is reproduced.

Where a fact drives code, the clean-room Swift model is named.

---

## Transport architecture
- Baseline is a **cloud relay**: Device Connectivity Gateway (DCG) over SignalR.
  No LAN discovery (no mDNS/Bonjour/SSDP).
- High-bandwidth / screen mirroring uses a **direct "Nano" path** (QUIC, Wi-Fi
  Direct / instant hotspot) negotiated via the side channel.
- Shared schema "YPP" (`com.microsoft.mmx.agents.ypp.*` ↔ `YourPhone.YPP.*`).
- DCG hosts (from the manifest + dex): `dcg.microsoft.com` (prod),
  `dcg-df.microsoft.com` (dogfood), `dcg-beta.microsoft.com` (beta),
  `dl.dcg.microsoft.com` / `ypdl.dcg.microsoft.com` (deep-link).
- App-level deep-link schemes: `ms-phone://connect`, `ms-phone://redirect/post`,
  `ms-phone://pair_manually`, `ms-appmanager://dl.dcg.microsoft.com`, `ypc://`.

## Auth (two independent layers)
- **MSA/Entra access token**, audience `dcg.microsoft.com/DCG.ReadWrite`, is the
  SignalR bearer. First-party protected → a third-party app is expected to be
  refused consent. Modeled: `DCGAuth` (`DCGAuthenticator`, scopes).
- **Device-to-device crypto trust**: an RS256 JWT per message carrying a DRS
  `nonce` + `dcgClientId`, wrapped in `SideChannelAuthorization`. Modeled:
  `DeviceTrustJWT`, `SecKeyRS256Signer`, `CertThumbprint`, `DRSNonceClient`,
  `DRSDiscoveryClient`, `DeviceTrustAuthorizer`.
- The **pairing proxy** wants an MSA token specifically; a plain DCG token is
  rejected ("Request pairing proxy service with dcg token unauthorized").

## DCG message framing
App payloads are fragmented into `DcgFragmentMessage`s (shared `message_id`,
ordered `fragment_id`, `sequence_number`), acked via `DcgAckMessage`. Modeled:
`DCGFramer` / `DCGReassembler` / `DCGAck`.

## QR pairing payload  — CONFIRMED grammar
Source: `FreQrCodeManager`, `FreParseDynamicLinkManager`, `DeeplinkResolver`.
- The scanner's `validateUri` **rejects any string without a scheme AND host** —
  so a bare `uaid=...` is "invalid". The QR is an **HTTPS dynamic link to a DCG
  host**:
  ```
  https://dcg.microsoft.com/?vm=5&uaid=<prefix><16-char code>&ti=<guid>&r=5&apn=com.microsoft.appmanager
  ```
- Host must be a DCG host (`isDcgHost`).
- `vm` — flow mode (`DynamicLinkModeType`, numeric string): `1`/`2` OOBE,
  **`5` = ideal flow**, `101`/`102` minimalism OOBE.
- `uaid` — the **YPP pairing code is the last 16 characters** of this value
  (`getYPPPairingCode`); a non-all-zeros prefix marks a real session.
- `ti` — trace id (GUID). `r` — ring (`RingDefinition`): `1` dev, `2` team,
  `3` canary, `4` beta, **`5` = PROD**.
- `apn` — android package (`com.microsoft.appmanager`); `patchIdealFlowMissingParams`
  injects `apn`/`r` if missing.
- `tsft` — MSA transfer token; `cpsi` — cloud pin-session id; `mvc` — present in
  the transfer modes. `validateDynamicLink` fails on `EMPTY_{VM,CPSI,RING,TSFT,MVC}`.
Modeled: `QRPairingPayload`, `DynamicLinkMode`, `RingDefinition`.

### Why a locally-built QR still won't pair
`dcg.microsoft.com` IS an `autoVerify` App Link in the manifest, so the format is
right — but `validateDynamicLink` only treats the link as a *pairing* link when
it carries a real `cpsi` + a Microsoft-minted `uaid`. A locally-generated link is
not recognized, so the app degrades to opening the raw URL, which hits DCG's API
host and returns a generic error page. This is the first-party wall. Creating a
real PinSession is cloud-side and gated.

## Device Pairing Proxy  — CONFIRMED surface
Hosted under the DCG domain, path root `/DevicePairingProxy/`. QR/PIN flow runs a
**PinSession** through states: `created → QRScanned → PINTyped →
ValidateTrustInfo → AccountTransferred` (`updatePinSessionStateAsync`; bodies
`UpdatePinSessionStateRequestBody`, `ValidateTrustInfoRequestBody`,
`CryptoTrustInfo`). Crypto-trust completes at `PairingSessions/{id}/Complete`.
Also `PhoneSessions/{id}/State` + `/PhoneState`. Service keyed by
`EnvironmentType` (`AccountPairingSessionService`). Modeled:
`PairingProxyEndpoints`, `PinSessionState`, `DCGEnvironment`.

## Pairing-channel ceremony  — CONFIRMED order
From the ordered state processors (`pairing.statemachine.processor.*`):
```
CheckPermission → GetChannelInfo → OpenConnection → JoinChannel(WithMsa)
  → SendDeviceInfo → SendCryptoInfo → SendNonce → WaitForPing
  → CommitCryptoTrust → Succeed | Failed
```
Messages (`pairing.protocol.*`): `JoinChannelWithMsaRequestMessage {msaToken}` →
`JoinChannelResponseMessage {channelExpireTime}`, `DeviceInfoExchangeMessage`,
`CryptoInfoExchangeMessage`, `NonceMessage`, `PingMessage`,
`PairingResponseMessage`, `ExitChannel*`, `PartnerExitedMessage`. Driver:
`PairingStateMachine`. Modeled: `PairingCeremony` (state order + message kinds).

## Account transfer + session key
`MsaA2DPairingManager.handleDynamicLink` → `pinSessionId`, then
`reportQRCodeScannedAsync` → `reportChallengePinAsync` →
`reportAccountTransferredAsync` → device enroll (`DeviceEnrollResult`). MSA
`TransferToken` moves the account; an AES-GCM **session key** (`SessionKeyUtil`,
`SessionKeyBasedDecryptorAesGcm`, Android KeyStore) encrypts the exchange —
derivation still to confirm. Not yet modeled (blocked path).

## Screen mirroring / app-remoting
Protos observed (now clean-room): config, resolution, orientation, permissions,
drag-and-drop (`Drag*Message`), audio (`AudioStreamReadyMessage`,
`VolumeMessage`), focus/lifecycle (`BringToForeground`, `LaunchApp`), clipboard
(`ClipDataItems`). Input injection (cursor/keyboard) was NOT in the vendor set we
extracted as protobuf — the direct path likely uses a compact control format; we
model our own clean-room `InputEventMessage` (normalized coords). Modeled:
`VideoStreamController`, `VTVideoDecoder`, `RemoteControl`/`RemoteInputView`
(cursor), `ClipboardSync`.

## Manifest app-links (why in-app scan opened a browser)
`autoVerify="true"` intent filters for `https` on `dcg.microsoft.com`,
`dcg-df.microsoft.com`, `dcg-beta.microsoft.com`, `dl.dcg.microsoft.com`, plus
`ms-phone` / `ms-appmanager` / `ypc` schemes. Confirms the host/scheme are right;
the open-in-browser fallback is the pairing-link rejection described above.

## Known uncertainties (verify against live traffic)
- SignalR hub method names for DCG send/receive (placeholders, configurable).
- DRS nonce URL / discovery contract field names (standard Workplace-Join shape).
- JWT `kid` hash variant (default base64url SHA-256; switchable).
- Nano QUIC ALPN value + whether control/media are separate streams.
- Mirror frame container (Annex B vs AVCC) and SPS-derived video size.
- Session-key derivation; exact DCG claim validation beyond nonce/dcgClientId.
