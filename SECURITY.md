# Security Policy

GhostTunnel is an open-source (GPLv3) VPN and privacy client for Apple platforms (iOS/macOS/tvOS), with Android and cross-platform desktop clients in progress. It is a fork of [Passepartout](https://github.com/partout-io/passepartout).

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

Use GitHub's **private vulnerability reporting** on this repository:

- Repo: <https://github.com/alzimerahmed/GhostTunnel> → **Security** tab → **Report a vulnerability** (GitHub Security Advisory / private vulnerability reporting).

Alternatively, contact the owner directly by email: **alzimerahmed84@gmail.com**.

Please include:

- Affected component (Apple app, NE tunnel extension, Android app, desktop client, tunnel binaries, hosted config).
- Affected version/commit.
- Steps to reproduce or a proof of concept.
- Impact assessment and any known mitigations.

We will acknowledge reports within a few days, coordinate a fix, and publish a GitHub Security Advisory once a patched release exists. Please give us a reasonable window before public disclosure.

## Supported Versions

| Version | Supported |
|---------|-----------|
| `master` (current main) | ✅ |
| Older tags / forks | ❌ |

Only the current `master` branch receives security fixes. Releases are currently **unsigned source releases** (no code signing/notarization yet); until signing exists, verify artifacts by building from source at a tagged commit.

## Scope

In scope:

- Apple clients (iOS, macOS, tvOS): app + NetworkExtension tunnel extension.
- Android client (`app-android/`) and cross-platform desktop client + tunnel binaries (`app-cross/`).
- Profile import parsers (`.ovpn`, WireGuard configurations) — hostile-input handling.
- Hosted configuration (`alzimerahmed84/ghosttunnel-config`) and its schema.

Out of scope:

- **`partout` core** (the VPN engine submodule) is upstream: report core bugs/vulnerabilities to [partout-io upstream](https://github.com/partout-io/passepartout) per their security policy. We will help coordinate and track fixes that land upstream.
- The upstream Passepartout website/API infrastructure (`partout.io`) — not operated by us.
- Social engineering, physical attacks, denial-of-service on GitHub infrastructure.

## No-Telemetry Guarantee

GhostTunnel ships **no telemetry, no analytics, no crash-reporting SDKs**. The app never sends usage data, device identifiers, or connection metadata to us or any third party. Network traffic is limited to: the VPN tunnel itself, and explicit user-triggered fetches (provider config/version checks against GitHub-hosted endpoints, and profile-import web receiver on the local network). This guarantee is normative — the full egress list and trust boundaries are documented in the project threat model (maintained in the private knowledge layer), and analytics must never be added.

## Hardening Notes

- Kill-switch / enforce-all-traffic mode (Phase 5) closes the leak window when the tunnel drops.
- Secrets (private keys, credentials) are stored in the Keychain / platform secure storage, never in plaintext preferences.
- Profile imports are parsed defensively; malformed or hostile configuration files must not crash the app or execute code.
- Hosted config is fetched over HTTPS from GitHub; treat its contents as untrusted input (parsed, never executed).
- Report anything that violates the no-telemetry guarantee as a security issue.
