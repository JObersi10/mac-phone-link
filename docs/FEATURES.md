# Feature map — Phone Link → mac-phone-link

This maps every feature visible in the Windows Phone Link UI to how
mac-phone-link provides it, which plane it lives on, and its current state.
Nothing here routes through Microsoft.

Legend: ✅ implemented · 🟡 partial / scaffolded · ⬜ planned

| Phone Link feature | Plane | How we do it | State |
| --- | --- | --- | --- |
| **Screen mirroring** | display | scrcpy-server H.264 → VideoToolbox → AppKit window | 🟡 code complete, needs device run |
| **Apps (each app in its own window)** | display | Android virtual display per app (`new_display` + `start_app`) | 🟡 wired in UI + launcher |
| **Mouse / keyboard control** | display | scrcpy control protocol (touch/scroll/keycode/text) | 🟡 implemented, on-device tuning pending |
| **Notifications** | companion | KDE Connect `kdeconnect.notification` (receive) + `.request` (dismiss) | 🟡 model + routing done, transport pending |
| **Media / "Audio player" controls** | companion | KDE Connect `kdeconnect.mpris` state + `.request` (Play/Pause/Next/Prev/volume) | 🟡 model + commands done, transport pending |
| **Ring my phone** | companion | KDE Connect `kdeconnect.findmyphone.request` | 🟡 command done, transport pending |
| **Battery indicator** | companion | KDE Connect `kdeconnect.battery` | 🟡 model done, UI surface pending |
| **Clipboard sync** | both | KDE Connect `kdeconnect.clipboard`, or scrcpy's own GET/SET_CLIPBOARD during mirroring | 🟡 both paths modeled |
| **Calls (incoming/missed)** | companion | KDE Connect `kdeconnect.telephony` | 🟡 model done, UI pending |
| **Messages (SMS)** | companion | KDE Connect `kdeconnect.sms.messages` | ⬜ model stubbed, UI planned |
| **Photos browsing** | companion | KDE Connect SFTP/share browse of DCIM | ⬜ planned |
| **Do Not Disturb toggle** | companion | Suppress local notification surfacing; no phone-side DND API in KDE Connect | ⬜ planned (desktop-side) |
| **Instant Hotspot** | — | Needs vendor hooks; no open equivalent | ❌ out of scope |
| **Wallpaper sync** | companion | Fetch via file share; cosmetic | ⬜ low priority |
| **Sync over mobile data** | — | N/A — we are LAN/USB, not cloud | ❌ not applicable |
| **File transfer** | companion | KDE Connect `kdeconnect.share` | ⬜ planned |

## Native macOS integrations (the "seamless, all-in-one" goals)

These go beyond Phone Link parity — they make the phone feel native to macOS.

| Integration | How | State |
| --- | --- | --- |
| **Now Playing on Control Center / lock screen / media keys** | Phone MPRIS → `MPNowPlayingInfoCenter`; media keys / Control Center → `MPRemoteCommandCenter` → phone (`NowPlayingBridge`) | 🟡 bridge implemented, needs companion transport for live data |
| **Click a notification → screen-mirror of that app** | Companion notification → `AppController.openAppMirror(forPackage:)` opens a per-app virtual-display window | 🟡 hook implemented; appName→package resolution + native-notification surfacing pending |
| **Live aspect-ratio toggle (Native ↔ 16:9)** | Top-bar button: relocks `window.contentAspectRatio` instantly; for virtual displays also sends scrcpy `RESIZE_DISPLAY` so the device relayouts live, no reopen | 🟡 client-side framing works any version; device resize needs scrcpy ≥ 4.0 |

## Notes on parity gaps

- **Instant Hotspot** and **Sync over mobile data** are cloud/vendor features
  with no open-protocol equivalent; they are intentionally out of scope rather
  than faked.
- **Do Not Disturb** in Phone Link mutes *PC-side* notification popups. We can
  do the same locally (stop surfacing incoming `kdeconnect.notification`
  packets) without any phone-side API.
- Several companion features share one dependency: the **encrypted transport +
  pairing** milestone. Once that lands, notifications, media, ring, battery,
  clipboard and telephony all light up together, because their packet handling
  is already implemented and tested.
