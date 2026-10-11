# Phone Link / Link to Windows — Architecture & Protocol Analysis

Interoperability notes for building a native macOS client. Derived from static analysis of:

- **Windows:** `Microsoft.YourPhone` 1.26082.117.0 (arm64 MSIX) — `PhoneExperienceHost.exe` + `YourPhoneAppProxy.exe`, .NET 10, WinUI/WPF.
- **Android:** `com.microsoft.appmanager` 1.26082.130.0 ("Link to Windows") — ships uncompiled `.proto` files under `/platform_sdk`, `/side_channel`, `/message`, `/phone_files`, etc. and Dalvik bytecode (`classes*.dex`).

> The single most important finding for a Mac client: **Phone Link is not a LAN/peer-to-peer app by default.** The baseline transport is a **cloud relay** (Microsoft "Device Connectivity Gateway", `dcg.microsoft.com`) carried over **SignalR**. Direct Wi-Fi only comes into play for high-bandwidth scenarios (app/screen streaming) via a secondary "**Nano**" transport. There is **no mDNS/Bonjour/SSDP** local discovery in this protocol.

---

## 1. Shared protocol namespace ("YPP" = Your Phone Protocol)

Both ends implement the same protocol under mirrored namespaces — this is the key to interop:

| Concept | Android (Java/Kotlin) | Windows (.NET) |
|---|---|---|
| Protocol root | `com.microsoft.mmx.agents.ypp.*` | `YourPhone.YPP.*` (`YourPhone.YPP.dll`, `.PlatformSdk.dll`, `.SideChannel.dll`, `.Auth.dll`, `.Bluetooth.dll`, `.PushNotifications.dll`) |
| Wire format | Google Protobuf (`.proto` files present) | `Google.Protobuf.dll`, generated `YourPhone.*.Protocol.dll` |
| Relay transport | `...ypp.signalr.transport.*` | `Microsoft.AspNetCore.SignalR.Client.dll` |
| Direct transport | `...ypp.nano.transport.*` | `msquic.dll` + `DotNetty.*` (QUIC/pipeline) |
| Serialization helper | protobuf + MessagePack | `MessagePack.dll`, `Google.Protobuf.dll` |

The `.proto` files set both `java_package = com.microsoft.mmx.agents.ypp.*` and `csharp_namespace = YourPhone.YPP.*`, confirming the two apps are generated from one schema. **Re-generating clients from these `.proto` files is the recommended starting point.**

---

## 2. Device registration & "discovery"

There is **no local network discovery**. Pairing and reconnection are brokered through the cloud:

1. **Initial pairing** is out-of-band: the PC shows a **QR code** (`SharedUtilities.QrCodeGenerator.dll` on Windows); the phone scans it to bootstrap the pairing material. Both sides then **register** with the cloud.
2. **Registration** (Android): `com.microsoft.mmx.agents.ypp.registration.RegistrationManager`, `registration.scheduling.RegistrationWorker/RegistrationScheduler`, `devicemanagement.DeviceManagementManager`, `DeviceMetadataProvider/DeviceMetadataCacheRepository`. Re-registration is triggered by `FcmTokenChangeRegistrationTrigger` and `LTWStatusChangeRegistrationTrigger`.
3. **Reconnect / "discovery"** is push-driven, not broadcast-driven:
   - **Android inbound push:** `com.microsoft.appmanager.extfcm.push.AppFcmListenerService` (Firebase Cloud Messaging) and `exthns.push` (HNS — Microsoft push for non-Google devices). Message type `FcmPushNotificationMessage` / `HnsPushNotificationMessage`.
   - **Wake/dispatch:** `...ypp.wake.DispatcherClient` / `IDispatcherClient`, `PushNotificationProcessor`, `PushNanoConnectionManager`. Wake payloads: `OpenConnectionWakeParams`, `DurableConnectionWakeParams`, `CryptoTrustWakeParams`, `CryptoSilentPairingWakeParams`.
   - **Windows inbound push:** `Microsoft.Windows.PushNotifications.Projection.dll` (WNS) + `YourPhone.YPP.PushNotifications.dll`.
