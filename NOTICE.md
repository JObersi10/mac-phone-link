# NOTICE — third-party credits & licensing

mac-phone-link is licensed under the MIT License (see `LICENSE`). It builds on
the work of others. This file records what we use, how, and why the licensing is
clean.

## scrcpy — Apache License 2.0

- Project: https://github.com/Genymobile/scrcpy
- Copyright © Romain Vimont, Genymobile and scrcpy contributors.

**How we use it:** mac-phone-link drives the released `scrcpy-server` binary on
the phone via `adb` and implements a compatible desktop client. The scrcpy wire
format (control messages, video framing) in `Sources/ScrcpyProtocol` is a clean
reimplementation based on scrcpy's public source and documentation.

**We do not vendor `scrcpy-server` in this repository.** The user supplies the
matching release. If you choose to redistribute `scrcpy-server` alongside a
build, Apache-2.0 requires that you include scrcpy's `LICENSE` and `NOTICE` with
it. Apache-2.0 is compatible with this project's MIT license.

## KDE Connect — GPL-2.0-or-later

- Project: https://github.com/KDE/kdeconnect-kde and the KDE Connect Android app
- Copyright © Albert Vaca Cintora and KDE Connect contributors.

**How we use it:** the companion plane (`Sources/Companion`) implements the
*desktop peer* of the KDE Connect network protocol so it interoperates with the
KDE Connect **Android app** that the user installs on their phone.

**No KDE Connect source code is copied into this project.** Network protocols,
packet type names, and JSON field names are facts/interfaces, not copyrightable
expression; reimplementing a wire protocol does not make this project a
derivative work of KDE Connect's GPL code. We intentionally wrote our own
implementation rather than porting theirs so that this project can remain MIT.

If that distinction ever matters to you for redistribution, the conservative
option is to keep the `Companion` target's networking as an independent process
or to relicense that target — but as written, it copies nothing.

## Apple frameworks

VideoToolbox, CoreMedia, Network, AppKit and CoreImage are used under the Apple
SDK license as part of normal macOS development.

## What this project explicitly does NOT use

- No Microsoft "Link to Windows" / Phone Link code, APIs, endpoints, or
  credentials.
- No Samsung proprietary (MDX / "Link to Windows") code or protocol.
- The Samsung APK that may have been shared during development was **not**
  decompiled, incorporated, or used to derive any protocol here.
