<#
    phonelink-trace.ps1 — one-click Phone Link pairing trace.

    Run it (as Administrator), do the pairing, press Enter. It then stops the
    trace, decodes it, redacts secrets, and drops the files on your Desktop.

    Flow:
      start WPR  ->  (you pair)  ->  press Enter  ->  stop  ->  decode  ->
      redact  ->  Desktop\phonelink_trace\

    What you SHARE:  phonelink.filtered.redacted.txt  (small, keyword-filtered)
    What stays LOCAL: phonelink.etl / phonelink.xml (raw — may contain secrets)

    Secrets are stripped by the redaction pass (JWTs, bearer tokens, long base64,
    emails), but the raw .etl is NEVER redactable in place — keep it local.

    Usage:
      1. Right-click Start -> "Terminal (Admin)" / "PowerShell (Admin)".
      2. Run:  powershell -ExecutionPolicy Bypass -File .\phonelink-trace.ps1
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$dest = Join-Path ([Environment]::GetFolderPath('Desktop')) 'phonelink_trace'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$etl = Join-Path $dest 'phonelink.etl'
$xml = Join-Path $dest 'phonelink.xml'
$red = Join-Path $dest 'phonelink.redacted.xml'
$flt = Join-Path $dest 'phonelink.filtered.redacted.txt'

function Redact([string[]]$lines) {
    $lines `
      -replace 'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9._-]+', '<JWT>' `
      -replace '(?i)(bearer )\S+', '$1<REDACTED>' `
      -replace '[A-Za-z0-9+/]{40,}={0,2}', '<B64>' `
      -replace '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '<EMAIL>'
}

try { wpr -cancel 2>$null } catch {}   # clear any stale session

Write-Host 'Starting WPR trace (General + Network + CPU)...' -ForegroundColor Cyan
wpr -start GeneralProfile -start Network -start CPU -filemode

Write-Host ''
Write-Host '>>> Do the pairing / repro NOW. <<<' -ForegroundColor Yellow
[void](Read-Host 'When finished, press Enter to STOP and process the trace')

Write-Host 'Stopping trace (can take a minute)...' -ForegroundColor Cyan
wpr -stop $etl

Write-Host 'Decoding to text (tracerpt)...' -ForegroundColor Cyan
# -y answers "overwrite?" yes. Large traces take a while and produce a big XML.
tracerpt $etl -o $xml -of XML -y | Out-Null

Write-Host 'Redacting...' -ForegroundColor Cyan
Redact (Get-Content $xml) | Set-Content $red -Encoding utf8

# Keyword-filtered, redacted, shareable slice.
$keywords = 'dcg|wlidsvc|LiveId|msa|token|nano|ice|stun|turn|pairing|ypp|signalr|' +
            'DeviceId|PUID|RST|PPCRL|MBI_SSL|appmanager|CDP|cross.?device'
Write-Host 'Building filtered shareable slice...' -ForegroundColor Cyan
$matched = Select-String -Path $red -Pattern $keywords -AllMatches | ForEach-Object { $_.Line }
Redact $matched | Set-Content $flt -Encoding utf8

Write-Host ''
Write-Host '===== DONE =====' -ForegroundColor Green
Write-Host "SHARE this:  $flt" -ForegroundColor Green
Write-Host "Full redacted (check before sharing): $red"
Write-Host "RAW (keep local, may contain secrets): $etl" -ForegroundColor DarkYellow
Write-Host ''
Write-Host 'Tip: if tracerpt produced little useful text, the richer data is in the'
Write-Host '.etl — open it in Windows Performance Analyzer (wpa.exe) instead.'
