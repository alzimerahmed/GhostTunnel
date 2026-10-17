// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
// SPDX-License-Identifier: GPL-3.0

@testable import AppLibrary
import CommonLibrary
import Foundation
import Testing

struct BlocklistCatalogTests {
    private let digest = String(repeating: "0", count: 64)

    private func catalog(schema: String = "ghosttunnel-blocklist-v1", sourceURL: String = "https://lists.example/hosts", hash: String? = nil) -> String {
        """
        {"schema":"\(schema)","name":"Privacy catalog","sources":[{"url":"\(sourceURL)","format":"hosts","sha256":"\(hash ?? digest)"}],"dohEndpoints":[{"name":"Filtered DNS","url":"https://dns.example/query"}]}
        """
    }

    private func decode(_ value: String) -> BlocklistCatalog? {
        guard let data = value.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSON.self, from: data) else { return nil }
        return BlocklistCatalog.decode(json)
    }

    @Test
    func acceptsValidCatalogAndEmptyEndpoints() throws {
        let result = try #require(decode(catalog().replacingOccurrences(of: #"[{"name":"Filtered DNS","url":"https://dns.example/query"}]"#, with: "[]")))
        #expect(result.sources.first?.format == "hosts")
        #expect(result.dohEndpoints.isEmpty)
    }

    @Test
    func rejectsWrongSchema() {
        #expect(decode(catalog(schema: "v0")) == nil)
    }

    @Test
    func rejectsInsecureSourceURL() {
        #expect(decode(catalog(sourceURL: "http://lists.example/hosts")) == nil)
    }

    @Test
    func rejectsSourceURLUserInfo() {
        #expect(decode(catalog(sourceURL: "https://user:pass@lists.example/hosts")) == nil)
    }

    @Test
    func rejectsNonHostsSourceFormat() {
        #expect(decode(catalog().replacingOccurrences(of: #""format":"hosts""#, with: #""format":"unknown""#)) == nil)
    }

    @Test
    func rejectsInsecureAndUserInfoDoHEndpoints() {
        #expect(decode(catalog().replacingOccurrences(of: "https://dns.example/query", with: "http://dns.example/query")) == nil)
        #expect(decode(catalog().replacingOccurrences(of: "https://dns.example/query", with: "https://user:pass@dns.example/query")) == nil)
    }

    @Test
    func rejectsDuplicateResolverURLs() {
        let oneEndpoint = #""dohEndpoints":[{"name":"Filtered DNS","url":"https://dns.example/query"}]"#
        let duplicateEndpoints = #""dohEndpoints":[{"name":"Filtered DNS","url":"https://DNS.example:443/query"},{"name":"Second name","url":"https://dns.example/query"}]"#
        #expect(decode(catalog().replacingOccurrences(of: oneEndpoint, with: duplicateEndpoints)) == nil)
    }

    @Test
    func rejectsInvalidHash() {
        #expect(decode(catalog(hash: "not-a-hash")) == nil)
    }

    @Test
    func applyingEndpointSetsHTTPSURLAndDisablesVPNInheritance() throws {
        let endpoint = try #require(decode(catalog())?.dohEndpoints.first)
        var builder = DNSModule.Builder(dotHostname: "dns.example", inheritsVPN: true)
        builder = BlocklistDNSSelection.applying(endpoint, to: builder)
        #expect(builder.protocolType == .https)
        #expect(builder.dohURL == endpoint.url.absoluteString)
        #expect(builder.dotHostname.isEmpty)
        #expect(!builder.inheritsVPN)
    }

    @Test
    func applyingVPNProvidedDNSSetsInheritanceAndPreservesProtocol() {
        var builder = DNSModule.Builder(
            protocolType: .https,
            dohURL: "https://dns.example/query",
            inheritsVPN: false
        )
        builder = BlocklistDNSSelection.applyingVPNProvidedDNS(to: builder)
        #expect(builder.inheritsVPN)
        #expect(builder.protocolType == .https)
        #expect(builder.dohURL == "https://dns.example/query")
    }

    @Test @MainActor
    func observablePublishesMetadataCatalogFromActiveBridge() throws {
        let json = #"{"schema":"ghosttunnel-blocklist-v1","name":"Privacy catalog","sources":[],"dohEndpoints":[]}"#
        let metadata = try JSONDecoder().decode(JSON.self, from: Data(json.utf8))
        let observable = ConfigObservable()
        observable.onUpdate(.refresh(.init(flags: [], data: [:])), blocklistMetadata: metadata)
        #expect(observable.blocklistCatalog?.name == "Privacy catalog")
    }
}
