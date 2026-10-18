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

## Windows identity layer — DDS + MSA device tokens  (external RE note)
Source: an independent Windows-side reverse-engineering writeup (GDID / MSA
Device PUID), not our own extraction. Recorded here as protocol facts because it
names the cloud identity layer that sits *under* the DCG/pairing wall. Nothing
from it is vendor source; no binaries or raw traces are committed.

- **DDS = Device Directory Service** is the cross-device graph behind Phone Link,
  cloud clipboard, "Continue on PC" and Nearby Share. Endpoints seen in `cdp.dll`:
  `dds.microsoft.com`, `fd.dds.microsoft.com`, `aad.cs.dds.microsoft.com`,
  `cdpcs.access.microsoft.com`. The Connected Devices Platform (`CDPSvc`) is the
  client that *registers* an installation into that graph (keyed `g:<decimal>`).
- **The real client authenticates with MSA *device* tokens, not user OAuth.**
  The MSA/Passport service (`wlidsvc`) mints device tokens scoped to exactly the
  graph endpoints:
  - `service::dds.microsoft.com::MBI_SSL_TOKEN_BROKER`
  - `service::activity.windows.com::MBI_SSL_SA_TOKEN_BROKER`
  These are `MBI_SSL` broker tokens tied to a machine-provisioned **Device PUID**
  (`0018…` class), provisioned against `login.live.com` (PPCRL SOAP
  `DeviceAssociateRequest`, `HWPUIDFlipped`) with a device cert bound by
  `BindDeviceToHardware` / `GetDeviceCert`.
- **Why this matters for us:** our sign-in uses a *user* Entra/MSAL token. The
  DCG/activity endpoints appear to expect an MSA **device**-broker credential
  (`MBI_SSL_*`) that only the first-party stack provisions — a strong candidate
  explanation for the `AADSTS65001` refusal on `DCG.ReadWrite`, and it lines up
  with "device-trust cert issuance" being gated. Confirming this needs a live
  `wlidsvc` token-mint trace during a real pairing (see `docs/EVIDENCE_PLAN.md`).

Confidence: the writeup tags its own claims (`[COURT]/[OBSERVED]/[STATIC]`); for
us this is **unconfirmed against Phone Link traffic** until an ETW/token trace
shows `wlidsvc` requesting these scopes in the pairing window.

## Browser login tops out at the MSA session  — CONFIRMED live
Live test (Claude-in-Chrome, user's own account, user-authenticated; only
request *shapes* captured, no password/token values): signed out, then a fresh
`login.live.com` sign-in. The whole flow was 31 requests — `ppsecure/post.srf`
(the session post, body not inspected), `GetExperimentAssignments.srf`, and
CDN/telemetry. **No `RST2.srf` / PPCRL, no `*.dcg.microsoft.com`, no
`msatoken.dcg.microsoft.com`, no `MBI_SSL` request appeared.**

**Conclusion:** a browser login only yields the MSA *session cookie*. The DCG
`MBI_SSL` device ticket is never minted in-browser — it is minted by the native
`wlidsvc` broker, which binds a device key + cert (`BindDeviceToHardware` /
`GetDeviceCert`, per the GDID writeup). So the in-app WebView sign-in
(`WebViewSignIn`) can authenticate the user, but that session **alone cannot
reach DCG**; a client must additionally emulate the device broker (generate a
device key/cert and call the RST endpoint for the DCG target). The exact shape of
that call is **not browser-observable** — it only happens natively, which is why
`docs/EVIDENCE_PLAN.md` item C (the `wlidsvc` ETW trace during pairing) is the
real unlock, not optional.

## Nano transport + mirroring  — CONFIRMED from YourPhone screen-mirroring stack
Static RE (REA + plaintext API-doc/winmd sidecars) of the shipped mirroring
stack: `LibNanoAPI.winmd/.dll`, `YourPhone.ScreenMirroring.Managed(.Protocol).dll`,
alongside `msquic.dll` + `System.Net.Quic.dll`. Type/interface/field identifiers
only; no vendor source copied.

### Transport = MsQuic, one Connect multiplexing typed Channels (`LibNanoAPI`)
- The direct transport is **MsQuic** (`msquic.dll`, `System.Net.Quic`), so our
  Network.framework `NWProtocolQUIC` choice is protocol-compatible. The exact
  **ALPN string and frame-header bytes are still unknown** (native LibNanoAPI /
  live capture — EVIDENCE_PLAN item A).
