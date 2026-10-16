// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation
import Partout
import Testing

@testable import CommonLibraryCore

/// Phase 4 — config ownership: endpoints must point at the GhostTunnel-owned
/// config repo (alzimerahmed84/ghosttunnel-config), not upstream partout.io.
@BusinessActor
struct GitHubConfigStrategyTests {
    private static let configBase = "https://raw.githubusercontent.com/alzimerahmed84/ghosttunnel-config"

    @Test
    func givenConstants_whenConfigURLs_thenPointAtGhostTunnelConfigRepo() {
        let constants = OpenAPIAppConstantsWebsites(
            partoutURL: URL(string: "https://partout.io")!,
            homeURL: URL(string: "https://partout.io/passepartout")!,
            eulaURL: URL(string: "https://example.com/eula")!,
            appStoreDownloadURL: URL(string: "https://example.com/appstore")!,
            macDownloadURL: URL(string: "https://example.com/mac")!,
            configTTL: 3600,
            betaTTLFactor: 0.1
        )
        #expect(constants.configURL.absoluteString == "\(configBase)/main/v1/bundle.json")
        #expect(constants.betaConfigURL.absoluteString == "\(configBase)/main/v1/bundle-beta.json")
    }

    @Test
    func givenExampleConfigJSON_whenDecoded_thenParsesFlags() throws {
        // Mirrors config/example.json at the GhostTunnel repo root
        // (schema: config/schema.md, v1).
        let json = """
        {
          "appNotWorking": {
            "rate": 100,
            "platforms": ["apple"],
            "minBuild": 1,
            "data": {"reason": "Example flag: marks builds with a known critical issue"}
          },
          "experimentalDaemon_202610": {
            "rate": 100,
            "minBuild": 500
          },
          "ghosttunnelBlocklistMetadata": {
            "rate": 100,
            "platforms": ["apple"],
            "data": {
              "schema": "ghosttunnel-blocklist-v1",
              "name": "GhostTunnel Basic",
              "sources": [
                {
                  "url": "https://raw.githubusercontent.com/alzimerahmed84/ghosttunnel-config/main/blocklists/basic.txt",
                  "format": "hosts",
                  "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
                }
              ],
              "dohEndpoints": []
            }
          }
        }
        """
        let sut = try ABI.decodeJSON(ConfigBundle.self, from: json)
        #expect(sut.activeFlags(withBuild: 1000) == [
            .appNotWorking,
            .experimentalDaemon_202610
        ])
        #expect(sut.activeFlags(withBuild: 100) == [.appNotWorking])
    }

    @Test
    func givenStrategy_whenFetching_thenUsesStableOrBetaURLAndParses() async throws {
        let stableURL = URL(string: "\(configBase)/main/v1/bundle.json")!
        let betaURL = URL(string: "\(configBase)/main/v1/bundle-beta.json")!
        let bundleJSON = #"{"appNotWorking":{"rate":100}}"#
        let recorder = FetchRecorder(responses: [
            stableURL: Data(bundleJSON.utf8),
            betaURL: Data(bundleJSON.utf8)
        ])

        let sut = GitHubConfigStrategy(
            url: stableURL,
            betaURL: betaURL,
            ttl: 60,
            betaTTLFactor: 0.1,
            isBeta: { false },
            fetcher: { url in
                try await recorder.fetch(url)
            }
        )
        let bundle = try await sut.bundle()
        #expect(bundle.activeFlags(withBuild: 1) == [.appNotWorking])
        #expect(await recorder.requests == [stableURL])

        // Rate limit kicks in after a successful fetch.
        do {
            _ = try await sut.bundle()
            Issue.record("Expected rate limit")
        } catch {
            guard case ABI.AppError.rateLimit = error else {
                Issue.record("Expected .rateLimit, got \(error)")
                return
            }
        }
    }
}

private actor FetchRecorder {
    private let responses: [URL: Data]
    private(set) var requests: [URL] = []

    init(responses: [URL: Data]) {
        self.responses = responses
    }

    func fetch(_ url: URL) throws -> Data {
        requests.append(url)
        guard let data = responses[url] else {
            throw FetchError.missingResponse
        }
        return data
    }
}

private enum FetchError: Error {
    case missingResponse
}
