// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import Foundation
import Testing
@testable import CommonLibraryCore

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
        let items = TopShelfContentBuilder.items(headers: headers, lastUsedProfileId: nil)

        #expect(items.map(\.title) == ["apple", "Mango", "Zebra"])
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

        )

        #expect(items.map(\.title) == ["Zebra", "apple"])
    }

    @Test
    func givenLastUsedMissing_whenBuildingItems_thenFallsBackToAlphabetical() {
        let headers = [header("apple", uuid: uuidB)]
        let items = TopShelfContentBuilder.items(
            headers: headers,
            lastUsedProfileId: Profile.ID(uuidString: uuidC),

        )

        #expect(items.map(\.title) == ["apple"])
    }

    @Test
    func givenMoreProfilesThanLimit_whenBuildingItems_thenCapped() {
        let headers = (0..<12).map {
            header("Profile \($0)", uuid: String(format: "00000000-0000-0000-0000-%012d", $0))
        }
        let items = TopShelfContentBuilder.items(headers: headers, lastUsedProfileId: nil)

        #expect(items.count == TopShelfContentBuilder.maxItems)
    }

    // MARK: No profiles

    @Test
    func givenNoProfiles_whenBuildingItems_thenEmpty() {
        let items = TopShelfContentBuilder.items(headers: [], lastUsedProfileId: nil)

        #expect(items.isEmpty)
    }

    // MARK: Identifiers & deep links

    @Test
    func whenBuildingItems_thenIdentifiersAndURLsMatchProfileIds() throws {
        let headers = [header("apple", uuid: uuidB)]
        let items = TopShelfContentBuilder.items(headers: headers, lastUsedProfileId: nil)

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
            URL(string: "ghosttunnel://connect"),
            URL(string: "ghosttunnel://connect/\(uuidB)/junk")
        ]
        for url in urls.compactMap({ $0 }) {
            #expect(TopShelfContentBuilder.profileId(fromDeepLink: url) == nil)
        }
    }
}
