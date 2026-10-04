# handoff.md — living state

> Update this after any big implementation step and before compaction, so the
> next session loses nothing crucial. Newest status at top.

## 2026-10-04 — Seamless-UX pass + claude/ folder

**Branch:** `ccr-151fd929-grpp95` · **PR:** JObersi10/mac-phone-link#1 (draft)

### Done
- Two-plane scaffold committed (display: scrcpy over adb + VideoToolbox;
  companion: KDE Connect protocol). ~2k LOC Swift, SwiftPM, CI on macos-latest.
- Protocol unit tests for control-message byte layout and KDE Connect packets.
- This pass added:
  - `claude/claude.md` + `claude/handoff.md` (this file), and a root `CLAUDE.md`
    pointer so guidance auto-loads.
  - `RESIZE_DISPLAY` control message (`ScrcpyProtocol`) + test.
  - Mirror-window **aspect-ratio toggle button** (native phone ratio ↔ 16:9),
    live via `window.contentAspectRatio` (client-side, always works) and, for
    virtual-display sessions, a device-side RESIZE_DISPLAY send (needs scrcpy
    ≥ 4.0 to actually relayout).
  - `NowPlayingBridge` (`PhoneLink`, MediaPlayer framework): publishes phone
    media to macOS Control Center and routes remote commands back to the phone.
  - Notification → open-app-mirror hook (clicking a companion notification asks
    AppController to open a per-app mirror window).
  - Docs updated (FEATURES, ROADMAP, ARCHITECTURE) + libraries recorded in
    claude.md.

### Not done / still true from before
- **Never compiled on macOS.** CI is the first real build; expect errors.
- Companion **encrypted transport** (mDNS + TLS pairing on :1716) not
  implemented. Until it is, `companion` is nil, Now Playing has no data source,
  notifications don't arrive, and companion menu items show a setup notice.
- On-device validation of the whole streaming path still pending.

### Next steps (in order)
1. Get CI green — fix whatever the macos-latest build surfaces first.
2. Milestone 1 (docs/ROADMAP.md): first on-device mirror; verify scrcpy 3.1
   handshake/video framing against a real device.
3. Milestone 3: companion transport — this unlocks notifications, Now Playing,
   ring, battery all at once.

### Open decisions
- **Bump scrcpy pin to 4.x?** The aspect-ratio button's *live device resize* and
  resizable virtual displays need scrcpy ≥ 4.0. Core control-message layouts are
  largely stable 3.x→4.x, but re-verify before bumping. Recommendation: bump at
  Milestone 2 and re-run the protocol tests. Until then the button does
  client-side framing only.
- appName→package resolution for notification→mirror: KDE Connect notifications
  carry `appName`, not the Android package. Need a lookup (e.g.
  `adb shell pm list packages` + label match, or a user-editable map). Hook is in
  place; resolution is a TODO.

### Known risks / gotchas
- `NWEndpoint.Host(host)` with a String variable — verify it compiles (vs. a
  string-literal-only init). One-line fix if CI complains.
- VideoToolbox async decode: block buffers must OWN their memory (fixed in
  `H264Decoder.decodeAVCC` — copies into an assured block buffer).
- `MPNowPlayingInfoCenter` from an `LSUIElement` accessory app: verify it still
  registers as a Now Playing source on macOS.
