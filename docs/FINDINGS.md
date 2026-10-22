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

### Real PC "Add device" link  — CONFIRMED from a live Windows PC
Captured from a real Windows Phone Link "Add device" button (live `cpsi`/`ti`/`et`
values redacted — the `cpsi` is a short-lived session token). The add-device link
the **PC** produces is a *different* shape from the `uaid` "ideal flow" above:
```
https://dcg.microsoft.com/dl?mvc=<int>&cpsi=<char><guid>&vm=101&et=<unix>&r=5&ti=<32-hex>
```
Corrections this forces to the earlier model:
- **Path is `/dl`** (a deeplink path), not `/`.
- **`vm=101`** is the real PC add-device mode (we'd labelled 101 "minimalism
  OOBE"); `vm=5` ideal-flow is a *different* entry point.
- **`cpsi`** carries the cloud PinSession — a single letter prefix + a GUID
  (e.g. `n<guid>`); this flow uses **no `uaid` and no `apn`**.
- **`et`** = Unix-seconds **expiry** (new param; observed ≈ capture time, so the
  session is short-lived — explains why an old link later reads "unavailable").
- **`mvc`** = numeric client **min-version code** (~5.23M).
- **`ti`** here is **32 lowercase hex, no dashes** — not a dashed GUID.
This is the link whose `cpsi` only the first-party pairing proxy can mint; the
grammar is now exact, but the session behind it is still cloud-gated.

**What `/dl` does when opened — CONFIRMED live (observed resolver behavior):**
opening the link on a non-Android client (Claude's browser) **302-redirects to
the Google Play page** for `com.microsoft.appmanager`, carrying the pairing
context as the Play **install `referrer`**:
`cpsi=<session>&ti=<32hex>&vm=101&r=5&et=<unix>&mvc=<int>&utm_source=pcqr`.
So pairing is a **deferred deep link via the Play Install Referrer**:
1. Phone scans the PC QR → hits `dcg.microsoft.com/dl`.
2. If the app isn't installed → redirect to Play **with the pairing params as
   the install referrer**; on first launch the app reads the Play Install
   Referrer API, recovers `cpsi`/`ti`/`vm`, and completes pairing cloud-side.
3. If the app **is** installed → the `autoVerify` App Link opens the app
   directly with the deeplink (no Play round-trip).
`utm_source=pcqr` tags the origin as the PC QR. This explains why a scan without
a live, cloud-minted `cpsi` just falls through to a web/Play page and never
pairs: the whole ceremony hinges on a `cpsi` the first-party proxy issues.

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

### Transport = ICE/STUN/TURN peer-to-peer + pseudo-TLS (`LibNanoAPI`, native)
Corrects an earlier guess: the Nano **media** path is **not plain QUIC**. The
native `LibNanoAPI.dll` (namespace `Microsoft::Nano::Streaming` / `::Input`) is a
**WebRTC-style ICE/STUN/TURN** transport:
- **ICE** candidate gathering + checks: `BaseIceTransport`,
  `OnICEHandshakeComplete`, candidate types `0=Host, 1=ServerReflexive,
  2=PeerReflexive, 3=Relayed, 4=Manual`, `m_relayedCandidatePairsOnly`.
- **STUN/TURN**: STUN binding messages carry a transaction id (`trId4`) "on base
  … to peer … via relay …"; TURN relay allocation with cloning (`CloneTurn`,
  turn-server reallocation). Transport flavors seen: `nano` (direct UDP),
  `tcp-turn`, `tls-turn`.
- **Pseudo-TLS handshake** over the relay/base ("Sending/Received Pseudo TLS
  handshake on base … to/from relay …"), wrapped inside STUN/"wrapper" messages.
- Media QoE uses **RTP/RTCP** (`NanoNetworkQOE`, "RTCP report count …").
- **Per-channel, versioned handshake packets** after the base is up — each channel
  does a `ClientHandshakePacket` → `ServerHandshakePacket` exchange
  (`Microsoft::Nano::Streaming::{Video,Audio,Blob,Message}Channel`,
  `Microsoft::Nano::Input::InputChannel`); video/audio/input are asymmetric
  (distinct Client/Server packets, "Server Handshake Packet V%d"), blob/message
  use a single `HandshakePacket`. "is incompatible with client protocol version"
  → the handshake negotiates a protocol version.
- Channel lifecycle: `ChannelCreateRequest` / `ChannelOpenRequest` /
  `ChannelBase Open`/`OnOpened`; channel id tokens `NANO_VIDEO`, `NANO_AUDIO`,
  `NANO_INPUT`, `NANO_MESSAGING`, `NANO_BLOB`, `NANO_DCT`.

**Implication for us:** our `NanoTransport` is built on Network.framework
`NWProtocolQUIC`, which is the wrong primitive for the media path — a faithful
client needs an **ICE agent + STUN/TURN + the pseudo-TLS handshake**, not QUIC.
`msquic.dll` / `System.Net.Quic` (and the `H3`/`HQ` ALPN tokens) are present but
most likely belong to the cloud/relay (HTTP/3) leg, not the P2P media path.
Exact STUN/pseudo-TLS/handshake-packet byte layouts still need the native disasm
or a live capture (EVIDENCE_PLAN item A).

- Managed facade over this (`LibNanoAPI.winmd`): a **`Connect`** created as
  client or server (`CreateClientConnect` /
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
  separate channels over a single ICE Connect, not one muxed byte stream.
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

Confidence: interface/type/field identifiers and the ICE/STUN/TURN + pseudo-TLS +
per-channel-handshake architecture are **observed** in the shipped artifacts; the
exact wire bytes (STUN attributes, pseudo-TLS record layout, handshake-packet
fields and version numbers, Nearby handshake order) are **not yet confirmed** and
need the native LibNanoAPI disasm (function-level) or a live packet capture.
## DCG auth + device identity  — CONFIRMED from `YourPhone.YPP.Auth.dll`
Static decompile of the Windows client's auth assembly (`YourPhone.YPP.Auth`,
.NET 10, sha256 `d1105c4a…`), read via REA (no execution). These are protocol
facts (endpoints, header names, api-version, algorithm identifiers, enum names)
pulled from `#US` string literals; vendor source was not copied.

### The login is MSA-token-based, NOT an Entra `DCG.ReadWrite` scope
The real client does **not** request an AAD/Entra access token for
`https://dcg.microsoft.com/DCG.ReadWrite`. It acquires a **Microsoft Account
(MSA)** ticket via the account broker (WAM `webAccount`) against the consumers
authority, then presents it to the DCG auth host:
- MSA authority seen: `https://login.microsoft.com` + `consumers`.
- Scope strategy (observed log): try a **SAPI** MSA token first, then
  **fall back to `MBI_SSL` scope** — matches the README's `service::…::MBI_SSL`
  device-broker form.
- DCG auth host: **`https://msatoken.dcg.microsoft.com`**.
- Request shape: `…&api-version=2.0&clientid=<dcg client id>` (`api-version=2.0`).
- Headers: `Authorization: Bearer <msaToken>`, **`Authorization-Type: MSA`**.

**Implication for us:** our `AADSTS65001` wall is likely partly self-inflicted —
we were requesting an Entra access token for a first-party scope. The shipped
client never does that; it rides an MSA broker ticket (SAPI→MBI_SSL) with
`Authorization-Type: MSA`. Worth retrying the DCG call with an MSA token of the
MBI_SSL form rather than an Entra `DCG.ReadWrite` scope.

### Per-environment DCG client ids (config keys, not secrets)
`dcg_client_id`, `dcg_prod_client_id`, `dcg_beta_client_id`, `dcg_df_client_id`
— the app selects one per `EnvironmentType` (PROD/BETA/DF), resolved through an
`EnvironmentDiscoveryManager` that calls a discovery service and can snap the
device PROD↔BETA.

### Device identity ceremony (`DcgAuthManager` / `AuthServiceCryptoHelper`)
Nonce-bound, certificate-based establish/refresh/rotate:
- Activities: `EstablishIdentityActivity`, `RefreshAccessTokenActivity`,
  `KeyRotationActivity`; states `DeviceIdProvisioned` / `DeviceIdDeprovisioned`.
- Nonce: fetched from the DCG auth service (not Workplace-Join DRS — see
  correction below), then a **nonce JWT** is signed and sent with establish /
  sign-in / key-rotation. Failure anomalies: `InvalidNonceEvent`,
  `DeviceIdCollisionEvent`.
- Key-rotation messages: `keyOwnershipProofRequest`,
  `newIdentityOwnershipProofRequest`, `keyRotationRequest`.
- **Signing:** ECDSA P-384 — `http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384`.
- **JWE:** `RSA-OAEP` key wrap + `A256CBC-HS512` content encryption.
- Self-signed cert with `CN=<distinguished name>`; cert + private key held in the
  platform key store (`CngKeyName`), DPAPI-protected key storage.

### Crypto trust relationships (device-to-device trust)
`CryptoTrustRelationship` records: `SelfClientId`, `PartnerClientId`,
`PartnerCertificate`, `PartnerTemporaryCertificate`, `PartnerKeyExpirationTime`,
`MsaCid`, `TrustType`, `TrustedClients`. **TrustType** enum:
`LegacyD2D`, `AccountPairingD2D`, `AsyncD2D`, `A2D` (+ `Unknown`). This is the
trust store that a completed pairing populates — `A2D` / `AccountPairingD2D`
correspond to the QR/account-transfer pairing path.

### Correction to earlier assumptions
Our `Sources/DCGAuth` modeled the nonce as a **Workplace-Join / DRS** flow
(`enterpriseregistration.windows.net`, `EnrollmentServer/contract`). The binary
shows the nonce is **DCG-native** (via `msatoken.dcg.microsoft.com`), and the
token is an **MSA** ticket, not an Entra `DCG.ReadWrite` scope. The DRS model is
likely wrong for Phone Link; treat `DCGWireContract` (new) as the confirmed shape.

Confidence: endpoint/header/api-version/algorithm/enum strings are **observed**
in the shipped artifact; the end-to-end sequence is **derived** from them and
not yet confirmed against live traffic (see `docs/EVIDENCE_PLAN.md` item A/C).

---

## Android companion surface  — CONFIRMED from live pairing logcat
From a redacted `adb logcat` taken during a Windows↔Android pairing (raw kept
local per `EVIDENCE_PLAN`; only names recorded here). App = `com.microsoft.appmanager`,
log tag `WindowsLink`, MSA tag `OneAuthLog`.

- **Phone-side auth is MSAL against `login.microsoftonline.com/consumers`** (MSA
  consumers authority), consistent with the DCG MSA-ticket finding. (The Windows
  DCG leg uses `login.microsoft.com/consumers` + `msatoken.dcg.microsoft.com`;
  two different legs.)
- **Transport bootstrap uses a Bluetooth RFCOMM server** on the phone
  (`method_is_rfcomm_server_opened`, `capability_bluetooth_transport`,
  `notifyConnectionState`) — confirms the BLE/RFCOMM side-channel + wake we
  inferred from the YPP layer; the media path (Nano/ICE) is negotiated after.
- **Capability flags the phone advertises to the PC** (cross-process query
  grammar `capability_<name>`): `adaptive_layout`, `android_apps_on_windows`,
  `audio_streaming`, `black_screen_control`, `bluetooth_transport`,
  `call_support`, `clipboard_redirector`, `device_info`, `drag_and_drop_broker`,
  `input_inject`, `instant_hotspot`, `launch_activity`, `message_support`,
  `pre_granted_permissions`, `recent_apps`, `remote_lock_simulation`,
  `tablet_support`, `wifi_direct`. This is the authoritative feature set a
  faithful client negotiates.
- **Internal content-provider IPC surface** (phone app): `DeviceInfo@{isFolded,
  getVendorRssiLevel,getMAXRssiLevel}`, `PermissionManager@{isWFDPermissionGranted,
  isBluetoothConnectPermissionGranted}`, `TaskInfoManager@getRecentTasks`,
  `UserInfo@isTwoPhoneModeEnabled`, `PreviewMode@isPreviewModeEnabled`,
  `ServiceInfo@getLauncherIconEnabled`, `WindowsLinkTileRequest@setStateOnAnd{Connected,Disconnected}`.
- Note: logcat does **not** carry the Nano/ICE/TURN wire bytes or the DCG HTTP —
  those live in native libs + on the network. (`quic`/`ice`/`turn` substring hits
  in logcat were Qualcomm-camera / "device" / "return" noise, not transport.)

## "Phone as webcam" feature  — CONFIRMED from live webcam logcat
Separate feature from screen mirroring: the phone's camera is streamed to the PC
and surfaced there as a **virtual camera** device.

- Phone-side owner: `com.microsoft.mmx.agents.camera` —
  `…ui.views.CameraStreamActivity`, `…foregroundservice.CameraStreamForegroundService`,
  `…ui.views.StreamConnectedFragment.showEffectsDialog` (so camera effects are a
  phone-side control surface).
- **Encoding = H.264** (`mime = "video/avc"`, input `video/raw`), via the
  Qualcomm hw encoder `c2.qti.avc.encoder` (sw fallback `c2.android.avc.encoder`),
  `bitrate-mode = 1` (VBR). Observed bitrate ladder ~1 Mbps / ~2 Mbps with a high
  max ceiling. This is the **same codec and transport as mirroring** — just the
  camera as the source instead of the screen.
- **Implication for the Mac client:** receiving/decoding reuses the existing
  H.264 path (`VTVideoDecoder`) over a Nano typed channel; the only genuinely new
  pieces are (a) the camera-stream control messages (start/stop/effects) and
  (b) a macOS-side sink. The macOS equivalent of the Windows virtual camera is a
  **Core Media IO camera extension** (`CMIOExtension` system extension) that
  publishes decoded frames as a system camera any app (FaceTime/Zoom) can select.
  Both are buildable independently of the first-party wall; lighting them up still
  needs the live Nano transport.

Confidence: component/class names, codec mime, encoder ids and MSAL authority are
**observed** in live logcat; the stream↔transport binding is **derived** (reuses
the confirmed mirroring/Nano path) and not yet confirmed on the wire.

## Windows auth leg  — CONFIRMED ON THE WIRE (live WPR/ETW trace)
From a targeted LiveId + WinHTTP/WinINet ETW trace during a live reconnect (raw
`.etl` kept local). This is the first **on-the-wire** confirmation of the DCG
auth model — it upgrades the earlier static-RE inferences to observed fact.

- **DCG.ReadWrite is acquired as an MSA *token-broker* scope, not an Entra OAuth
  scope.** The exact request scope string on the wire is
  `scope=https://dcg.microsoft.com/DCG.ReadWrite&api-version=2.0`, used inside a
  WS-Trust `RequestSecurityToken` SOAP with a `_TOKEN_BROKER` policy suffix
  (`.../DCG.ReadWrite_TOKEN_BROKER`). So the client asks **wlidsvc / the MSA
  token broker** for a ticket to the DCG resource — it never does an Entra
  `/oauth2/v2.0/token` call for that scope. **This is the concrete explanation
  for `AADSTS65001`:** we were asking the wrong authority (Entra) for a scope the
  real client only ever requests through the MSA broker.
- **Device-token broker scopes confirmed live** (match the external DDS note
  exactly): `service::dds.microsoft.com::MBI_SSL` and
  `service::dds.microsoft.com::MBI_SSL_TOKEN_BROKER`.
- **The device identity ceremony is live PPCRL / WS-Trust:** `GetDeviceCert`,
  `RequestSecurityToken` / `RequestMultipleSecurityTokens` (RST/RSTR), `wsse:`
  security headers, and `DeviceAssociateService` all appear during the window —
  against `login.live.com` / `login.microsoft.com`. The device cert + MBI_SSL
  device ticket are minted here by the native stack; this is the gated step.
- **Device-graph endpoint (DDS / "Continuum"):**
  `GET https://continuum.dds.microsoft.com/Command/user/Continuum/Devices?scenario=…`
  (resolves via Azure Front Door, `*.tm-azurefd.net`). This is the cross-device
  directory the client registers into — the `g:<decimal>` graph from the DDS note.
- Hosts seen: `login.microsoft.com`, `login.live.com`, `dcg.microsoft.com`,
  `continuum.dds.microsoft.com`, `account.live.com`. `api-version=2.0` confirmed.
- **No Nano/TURN/relay host appeared** in this trace — expected, the ETW
  providers were HTTP/auth only. The transport leg still needs a packet capture
  (`capture/phonelink-transport-pktmon.ps1`).

Net: the auth side is now **confirmed, not inferred** — and it confirms the wall
is specifically the MSA device-token / device-cert mint (`wlidsvc` PPCRL), which
a third party cannot reproduce. `Sources/DCGAuth` should target the MSA
token-broker path (`DCGWireContract`), not Entra OAuth.

## Nano transport  — CONFIRMED ON THE WIRE (live pktmon capture)
From a `pktmon` packet capture of a live mirroring/camera session, decoded by
`scripts/parse_transport.py` (headers + STUN only; media never read; raw kept
local). This confirms the ICE/STUN/TURN model from static RE **on the wire** and
answers the open relay-vs-P2P question.

- **Media is delivered PEER-TO-PEER over the local network**, not relayed. The
  dominant flow was phone→PC directly between the two LAN addresses (~116k UDP
  packets for the video leg), alongside **5–6 parallel UDP channel pairs** —
  matching the Nano multi-channel model (video / audio / input / message / blob).
- **ICE connectivity checks confirmed:** ~48 STUN **Binding Request** / ~44
  **Binding Success** between the peers (RFC 5389/8445).
- **TURN is used for candidate gathering / fallback against Microsoft Azure**
  STUN-TURN servers on **port 3478** (hosts in the `20.202.x.x` Azure range).
  The classic long-term-credential dance was observed: `Allocate` → `Error`
  (401, no creds) → `CreatePermission` **Success**. So a faithful client needs a
  real TURN client (Allocate/Refresh/CreatePermission/ChannelBind), even though
  the happy path on a shared LAN is a direct host-candidate pair.
- **Candidate types seen** (via `XOR-MAPPED-ADDRESS` / `XOR-PEER-ADDRESS`):
  **host** candidates (both devices' LAN addresses, on several ports) and a
  **server-reflexive** candidate (the public address returned by the STUN
  server). Both ends reflexed to the *same* public IP → same NAT → ICE correctly
  selected the direct LAN path and kept TURN as fallback.
- Also present (cloud/signaling legs, not the media path): UDP/443 to Cloudflare
  (`162.159.x` — likely HTTP/3/QUIC signaling) and assorted `:443` to Azure/CDN.
  These are the control/relay-coordination legs, separate from the P2P media.
- Not visible in this capture: the pseudo-TLS record layout and per-channel
  versioned handshake bytes (packets were header-truncated). Those still need a
  fuller payload capture or native disasm — but the **transport selection and
  ICE/STUN/TURN behaviour are now confirmed fact**.

Implication for `Sources/NanoTransport`: the ICE/STUN core is the right
primitive (confirmed). Priorities are a working **TURN client** and the ICE
nomination/USE-CANDIDATE path; `QUICNanoConnection` remains the wrong primitive
for the media leg (QUIC is only the cloud/signaling leg).

## Prior art + the TWO pairing paths  — CORRECTION
Earlier notes treated "the first-party wall" as one thing blocking everything.
A survey of existing open-source clients shows that was wrong: there are **two
distinct pairing models**, and only one is hard-gated.

Prior art:
- **LinkMyPhone** (`github.com/YMGPwcca/linkmyphone`) — an unofficial **Linux**
  client that **actually interoperates** with Microsoft's DCG + Hub Relay.
  Working: **clipboard (bidirectional) and notifications** (dismiss/actions/
  reply). Not implemented: messages, calls, media, files, **screen mirroring**,
  and **no QR pairing**. Crucially, it authenticates with an **OAuth
  device-code flow** (standard MSA sign-in) and stores self-generated
  **private keys** — *not* a TPM/`wlidsvc` device certificate.
- **SapkaLabs/sapkalink** — research only; treats independent pairing as an
  unresolved gate; explicitly refuses token extraction / impersonation.
- Sefirah / mdgspace / KDE Connect — own-protocol apps, not MS interop.

The two paths:
1. **QR / `cpsi` pairing** — the cloud PinSession from the first-party pairing
   proxy (the `/dl?...cpsi=` link). Needs the MSA device token / device cert.
   **Hard-gated; not reproducible client-side.** (This is the wall we kept hitting.)
2. **Account device-to-device** — both ends signed into the *same* MSA; the
   client signs in via **device-code**, generates its **own** device key pair,
   and **registers into the DDS device graph** (the
   `continuum.dds.microsoft.com/.../Devices` endpoint we saw live) under an
   `AccountPairingD2D`-type `CryptoTrustRelationship` (the trust types we
   documented). **Open enough that LinkMyPhone's clipboard + notifications work
   today** — no QR, no `cpsi`, no TPM.

Implication: the **feature layer (clipboard, notifications, likely messages/
contacts) is reachable on Mac via path 2** — device-code sign-in + DDS
registration + Hub Relay — which is what we should build. **Screen mirroring +
QR pairing stay the hard part** (mirroring rides the Nano ICE/STUN/TURN
transport; QR/`cpsi` stays gated).

**Clean-room gate — RESOLVED (no-go for a clean client).** The question was
which **client id** the device-code flow presents. Answer, from the Android app
+ LinkMyPhone's own docs:
- The flow authenticates with the **first-party Phone Link MSA client id** (a
  fixed GUID shipped in the APK; the *same* id appears in our live DCG trace
  next to `DCG.ReadWrite_TOKEN_BROKER`). Not recorded verbatim here, by our own
  "no first-party client ids" rule.
- LinkMyPhone works by **presenting that first-party id** — i.e. **impersonating
  the Phone Link app.** Its docs call the device-code path "an interoperability
  experiment, not a source-confirmed replacement," and note there's no evidence
  a *user-registered* client id is accepted by DCG (consistent with our earlier
  `AADSTS65001`).
- **Correction to the TPM assumption:** DCG device trust is a **self-signed**
  device cert via `EnrollDevice` (trust identity `SelfSigned`), **not** the
  TPM/`wlidsvc` cert. So the device cert is *not* the blocker — the **client id
  is.**

Net: the account/device-code path is technically real but only functions by
embedding Microsoft's first-party client id = impersonation, which this project
will not do. The clean ceiling is unchanged: everything up to the first-party
client-id gate is buildable; the auth itself is not reproducible by a
non-impersonating third-party client. Options are (1) ship clean up to the wall,
(2) impersonate (out of scope for this repo), or (3) run real Windows in a VM.
