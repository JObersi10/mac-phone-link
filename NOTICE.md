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

**We bundle `scrcpy-server` (v4.1) in this repository** at `vendor/scrcpy-server`,
and the build copies it into `PhoneLink.app/Contents/Resources/` so the app is
self-contained. Apache-2.0 permits this; the required `LICENSE` is shipped
alongside at `vendor/scrcpy-LICENSE` and copied into the app bundle. Apache-2.0
is compatible with this project's MIT license.

## Android Debug Bridge (adb) — Apache License 2.0

- Part of the Android SDK Platform-Tools, © Google LLC.

**How we use it / bundle it:** `adb` (from the scrcpy macOS v4.1 distribution,
a universal x86_64+arm64 binary) is committed at `vendor/adb` and copied into
the app bundle so screen mirroring works without a separate platform-tools
install. adb is the supported interface to the device; the app only runs
commands the user could run themselves.

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
