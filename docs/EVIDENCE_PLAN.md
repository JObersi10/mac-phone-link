# Evidence-collection plan — getting past the first-party wall

What to capture from a real, paired **Windows 11 + Android "Link to Windows"**
setup to unblock the items the Mac client can't finish by static RE alone, how to
redact each safely, and which blocked item it unblocks.

Everything here is **passive capture of your own authorized traffic/telemetry**.
Nothing decompiled or copied goes in git. Raw captures (`.etl`, `.pml`, `.pcapng`,
`.har`, `.log`, keylog files) **stay in a local evidence folder outside the repo**
— only sanitized, paraphrased *findings* land in `docs/FINDINGS.md`.

## Blocked items (from the roadmap)
1. **Complete a real pair** — QR needs a Microsoft-minted `uaid` + cloud `cpsi`
   (PinSession) from the Device Pairing Proxy; gated to first-party identities.
2. **DCG resource consent** — `dcg.microsoft.com/DCG.ReadWrite` → `AADSTS65001`.
3. **Device-trust cert issuance** — issued during the gated pairing enrollment.
4. **Nano live bring-up** — real ALPN, Annex B vs AVCC framing, `context_source`
   handshake on the wire.

## Ranking
Do the **ungated** capture first. #4 (QUIC/Nano wire capture) needs no fresh
pairing and no working Azure — it runs on devices already paired from a prior
session, so it is **the one you can do today**. The pairing-/auth-side items
(#1, #2, #3, #5, #6) are parked until an MSA/Entra path that DCG accepts exists;
they are documented so the work is ready when that unblocks.

---

### A. QUIC / Nano wire capture — post-pairing (unblocks roadmap #4) — DO FIRST
No fresh pairing required; use an already-paired PC+phone during an active
mirroring session.
- Capture: on the Windows box, log TLS 1.3 keys and capture the UDP flow, so the
  QUIC payload decrypts in Wireshark.
  - set `SSLKEYLOGFILE` to a local path **before** launching Phone Link
  - `tshark -i <iface> -w nano_capture.pcapng -f "udp"` during ~30–60 s of mirroring
- Yields: real **ALPN** string, **Annex B vs AVCC** (NAL start-code pattern vs
  4-byte length prefix, visible directly), and the `context_source` handshake
  byte layout.
- Redact: the keylog file decrypts the whole session — **never** let it leave the
  machine; delete right after. From the decrypted capture keep only protocol
  headers (ALPN, frame-type bytes, handshake fields); drop any payload that is
  personal content (clipboard text, notifications, SMS, video frames). Describe
  structure ("4-byte length prefix, no start codes → AVCC"), don't paste raw hex
  of real content.
- Clean-room risk: low for protocol facts; keep content bytes out entirely.

### B. AADSTS65001 error body from your own Entra app (unblocks #2) — free, 5 min
Only possible once you have *any* Entra app that can request `DCG.ReadWrite`.
- Capture: the full JSON error body (not a screenshot) from your auth library's
  debug output on the token request.
- Yields: whether the block is a pure first-party-audience restriction (expected)
  or something fixable on our side (wrong resource URI, missing grant, tenant
  policy). Worth doing before any proxy work.
- Redact: strip your own client secret / cert thumbprint; the `AADSTS` body
  itself is a generic consent-error schema and is safe.
- Clean-room risk: none.

### C. `wlidsvc` / Phone Link token-mint trace during a FRESH pairing (unblocks #2, #3)
Needs a from-scratch "Add a device" pairing event.
- Capture (Administrator, right before opening the pairing screen):
  - broad: `wpr -start GeneralProfile -start CPU -filemode` … pair … `wpr -stop …etl`
  - narrow: `logman create trace … -p "Microsoft-Windows-LiveId" … -ets` … pair … `logman stop … -ets`
  - decode locally: `tracerpt …etl -o …xml -of XML`
- Yields: the scope strings + audience `wlidsvc` requests (confirms
  `service::dds.microsoft.com::MBI_SSL_TOKEN_BROKER` etc.), and whether a device
  **cert** request happens in the same window (answers #3: existing device-token
  flow vs. a separate CSR/enrollment).
- Redact (with a script you review, not by eye — traces are large): `MBI_SSL*`
  token blobs → `<REDACTED_TOKEN>`; `puid=`/`cid=`/SIDs → `<REDACTED_ID>`; keep
  the pairing `ti=` GUID structure, redact values you can't attribute. Keep the
  `.etl`/`.xml` local; never commit even redacted.
- Clean-room risk: low — telemetry metadata, not source.

### D. Device-trust cert-issuance trace (Procmon, narrow) (unblocks #3)
- Capture: Procmon filtered to the Phone Link process + any cert-enrollment child,
  during the on-screen "pairing" step; watch for `Software\Microsoft\SystemCertificates`
  writes and `ncrypt.dll` / `crypt32.dll` calls. Export to CSV locally.
- Yields: the mechanism — cloud-CA-signed CSR during pairing vs. a client
  self-signed cert vouched for by a DCG attestation blob (very different client
  implementations).
- Redact: file/registry paths are fine (OS structure); grep for `Bearer`, `eyJ`,
  long base64 in any command lines and redact those.
- Clean-room risk: low.

### E. DCG + Pairing-Proxy HTTPS capture (unblocks #2; partial #1) — only if not pinned
Phone Link is largely Win32/WinHTTP, which usually respects the system cert store,
so a user-trusted root may let mitmproxy/Fiddler see these. The real pairing-proxy
hostname will already be visible in trace C.
- Capture: `mitmdump` limited to `dcg.microsoft.com` + the pairing-proxy host;
  export HAR for inspection.
- Yields: exact DCG resource/audience and the `AADSTS65001` body shape; the
  **shape** of a real `cpsi`-issuing response (field layout only — you still can't
  mint one without first-party auth).
- Redact (highest-risk capture — live tokens): blank every `Authorization`
  value, `Set-Cookie`/`Cookie`, and body `*_token` fields via a jq/python pass.
  Keep URL paths, query-param *names*, header *names*, status codes, JSON field
  *names*. Store no real token value anywhere, even locally.
- Clean-room risk: medium. This is normal TLS inspection of your own device, not
  a pinning bypass. **Time-box ~30 min**; if those specific calls are pinned, stop
  and fall back to the ETW evidence (C, D). Do **not** attempt to defeat pinning.

### F. Android-side logcat during pairing (partial #1, #5)
- Capture: `adb logcat -c` … scan QR … `adb logcat -d > …log`, pre-filtered to
  `phonelink|yourphone|dcg|pairing|nano`.
- Yields: the client-side rejection — does the app log the consent/audience error,
  or never reach it because a non-first-party QR is malformed upstream.
- Redact: strip `Bearer`, `access_token`, long base64, IMEI/serial strings, MSA
  emails.
- Clean-room risk: low.

### Z. Dead end — do not attempt
Breaking cert pinning on the DCG / pairing-proxy calls (if E shows they're pinned).
Diminishing returns and a different risk category than passive capture. Fall back
to ETW (C, D) for those paths — you get call shape + timing without the payload.

---

## Open questions (answer when you have hardware)
1. A spare MSA + phone you can fully unpair/re-pair? C and D need a **fresh**
   pairing event, not a steady state.
2. Does Phone Link's Win32 process respect a user-installed proxy CA, or does it
   pin? (Try B first; attempt E only if B's error body is ambiguous.)
3. Is your current paired setup already using the real Nano/QUIC mirroring path,
   or have you only run our own scaffolding? If you've never captured the real
   client's mirroring traffic, A is the top priority (as ranked).
4. Will you redact on the Windows box (PowerShell/Python there) or copy raw files
   to the Mac first? Determines the exact tool invocations.

## What stays out of git
Raw `.etl` / `.pml` / `.pcapng` / `.har` / `.log` / `SSLKEYLOGFILE`, any real
token/PUID/CID/SID/cert value, and any raw payload hex of personal content. Only
sanitized, paraphrased findings (endpoint names, scope strings, frame-structure
descriptions, field layouts) go into `docs/FINDINGS.md`.