4. **Bluetooth side channel** (`...ypp.wake.bluetooth.*`, `YourPhone.YPP.Bluetooth.dll`, `Microsoft.Internal.Bluetooth.*`): a BLE link used to **wake** the peer and to negotiate instant-hotspot before the main transport is up. See `side_channel/v1/*.proto`.

**Implication for Mac:** you cannot find the PC by scanning the LAN. You must (a) complete MSA-based registration against the same cloud, and (b) either receive a cloud push or open the relay connection yourself.

---

## 3. Authentication & trust model (two layers)

### Layer A — Microsoft Account (MSA / AAD)
- OAuth endpoints seen in bytecode: `login.live.com/oauth20_{authorize,token,desktop}.srf`, `login.microsoftonline.com/common`, sovereign-cloud variants (US gov, DE, CN, etc.).
- Resource/scope: **`https://dcg.microsoft.com/DCG.ReadWrite`** (and `-df`/`-beta` rings) — this is the token audience for the Device Connectivity Gateway.
- Token broker artifacts: **`PRT.proto`** (`com.microsoft.identity.broker.prt` — Primary Refresh Token: `refreshToken`, `idToken`, `homeAuthority`, `isRegisteredDevicePrt`, `deviceId`) and **`TransferToken.proto`** (broker token transfer).

### Layer B — device-to-device crypto trust (the important one for interop)
Independent of MSA, the two devices establish a **mutual cryptographic trust** with per-device key pairs and certificates:

- Android: `...ypp.authclient.crypto.ICryptoManager`, `JwtHelper`; `...authclient.trust.{ITrustManager, CryptoTrustManager, CryptoTrustCertChainManager, ICryptoTrustRelationshipRepository}`; `...authclient.trust.accountsecret.IAccountSecretManager`; `...deviceauthenticationproxy.IDeviceAuthProxyClient`.
- **Pairing proxy** issues/validates device certs: `...ypp.pairingproxyclient.service.PairingProxyServiceClient`, `pairingproxyclient.auth.PairingProxyCertificateValidator`. Windows mirror: `YourPhone.YPP.Auth.dll`.
- **Message authorization** rides as a signed JWT: `side_channel/v1/authorization.proto → SideChannelAuthorization { signed_jwt_payload }`. Validation: `...authclient.auth.IAuthPairingValidation`.
- **A2D ("app-to-device") trust** refresh scheduling: `authclient.trust.scheduling.RefreshA2DTrustScheduler`.

### Credential persistence
- **Android:** MSAL/identity broker cache (`com.microsoft.authentication.storage.Cache`), Android `SharedPreferences` for trust repositories, device keys in the **Android Keystore** (WolfSSL/`wolfcrypt` present).
- **Windows:** standard for this stack is **DPAPI** (`System.Security.Cryptography.ProtectedData.dll` is shipped) and MSAL token cache; device/trust state under the packaged app's `LocalState`. (Exact file layout not in the manifest — confirm at runtime under `%LocalAppData%\Packages\Microsoft.YourPhone_8wekyb3d8bbwe\`.)

---

## 4. Transports

### 4a. Primary: SignalR over the Device Connectivity Gateway (cloud relay)
- Android: `...ypp.signalr.transport.connection.{SignalRConnectionManager, SignalRConfiguration}`, `SignalRPlatformConnection`, `MessageReceiver`, `SignalRUserSessionTracker`, built on `com.microsoft.signalr.HubConnection`.
- Windows: `Microsoft.AspNetCore.SignalR.Client.dll` (+ `Http.Connections.Client`, MessagePack & JSON hub protocols).
- Endpoints: `https://dcg.microsoft.com/` (rings: `dcg-df`, `dcg-beta`; download/relay host `dl.dcg.microsoft.com`).
- **Framing:** application messages are **DCG packets**, chunked/reassembled by a fragment layer:
  - `...ypp.transport.protocol.{DCGPacketProcessor, DCGMessage, DCGFragmentMessage, DCGAckMessage}`
  - `...ypp.transport.chunking.IFragmentSenderTransport`, `transport.messaging.{IOutgoingMessageClient, IIncomingMessageClient, IdManager}`
  - Reliability: per-transport **circuit breakers** (`SignalRMessageSenderCircuitBreakerManager`, `NanoMessageSenderCircuitBreakerManager`) and `TransportMetricsTracker`.

