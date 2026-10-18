// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// App-layer feature flags for frontier features that depend on upstream
/// `partout` core work (docs/plan.md Phase 15). Every flag defaults to OFF;
/// a flag may only light up once its upstream dependency lands in the pinned
/// `partout` submodule AND the flag is explicitly enabled via a UserDefaults
/// override (debug/beta opt-in). No flagged-off code path is reachable while
/// the flag is OFF, so shipping this scaffolding is behavior-neutral.
public enum FeatureFlag: String, CaseIterable, Sendable, Hashable {
    /// Feature #2 — multi-hop / chained WireGuard profiles.
    /// Requires chained WireGuard endpoint support in the `partout` core
    /// (no upstream issue/PR exists yet as of 2026-10).
    case multiHop

    /// Feature #4 — post-quantum WireGuard option.
    /// Requires a PQ handshake in the upstream WireGuard implementation
    /// (see WireGuard/wireguard-go#133 for the prototype upstream-of-upstream).
    case postQuantumWireGuard

    /// Feature #5 — WireGuard traffic obfuscation / stealth.
    /// Requires a masking transport in the core. OpenVPN XOR (Tunnelblick
    /// patch) is already inherited; upstream WG obfuscation work is tracked
    /// in partout-io/partout#481 / passepartout#1863 (AmneziaWG, open PRs).
    case wgObfuscation

    /// Feature #7 — per-app split tunneling on macOS.
    /// Requires NE transparent-proxy support beyond the current route-level
    /// split (NEAppRule per-app mode is MDM-restricted; see PIA
    /// mac-split-tunnel for prior art). Not purely upstream-core work.
    case perAppSplitTunneling
}

/// Immutable snapshot of enabled frontier feature flags.
public struct FeatureFlags: Sendable, Hashable {
    public let enabled: Set<FeatureFlag>

    public init(enabled: Set<FeatureFlag> = []) {
        self.enabled = enabled
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        enabled.contains(flag)
    }

    public var isAnyEnabled: Bool {
        !enabled.isEmpty
    }
}

extension FeatureFlags {
    /// UserDefaults key prefix for opt-in overrides. A boolean set to `true`
    /// for `overridesKeyPrefix + flag.rawValue` enables that flag; absent or
    /// false keys leave the flag OFF.
    public static let overridesKeyPrefix = "FeatureFlags."

    /// Loads flags from UserDefaults overrides. Absent keys mean OFF, so the
    /// default snapshot is all-OFF.
    public init(defaults: UserDefaults) {
        var enabled: Set<FeatureFlag> = []
        for flag in FeatureFlag.allCases
        where defaults.bool(forKey: Self.overridesKeyPrefix + flag.rawValue) {
            enabled.insert(flag)
        }
        self.init(enabled: enabled)
    }
}
