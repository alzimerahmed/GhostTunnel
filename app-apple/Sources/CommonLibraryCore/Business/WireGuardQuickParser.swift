// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Parses a wg-quick configuration (the INI text typically encoded in
/// WireGuard QR codes) into a Partout `WireGuardModule`.
///
/// This is the app-layer guarantee for QR-code WireGuard import: the camera
/// scanner (see `QRScanView`) yields the decoded text, which is fed to
/// `AppImportExport.importedProfile` and ends up here when the payload is a
/// wg-quick configuration.
///
/// Parsing is strict about secret material (keys must be 32-byte base64) and
/// lenient about unrecognized keys/sections, which are ignored.
public struct WireGuardQuickParser: Sendable {
    public init() {
    }

    // MARK: API

    public func module(fromContents contents: String) throws -> WireGuardModule {
        let builder = try configurationBuilder(fromContents: contents)
        return try WireGuardModule.Builder(configurationBuilder: builder).build()
    }

    public func configurationBuilder(fromContents contents: String) throws -> WireGuard.Configuration.Builder {
        var privateKey = ""
        var addresses: [String] = []
        var dns: DNSModule.Builder?
        var mtu: UInt16?
        var hasInterface = false
        var peers: [WireGuard.RemoteInterface.Builder] = []
        var peerKeys = Set<String>()
        var section: Section?

        for rawLine in contents.lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            if line.hasPrefix("["), line.hasSuffix("]") {
                switch line.dropFirst().dropLast().lowercased() {
                case "interface":
                    guard !hasInterface else {
                        throw ABI.AppError.importError(message: Strings.multipleInterfaces)
                    }
                    hasInterface = true
                    section = .interface
                case "peer":
                    section = .peer
                default:
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
                    let servers = entries.filter(Self.isIPAddressLike)
                    let domains = entries.filter { !Self.isIPAddressLike($0) }
                    dns = DNSModule.Builder(
                        servers: servers,
                        domains: domains.nilIfEmpty
                    )
                case "mtu":
                    guard let parsedMTU = UInt16(value) else {
                        throw ABI.AppError.importError(message: Strings.invalidMTU)
                    }
                    mtu = parsedMTU
                default:
                    // ListenPort and unrecognized keys are ignored.
                    break
                }

            case .peer:
                switch key {
                case "publickey":
                    try validateBase64Key(value, message: Strings.invalidPublicKey)
                    guard peerKeys.insert(value).inserted else {
                        throw ABI.AppError.importError(message: Strings.duplicatedPublicKey)
                    }
                    peers.append(WireGuard.RemoteInterface.Builder(publicKey: value))

                case "presharedkey", "allowedips", "endpoint", "persistentkeepalive":
                    guard !peers.isEmpty else {
                        // Key before any PublicKey: ignore the stray line.
                        break
                    }
                    var lastPeer = peers.removeLast()
                    switch key {
                    case "presharedkey":
                        try validateBase64Key(value, message: Strings.invalidPresharedKey)
                        lastPeer.preSharedKey = value
                    case "allowedips":
                        lastPeer.allowedIPs = parsedList(value)
                    case "endpoint":
                        lastPeer.endpoint = value
                    case "persistentkeepalive":
                        guard let keepAlive = UInt16(value) else {
                            throw ABI.AppError.importError(message: Strings.invalidKeepAlive)
                        }
                        lastPeer.keepAlive = keepAlive
                    default:
                        break
                    }
                    peers.append(lastPeer)

                default:
                    break
                }

            case .none:
                break
            }
        }

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

    /// Heuristic IP check: an IP literal only contains hex digits and
    /// separators. Domain names with hex-only labels ("cafe.com") are a
    /// known misclassification edge case, mitigated by the fact that
    /// `DNSModule` tolerates hostname servers.
    static func isIPAddressLike(_ entry: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF.:")
        guard !entry.isEmpty, entry.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return false
        }
        return entry.contains(".") || entry.contains(":")
    }
}
