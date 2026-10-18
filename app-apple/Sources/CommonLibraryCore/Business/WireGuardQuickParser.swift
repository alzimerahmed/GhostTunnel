// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation
import Partout

/// Parses a wg-quick configuration (the INI text typically encoded in
/// WireGuard QR codes) into a Partout `WireGuardModule`.
///
/// This is the app-layer guarantee for QR-code WireGuard import: the camera
/// scanner (see `QRScanView`) yields the decoded text, which is fed to
/// `AppImportExport.importedProfile` and ends up here when the payload is a
/// wg-quick configuration.
///
/// Parsing is strict about secret material (keys must be 32-byte base64) and
/// lenient about unrecognized keys/sections, which are reported as warnings
/// (Phase 10: full wg-quick superset — Table, FwMark, SaveConfig, Pre/Post
/// Up/Down hooks and ListenPort are recognized and ignored with a warning
/// instead of silently dropped).
public struct WireGuardQuickParser: Sendable {
    public init() {
    }

    // MARK: API

    /// Parse result with the non-fatal warnings collected along the way
    /// (unsupported wg-quick directives, unrecognized keys).
    public struct ParseOutcome: Sendable {
        public let builder: WireGuard.Configuration.Builder

        public let warnings: [String]
    }

    public func parseOutcome(fromContents contents: String) throws -> ParseOutcome {
        var warnings: [String] = []
        let builder = try configurationBuilder(fromContents: contents, warnings: &warnings)
        return ParseOutcome(builder: builder, warnings: warnings)
    }

    public func module(fromContents contents: String) throws -> WireGuardModule {
        let builder = try configurationBuilder(fromContents: contents)
        return try WireGuardModule.Builder(configurationBuilder: builder).build()
    }

    public func configurationBuilder(fromContents contents: String) throws -> WireGuard.Configuration.Builder {
        var warnings: [String] = []
        return try configurationBuilder(fromContents: contents, warnings: &warnings)
    }

    private func configurationBuilder(
        fromContents contents: String,
        warnings: inout [String]
    ) throws -> WireGuard.Configuration.Builder {
        var privateKey = ""
        var addresses: [String] = []
        var dns: DNSModule.Builder?
        var mtu: UInt16?
        var hasInterface = false
        var peers: [WireGuard.RemoteInterface.Builder] = []
        var peerKeys = Set<String>()
        var section: Section?
        // Peer fields buffered until they can be attributed to a peer:
        // merged when `PublicKey` arrives (fields before it) or when the
        // section ends (fields after it), so field order does not matter.
        var pendingPeer = PendingPeer()
        var hasPendingPeer = false
        var peerSeenInCurrentSection = false

        func flushPendingPeer() {
            guard hasPendingPeer else {
                return
            }
            if peerSeenInCurrentSection, !peers.isEmpty {
                peers[peers.count - 1].merge(pendingPeer)
            }
            pendingPeer = PendingPeer()
            hasPendingPeer = false
            peerSeenInCurrentSection = false
        }

        for rawLine in contents.split(omittingEmptySubsequences: false, whereSeparator: .isNewline) {
            // Strip a UTF-8 BOM that may lead the first line.
            let line = rawLine.trimmingCharacters(in: .whitespaces)
                .trimmingPrefix("\u{feff}")
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            if line.hasPrefix("["), line.hasSuffix("]") {
                switch line.dropFirst().dropLast().lowercased() {
                case "interface":
                    guard !hasInterface else {
                        throw ABI.AppError.importError(message: Strings.multipleInterfaces)
                    }
                    flushPendingPeer()
                    hasInterface = true
                    section = .interface
                case "peer":
                    flushPendingPeer()
                    section = .peer
                default:
                    flushPendingPeer()
                    warnings.append(Strings.unrecognizedSection(
                        String(line.dropFirst().dropLast())
                    ))
                    section = nil
                }
                continue
            }

            guard let currentSection = section,
                  let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<separator]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)

