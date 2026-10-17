// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Foundation
import Partout
import Testing

/// Phase 6 — blocklist metadata bridge: ConfigManager publishes the active
/// snapshot of `ghosttunnelBlocklistMetadata` via `blocklistMetadata`, gated
/// by the same rate/platforms/minBuild rules as regular flags.
@BusinessActor
struct ConfigManagerTests {
    private func manager(with json: String, buildNumber: Int = 1) async throws -> ConfigManager {
        let decodedBundle = try ABI.decodeJSON(ConfigBundle.self, from: json)
        let sut = ConfigManager(
            strategy: InMemoryConfigStrategy(storedBundle: decodedBundle),
            buildNumber: buildNumber
        )
        await sut.refreshBundle()
        return sut
    }

    @Test
    func givenRate100AppleMetadata_whenRefreshed_thenPublishesMetadata() async throws {
        let json = #"{"ghosttunnelBlocklistMetadata":{"rate":100,"platforms":["apple"],"data":{"schema":"ghosttunnel-blocklist-v1","name":"GhostTunnel Basic","sources":[],"dohEndpoints":[]}}}"#
        let sut = try await manager(with: json)
        let expected = try JSONDecoder().decode(
            JSON.self,
            from: Data(#"{"schema":"ghosttunnel-blocklist-v1","name":"GhostTunnel Basic","sources":[],"dohEndpoints":[]}"#.utf8)
        )
        #expect(sut.blocklistMetadata == expected)
    }

    @Test(arguments: [0, 50, 99])
    func givenRateBelow100Metadata_whenRefreshed_thenPublishesNil(rate: Int) async throws {
        let json = #"{"ghosttunnelBlocklistMetadata":{"rate":\#(rate),"data":{"schema":"ghosttunnel-blocklist-v1"}}}"#
        let sut = try await manager(with: json)
        #expect(sut.blocklistMetadata == nil)
    }

    @Test
    func givenNonAppleMetadata_whenRefreshed_thenPublishesNil() async throws {
        let json = #"{"ghosttunnelBlocklistMetadata":{"rate":100,"platforms":["android"],"data":{"schema":"ghosttunnel-blocklist-v1"}}}"#
        let sut = try await manager(with: json)
        #expect(sut.blocklistMetadata == nil)
    }

    @Test
    func givenMinBuildGatedMetadata_whenRefreshed_thenPublishesOnlyAtOrAboveMinBuild() async throws {
        let json = #"{"ghosttunnelBlocklistMetadata":{"rate":100,"minBuild":500,"data":{"schema":"ghosttunnel-blocklist-v1"}}}"#
        let below = try await manager(with: json, buildNumber: 499)
        #expect(below.blocklistMetadata == nil)
        let atMin = try await manager(with: json, buildNumber: 500)
        #expect(atMin.blocklistMetadata != nil)
    }

    @Test
    func givenNoMetadata_whenRefreshed_thenPublishesNil() async throws {
        let sut = try await manager(with: #"{"appNotWorking":{"rate":100}}"#)
        #expect(sut.blocklistMetadata == nil)
    }
}

private struct InMemoryConfigStrategy: ConfigManagerStrategy {
    let storedBundle: ConfigBundle

    func bundle() async throws -> ConfigBundle {
        storedBundle
    }
}
