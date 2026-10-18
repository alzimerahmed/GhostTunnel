// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
// SPDX-License-Identifier: GPL-3.0

import Foundation
import Testing
@testable import CommonLibraryCore

struct FeatureFlagsTests {
    @Test
    func givenDefaultInit_thenAllFlagsOff() {
        let sut = FeatureFlags()
        for flag in FeatureFlag.allCases {
            #expect(!sut.isEnabled(flag))
        }
        #expect(!sut.isAnyEnabled)
    }

    @Test
    func givenEmptyDefaults_thenAllFlagsOff() throws {
        let suiteName = "FeatureFlagsTests.empty.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let sut = FeatureFlags(defaults: defaults)
        for flag in FeatureFlag.allCases {
            #expect(!sut.isEnabled(flag))
        }
        #expect(!sut.isAnyEnabled)
    }

    @Test
    func givenOverrides_whenLoad_thenOnlySetFlagsEnabled() throws {
        let suiteName = "FeatureFlagsTests.overrides.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(true, forKey: FeatureFlags.overridesKeyPrefix + FeatureFlag.wgObfuscation.rawValue)
        defaults.set(false, forKey: FeatureFlags.overridesKeyPrefix + FeatureFlag.multiHop.rawValue)

        let sut = FeatureFlags(defaults: defaults)
        #expect(sut.isEnabled(.wgObfuscation))
        #expect(!sut.isEnabled(.multiHop))
        #expect(!sut.isEnabled(.postQuantumWireGuard))
        #expect(!sut.isEnabled(.perAppSplitTunneling))
        #expect(sut.isAnyEnabled)
    }

    @Test
    func givenExplicitlyEnabledFlags_thenIsEnabledMatches() {
        let sut = FeatureFlags(enabled: [.multiHop, .perAppSplitTunneling])
        #expect(sut.isEnabled(.multiHop))
        #expect(sut.isEnabled(.perAppSplitTunneling))
        #expect(!sut.isEnabled(.postQuantumWireGuard))
        #expect(!sut.isEnabled(.wgObfuscation))
        #expect(sut.isAnyEnabled)
    }

    @Test
    func givenAllFlagRawValues_thenUniqueAndStable() {
        let rawValues = FeatureFlag.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
        #expect(rawValues == [
            "multiHop",
            "postQuantumWireGuard",
            "wgObfuscation",
            "perAppSplitTunneling"
        ])
    }
}
