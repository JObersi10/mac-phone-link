<#
    phonelink-transport-pktmon.ps1 — capture the Nano media TRANSPORT leg.

    The auth trace (phonelink-trace.ps1) sees the token mint but NOT the
    ICE/STUN/TURN/pseudo-TLS media path — that is packet payload, not ETW.
    This script uses the built-in `pktmon` (no install) to record the packets
    to/from your PHONE and/or the relay, then converts to .pcapng for Wireshark.

    You need the phone's current IP on the shared network (or the relay IP from
    the auth trace). Pass it with -PeerIp. Capture is scoped to that IP so the
    file stays small (a few MB for ~60 s of mirroring).

    Flow:
      filter to PeerIp -> start pktmon -> (you mirror ~30-60s) -> Enter ->
      stop -> convert to .pcapng -> Desktop\phonelink_transport\

    The .pcapng is RAW TRAFFIC — keep it LOCAL. The media payload (video/audio/
    clipboard/SMS) is personal content. Share only paraphrased structure
    (ALPN string, STUN attribute names, frame-type bytes, handshake field
    layout), never raw payload hex of real content.

    Usage (Administrator):
      powershell -ExecutionPolicy Bypass -File .\phonelink-transport-pktmon.ps1 -PeerIp 192.168.1.42
#>

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PeerIp,
    # Optional second IP (e.g. the TURN relay seen in the auth trace).
    [string]$RelayIp
)
$ErrorActionPreference = 'Stop'

$dest = Join-Path ([Environment]::GetFolderPath('Desktop')) 'phonelink_transport'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$etl  = Join-Path $dest 'transport.etl'
$pcap = Join-Path $dest 'transport.pcapng'

Write-Host 'Resetting pktmon filters...' -ForegroundColor Cyan
pktmon filter remove | Out-Null
pktmon filter add PhoneLinkPeer -i $PeerIp | Out-Null
if ($RelayIp) { pktmon filter add PhoneLinkRelay -i $RelayIp | Out-Null }
pktmon filter list

Write-Host ''
Write-Host "Starting pktmon capture (peer $PeerIp$(if($RelayIp){", relay $RelayIp"}))..." -ForegroundColor Cyan
# --pkt-size 0 = full packet; --capture captures to the real-time .etl file.
pktmon start --capture --pkt-size 0 --file-name $etl | Out-Null

Write-Host ''
Write-Host '>>> Start a mirroring session now and let it run ~30-60s. <<<' -ForegroundColor Yellow
[void](Read-Host 'When finished, press Enter to STOP')

Write-Host 'Stopping capture...' -ForegroundColor Cyan
pktmon stop | Out-Null

Write-Host 'Converting to .pcapng for Wireshark...' -ForegroundColor Cyan
# pktmon can emit pcapng directly from the etl.
pktmon pcapng $etl -o $pcap | Out-Null

pktmon filter remove | Out-Null

$pcapMB = [math]::Round((Get-Item $pcap).Length / 1MB, 1)
Write-Host ''
Write-Host '===== DONE =====' -ForegroundColor Green
Write-Host "pcapng size: $pcapMB MB"
Write-Host "RAW capture (keep LOCAL — contains media payload): $pcap" -ForegroundColor DarkYellow
Write-Host ''
Write-Host 'Open in Wireshark. Useful first-pass filters:'
Write-Host '  stun                          (ICE connectivity checks / TURN)'
Write-Host '  udp && ip.addr == '"$PeerIp"'   (the peer leg)'
Write-Host 'Share only paraphrased STRUCTURE (ALPN, STUN attribute names, frame-type'
Write-Host 'bytes, handshake field layout) — never raw payload hex of real content.'
