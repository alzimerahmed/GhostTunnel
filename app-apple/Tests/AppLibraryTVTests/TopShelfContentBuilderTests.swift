// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import Foundation
import Testing
@testable import AppLibraryTV

struct TopShelfContentBuilderTests {

    // MARK: Fixtures

    private func header(_ name: String, uuid: String) -> ABI.AppProfileHeader {
        ABI.AppProfileHeader(
            id: Profile.ID(uuidString: uuid)!,
            name: name,
            moduleTypes: [],
            primaryModuleType: nil,
            secondaryModuleTypes: nil,
            fingerprint: uuid,
            sharingFlags: [],
            requiredFeatures: []
        )
    }

    private let uuidA = "00000000-0000-0000-0000-00000000000A"

    private let uuidB = "00000000-0000-0000-0000-00000000000B"

    private let uuidC = "00000000-0000-0000-0000-00000000000C"

    // MARK: Ordering

    @Test
    func givenNoLastUsed_whenBuildingItems_thenFirstAlphabeticalIsFeatured() {
        let headers = [
            header("Zebra", uuid: uuidA),
            header("apple", uuid: uuidB),
            header("Mango", uuid: uuidC)
        ]
        let items = TopShelfContentBuilder.items(headers: headers, lastUsedProfileId: nil, tunnelState: nil)

        #expect(items.map(\.title) == ["apple", "Mango", "Zebra"])
        #expect(items.first?.subtitle == nil)
    }

    @Test
    func givenLastUsed_whenBuildingItems_thenLastUsedIsFirst() {
        let headers = [
            header("Zebra", uuid: uuidA),
            header("apple", uuid: uuidB)
        ]
        let items = TopShelfContentBuilder.items(
            headers: headers,
            lastUsedProfileId: Profile.ID(uuidString: uuidA),
            tunnelState: nil
        )

        #expect(items.map(\.title) == ["Zebra", "apple"])
    }

    @Test
    func givenLastUsedMissing_whenBuildingItems_thenFallsBackToAlphabetical() {
        let headers = [header("apple", uuid: uuidB)]
        let items = TopShelfContentBuilder.items(
            headers: headers,
            lastUsedProfileId: Profile.ID(uuidString: uuidC),
            tunnelState: nil
        )

        #expect(items.map(\.title) == ["apple"])
    }

    @Test
    func givenMoreProfilesThanLimit_whenBuildingItems_thenCapped() {
        let headers = (0..<12).map {
            header("Profile \($0)", uuid: String(format: "00000000-0000-0000-0000-%012d", $0))
        }
        let items = TopShelfContentBuilder.items(headers: headers, lastUsedProfileId: nil, tunnelState: nil)

        #expect(items.count == TopShelfContentBuilder.maxItems)
    }

    // MARK: Status subtitle

    @Test
    func givenConnectedStateForFeatured_whenBuildingItems_thenSubtitleIsConnected() {
        let headers = [header("apple", uuid: uuidB)]
        let state = TunnelWidgetState(
            kind: .connected,
            profileId: uuidB,
            profileName: "apple"
        )
        let items = TopShelfContentBuilder.items(headers: headers, lastUsedProfileId: nil, tunnelState: state)

        #expect(items.first?.subtitle == "Connected")
    }

    @Test
    func givenConnectedStateForOtherProfile_whenBuildingItems_thenNoSubtitle() {
        let headers = [
            header("apple", uuid: uuidB),
            header("Zebra", uuid: uuidA)
        ]
        let state = TunnelWidgetState(
            kind: .connected,
            profileId: uuidA,
            profileName: "Zebra"
        )
        let items = TopShelfContentBuilder.items(headers: headers, lastUsedProfileId: nil, tunnelState: state)

        #expect(items.first { $0.title == "apple" }?.subtitle == nil)
    }

    @Test
    func givenNoProfiles_whenBuildingItems_thenEmpty() {
        let items = TopShelfContentBuilder.items(headers: [], lastUsedProfileId: nil, tunnelState: nil)

        #expect(items.isEmpty)
    }

    // MARK: Identifiers & deep links

    @Test
    func whenBuildingItems_thenIdentifiersAndURLsMatchProfileIds() throws {
        let headers = [header("apple", uuid: uuidB)]
        let items = TopShelfContentBuilder.items(headers: headers, lastUsedProfileId: nil, tunnelState: nil)

        let item = try #require(items.first)
        #expect(item.identifier == "profile:\(uuidB)")
        #expect(item.url?.absoluteString == "ghosttunnel://connect/\(uuidB)")
    }

    // MARK: Deep-link parsing

    @Test
    func givenValidDeepLink_whenParsing_thenReturnsProfileId() throws {
        let url = try #require(URL(string: "ghosttunnel://connect/\(uuidB)"))
        let parsed = TopShelfContentBuilder.profileId(fromDeepLink: url)

        #expect(parsed == Profile.ID(uuidString: uuidB))
    }

    @Test
    func givenForeignURLs_whenParsing_thenReturnsNil() {
        let urls = [
            URL(string: "https://connect/\(uuidB)"),
            URL(string: "ghosttunnel://other/\(uuidB)"),
            URL(string: "ghosttunnel://connect/not-a-uuid"),
            URL(string: "ghosttunnel://connect")
        ]
        for url in urls.compactMap({ $0 }) {
            #expect(TopShelfContentBuilder.profileId(fromDeepLink: url) == nil)
        }
    }
}
