// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Partout
import Testing

struct ConfigBundleTests {
    @Test
    func givenBundle_whenLegacyDaemonKeys_thenOnlyCurrentKeysAreActive() throws {
        let json = #"{"daemonLooperV2":{"rate":100},"daemonLooperV2WireGuard":{"rate":100},"experimentalDaemon_202610":{"rate":100},"experimentalDaemonOpenVPN_202610":{"rate":100},"experimentalDaemonWireGuard_202610":{"rate":100},"appNotWorking":{"rate":100}}"#
        let sut = try ABI.decodeJSON(ConfigBundle.self, from: json)
        #expect(sut.activeFlags(withBuild: 1) == [
            .appNotWorking,
            .experimentalDaemon_202610,
            .experimentalDaemonOpenVPN_202610,
            .experimentalDaemonWireGuard_202610
        ])
    }

    @Test
    func givenBlocklistMetadataAndOtherUnknown_whenDecoding_thenOnlyMetadataIsRetained() throws {
        let json = #"{"ghosttunnelBlocklistMetadata":{"rate":100,"data":{"schema":1}},"arbitraryUnknown":{"rate":100}}"#
        let sut = try ABI.decodeJSON(ConfigBundle.self, from: json)
        #expect(sut.blocklistMetadata?.data != nil)
        #expect(sut.map.isEmpty)
        #expect(sut.activeFlags(withBuild: 1).isEmpty)
    }

    @Test
    func givenInactiveBlocklistMetadata_whenDecoding_thenMetadataIsNotActive() throws {
        let json = #"{"ghosttunnelBlocklistMetadata":{"rate":50,"data":{"schema":1}}}"#
        let sut = try ABI.decodeJSON(ConfigBundle.self, from: json)
        #expect(sut.blocklistMetadata?.data != nil)
        #expect(!sut.blocklistMetadata!.isActive(withBuild: 1))
        #expect(sut.activeFlags(withBuild: 1).isEmpty)
    }

    @Test
    func givenActiveBlocklistMetadata_whenDecoding_thenMetadataIsActiveWithoutChangingUnknownFlag() throws {
        let json = #"{"ghosttunnelBlocklistMetadata":{"rate":100,"data":{"schema":1}}}"#
        let sut = try ABI.decodeJSON(ConfigBundle.self, from: json)
        #expect(sut.blocklistMetadata?.isActive(withBuild: 1) == true)
        #expect(sut.activeFlags(withBuild: 1).isEmpty)
    }

    @Test(arguments: [
        ([ABI.ConfigFlag.appNotWorking: ConfigBundle.Config(rate: 10, minBuild: nil, data: nil)], false),
        ([ABI.ConfigFlag.appNotWorking: ConfigBundle.Config(rate: 100, minBuild: nil, data: nil)], true),
        ([ABI.ConfigFlag.appNotWorking: ConfigBundle.Config(rate: 200, minBuild: nil, data: nil)], false)
    ])
    func givenBundle_whenRate100_thenIsActive(map: [ABI.ConfigFlag: ConfigBundle.Config], isActive: Bool) {
        let sut = ConfigBundle(map: map)
        let activeFlags: Set<ABI.ConfigFlag> = isActive ? [.appNotWorking] : []
        #expect(sut.activeFlags(withBuild: 1) == activeFlags)
    }

    @Test(arguments: [
        ([ABI.ConfigFlag.appNotWorking: ConfigBundle.Config(rate: 100, minBuild: nil, data: nil)], true),
        ([ABI.ConfigFlag.appNotWorking: ConfigBundle.Config(rate: 100, minBuild: 500, data: nil)], true),
        ([ABI.ConfigFlag.appNotWorking: ConfigBundle.Config(rate: 100, minBuild: 1000, data: nil)], false)
    ])
    func givenBundle_whenMinBuild_thenIsActive(map: [ABI.ConfigFlag: ConfigBundle.Config], isActive: Bool) {
        let sut = ConfigBundle(map: map)
        let activeFlags: Set<ABI.ConfigFlag> = isActive ? [.appNotWorking] : []
        #expect(sut.activeFlags(withBuild: 750) == activeFlags)
    }
}
