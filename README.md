# GhostTunnel

[![Unit Tests](https://github.com/alzimerahmed/GhostTunnel/actions/workflows/test.yml/badge.svg)](https://github.com/alzimerahmed/GhostTunnel/actions/workflows/test.yml)

GhostTunnel is a privacy-first VPN client for Apple platforms (iOS, macOS, tvOS, watchOS), Android, and desktop — built on OpenVPN and WireGuard. No telemetry, no ads, no donations.

Fork of [Passepartout](https://github.com/partout-io/passepartout) (GPLv3), fully re-engineered under the GhostTunnel identity: `com.ghosttunnel.*` bundle IDs, GhostTunnel app icon and display names across all platforms, self-hosted provider config, and donation/IAP-gratitude surfaces removed.

## Features

GhostTunnel is an [OpenVPN®][openvpn] and [WireGuard®][wireguard] client. The OpenVPN stack also implements the [Tunnelblick XOR patch][openvpn-xor-patch].

Core (inherited from Passepartout):

- On-demand rules
- Override DNS and HTTP proxy
- Custom routing
- Presets for multiple providers (virtually any)
- iCloud sync, Shortcuts, no background activities, wise on battery

GhostTunnel additions (v1.0.0):

- **Quick connect surfaces** — home-screen widgets, iOS Control Center control, macOS menu-bar quick connect
- **Import** — QR-code WireGuard import, wg-quick, Tunnelblick `.tblk`, Tailscale config stubs
- **App Lock** — FaceID/passcode gate with privacy screen
- **Backup** — profile export/import to portable (optionally encrypted) archives
- **Diagnostics** — leak test, sanitized debug bundle export, in-app speed test with fastest-server pick
- **tvOS** — Top Shelf integration, multi-profile browsing
- **watchOS** — companion app with glanceable status and quick connect
- **Android** — connect/disconnect, profile import, on-demand subset
- **Desktop** — minimal connect/disconnect client (`app-cross`, CMake + wxWidgets)
- **Frontier features staged behind flags** — multi-hop, post-quantum WireGuard, WG obfuscation, per-app split tunneling (pending upstream `partout` core support)

## Privacy

- **No telemetry** — the app never phones home; diagnostics go only where you send them
- **No donations, no ads** — donation links and donation in-app products are removed entirely
- **Self-hosted config** — provider presets/blocklists come from the GhostTunnel-owned [`ghosttunnel-config`](https://github.com/alzimerahmed84/ghosttunnel-config) repo, not upstream servers

See [SECURITY.md](SECURITY.md) for the vulnerability-reporting policy and threat model notes.

## Installation

### Requirements

- iOS 17+ / macOS 14+ / tvOS 17+ / watchOS (companion)
- Xcode 26, Swift 6
- Git (preinstalled with the Xcode Command Line Tools)
- Java (optional, for the OpenAPI Generator)
- Android: Android SDK/NDK + CMake (Gradle build)
- Desktop: CMake + wxWidgets (`CMakePresets.json`)

### Building from source

Download the codebase locally:

```shell
git clone https://github.com/alzimerahmed/GhostTunnel
cd GhostTunnel
git submodule update --init partout
```

Then find the Xcode project in `app-apple`. For everything to work properly, you must comply with all the capabilities and entitlements in the main app and the tunnel extension target. Therefore, you must update the `Config.xcconfig` file according to your developer account.

To test the app on your Mac or iOS/tvOS Simulator:

- Open `Passepartout.xcodeproj` in Xcode
- Run the `Passepartout` target

Android: `./gradlew assembleDebug` in `app-android/`. Desktop: `app-cross/scripts/build.sh` (CMake presets).

### CI

All verification runs on GitHub Actions (`checks.yml` / `test.yml`): Apple tests + builds (macOS), Partout core tests, Cross checks, Android build, desktop build. Releases are tagged `vX.Y.Z`; unsigned/source releases until a signing identity exists.

## License

This project is licensed under the [GPLv3][license-content].

## Credits

This is a fork of [Passepartout][upstream] by Davide De Rosa. Credits for the original project's dependencies:

- [fastlane][credits-fastlane]
- [GenericJSON][credits-genericjson]
- [MbedTLS][credits-mbedtls]
- [OpenSSL][credits-openssl]
- [SwiftGen][credits-swiftgen]
- [SwiftLint][credits-swiftlint]
- [Tejas Mehta][credits-tmthecoder] for the implementation of the [OpenVPN XOR patch][credits-tmthecoder-xor]
- [url.c][credits-url.c]
- [Wintun][credits-wintun]
- [WireGuard (Go)][credits-wireguard-go]

The GhostTunnel app icon is an original GhostTunnel asset.

### OpenSSL

This product includes software developed by the OpenSSL Project for use in the OpenSSL Toolkit. ([https://www.openssl.org/][dep-openssl])

### OpenVPN

© Copyright 2026 OpenVPN | OpenVPN is a registered trademark of OpenVPN, Inc.

### WireGuard

© Copyright 2015-2026 Jason A. Donenfeld. All Rights Reserved. "WireGuard" and the "WireGuard" logo are registered trademarks of Jason A. Donenfeld.

[upstream]: https://github.com/partout-io/passepartout

[openvpn]: https://openvpn.net/index.php/open-source/overview.html
[openvpn-xor-patch]: https://tunnelblick.net/cOpenvpn_xorpatch.html
[wireguard]: https://www.wireguard.com/

[dep-brew]: https://brew.sh/
[dep-openssl]: https://www.openssl.org/

[license-content]: LICENSE

[credits-fastlane]: https://github.com/fastlane/fastlane
[credits-genericjson]: https://github.com/iwill/generic-json-swift
[credits-mbedtls]: https://github.com/Mbed-TLS/mbedtls
[credits-openssl]: https://github.com/openssl/openssl
[credits-swiftgen]: https://github.com/SwiftGen/SwiftGen
[credits-swiftlint]: https://github.com/realm/SwiftLint
[credits-tmthecoder]: https://github.com/tmthecoder
[credits-tmthecoder-xor]: https://github.com/partout-io/tunnelkit/pull/255
[credits-url.c]: https://github.com/cozis/url.c
[credits-wintun]: https://github.com/wireguard/wintun
[credits-wireguard-go]: https://github.com/wireguard/wireguard-go
