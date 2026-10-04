# Protocol notes

Two wire protocols, one per plane. Both are **reimplemented from public
documentation and source**, pinned to specific upstream versions, and verified
by unit tests. When you bump a pinned version, re-check the layouts here against
upstream.

## Display plane — scrcpy (pinned: see `ScrcpyServer.pinnedVersion`)

scrcpy's wire format is not a stable public API; it changes across major
versions. Everything below is for the pinned server release and lives in
`Sources/ScrcpyProtocol`.

### Sockets

With `tunnel_forward=true`, scrcpy-server *listens* on the device abstract
socket `scrcpy_<scid>`; we `adb forward tcp:<port> localabstract:scrcpy_<scid>`
and connect to `127.0.0.1:<port>`. The client opens sockets in order: **video**,
then **control** (audio disabled here). The control socket is the only
bidirectional one.

### Video socket

```
[ codec id : u32 ]            e.g. "h264" = 0x68323634
[ width    : u32 ]
[ height   : u32 ]
then, repeatedly, media packets:
[ header : 12 bytes ][ payload : N bytes ]
```

Media packet header (big-endian):

```
bits 63     : config packet flag (SPS/PPS, no displayable frame)
bits 62     : key frame flag
bits 61..0  : PTS in microseconds
next 4 bytes: payload size (u32)
```

Config packets carry Annex-B SPS/PPS used to build the VideoToolbox format
description; frame packets are converted Annex-B → AVCC before decode.

### Control messages (client → device)

Serialized big-endian, implemented in `ControlMessage.serialize()`:

| Message | Type | Layout after the 1-byte type |
| --- | --- | --- |
| inject keycode | 0 | action(1) keycode(4) repeat(4) metastate(4) |
| inject text | 1 | len(4) utf8(len) |
| inject touch | 2 | action(1) pointerId(8) x(4) y(4) w(2) h(2) pressure(2) actionButton(4) buttons(4) |
| inject scroll | 3 | x(4) y(4) w(2) h(2) hscroll(2) vscroll(2) buttons(4) |
| back/screen on | 4 | action(1) |
| get clipboard | 8 | copyKey(1) |
| set clipboard | 9 | sequence(8) paste(1) len(4) utf8(len) |
| start app | 16 | len(1) utf8(len) |

Pressure is a u16 fixed-point of [0,1]; scroll deltas are i16 fixed-point of
[-1,1] (`FixedPoint` in `Wire.swift`).

### Device messages (device → client, on control socket)

| Message | Type | Layout after the 1-byte type |
| --- | --- | --- |
| clipboard | 0 | len(4) utf8(len) |
| ack clipboard | 1 | sequence(8) |
| uhid output | 2 | id(2) size(2) data(size) |

## Companion plane — KDE Connect (pinned protocol v7)

Each packet is a single line of JSON terminated by `\n`:

```json
{ "id": 1712345678901, "type": "kdeconnect.<name>", "body": { ... } }
```

Implemented packet types (`Sources/Companion`):

| Purpose | type | Direction |
| --- | --- | --- |
| Ring my phone | `kdeconnect.findmyphone.request` | → phone |
| Notification posted/updated/cancelled | `kdeconnect.notification` | ← phone |
| Dismiss notification | `kdeconnect.notification.request` | → phone |
| Media state | `kdeconnect.mpris` | ← phone |
| Media command (Play/Pause/Next/Prev/volume) | `kdeconnect.mpris.request` | → phone |
| Battery | `kdeconnect.battery` | ← phone |
| Clipboard | `kdeconnect.clipboard` | both |
| Calls/SMS events | `kdeconnect.telephony` | ← phone |
| Signal/connectivity | `kdeconnect.connectivity_report` | ← phone |
| Identity (capabilities) | `kdeconnect.identity` | both |

Field names match KDE Connect's schemas so the real Android app interoperates.
The transport (mDNS `_kdeconnect._udp` discovery, TLS on 1716, cert-pinned
pairing) is defined by the `CompanionTransport` protocol and is the next
milestone — see [ROADMAP.md](ROADMAP.md).
