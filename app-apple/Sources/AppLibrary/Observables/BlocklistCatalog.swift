// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import Foundation

public struct BlocklistCatalog: Decodable, Equatable, Sendable {
    public struct Source: Decodable, Equatable, Sendable {
        public let url: URL
        public let format: String
        public let sha256: String
    }

    public struct DoHEndpoint: Decodable, Equatable, Sendable, Identifiable {
        public let name: String
        public let url: URL
        public var id: String { url.absoluteString }
    }

    public let schema: String
    public let name: String
    public let sources: [Source]
    public let dohEndpoints: [DoHEndpoint]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let name = try container.decode(String.self, forKey: .name)
        let sources = try container.decode([Source].self, forKey: .sources)
        let endpoints = try container.decode([DoHEndpoint].self, forKey: .dohEndpoints)
        guard schema == "ghosttunnel-blocklist-v1",
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sources.allSatisfy({
                  Self.isHTTPS($0.url) && $0.url.user == nil && $0.url.password == nil && $0.format == "hosts"
                      && $0.sha256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil
              }),
              endpoints.allSatisfy({
                  Self.isHTTPS($0.url) && $0.url.user == nil && $0.url.password == nil
                      && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              Set(endpoints.map { Self.resolverIdentity($0.url) }).count == endpoints.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid blocklist catalog"))
        }
        self.schema = schema
        self.name = name
        self.sources = sources
        dohEndpoints = endpoints
    }

    public static func decode(_ json: JSON?) -> Self? {
        guard let json, let data = try? JSONEncoder().encode(json) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    private static func resolverIdentity(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.port == 443 {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

private extension BlocklistCatalog {
    enum CodingKeys: String, CodingKey { case schema, name, sources, dohEndpoints }
}

public enum BlocklistDNSSelection {
    public static func applying(_ endpoint: BlocklistCatalog.DoHEndpoint, to original: DNSModule.Builder) -> DNSModule.Builder {
        var builder = original
        builder.protocolType = .https
        builder.dohURL = endpoint.url.absoluteString
        builder.dotHostname = ""
        builder.inheritsVPN = false
        return builder
    }

    public static func applyingVPNProvidedDNS(to original: DNSModule.Builder) -> DNSModule.Builder {
        var builder = original
        builder.inheritsVPN = true
        return builder
    }
}
