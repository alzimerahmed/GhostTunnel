// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Partout
import Testing

struct BackupManagerTests {
    private static let privateKey = base64Key(0x11)

    private static let peerKey = base64Key(0x22)

    private static let presharedKey = base64Key(0x33)

    private func wireGuardProfile(name: String = "Test") throws -> Profile {
        var wgBuilder = WireGuard.Configuration.Builder(privateKey: Self.privateKey)
        var peer = WireGuard.RemoteInterface.Builder(publicKey: Self.peerKey)
        peer.preSharedKey = Self.presharedKey
        peer.allowedIPs = ["0.0.0.0/0"]
        wgBuilder.peers = [peer]
        let module = try WireGuardModule.Builder(configurationBuilder: wgBuilder).build()
        return try Profile.Builder(name: name, modules: [module]).build()
    }

    private static func base64Key(_ seed: UInt8) -> String {
        Data((0..<32).map { _ in seed }).base64EncodedString()
    }

    // MARK: Archive round-trip

    @Test
    func givenEntries_whenZipRoundTrip_thenPreservesEntries() throws {
        let coder = ZipBackupArchiveCoder()
        let entries = [
            BackupEntry(name: "a.json", data: Data("hello".utf8)),
            BackupEntry(name: "b.json", data: Data((0..<256).map { UInt8($0) }))
        ]
        let encoded = try coder.encode(entries)
        let decoded = try coder.decode(encoded)
        #expect(decoded == entries)
    }

