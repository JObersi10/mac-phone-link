<#
    phonelink-trace.ps1 — one-click Phone Link pairing / auth trace.

    Run it (as Administrator), do the pairing, press Enter. It then stops the
    trace, decodes it, redacts secrets, and drops the files on your Desktop.

    Flow:
      start WPR  ->  (you pair)  ->  press Enter  ->  stop  ->  decode  ->
      redact  ->  Desktop\phonelink_trace\

    -Mode Auth  (DEFAULT, recommended): targeted profile (phonelink-auth.wprp) —
                only LiveId + WinHTTP/WinINet/WebIO. This is the AUTH / token-mint
                leg. Output is TENS OF MB, not gigabytes.
    -Mode Full: the old whole-system GeneralProfile+Network+CPU. Records the
                entire machine -> multi-GB. Only use if the targeted profile
                missed something and you know you need system-wide context.

    NOTE: neither mode captures the Nano media transport bytes
    (ICE/STUN/TURN/pseudo-TLS). ETW carries events, not packet payloads.
    For that leg use capture\phonelink-transport-pktmon.ps1.

    What you SHARE:  phonelink.filtered.redacted.txt  (small, keyword-filtered)
    What stays LOCAL: phonelink.etl / phonelink.xml (raw — may contain secrets)

    Usage:
      1. Right-click Start -> "Terminal (Admin)" / "PowerShell (Admin)".
      2. Run:  powershell -ExecutionPolicy Bypass -File .\phonelink-trace.ps1
         or:   powershell -ExecutionPolicy Bypass -File .\phonelink-trace.ps1 -Mode Full
#>

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet('Auth', 'Full')]
    [string]$Mode = 'Auth'
)
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wprp = Join-Path $scriptDir 'phonelink-auth.wprp'

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

if ($Mode -eq 'Auth') {
    if (-not (Test-Path $wprp)) { throw "Missing profile: $wprp" }
    Write-Host "Starting TARGETED WPR trace (auth/token-mint + HTTP only)..." -ForegroundColor Cyan
    Write-Host "  profile: $wprp" -ForegroundColor DarkGray
    wpr -start "$wprp!PhoneLinkAuth.Verbose.File" -filemode
} else {
    Write-Host "Starting FULL WPR trace (General + Network + CPU) — this will be LARGE..." -ForegroundColor Yellow
    wpr -start GeneralProfile -start Network -start CPU -filemode
}

Write-Host ''
Write-Host '>>> Do the pairing / repro NOW. <<<' -ForegroundColor Yellow
[void](Read-Host 'When finished, press Enter to STOP and process the trace')

Write-Host 'Stopping trace (can take a minute)...' -ForegroundColor Cyan
wpr -stop $etl

Write-Host 'Decoding to text (tracerpt)...' -ForegroundColor Cyan
# -y answers "overwrite?" yes.
tracerpt $etl -o $xml -of XML -y | Out-Null

Write-Host 'Redacting...' -ForegroundColor Cyan
Redact (Get-Content $xml) | Set-Content $red -Encoding utf8

# Keyword-filtered, redacted, shareable slice.
$keywords = 'dcg|wlidsvc|LiveId|msa|token|nano|ice|stun|turn|pairing|ypp|signalr|' +
            'DeviceId|PUID|RST|PPCRL|MBI_SSL|appmanager|CDP|cross.?device|' +
            'msatoken|authority|scope|consumers'
Write-Host 'Building filtered shareable slice...' -ForegroundColor Cyan
$matched = Select-String -Path $red -Pattern $keywords -AllMatches | ForEach-Object { $_.Line }
Redact $matched | Set-Content $flt -Encoding utf8

$etlMB = [math]::Round((Get-Item $etl).Length / 1MB, 1)
Write-Host ''
Write-Host '===== DONE =====' -ForegroundColor Green
Write-Host "Raw .etl size: $etlMB MB   (Auth mode should be tens of MB; Full is GB)"
Write-Host "SHARE this:  $flt" -ForegroundColor Green
Write-Host "Full redacted (check before sharing): $red"
Write-Host "RAW (keep local, may contain secrets): $etl" -ForegroundColor DarkYellow
Write-Host ''
Write-Host 'Tip: if tracerpt produced little useful text, open the .etl in Windows'
Write-Host 'Performance Analyzer (wpa.exe) and filter the "Generic Events" graph to'
Write-Host 'the LiveId / WinHttp providers.'
