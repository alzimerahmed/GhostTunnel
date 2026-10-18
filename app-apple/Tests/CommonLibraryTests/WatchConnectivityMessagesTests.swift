// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import Foundation
import Testing

struct WatchConnectivityMessagesTests {
    // MARK: Message round-trips

    @Test
    func givenRequestStatus_whenEncodedAndDecoded_thenRoundTrips() {
        let message = WatchTunnelMessage.requestStatus
        guard let dictionary = message.encodedDictionary() else {
            Issue.record("Encoding failed")
            return
        }
        #expect(WatchTunnelMessage(dictionary: dictionary) == message)
    }

    @Test
    func givenStatusMessage_whenEncodedAndDecoded_thenRoundTrips() {
        let message = WatchTunnelMessage.status(WatchTunnelStatus(
            kind: .connected,
            profileId: UUID().uuidString,
            profileName: "Home",
            lastUpdate: Date(timeIntervalSince1970: 1_760_000_000)
        ))
        guard let dictionary = message.encodedDictionary() else {
            Issue.record("Encoding failed")
            return
        }
        #expect(WatchTunnelMessage(dictionary: dictionary) == message)
    }

    @Test
    func givenActionMessages_whenEncodedAndDecoded_thenRoundTrip() {
        let id = UUID().uuidString
        for message in [
            WatchTunnelMessage.connect(profileId: id),
            WatchTunnelMessage.disconnect(profileId: id),
            WatchTunnelMessage.failure("iPhone not reachable")
        ] {
            guard let dictionary = message.encodedDictionary() else {
                Issue.record("Encoding failed for \(message)")
                continue
            }
            #expect(WatchTunnelMessage(dictionary: dictionary) == message)
        }
    }

    @Test
    func givenForeignDictionary_thenDecodingReturnsNil() {
        #expect(WatchTunnelMessage(dictionary: [:]) == nil)
        #expect(WatchTunnelMessage(dictionary: ["payload": "not-data"]) == nil)
        #expect(WatchTunnelMessage(dictionary: ["unrelated": Data([0x00])]) == nil)
        #expect(WatchTunnelMessage(dictionary: ["payload": Data([0xff])]) == nil)
    }

    // MARK: Status mapping (phone widget state → watch status)

    @Test
    func givenWidgetState_whenMapped_thenStatusMirrorsKindAndProfile() {
        let id = UUID()
        let state = TunnelWidgetState(
            kind: .connecting,
            profileId: id.uuidString,
            profileName: "Office",
            lastUpdate: Date(timeIntervalSince1970: 1_760_000_100)
        )
        let status = WatchTunnelStatus(state: state)
        #expect(status.kind == .connecting)
        #expect(status.profileId == id.uuidString)
        #expect(status.profileName == "Office")
        #expect(status.lastUpdate == state.lastUpdate)
    }

    @Test
    func givenDisconnectedWidgetState_whenMapped_thenStatusIsDisconnected() {
        let status = WatchTunnelStatus(state: TunnelWidgetState(kind: .disconnected))
        #expect(status.kind == .disconnected)
        #expect(status.profileId == nil)
        #expect(status.profileName == nil)
    }

    // MARK: Watch-side store

    @Test
    func givenWatchStore_whenSaveAndLoad_thenRoundTrips() {
        let suite = "WatchConnectivityMessagesTests"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let store = WatchStatusStore(defaults: defaults)
        let status = WatchTunnelStatus(
            kind: .connected,
            profileId: UUID().uuidString,
            profileName: "Home"
        )
        store.save(status)
        #expect(store.load() == status)
    }

    @Test
    func givenEmptyWatchStore_thenLoadReturnsNil() {
        let suite = "WatchConnectivityMessagesTests.empty"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        #expect(WatchStatusStore(defaults: defaults).load() == nil)
    }
}