    @Test
    func givenGarbage_whenDecodeZip_thenThrows() {
        let coder = ZipBackupArchiveCoder()
        #expect(throws: BackupError.corruptedArchive) {
            try coder.decode(Data("garbage".utf8))
        }
    }

    @Test
    func givenMalformedCentralDirectory_whenDecodeZip_thenThrowsInsteadOfCrashing() throws {
        let coder = ZipBackupArchiveCoder()
        let entries = [BackupEntry(name: "a.json", data: Data("hello".utf8))]
        let encoded = try coder.encode(entries)
        // Patch the central-directory entry's name length to claim more
        // bytes than the archive contains.
        var malformed = encoded
        let cdOffset = Int(encoded.u32LE(at: encoded.count - 22 + 16))
        malformed[cdOffset + 28] = 0xff
        malformed[cdOffset + 29] = 0xff
        #expect(throws: BackupError.corruptedArchive) {
            try coder.decode(malformed)
        }
    }

    @Test
    func givenCorruptEOC_whenDecodeZip_thenThrows() {
        let coder = ZipBackupArchiveCoder()
        var data = Data([0x50, 0x4b, 0x05, 0x06]) // EOCD signature
        data.append(Data(repeating: 0, count: 18))
        data.append(contentsOf: [0xff, 0xff, 0xff, 0xff]) // huge central size
        #expect(throws: BackupError.corruptedArchive) {
            try coder.decode(data)
        }
    }

    @Test
    func givenEncryptedExport_whenRoundTrip_thenPreservesProfiles() async throws {
        let sut = BackupManager()
        let profile = try wireGuardProfile()
        let archive = try await sut.exportArchive(from: [profile], passphrase: "secret")
        let imported = try await sut.importArchive(archive, passphrase: "secret")
        #expect(imported.count == 1)
        #expect(imported.first == profile)
    }

    @Test
    func givenEncryptedExport_whenWrongPassphrase_thenFails() async throws {
        let sut = BackupManager()
        let profile = try wireGuardProfile()
        let archive = try await sut.exportArchive(from: [profile], passphrase: "secret")
        await #expect(throws: BackupError.decryptionFailed) {
            try await sut.importArchive(archive, passphrase: "wrong")
        }
    }

    @Test
    func givenEncryptedExport_whenNoPassphrase_thenThrows() async throws {
        let sut = BackupManager()
        let profile = try wireGuardProfile()
        let archive = try await sut.exportArchive(from: [profile], passphrase: "secret")
        await #expect(throws: BackupError.emptyPassphrase) {
            try await sut.importArchive(archive, passphrase: nil)
        }
    }

    // MARK: No plaintext secrets

    @Test
    func givenEncryptedExport_whenInspectRawArchive_thenNoPlaintextSecrets() async throws {
        let sut = BackupManager()
        let profile = try wireGuardProfile()
        let archive = try await sut.exportArchive(from: [profile], passphrase: "secret")
        for secret in [Self.privateKey, Self.peerKey, Self.presharedKey] {
            #expect(archive.firstRange(of: Data(secret.utf8)) == nil)
        }
    }

    @Test
    func givenUnencryptedExport_whenInspectArchive_thenSecretsAreRedacted() async throws {
        let sut = BackupManager()
        let profile = try wireGuardProfile()
        let archive = try await sut.exportArchive(from: [profile], passphrase: nil)
        for secret in [Self.privateKey, Self.peerKey, Self.presharedKey] {
            #expect(archive.firstRange(of: Data(secret.utf8)) == nil)
        }
        // Redacted profile is still importable, with a placeholder key.
        let imported = try await sut.importArchive(archive, passphrase: nil)
        #expect(imported.count == 1)
        let wgModule = try #require(imported[0].modules.first as? WireGuardModule)
        #expect(wgModule.configuration?.builder()?.interface.privateKey == BackupManager.redactedKey)
    }

    @Test
    func givenUnencryptedExport_whenImport_thenModulesStayActive() async throws {
        let sut = BackupManager()
        let profile = try wireGuardProfile()
        let archive = try await sut.exportArchive(from: [profile], passphrase: nil)
        let imported = try await sut.importArchive(archive, passphrase: nil)
        let wgModule = try #require(imported[0].modules.first as? WireGuardModule)
        #expect(imported[0].activeModulesIds.contains(wgModule.id))
    }

    @Test
    func givenEncryptedExport_whenDecrypt_thenContainsSecrets() async throws {
        let sut = BackupManager()
        let profile = try wireGuardProfile()
        let archive = try await sut.exportArchive(from: [profile], passphrase: "secret")
        let payload = try BackupCrypto.unwrap(archive, passphrase: "secret")
        #expect(payload.firstRange(of: Data(Self.privateKey.utf8)) != nil)
    }

    // MARK: Edge cases

    @Test
    func givenNoProfiles_whenExport_thenThrows() async {
        let sut = BackupManager()
        await #expect(throws: BackupError.emptyBackup) {
            try await sut.exportArchive(from: [], passphrase: nil)
        }
    }

    @Test
    func givenProfileWithUnsafeName_whenExport_thenSanitizesFilename() async throws {
        let sut = BackupManager()
        let profile = try wireGuardProfile(name: "my/profile:name")
        let archive = try await sut.exportArchive(from: [profile], passphrase: nil)
        let payload = try BackupCrypto.unwrap(archive, passphrase: nil)
        let entries = try ZipBackupArchiveCoder().decode(payload)
        #expect(entries.count == 1)
        #expect(!entries[0].name.contains("/"))
        #expect(!entries[0].name.contains(":"))
    }

    @Test
    func givenMultipleProfilesWithSameName_whenExport_thenUniqueEntryNames() async throws {
        let sut = BackupManager()
        let profiles = [
            try wireGuardProfile(name: "same"),
            try wireGuardProfile(name: "same")
        ]
        let archive = try await sut.exportArchive(from: profiles, passphrase: nil)
        let payload = try BackupCrypto.unwrap(archive, passphrase: nil)
        let entries = try ZipBackupArchiveCoder().decode(payload)
        #expect(entries.count == 2)
        #expect(entries[0].name != entries[1].name)
    }

    @Test
    func givenOpenVPNProfile_whenUnencryptedExport_thenPasswordIsRedacted() async throws {
        var ovpnBuilder = OpenVPN.Configuration.Builder()
        ovpnBuilder.ca = OpenVPN.CryptoContainer(pem: "ca is required")
        ovpnBuilder.remotes = [
            try ExtendedEndpoint("host.name", EndpointProtocol(.tcp, 80))
        ]
        let credentials = OpenVPN.Credentials.Builder(
            username: "user",
            password: "topsecret"
        ).build()
        let module = try OpenVPNModule.Builder(
            configurationBuilder: ovpnBuilder,
            credentials: credentials
        ).build()
        let profile = try Profile.Builder(name: "ovpn", modules: [module]).build()

        let sut = BackupManager()
        let archive = try await sut.exportArchive(from: [profile], passphrase: nil)
        #expect(archive.firstRange(of: Data("topsecret".utf8)) == nil)
    }
}