So the default data path is: **phone ⇄ DCG cloud ⇄ PC**, each side holding an authenticated SignalR hub connection; payloads are protobuf, fragmented into DCG messages, ack'd end-to-end, and signed with the device-trust JWT.

### 4b. Secondary: "Nano" direct transport (local, high-bandwidth)
- Android: `...ypp.nano.transport.{NanoFragmentTransport, NanoTransportModule, NanoMessageSenderCircuitBreakerManager, NanoTransportTelemetry}`; capability negotiated via `PROTO_PLATFORM_CAPABILITIES_NANO_TRANSPORT_PREFERENCE` and `nano_transport_preference_version` (see `session_validation.proto`).
- Windows: `LibNanoAPI.dll` + `LibNanoAPI.winmd` (WinRT projection), `NativeHostNE.dll`, **`msquic.dll`** (QUIC), `DotNetty.*` (byte-pipeline). `WindowsUdk.dll`.
- Connection setup is **push-initiated** (`PushNanoConnectionManager`, `observePushNanoConnectionChanges`, `reestablishPushNanoConnectionAsync`) and can run over **Wi-Fi Direct** or a shared network.
- Used for: screen/app mirroring, app streaming (`YourPhone.ScreenMirroring.Managed*`, `phone_mirroring/v1/app_remoting_message.proto`), and large transfers.

### 4c. Wi-Fi Direct / Instant Hotspot
- Android: `...ypp.wifidirect.{WifiRadioAdapter, IWifiRadioAdapter, SelectMessage/SelectResponseMessage, CancelMessage/CancelResponseMessage}`, `WifiP2pConnectionManagerInternal` (uses `android.net.wifi.p2p.WifiP2pInfo/WifiP2pGroup` and a `java.nio.channels.DatagramChannel`).
- Negotiated/credentialed through the **Bluetooth side channel**: `side_channel/v1/{hotspot.proto, main.proto}` — `SideChannelHotspotRequest`, `SideChannelInstantHotspotRequest`, encrypted response variants; `hotspot/v1/{configuration,credentials,hotspot}.proto`.

### 4d. Local TLS listener (the actual socket)
When a direct socket is used, it is wrapped in **mutual TLS via WolfSSL** (not plain sockets):
- `com.wolfssl.*` / `wolfcrypt` present; log strings: `createServerSocket(port: …)`, `creating new WolfSSLServerSocket(port: …)`, `setNeedClientAuth(need: …)`, `setWantClientAuth`, `Pinned certificates for …`.
- **Mutual auth + certificate pinning** using the device-trust certs from §3B. There is no fixed well-known port in the strings — the listener port is negotiated/assigned at connection time, not a constant.

---

## 5. Feature channels (protobuf schemas you can regenerate)

Each capability is its own versioned proto package carried as a DCG/Nano payload:

| Feature | `.proto` (Android) |
|---|---|
| Messaging / SMS | `message/v1/message.proto` |
| Notifications (mirroring) | `notification/v1/notification.proto` |
| Contacts | `contacts/v1/contact.proto` |
| Clipboard sync | `clipboard/v1/clipboard.proto` |
| Phone/device status, wallpaper | `device_info/v1/{status,wallpaper}.proto` |
| Photos / file browse | `phone_files/v1/{sync,get,metadata,streams_response,delete,update,status,batch_token}.proto` |
| File/photo transfer | `file_transfer/v1/{get,session_info,transfer_info}.proto` |
| Installed apps / launch | `phoneapps/v1/phoneapps.proto` |
| App streaming / remoting | `phone_mirroring/v1/{app_remoting_message,nearby_message,permissions_message,workflow_launcher_message,early_launch_message}.proto` |
| Continuity (resume) | `continuity/v1/continuity.proto` |
| Ring my phone | `ring_my_phone/v1/update.proto` |
| Hotspot | `hotspot/v1/*.proto` |
| Remote control (input) | `remote_control/v1/control_message.proto` |
| Sync envelope / metadata | `sync/v1/{sync_publish,metadata}.proto` |

