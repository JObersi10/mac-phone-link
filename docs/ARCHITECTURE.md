# Architecture

mac-phone-link is deliberately split into two planes that share nothing but the
phone. This keeps the hard real-time video path independent from the chatty
event/control path, and lets either evolve without destabilizing the other.

## Modules (Swift Package targets)

| Target | Plane | Responsibility | Platform deps |
| --- | --- | --- | --- |
| `ScrcpyProtocol` | display | scrcpy wire format: control messages, video framing, codec ids, device messages. Pure logic, no I/O. | none (portable) |
| `AdbBridge` | display | Drive the real `adb`: device discovery, push `scrcpy-server`, port-forward tunnel, launch server with options. | Foundation (`Process`) |
| `VideoPipeline` | display | H.264 Annex-B handling + VideoToolbox hardware decode → `CVImageBuffer`. | VideoToolbox, CoreMedia |
| `Streaming` | display | One `DeviceSession` per display/app: sockets, de-framing, decode wiring, control send. | Network |
| `Companion` | companion | KDE Connect packet models + client logic for notifications, media, ring, battery, clipboard, telephony. Pure logic, no I/O. | none (portable) |
| `PhoneLink` | app | Menu-bar AppKit app, per-app mirror windows, input mapping, feature menus. | AppKit |

The two "pure logic, no I/O" targets (`ScrcpyProtocol`, `Companion`) are where
all the protocol correctness lives, which is why they are the ones with unit
tests — they run anywhere and have no reason to break on a UI change.

## Display plane

```
AppController
   └─ SessionManager            allocates SCID + local port, finds scrcpy-server
        └─ DeviceSession        one per window
             ├─ ScrcpyServerLauncher (AdbBridge)  push jar, adb forward, spawn server
             ├─ SocketConnection x2 (Streaming)   video socket, control socket
             ├─ VideoDemuxer (ScrcpyProtocol)     carve 12-byte-header packets
             ├─ H264Decoder (VideoPipeline)       VideoToolbox → CVImageBuffer
             └─ ControlMessage (ScrcpyProtocol)   AppKit events → injected input
```

**Per-app windows.** Each app the user opens is launched on its own Android
*virtual display* via scrcpy `new_display=WxH` + `start_app=<pkg>`. One virtual
display = one scrcpy session = one `DeviceSession` = one `NSWindow`. The phone's
own screen stays free. This is Android's documented virtual-display capability,
surfaced by scrcpy 3.x — not a Samsung/Microsoft feature.

**Why reuse scrcpy-server instead of writing our own Android app?** Screen
capture, encoder setup, virtual displays, and input injection are the parts that
are genuinely hard and need per-OEM/-Android-version maintenance. scrcpy already
does them, is Apache-2.0, and is actively maintained. The weak point of the
stock scrcpy *app* is its generic SDL client; replacing just that with a native
macOS client is the highest-leverage, lowest-maintenance path to "better than
scrcpy on Mac."

## Companion plane

```
CompanionClient (Companion)
   ├─ CompanionTransport   (protocol)  ⟵ TLS socket on :1716 after pairing  [next milestone]
   ├─ outgoing: ringPhone / mediaCommand / dismissNotification / pushClipboard
   └─ incoming: route JSON line → delegate (notification / media / battery / clipboard / telephony)
```

The phone side is the **KDE Connect Android app**, which already implements all
of these features and is widely installed. We implement the *desktop* peer of
its protocol. The transport (mDNS discovery of `_kdeconnect._udp`, a TLS channel
on port 1716, and certificate-pinned pairing) is the remaining piece; the packet
layer and client logic are done and tested with an in-memory transport.

## Threading & concurrency

- Socket I/O is `async`/`await` over `NWConnection` continuations.
- VideoToolbox decode is asynchronous; decoded frames arrive on a callback and
  are marshaled to the main thread before touching any layer.
- Each `DeviceSession` is self-contained; multiple sessions run concurrently
  (one per window) with independent SCIDs and ports.
