# mac-phone-link — roadmap

What's done, what's left, and what's blocked. Honest about the ceiling: almost
everything on the Mac side is buildable, but completing a live phone link ends
at a **Microsoft first-party-gated cloud boundary** (pairing proxy + DCG) that
static reverse-engineering cannot open. See `docs/FINDINGS.md` for the evidence.

## Legend
- ✅ done · ⚠️ scaffolded (builds, needs live bring-up) · 🚧 blocked (first-party) · ⬜ not started

---

## Done (✅)
- Clean-room protos (36) incl. mirroring input, auth, DCG framing.
- DCG auth (MSAL) + device-trust JWT + DRS nonce/discovery.
- DCG transport: framing, SignalR channel, `DCGSession`, side-channel auth.
- VideoToolbox decode (`VTVideoDecoder`) + `AVSampleBufferDisplayLayer`.
- `.app` packaging (framework-embed, ad-hoc sign) + CI artifact on every PR +
  Releases on `v*` tags + Developer-ID/notarize path (needs secrets).
- Microsoft sign-in wired (own Entra client id) + "skip for now".
- Pairing module: confirmed QR grammar + proxy endpoints + ceremony order.
- Nano/QUIC transport (framing, handshake, loopback) + UI Connect action.
- Screen-mirror UI with **cursor/keyboard control** (letterbox-mapped, coalesced).
- Clipboard sync (NSPasteboard ↔ proto, both directions).
- Notifications decode into the list.
- **Feature channel backbone** (`FeatureHub`/`FeatureTransport`/`FeatureHandler`):
  routes payloads by handler-type over any byte channel; loopback for tests.
- **Messaging** send (`MessagingClient` + Messages tab) over the feature channel.
- **Contacts** search (`ContactsClient`) over the feature channel.
- **Clipboard as a live handler** (`ClipboardSync: FeatureHandler`).
- **H.264 SPS parse** → real video dimensions feed the cursor mapping.
- **QUIC cert pinning** (`pinnedCertificateSHA256`, SHA-256 leaf match).

---

## Phase 1 — feature breadth on the Mac side (⚠️/⬜, no first-party dependency)
These need only a live byte channel (the Nano/DCG transport) to attach to; the
logic is buildable and testable now.

1. **Attach clipboard to a live channel** (✅) — `ClipboardSync` is a
   `FeatureHandler`; `FeatureHub` wires its `send`/`handleIncoming` to the
   transport. Still needs a real transport attached via `FeaturesViewModel.attach`.
2. **Notification actions** (⬜) — dismiss / mute / inline reply. Extend
   `ConnectionViewModel` + a notification request message; UI buttons per item.
   (Needs a proto op beyond `.get` — the one Phase-1 item still fully open.)
3. **Messaging (SMS/RCS)** (⚠️) — send is done (`MessagingClient` + Messages tab);
   thread list + message history still to add once a live channel feeds inbound.
4. **Contacts** (⚠️) — search is done (`ContactsClient`); bulk sync + lookup
   wiring into the message/call UIs still to add.
5. **Phone files / photos** (⬜) — `maclink.files.v1`: browse, thumbnail, pull.
6. **Richer input** (⬜) — drag-and-drop (protos exist: `Drag*Message`),
   two-finger gestures, full key map, `BringToForeground` / `LaunchApp`.
7. **Audio** (⬜) — `AudioStreamReadyMessage` / `VolumeMessage`; decode + play
   the mirror's audio alongside video.

## Phase 2 — Nano transport live bring-up (⚠️)
Make the direct path actually carry media once a peer exists.
1. **Frame container** — SPS parse now sets `videoSize` (✅); still confirm
   Annex B vs AVCC and PPS/VPS signaling against real bytes from a peer.
2. **Transport primitive** — CORRECTED: the media path is **ICE/STUN/TURN +
   pseudo-TLS** (WebRTC-style), **not QUIC** (✅ confirmed, FINDINGS). Our
   `QUICNanoConnection` is the wrong primitive; a faithful client needs an ICE
   agent + STUN/TURN + the pseudo-TLS handshake. Multi-stream confirmed — one
   Connect multiplexes typed channels (video/audio/input/message/blob, modeled in
   `NanoChannel`, ✅). `msquic` is likely the cloud/relay (HTTP/3) leg. Exact
   STUN/pseudo-TLS/handshake-packet bytes still need native disasm or live capture.
3. **Handshake on the wire** — drive `NanoHandshake` (context_source) end to end;
   confirm message framing (netty codec) of the pairing-channel ceremony.
4. **Transport negotiation** — confirmed there is a `hotspotSideChannelService`
   plus BLE wake (MSAEP) in the YPP layer (✅, FINDINGS). Wi-Fi Direct / instant-hotspot selection via the
   side channel (`hotspot`/`wake` protos) before opening QUIC.

## Phase 3 — hardening / distribution (⬜, one has a cost)
1. **Developer ID signing + notarization** — set CI secrets (`MACOS_CERTIFICATE*`,
   `MACOS_SIGN_IDENTITY`, `AC_API_KEY_*`); needs a paid Apple Developer account.
   Removes the Gatekeeper "damaged" prompt and lets MSAL's keychain cache persist.
2. **Universal binary** — `--arch arm64 --arch x86_64` (needs full Xcode on CI).
3. **Settings UI** — Entra client id, environment (prod/df/beta), codec choice.

---

## Blocked — the first-party wall (🚧, not solvable client-side)
Documented so no one burns time here expecting a code fix:
1. **Completing a pair** — the QR must carry a Microsoft-minted `uaid` + a cloud
   `cpsi` (PinSession); creating that session requires the pairing proxy to trust
   the caller, and it is gated to first-party identities. Our structurally-valid
   QR is accepted as a URL but not as a pairing link. (`docs/FINDINGS.md` §QR.)
2. **DCG resource consent** — `dcg.microsoft.com/DCG.ReadWrite` is first-party
   protected; a user Entra app is expected to be refused (`AADSTS65001`).
3. **Device-trust cert issuance** — we can sign a device-trust JWT, but the cert
   itself is issued during the (gated) pairing-proxy enrollment.

Only two things could move these: Microsoft permitting third-party clients, or a
live-traffic study on a paired device (out of scope for static RE). The concrete
capture plan for that study — what to collect, how to redact it, and which item
each piece unblocks — is in `docs/EVIDENCE_PLAN.md`. Everything in Phases 1–3 is
worth doing regardless; it makes the client complete up to the wall.

---

## Suggested order
Phase 1.1 (clipboard live) → 1.2 (notification actions) → 1.3 (messaging) →
Phase 2.1 (frame container) in parallel when a peer is available → Phase 3.1
(signing) when a Developer ID exists. Each is independent; none unblocks the
first-party wall, which stays a research question.
