// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Container format for profile backup archives.
///
/// Layout:
///
///     "GTBK" | version (1 byte) | flags (1 byte) | payload
///
/// - Unencrypted (`flags == 0`): `payload` is the raw archive (ZIP) produced
///   by `BackupArchiveCoding`. Profiles in an unencrypted backup have their
///   secrets REDACTED by `BackupManager` (WireGuard private/preshared keys,
///   OpenVPN passwords), so no plaintext secrets are ever written to disk.
/// - Encrypted (`flags == 1`): `payload` is `salt (16 bytes) || AES-GCM box`,
///   where the box is `nonce (12) || ciphertext || tag` (`SealedBox.combined`).
///   The key is derived from the user passphrase with PBKDF2-HMAC-SHA256
///   (600k iterations, 32-byte key) via CommonCrypto, then used with
///   CryptoKit AES-GCM.
///
/// Both crypto primitives are system frameworks (CommonCrypto, CryptoKit,
/// Security): no third-party dependency, GPLv3-compatible by construction.
enum BackupCrypto {
    static let magic = Data([0x47, 0x54, 0x42, 0x4b]) // "GTBK"

    static let version: UInt8 = 1

    static let saltLength = 16

    static let keyLength = 32

    static let pbkdf2Iterations: UInt32 = 600_000

    struct Flags: OptionSet {
        let rawValue: UInt8

        static let encrypted = Flags(rawValue: 1 << 0)
    }

    // MARK: Container

    static func wrap(_ payload: Data, passphrase: String?) throws -> Data {
        var container = magic
        container.append(version)
        if let passphrase, !passphrase.isEmpty {
            container.append(Flags.encrypted.rawValue)
            let salt = randomBytes(saltLength)
            let key = try deriveKey(passphrase: passphrase, salt: salt)
            let box = try AES.GCM.seal(payload, using: key)
            guard let combined = box.combined else {
                throw BackupError.encodingFailed
            }
            container.append(salt)
            container.append(combined)
        } else {
            container.append(Flags(rawValue: 0).rawValue)
            container.append(payload)
        }
        return container
    }

    static func unwrap(_ container: Data, passphrase: String?) throws -> Data {
        let headerLength = magic.count + 2
        guard container.count > headerLength,
              container.prefix(magic.count) == magic,
              container[magic.count] == version else {
            throw BackupError.corruptedArchive
        }
        let flags = Flags(rawValue: container[magic.count + 1])
        let payload = container.subdata(in: headerLength..<container.count)
        guard flags.contains(.encrypted) else {
            return payload
        }
        guard let passphrase, !passphrase.isEmpty else {
            throw BackupError.emptyPassphrase
        }
        guard payload.count > saltLength else {
            throw BackupError.corruptedArchive
        }
        let salt = payload.prefix(saltLength)
        let combined = payload.subdata(in: saltLength..<payload.count)
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw BackupError.decryptionFailed
        }
    }

    // MARK: Key derivation

    static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        guard !passphrase.isEmpty else {
            throw BackupError.emptyPassphrase
        }
        let passphraseData = Data(passphrase.utf8)
        var keyData = Data(repeating: 0, count: keyLength)
        let status = passphraseData.withUnsafeBytes { passPtr -> Int32 in
            salt.withUnsafeBytes { saltPtr -> Int32 in
                keyData.withUnsafeMutableBytes { keyPtr -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passphraseData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Iterations,
                        keyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyData.count
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.keyDerivationFailed
        }
        return SymmetricKey(data: keyData)
    }

    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        if status != errSecSuccess {
            // Fall back to the Swift RNG, which is cryptographically secure too.
            data = Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
        }
        return data
    }
}
