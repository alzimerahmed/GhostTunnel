# GhostTunnel

[![Unit Tests](https://github.com/alzimerahmed/GhostTunnel/actions/workflows/test.yml/badge.svg)](https://github.com/alzimerahmed/GhostTunnel/actions/workflows/test.yml)

GhostTunnel is a VPN and privacy client for Apple platforms, built on OpenVPN and WireGuard.

Fork of [Passepartout](https://github.com/partout-io/passepartout) (GPLv3).

## Features

GhostTunnel is an [OpenVPN®][openvpn] and [WireGuard®][wireguard] client for Apple platforms. The OpenVPN stack also implements the [Tunnelblick XOR patch][openvpn-xor-patch].

Other features:

- On-demand rules
- Override DNS and HTTP proxy
- Custom routing
- Presets for multiple providers (virtually any)

Tailored for Apple platforms:

- iPhone, iPad, Mac, and Apple TV
- iCloud
- Shortcuts
- No background activities
- Wise on battery

## Installation

### Requirements

- iOS 17+ / macOS 14+ / tvOS 17+
- Xcode 26
- Swift 6
- Git (preinstalled with the Xcode Command Line Tools)
- Java (optional, for the OpenAPI Generator)

It's highly recommended that you use the Git and Ruby packages provided by [Homebrew][dep-brew].

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

The logo is taken from the awesome Circle Icons set by Nick Roach.

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