- Model: a **`Connect`** created as client or server (`CreateClientConnect` /
  `CreateServerConnect`, `IConnect`/`IConnectDelegate`, `ConnectionId`,
  `ConnectionType`, `ConnectCloseReason`/`ClientCloseReason`, `IsConnected`,
  `GetConnectionMetrics`/`GetRealTimeConnectionMetrics`).
- Over one Connect, typed **Channels** are multiplexed (`ChannelFactory`,
  `CreateChannel`, `ChannelId`, `ChannelType`, `ChannelStack`, `IChannelDelegate`):
  - `IVideoTargetChannel` (+Delegate) — video down to the PC
  - `IAudioTargetChannel` (+Delegate) — audio down to the PC
  - `IInputSourceChannel` — input up to the phone
  - `IMessageChannel` — control messages
  - `IBlobChannel` / `IBlobStream` — bulk/blob transfer
- **Answers the Phase-2 "multi-stream?" question: yes** — control vs media are
  separate channels over a single QUIC Connect, not one muxed byte stream.
- Video delegate surface: `OnFramesReady`, `OnVideoFirstFrameDecoded`,
  `OnExpiredFramesThreshold`, `RawFrames`, `frameLengthMs`, `useFrameInterpolation`,
  `GetVideoMetrics`. Input: `SendKeyPress` with `wasKeyDown` / `isKeyReleased` /
  `isExtendedKey` / `isAltGrOnKeyboard` — richer than our normalized pointer model.

### Mirroring app messages — protobuf `YourPhone.PhoneMirroring.Protocol.V1`
Transport-control message type is **`NearbyMessage`** (the mirroring handshake/
control envelope). App messages (new/confirming beyond our set): `ConfigMessage`
(MaxMainDisplayFps, AppsFeatureType, Width, Height, Dpi, HostDisplayWidth/Height),
`LaunchPhoneScreenAppMessage` / `LaunchAppMessage` (PackageName, SessionId,
TargetScreenLayout, TransferTaskId, Flags), `BlackScreenMessage`,
`SetLockedStateMessage`, `DeviceLockMessage` (IsLocked, IsSecureLocked),
`RequestSetting(Result)Message` (SkipUnlock, SkipVerification),
`SendPinCodeMessage`, `VerificationResultMessage` (IsQrCode, ExpiryToken),
permission messages (Request/Check/Show + LaunchSettings + Status + Result).

### YPP messaging transport (separate from Nano) — `YourPhone.Connectivity.YPP.Managed`
The notifications/messages/file layer is **SignalR + a cloud relay**, not Nano:
`signalRPlatformConnectionManager`, `SignalRSendResponseMessageActivity`,
`cloudRelayManager` ("calling cloud relay service"), `CustomPlatformConnectionManager`,
`OutOfProcPlatformConnection`, `YppPlatformConnection`.
- **Connection-string schema**: `selfClientId`, `signalRDetails`, `regionInfo`,
  `regionName`, `installationId`, `dcgClientId`, `traceId`.
- **Message envelope fields**: `_requestId`, `_originalRequestId`, `_route`,
  `contentType`, `remoteAppId`, `_isGzippedCompressed` (gzip), `/internal/response`.
- **File transfer headers**: `x-drm-resource-path`, `x-drm-resource-type`,
  `x-drm-resource-request-type`, `x-bt-content`; OneDrive path (`FILE_TRANSFER_ONEDRIVE`).
- **Side channels**: `hotspotSideChannelService` (Wi-Fi hotspot negotiation — the
  Phase-2 transport-negotiation piece) and BLE wake via **MSAEP** (MsaepManager,
  timer background task) for waking the phone over Bluetooth LE.
- App id: `Microsoft Your Phone`, app GUID `8CF55838-E496-42C5-829B-F8D6945288F3`.
- Cert-recovery deep link: `ms-phone:fre?reason=CertificateRecovery&devicetype=Android`.

Confidence: interface/type/field identifiers are **observed** in the shipped
artifacts; wire bytes (QUIC ALPN, Nano frame header, Nearby handshake order) are
**not yet confirmed** and need the native LibNanoAPI disasm or a live QUIC capture.
