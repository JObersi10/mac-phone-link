# capture/ — pairing/diagnostic capture scripts

One-click capture helpers for diagnosing a **fresh Phone Link ↔ Android pairing**.
Everything is **passive capture of your own authorized traffic/telemetry**, and
each script ends with a redaction pass (strips JWTs, bearer tokens, long base64,
emails). Share only the `*.redacted.*` outputs; keep raw captures local.

## Two legs, two tools
Phone Link has two separable layers, and **one capture tool does not see both**:
- **Auth / token-mint** (wlidsvc MSA ticket, DCG HTTP) → **ETW** (`phonelink-trace.ps1`).
- **Media transport** (ICE/STUN/TURN/pseudo-TLS) → **packet capture**
  (`phonelink-transport-pktmon.ps1`). ETW carries events, not packet payloads,
  so the transport bytes are invisible to the WPR trace.

> **Why the old capture was ~7 GB:** it used `GeneralProfile + CPU`, which records
> the *whole machine*. You cannot usefully carve "just Phone Link" back out of
> that afterwards. Re-capture with the **targeted** default instead (tens of MB).

## PC side — auth: `phonelink-trace.ps1` + `phonelink-auth.wprp`
A WPR trace with one keystroke to finish. **Defaults to a targeted profile** that
records only LiveId + WinHTTP/WinINet/WebIO.

1. Open **Terminal/PowerShell as Administrator**.
2. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\phonelink-trace.ps1
   ```
   (Add `-Mode Full` only if you deliberately need the old whole-system trace.)
3. Do the pairing, then press **Enter**. It stops the trace, decodes it, redacts,
   and writes everything to `Desktop\phonelink_trace\`.

Outputs:
- `phonelink.filtered.redacted.txt` — **share this** (small, keyword-filtered).
- `phonelink.redacted.xml` — full redacted decode (check before sharing).
- `phonelink.etl` / `phonelink.xml` — raw; **keep local**, may contain secrets.

## PC side — transport: `phonelink-transport-pktmon.ps1`
Captures the actual UDP/relay packets, scoped to the phone (and optional relay)
IP so the file stays small. Needs the phone's IP on the shared network.
```powershell
powershell -ExecutionPolicy Bypass -File .\phonelink-transport-pktmon.ps1 -PeerIp <phone-ip> [-RelayIp <relay-ip>]
```
Mirror for ~30–60 s, press **Enter**. Produces `Desktop\phonelink_transport\transport.pcapng`
for Wireshark. **Keep it local** — it contains media payload. Share only
paraphrased structure (ALPN, STUN attribute names, frame-type bytes).

## Phone side (Android) — `phonelink-logcat.sh`
Needs `adb` on PATH and USB debugging on.
```bash
./phonelink-logcat.sh
```
Do the pairing, press **Enter**. Share `phonelink_pairing_android.redacted.txt`.

## Best workflow
Start the phone capture, start the PC trace, note the time, scan the QR / add the
PC, let it finish, stop both. The two timelines line up for correlation.

> Redaction is best-effort. Skim the `*.redacted.*` file before sharing; if you
> see anything that looks like a secret the patterns missed, remove it.
