# capture/ — pairing/diagnostic capture scripts

One-click capture helpers for diagnosing a **fresh Phone Link ↔ Android pairing**.
Everything is **passive capture of your own authorized traffic/telemetry**, and
each script ends with a redaction pass (strips JWTs, bearer tokens, long base64,
emails). Share only the `*.redacted.*` outputs; keep raw captures local.

## PC side (Windows) — `phonelink-trace.ps1`
A WPR trace with one keystroke to finish.

1. Open **Terminal/PowerShell as Administrator**.
2. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\phonelink-trace.ps1
   ```
3. Do the pairing, then press **Enter**. It stops the trace, decodes it, redacts,
   and writes everything to `Desktop\phonelink_trace\`.

Outputs:
- `phonelink.filtered.redacted.txt` — **share this** (small, keyword-filtered).
- `phonelink.redacted.xml` — full redacted decode (check before sharing).
- `phonelink.etl` / `phonelink.xml` — raw; **keep local**, may contain secrets.

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
