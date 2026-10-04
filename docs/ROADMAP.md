# Roadmap

Ordered roughly by dependency and impact. The protocol layers for both planes
are done; most remaining work is transport, rendering, and UX.

## Milestone 1 — First on-device mirror (display plane)
- [ ] Validate the scrcpy 3.1 handshake ordering against a real device; fix any
      off-by-one in the video header / socket order.
- [ ] Confirm `adb forward` + `tunnel_forward=true` path end to end.
- [ ] Verify VideoToolbox SPS/PPS ingestion and AVCC conversion decode real
      frames.
- [ ] Vendoring helper: a `make` target / script that downloads the pinned
      `scrcpy-server` into Application Support (checksum-verified).

## Milestone 2 — Per-app windows polish
- [ ] App picker that lists installed packages (`adb shell pm list packages`).
- [ ] Remember window size/DPI per app.
- [ ] Handle virtual-display rotation and resize (`RESIZE_DISPLAY`).

## Milestone 3 — Companion transport (unlocks notifications/media/ring/battery)
- [ ] mDNS discovery of `_kdeconnect._udp` on the LAN.
- [ ] TLS channel on port 1716 with the KDE Connect pairing/cert-pinning flow.
- [ ] Wire `CompanionClient` to the live transport; surface a real
      `companion` instance in `AppController`.
- [ ] Notification Center UI; media "now playing" card; battery in the menu bar.

## Milestone 4 — The real latency win
- [ ] Replace the CoreImage→CGImage render path with a `CAMetalLayer`
      zero-copy renderer drawing the decoded `CVPixelBuffer`'s IOSurface.
- [ ] Decouple decode/render with a small frame queue; drop late frames.
- [ ] Optional H.265/AV1 decode paths (codec id is already modeled).

## Milestone 5 — Input fidelity
- [ ] Full keyboard via scrcpy UHID messages (`UHID_CREATE`/`UHID_INPUT`).
- [ ] Right-click / multi-touch / pinch mapping.
- [ ] Clipboard two-way sync during mirroring.

## Milestone 6 — Distribution
- [ ] Developer ID signing + notarization in CI (gated on secrets).
- [ ] Sparkle (or similar) auto-update for the `.dmg`.

## Out of scope
- Anything that impersonates Microsoft's Link to Windows host or touches
  Microsoft/Samsung proprietary cloud APIs. See the README.
- Instant Hotspot and cloud "sync over mobile data" — no open equivalent.
