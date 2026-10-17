// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Errors surfaced by `BackupManager`.
public enum BackupError: Error, Equatable, Sendable {
    /// Encrypted archive imported without a passphrase.
    case emptyPassphrase

    /// Export requested with no profiles.
    case emptyBackup

    /// Archive is not a valid GhostTunnel backup.
    case corruptedArchive

    /// Wrong passphrase (AES-GCM authentication failure).
    case decryptionFailed

    /// PBKDF2 key derivation failed.
    case keyDerivationFailed

    /// Entry exceeds the ZIP format limits.
    case oversizedEntry

    /// Too many entries for the ZIP format limits.
    case tooManyEntries

    /// JSON encoding/decoding of a profile failed.
    case encodingFailed
}

/// Exports/imports profiles to/from a portable backup archive.
///
/// Archive format (see `BackupCrypto`): "GTBK" container wrapping a ZIP of
/// one JSON profile per entry. With a passphrase, the whole archive is
/// AES-GCM encrypted (PBKDF2-HMAC-SHA256 key derivation). Without a
/// passphrase, secrets are REDACTED from the exported profiles so that no
/// plaintext key material ever leaves the app.
///
/// The class is stateless and `Sendable`; heavy work (PBKDF2, ZIP, JSON) runs
/// off the caller's actor via `Task.detached`.
public final class BackupManager: Sendable {
    private let archiveCoder: any BackupArchiveCoding

    public init(archiveCoder: any BackupArchiveCoding = ZipBackupArchiveCoder()) {
        self.archiveCoder = archiveCoder
    }

    // MARK: Export

    /// - Parameters:
    ///   - profiles: profiles to export.
    ///   - passphrase: when non-nil and non-empty, encrypts the archive;
    ///     otherwise exports with secrets redacted.
    public func exportArchive(
        from profiles: [Profile],
        passphrase: String?
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { [archiveCoder] in
            try Self.export(
                from: profiles,
                passphrase: passphrase,
                archiveCoder: archiveCoder
            )
        }.value
    }

    // MARK: Import

    /// - Parameters:
    ///   - passphrase: required when the archive is encrypted, ignored
    ///     otherwise.
    /// - Returns: the profiles found in the archive, ready to be saved.
    public func importArchive(
        _ data: Data,
        passphrase: String?
    ) async throws -> [Profile] {
        try await Task.detached(priority: .userInitiated) { [archiveCoder] in
            try Self.importArchive(
                data,
                passphrase: passphrase,
                archiveCoder: archiveCoder
            )
        }.value
    }
}

// MARK: - Pure implementation

extension BackupManager {
    static func export(
        from profiles: [Profile],
        passphrase: String?,
        archiveCoder: any BackupArchiveCoding
    ) throws -> Data {
        guard !profiles.isEmpty else {
            throw BackupError.emptyBackup
        }

        let isEncrypted = !(passphrase ?? "").isEmpty
        var entries: [BackupEntry] = []
        var usedNames = Set<String>()
        for profile in profiles {
            let exportProfile = isEncrypted ? profile : try redactedSecrets(of: profile)
            let baseName = sanitizedFilename(from: exportProfile.name)
            let isDuplicate = !usedNames.insert(baseName).inserted
            let entryName = isDuplicate
                ? "\(baseName).\(profile.id.uuidString).json"
                : "\(baseName).json"
            let json = try JSONEncoder.shared().encodeJSON(exportProfile.asTaggedProfile)
            entries.append(BackupEntry(name: entryName, data: Data(json.utf8)))
        }
        let payload = try archiveCoder.encode(entries)
        return try BackupCrypto.wrap(payload, passphrase: passphrase)
    }

    static func importArchive(
        _ data: Data,
        passphrase: String?,
        archiveCoder: any BackupArchiveCoding
    ) throws -> [Profile] {
        let payload = try BackupCrypto.unwrap(data, passphrase: passphrase)
        let entries = try archiveCoder.decode(payload)
        guard !entries.isEmpty else {
            throw BackupError.corruptedArchive
        }
        let legacyDecoder = LegacyProfileDecoder()
        return try entries.map { entry in
            let string = String(decoding: entry.data, as: UTF8.self)
            do {
                return try JSONDecoder.shared()
                    .decode(TaggedProfile.self, from: entry.data)
                    .asProfile()
            } catch {
                // Fall back to the legacy profile format.
                return try legacyDecoder.profile(fromString: string)
            }
        }
    }

    /// Redact secret material from a profile for unencrypted exports:
    /// WireGuard private/preshared keys and OpenVPN passwords. The resulting
    /// profile is still importable, the user just needs to re-enter secrets.
    static func redactedSecrets(of profile: Profile) throws -> Profile {
        var builder = profile.builder()
        builder.modules = try builder.modules.map { module in
            if let wg = module as? WireGuardModule {
                var configuration = wg.configuration?.builder()
                    ?? WireGuard.Configuration.Builder(privateKey: "")
                configuration.interface.privateKey = ""
                configuration.peers = configuration.peers.map { peer in
                    var peer = peer
                    peer.preSharedKey = nil
                    return peer
                }
                return try WireGuardModule.Builder(configurationBuilder: configuration).build()
            }
            if let ovpn = module as? OpenVPNModule {
                guard let credentials = ovpn.credentials else {
                    return module
                }
                var credentialsBuilder = credentials.builder()
                credentialsBuilder.password = ""
                let newModule = try OpenVPNModule.Builder(
                    configurationBuilder: ovpn.configuration?.builder()
                        ?? OpenVPN.Configuration.Builder(),
                    credentials: credentialsBuilder.build()
                ).build()
                return newModule
            }
            return module
        }
        return try builder.build()
    }

    static func sanitizedFilename(from name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:")
        let components = name.components(separatedBy: invalid)
        let sanitized = components
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "profile" : sanitized
    }
}