**Platform SDK envelope** (how channels multiplex): `platform_sdk/v1/*.proto`
- `platform_message.proto`, `platform_channel.proto` (channel types: named-streams, video-streaming, blob, input-source, audio-target, app-remote…), `pub_sub_payload.proto`, `dcg_{base,fragment,ack}_message.proto`, `capabilities_manifest.proto`, `manifest.proto`, `session_validation.proto`, `channel_validation.proto`, `context_source.proto`, `device_resource_manager.proto`, `msaep_message.proto`.

---

## 6. Windows-side process & IPC model (for completeness / behavioral reference)

- **`PhoneExperienceHost.exe`** — main WinUI app (`AppxManifest` `Application Id="App"`, `EntryPoint=Windows.FullTrustApplication`). Also hosts COM servers via args `-ComServer:AppProxy|Background|Widgets|DelegateExecute`.
- **`YourPhoneAppProxy.exe` / `YourPhoneAppProxyHost.exe`** — `windows.hostRuntime` extensions (`packagedClassicApp`, mediumIL). These bridge to the UWP/WinRT surface.
- **Local IPC = COM**, not named pipes: `windows.comServer` CLSIDs (AppProxy `46F7D930-7697-4072-AC90-0E5D68D768AE`, Background `283EDD52-…`, Widgets `54347DF9-…`). Proxy/stub `YourPhone.Contracts.AppProxyConnection.ProxyStub.dll`, interface **`IAppProxyConnector`** (`EFC72204-DFB1-459A-B979-BE9927D795BF`), `IAppProxyConnectorClient`, `SendMessageToAppProxyEventHandler`, `IPointerUpdate`.
- **Background tasks:** `YourPhone.Background.Tasks.{BackgroundTask, UpdateTask, PreInstalledConfigTask}`; manifest `systemEvent`/`timer`/`bluetooth`/`phoneCall` triggers.
- **Capabilities** worth noting: `phoneCall`, `phoneCallSystem`, `phoneLineTransportManagement`, `contacts`, `bluetooth`, `radios`, `packageManagement`, plus custom `coreAppActivation` / `unsignedPackageManagement`.
- **Protocol activations:** `ms-phone:`, `tel:`, `sms:`.

> None of the COM/IPC detail is needed to interoperate from a Mac — it is purely internal to the Windows host. The Mac client should target the **YPP protobuf + SignalR(DCG) / Nano** surface, not COM.

---

## 7. Practical path for a macOS client

1. **Regenerate protobuf models** from the `.proto` set in the APK (`protoc --swift_out` or your language of choice). These are the authoritative message contracts.
2. **Implement MSA auth** (OAuth to `login.microsoftonline.com` / `login.live.com`) and acquire a token for audience `dcg.microsoft.com/DCG.ReadWrite`. Expect a device-registration + PRT step (`PRT.proto`).
3. **Establish the device-trust layer**: generate a device key pair, run the pairing-proxy cert flow, and be prepared to present a client cert for **mutual TLS** and to sign per-message JWTs (`SideChannelAuthorization`).
4. **Connect to DCG via SignalR** (ASP.NET Core SignalR protocol; MessagePack or JSON hub protocol). Implement the **DCG fragment/ack** layer (`dcg_*_message.proto`) and per-channel multiplexing (`platform_channel`/`platform_message`).
5. Start with **relay-only** (clipboard, notifications, messages, contacts — low bandwidth). Treat **Nano/QUIC + Wi-Fi Direct** (streaming) as a later phase; it needs the side-channel/hotspot negotiation and QUIC.
6. There is **no LAN discovery to implement** — rely on cloud registration + push, or open the relay connection directly.

### Legal / scope note
This is clean-room-style interoperability analysis from artifacts on your own machine. Microsoft's cloud endpoints (`dcg.microsoft.com`, MSA) enforce their own auth, rate limits, and Terms of Use; a third-party client will still be subject to those server-side controls, and some flows (device attestation, Play Integrity / `IntegrityTokenProvider`, Windows-specific device registration) may not be reproducible off-platform. Validate each assumption against live traffic before committing to an implementation.
