// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Parses a Tailscale-style configuration file (the JSON consumed by
/// `tailscaled --config`, Phase 10, Feature #19).
///
/// Tailscale's coordination-server model means a config file contains NO
/// tunnel credentials (no WireGuard private key, no peer endpoints): nodes
/// derive keys from the coordination server. Nothing in the file can produce
/// a usable GhostTunnel profile. The parser therefore:
/// - validates and summarizes the file (so the user gets a real parse result,
///   not a silent failure),
/// - extracts what is human-mappable (hostname, DNS settings, advertised
///   routes, ACL count) as migration notes,
/// - explains that the correct migration path is exporting a WireGuard
///   configuration from the Tailscale client and importing that instead.
public struct TailscaleConfigParser: Sendable {
    public struct Result: Sendable, Equatable {
        public let suggestedName: String?

        public let notes: [String]
    }

    public init() {
    }

    // MARK: Limits (hostile-input surface)

    public static let maxConfigSize = 4 * 1_024 * 1_024

    // MARK: API

    /// Throws on malformed JSON; returns notes on a well-formed Tailscale
    /// config (which is never directly importable).
    public func parse(data: Data) throws -> Result {
        guard !data.isEmpty, data.count <= Self.maxConfigSize else {
            throw ABI.AppError.importError(message: Strings.invalidConfig)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // JSONSerialization throws its own error on malformed JSON;
            // rethrow as an import error for a consistent surface.
            do {
                _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch {
                throw ABI.AppError.importError(message: "Invalid JSON: \(error.localizedDescription)")
            }
            throw ABI.AppError.importError(message: Strings.invalidConfig)
        }

        var notes: [String] = []
        notes.append(Strings.coordinationServer)

        if let hostname = object["hostname"] as? String, !hostname.isEmpty {
            notes.append(Strings.hostname(hostname))
        }
        if let dns = object["dns"] as? [String: Any] {
            if let resolvers = dns["resolvers"] as? [Any], !resolvers.isEmpty {
                notes.append(Strings.dnsResolvers(resolvers.count))
            }
            if let searchDomains = dns["searchDomains"] as? [Any], !searchDomains.isEmpty {
                notes.append(Strings.searchDomains(searchDomains.count))
            }
        }
        if let acls = object["acls"] as? [Any] {
            notes.append(Strings.acls(acls.count))
        }
        if object["advertiseExitNode"] != nil || object["advertiseRoutes"] != nil {
            notes.append(Strings.advertisedRoutes)
        }
        if object["authKey"] != nil {
            notes.append(Strings.authKey)
        }
        notes.append(Strings.migrationPath)
        return Result(suggestedName: object["hostname"] as? String, notes: notes)
    }

    enum Strings {
        static let invalidConfig = "Not a valid Tailscale configuration file"
        static let coordinationServer = "Tailscale uses a coordination server; this file contains no tunnel credentials"
        static let migrationPath = "To migrate a Tailscale node, export a WireGuard configuration from the Tailscale client and import that instead"
        static let authKey = "The auth key is an enrollment secret and is not reusable here"
        static func hostname(_ name: String) -> String {
            "Node hostname: \(name)"
        }
        static func dnsResolvers(_ count: Int) -> String {
            "\(count) DNS resolver(s) defined — re-enter them in the profile's DNS settings"
        }
        static func searchDomains(_ count: Int) -> String {
            "\(count) DNS search domain(s) defined — re-enter them in the profile's DNS settings"
        }
        static func acls(_ count: Int) -> String {
            "\(count) ACL rule(s) — network access rules have no GhostTunnel equivalent"
        }
        static let advertisedRoutes = "Subnet routing/exit-node settings have no GhostTunnel equivalent"
    }
}
