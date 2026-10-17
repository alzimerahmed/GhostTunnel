// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Foundation
import Testing

struct TailscaleConfigParserTests {
    private let sut = TailscaleConfigParser()

    private static let validConfig = """
    {
      "version": "0.1.0",
      "hostname": "workstation",
      "authKey": "secret-enrollment-key",
      "acls": [{"action": "accept", "src": ["*"]}],
      "dns": {
        "resolvers": ["1.1.1.1"],
        "searchDomains": ["example.com"]
      },
      "advertiseExitNode": true
    }
    """

    @Test
    func givenValidTailscaleConfig_whenParse_thenReturnsNotesAndNeverAProfile() throws {
        let result = try sut.parse(data: Data(Self.validConfig.utf8))
        #expect(result.suggestedName == "workstation")
        #expect(result.notes.contains { $0.contains("coordination server") })
        #expect(result.notes.contains { $0.contains("WireGuard") })
        #expect(result.notes.contains { $0.contains("1 DNS resolver") })
        #expect(result.notes.contains { $0.contains("1 ACL rule") })
    }

    @Test
    func givenMalformedJSON_whenParse_thenThrows() {
        #expect(throws: (any Error).self) {
            _ = try sut.parse(data: Data("{not json".utf8))
        }
    }

    @Test
    func givenEmptyData_whenParse_thenThrows() {
        #expect(throws: (any Error).self) {
            _ = try sut.parse(data: Data())
        }
    }

    @Test
    func givenOversizedConfig_whenParse_thenThrows() {
        let huge = Data(repeating: UInt8(0x61), count: TailscaleConfigParser.maxConfigSize + 1)
        #expect(throws: (any Error).self) {
            _ = try sut.parse(data: huge)
        }
    }

    @Test
    func givenMinimalConfig_whenParse_thenStillExplainsMigrationPath() throws {
        let result = try sut.parse(data: Data(#"{"hostname": "n1"}"#.utf8))
        #expect(result.suggestedName == "n1")
        #expect(!result.notes.isEmpty)
    }

    @Test
    func givenDeeplyNestedJSON_whenParse_thenThrowsOrSucceedsNeverCrashes() {
        var json = ""
        for _ in 0..<2_000 {
            json += "{\"a\":"
        }
        json += "1"
        for _ in 0..<2_000 {
            json += "}"
        }
        // Foundation's JSON parser has its own depth limit; either outcome is
        // fine as long as it does not crash.
        _ = try? sut.parse(data: Data(json.utf8))
    }
}
