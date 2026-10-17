// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import Testing

struct TunnelWidgetStateTests {
    @Test
    func givenNoActiveProfiles_thenDisconnected() {
        let state = TunnelWidgetState(profiles: [:])
        #expect(state.kind == .disconnected)
        #expect(state.profileId == nil)
    }

    @Test
    func givenConnectedProfile_thenKindAndIdMatch() {
        let id = UUID()
        let info = ABI.AppTunnelInfo(
            id: id,
            isEnabled: true,
            tunnelStatus: .active,
            onDemand: false,
            environment: nil
        )
        let state = TunnelWidgetState(profiles: [id: info])
        #expect(state.kind == .connected)
        #expect(state.profileId == id.uuidString)
    }

    @Test
    func givenDisconnectedProfile_thenKindIsDisconnected() {
        let id = UUID()
        let info = ABI.AppTunnelInfo(
            id: id,
            isEnabled: true,
            tunnelStatus: .inactive,
            onDemand: false,
            environment: nil
        )
        let state = TunnelWidgetState(profiles: [id: info])
        #expect(state.kind == .disconnected)
    }

    @Test
    func givenStore_whenSaveAndLoad_thenRoundTrips() {
        let defaults = UserDefaults(suiteName: "TunnelWidgetStateTests")!
        defer {
            defaults.removePersistentDomain(forName: "TunnelWidgetStateTests")
        }
        let store = TunnelWidgetStatusStore(defaults: defaults)
        let state = TunnelWidgetState(
            kind: .connected,
            profileId: UUID().uuidString,
            profileName: "Home"
        )
        store.save(state)
        #expect(store.load() == state)
    }

    @Test
    func givenEmptyStore_thenLoadReturnsNil() {
        let defaults = UserDefaults(suiteName: "TunnelWidgetStateTests.empty")!
        defer {
            defaults.removePersistentDomain(forName: "TunnelWidgetStateTests.empty")
        }
        #expect(TunnelWidgetStatusStore(defaults: defaults).load() == nil)
    }
}