            switch currentSection {
            case .interface:
                guard hasInterface else {
                    throw ABI.AppError.importError(message: Strings.noInterface)
                }
                switch key {
                case "privatekey":
                    try validateBase64Key(value, message: Strings.invalidPrivateKey)
                    privateKey = value
                case "address":
                    addresses = parsedList(value)
                case "dns":
                    let entries = parsedList(value)
                    var servers = entries.filter(Self.isIPAddress)
                    let domains = entries.filter { !Self.isIPAddress($0) }
                    // A domain-only DNS line would make `DNSModule.build()`
                    // throw `emptyServers`; fall back to public resolvers
                    // while keeping the search domains.
                    if servers.isEmpty, !domains.isEmpty {
                        servers = Self.defaultDNSServers
                    }
                    dns = DNSModule.Builder(
                        servers: servers,
                        domains: domains.nilIfEmpty
                    )
                case "mtu":
                    guard let parsedMTU = UInt16(value) else {
                        throw ABI.AppError.importError(message: Strings.invalidMTU)
                    }
                    mtu = parsedMTU
                case "table", "fwmark", "saveconfig":
                    // Recognized wg-quick directives with no counterpart in
                    // the profile model: ignore with a warning.
                    warnings.append(Strings.unsupportedDirective(key))
                case "preup", "postup", "predown", "postdown":
                    warnings.append(Strings.unsupportedHooks)
                case "listenport":
                    // Client profiles bind an ephemeral local port.
                    warnings.append(Strings.unsupportedListenPort)
                default:
                    warnings.append(Strings.unrecognizedKey(key, section: "Interface"))
                    break
                }

            case .peer:
                switch key {
                case "publickey":
                    try validateBase64Key(value, message: Strings.invalidPublicKey)
                    guard peerKeys.insert(value).inserted else {
                        throw ABI.AppError.importError(message: Strings.duplicatedPublicKey)
                    }
                    var peer = WireGuard.RemoteInterface.Builder(publicKey: value)
                    peer.merge(pendingPeer)
                    peers.append(peer)
                    pendingPeer = PendingPeer()
                    hasPendingPeer = false
                    peerSeenInCurrentSection = true

                case "presharedkey", "allowedips", "endpoint", "persistentkeepalive":
                    hasPendingPeer = true
                    switch key {
                    case "presharedkey":
                        try validateBase64Key(value, message: Strings.invalidPresharedKey)
                        pendingPeer.preSharedKey = value
                    case "allowedips":
                        pendingPeer.allowedIPs = parsedList(value)
                    case "endpoint":
                        pendingPeer.endpoint = value
                    case "persistentkeepalive":
                        guard let keepAlive = UInt16(value) else {
                            throw ABI.AppError.importError(message: Strings.invalidKeepAlive)
                        }
                        pendingPeer.keepAlive = keepAlive
                    default:
                        break
                    }

                default:
                    warnings.append(Strings.unrecognizedKey(key, section: "Peer"))
                    break
                }
            }
        }
        flushPendingPeer()

        guard hasInterface else {
            throw ABI.AppError.importError(message: Strings.noInterface)
        }
        guard !privateKey.isEmpty else {
            throw ABI.AppError.importError(message: Strings.missingPrivateKey)
        }
        guard !peers.isEmpty else {
            throw ABI.AppError.importError(message: Strings.emptyPeers)
        }
        var interface = WireGuard.Configuration.Builder(privateKey: privateKey).interface
        interface.addresses = addresses
        interface.dns = dns
        interface.mtu = mtu
        return WireGuard.Configuration.Builder(
            interface: interface,
            peers: peers
        )
    }
}

// MARK: - Helpers

private extension WireGuardQuickParser {
    enum Section {
        case interface

        case peer
    }

    /// Per-peer fields buffered until the peer's `PublicKey` line arrives.
    struct PendingPeer {
        var preSharedKey: String?

        var endpoint: String?

        var allowedIPs: [String] = []

        var keepAlive: UInt16?
    }

    enum Strings {
        static let multipleInterfaces = "Multiple [Interface] sections"
        static let noInterface = "Missing [Interface] section"
        static let invalidPrivateKey = "Invalid interface private key"
        static let invalidPublicKey = "Invalid peer public key"
        static let invalidPresharedKey = "Invalid preshared key"
        static let duplicatedPublicKey = "Duplicated peer public key"
        static let invalidMTU = "Invalid MTU"
        static let invalidKeepAlive = "Invalid persistent keepalive"
        static let missingPrivateKey = "Missing interface private key"
        static let emptyPeers = "No peers defined"
        static func unsupportedDirective(_ key: String) -> String {
            "Unsupported wg-quick directive '\(key)' was ignored"
        }
        static let unsupportedHooks = "PreUp/PostUp/PreDown/PostDown hook commands are not supported and were ignored"
        static let unsupportedListenPort = "ListenPort is not configurable for client profiles and was ignored"
        static func unrecognizedKey(_ key: String, section: String) -> String {
            "Unrecognized option '\(key)' in [\(section)] was ignored"
        }
        static func unrecognizedSection(_ name: String) -> String {
            "Unrecognized section [\(name)] was ignored"
        }
    }

    func parsedList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            .filter {
                !$0.isEmpty
            }
    }

    func validateBase64Key(_ value: String, message: String) throws {
        guard let keyData = Data(base64Encoded: value), keyData.count == 32 else {
            throw ABI.AppError.importError(message: message)
        }
    }

    /// Real IP-literal check via Partout's `Address` parser, so that
    /// domain names like "cafe.de" are never misclassified as IPs.
    static func isIPAddress(_ entry: String) -> Bool {
        guard let address = Address(rawValue: entry) else {
            return false
        }
        return address.isIPAddress
    }

    /// Fallback resolvers for domain-only `DNS =` lines.
    static let defaultDNSServers = ["1.1.1.1", "8.8.8.8"]
}

private extension WireGuard.RemoteInterface.Builder {
    mutating func merge(_ pending: WireGuardQuickParser.PendingPeer) {
        preSharedKey = pending.preSharedKey
        endpoint = pending.endpoint
        allowedIPs = pending.allowedIPs
        keepAlive = pending.keepAlive
    }
}
