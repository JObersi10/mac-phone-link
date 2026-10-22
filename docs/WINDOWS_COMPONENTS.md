# Windows Phone Link — component map & connection flow

Which shipped Windows components own each part of the link, how they connect,
and how each maps to our Mac modules. Built from the `YourPhone.Package`
managed assemblies + `LibNanoAPI` native, and our live captures. This documents
**roles and data flow** (clean-room facts) — it does not carry Microsoft's
first-party client id or any credential.

## The identity boundary (read first)
`YourPhone.YPP.Auth.dll` is the single component that carries the **first-party
client identity**. A clean interop client replicates its *protocol* with a
**caller-supplied client id** — it never hardcodes Microsoft's. That one value
is the whole difference between "interoperating" and "impersonating the app",
so our code keeps it a required runtime input (see `DCGAuth`).

## Components by role

### Identity / auth
- **`YourPhone.YPP.Auth.dll`** — `DcgAuthManager`, `AuthServiceCryptoHelper`.
  MSA token acquisition (device-code / WAM broker), **device enrollment with a
  self-signed device cert** (`EnrollDevice`, trust identity `SelfSigned` — NOT a
  TPM/`wlidsvc` cert), device-trust JWT signing (ECDSA P-384 / SHA-384), JWE
  (RSA-OAEP + A256CBC-HS512). Requests the broker scope
  `service::msatoken.dcg.microsoft.com::MBI_SSL` (+ `DCG.ReadWrite`/`.SAPI`).
  **This is the component whose client id gates everything.**
- **`Microsoft.Security.Authentication.OAuth.Projection.dll`** — OAuth primitives.
- **`YourPhone.YPP.Onboarding.dll`** — first-run / pairing orchestration (QR for
  the `cpsi` path; consent; enrollment sequencing).

### Device graph / REST
- **`YourPhone.YPP.Kiota.dll`** — Kiota-generated REST client for DDS/DCG; the
  device registration into the Continuum graph
  (`continuum.dds.microsoft.com/Command/user/Continuum/Devices`, seen live).

### Connectivity / feature relay
- **`YourPhone.Connectivity.YPP.Managed.dll`** + **`YourPhone.Contracts.Connectivity.YPP.dll`**
  — YPP connectivity + Hub Relay session.
- **`Microsoft.AspNetCore.SignalR.Client*.dll`** — SignalR transport to the Hub
  Relay (negotiate; JSON + MessagePack protocols).
- **`YourPhone.YPP.PlatformSdk.dll` / `.Protocol.dll`** — YPP platform SDK +
  message envelopes (`_requestId`/`_route`/contentType/remoteAppId/gzip).
- **`YourPhone.YPP.PushNotifications.dll`** — push / wake.
- **`YourPhone.YPP.SideChannel.dll` / `.Protocol.dll`** — BLE/hotspot side
  channel + MSAEP wake.
- **`YourPhone.Connectivity.Bluetooth.*`** — Bluetooth/RFCOMM bootstrap
  (matches the Android `rfcomm_server` finding).

### Media transport (mirroring + "phone as webcam")
- **`LibNanoAPI.dll` / `.winmd` / `.Projection.dll`** — Nano ICE/STUN/TURN +
  pseudo-TLS, typed channels (video/audio/input/message/blob). Confirmed P2P-LAN
  + Azure `:3478` TURN fallback on the wire.
- **`YourPhone.ScreenMirroring.Managed.dll` / `.Protocol.dll`** +
  **`YourPhone.Contracts.ScreenMirroring.dll`** — mirroring protocol (H.264
  `video/avc`, config, input); the camera feature reuses this path.
- **`msquic.dll` / `System.Net.Quic.dll`** — QUIC for the cloud/signaling leg
  only (not the media path).

## Connection flow (how they connect)
```
Onboarding ──▶ Auth (YPP.Auth)
                 device-code sign-in [client id]  ─▶ MSA broker ticket
                 (service::msatoken.dcg.microsoft.com::MBI_SSL)
                 EnrollDevice (self-signed cert) ─▶ device-trust JWT
                      │
                      ▼
            Kiota/DDS: register device into the Continuum graph
                      │
                      ▼
      Connectivity.YPP + SignalR ─▶ Hub Relay (authed by DCG token)
                      │                     feature msgs: clipboard,
                      │                     notifications, messages…
         SideChannel/Bluetooth ─▶ BLE/RFCOMM discovery + wake
                      │
                      ▼ (mirroring / webcam only)
            LibNanoAPI: ICE/STUN/TURN ─▶ typed channels ─▶ H.264 media
```

## Map to our Mac modules
| Windows component | Our module |
|---|---|
| `YourPhone.YPP.Auth` | `Sources/DCGAuth` (device-code + enroll; caller-supplied client id) |
| `YourPhone.YPP.Kiota` (DDS) | *to build* — DDS device-registration client |
| `Connectivity.YPP` + SignalR | *to build* — Hub Relay (SignalR) feature channel |
| `YourPhone.YPP.PlatformSdk.Protocol` | feature envelopes → `FeatureHub` |
| `LibNanoAPI` | `Sources/NanoTransport` (ICE/STUN core done; TURN client next) |
| `ScreenMirroring.Protocol` | mirroring protos + `VTVideoDecoder` |
| `Connectivity.Bluetooth` / `SideChannel` | *to build* — BLE/RFCOMM wake |
| `YourPhone.YPP.Onboarding` | `Sources/PhoneLinkPairing` + onboarding UI |

## Build order toward a working client
1. **Device-code auth** in `DCGAuth` (caller-supplied client id) → MSA broker
   ticket → self-signed `EnrollDevice` → device-trust JWT.
2. **DDS registration** (Kiota-equivalent REST) into the Continuum graph.
3. **Hub Relay** SignalR connection + feature envelopes → clipboard/notifications.
4. **Messages/contacts** over the feature channel.
5. **Nano TURN client** + mirroring/webcam (stretch).
