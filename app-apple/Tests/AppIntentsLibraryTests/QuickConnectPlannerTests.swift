// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppIntentsLibrary
import CommonLibrary
import Testing

struct QuickConnectPlannerTests {
    private func header(_ id: UUID, name: String = "Profile") -> ABI.AppProfileHeader {
        ABI.AppProfileHeader(
            id: id,
            name: name,
            moduleTypes: [],
            primaryModuleType: nil,
            secondaryModuleTypes: nil,
            fingerprint: id.uuidString,
            sharingFlags: [],
            requiredFeatures: []
        )
    }

    @Test
    func givenDisconnected_whenToggle_thenConnectsLastUsed() {
        let a = UUID()
        let b = UUID()
        let action = QuickConnectPlanner.action(
            current: TunnelWidgetState(kind: .disconnected),
            profiles: [header(a), header(b)],
            lastUsedProfileId: b
        )
        #expect(action == .connect(b))
    }

    @Test
    func givenNoLastUsed_whenToggle_thenConnectsFirstProfile() {
        let a = UUID()
        let b = UUID()
        let action = QuickConnectPlanner.action(
            current: nil,
            profiles: [header(b), header(a)],
            lastUsedProfileId: nil
        )
        #expect(action == .connect(a))
    }

    @Test
    func givenConnectedKnownProfile_whenToggle_thenDisconnects() {
        let a = UUID()
        let action = QuickConnectPlanner.action(
            current: TunnelWidgetState(kind: .connected, profileId: a.uuidString),
            profiles: [header(a)],
            lastUsedProfileId: a
        )
        #expect(action == .disconnect(a))
    }

    @Test
    func givenConnectingKnownProfile_whenToggle_thenDisconnects() {
        let a = UUID()
        let action = QuickConnectPlanner.action(
            current: TunnelWidgetState(kind: .connecting, profileId: a.uuidString),
            profiles: [header(a)],
            lastUsedProfileId: nil
        )
        #expect(action == .disconnect(a))
    }

    @Test
    func givenConnectedUnknownProfile_whenToggle_thenConnectsLastUsed() {
        let a = UUID()
        let b = UUID()
        let action = QuickConnectPlanner.action(
            current: TunnelWidgetState(kind: .connected, profileId: a.uuidString),
            profiles: [header(b)],
            lastUsedProfileId: b
        )
        #expect(action == .connect(b))
    }

    @Test
    func givenNoProfiles_whenToggle_thenDoesNothing() {
        let action = QuickConnectPlanner.action(
            current: nil,
            profiles: [],
            lastUsedProfileId: nil
        )
        #expect(action == .none)
    }

    @Test
    func givenStaleLastUsed_whenToggle_thenConnectsFirstProfile() {
        let a = UUID()
        let b = UUID()
        let action = QuickConnectPlanner.action(
            current: nil,
            profiles: [header(a)],
            lastUsedProfileId: b
        )
        #expect(action == .connect(a))
    }
}
