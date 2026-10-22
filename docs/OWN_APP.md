# Own-protocol app — the no-wall alternative

A direct Mac↔Android link using **our own protocol**, informed by the Phone Link
RE but with **no Microsoft account, no cloud, no pairing proxy, no first-party
wall**. Not KDE Connect — our own, reusing the Mac engine we already built.

## Why this is the pragmatic path
The Microsoft interop is blocked only at the *identity* layer (device cert +
first-party client id). Everything *downstream* of that — decode, transport,
input, features — we already built on the Mac side. An own-protocol app keeps
all of it and replaces the gated identity layer with a trivial local pairing.

## What transfers (already built on Mac)
- `PhoneLinkVideo` / `VTVideoDecoder` — H.264 decode (phone encodes `video/avc`,
  confirmed in RE; Qualcomm `c2.qti.avc.encoder`).
- `NanoTransport` — ICE/STUN core (optional, for cross-network later).
- Mirroring UI + letterbox-mapped cursor/keyboard input.
- `FeatureHub` / feature handlers — clipboard, messaging, contacts.
- The `capability_*` set from the RE as our feature checklist: mirroring, audio,
  clipboard, notifications, input inject, files, camera.

## Architecture (own protocol)
- **Discovery:** Bonjour/mDNS (`_maclink._tcp`) on the local network.
- **Pairing:** local QR or 6-digit PIN that carries a public key; both sides
  pin each other's key (TOFU). No account, no server.
- **Transport:** direct TLS over TCP on the LAN (Network.framework `NWListener`/
  `NWConnection`). Our ICE/STUN core is the upgrade path for different networks.
- **Channels:** one connection, typed channels (mirror/input/clip/notif/files) —
  same multiplexing idea the Nano transport uses, modeled in `NanoChannel`.
- **Codec:** H.264 Annex B from the phone → `VTVideoDecoder` (as-is).

## Android app (the new build, Kotlin)
Normal-permission features (no root):
- **Mirroring:** `MediaProjection` + `MediaCodec` AVC encoder → stream.
- **Notifications:** `NotificationListenerService` → forward + actions.
- **Clipboard:** `ClipboardManager` (note: Android 10+ throttles background reads).
- **Files/photos:** `MediaStore` browse/pull.
- **Camera:** `Camera2` → H.264 → Mac CMIO virtual camera (stretch).

Elevated features (need Accessibility service, or Shizuku/adb):
- **Input injection** into the phone from the Mac (same constraint scrcpy has).
  Milestone 1 ships **view-only**; input is a later milestone.

## Milestones
1. **M1 — pair + mirror (view) + clipboard.** Bonjour + TLS socket on Mac
   (new `LANTransport`), QR/PIN pairing, Android `MediaProjection`→AVC→Mac
   decoder, clipboard both ways. Reuses the decoder/UI/feature hub.
2. **M2 — notifications** (Android `NotificationListenerService` → Mac list +
   actions).
3. **M3 — input injection** (Accessibility/Shizuku) → the existing cursor/
   keyboard mapping drives the phone.
4. **M4 — files/photos**, then **camera → CMIO virtual camera**.

## What stays, what's parked
- **Parked (not deleted):** the Microsoft interop track (`DCGAuth`,
  `DDSDeviceRegistration`, `YPPEnvelope`, Nano). The wiring step is deferred per
  request; it stays in the repo as the "if MS ever opens a 3rd-party id" path.
- **New:** `android/` Kotlin app + a Mac `LANTransport` + a small own-protocol
  spec. The own protocol is documented here and will get a wire spec doc.
