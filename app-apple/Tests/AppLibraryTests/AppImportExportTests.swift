// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

@testable import AppLibrary
@testable import CommonLibraryCore
import CommonLibrary
import Foundation
import Testing

struct AppImportExportTests {
    @Test(arguments: [1, 2, 3])
    func givenLegacyProfile_whenDecode_thenPreservesKnownModules(version: Int) throws {
        for module in try newKnownModules() {
            var builder = Profile.Builder(name: "legacy", modules: [module])
            builder.activeModulesIds = [module.id]
            builder.userInfo = .object(["source": .string("legacy")])
            let profile = try builder.build()
            let encoded = try legacyString(profile, version: version)

            let decoded = try AppImportExport.dummy.profile(fromString: encoded)

            #expect(decoded == profile)
            #expect(decoded.modules.first?.moduleType == module.moduleType)
            #expect(String(reflecting: type(of: decoded.modules[0])) == String(reflecting: type(of: module)))
        }
    }

    @Test
    func givenFlattenedV2Profile_whenDecode_thenPreservesModules() throws {
        let profile = try Profile.Builder(name: "flattened", modules: Array(newKnownModules().dropLast())).build()
        var object = try #require(JSONSerialization.jsonObject(
            with: Data(legacyString(profile, version: 2).utf8)
        ) as? [String: Any])
        let modules = try #require(object["modules"] as? [[String: Any]])
        object["modules"] = try modules.map { module in
            var payload = try #require(module["payload"] as? [String: Any])
            payload["type"] = module["moduleType"]
            return payload
        }
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let decoded = try AppImportExport.dummy.profile(fromString: encoded)
        #expect(decoded == profile)
    }

    @Test
    func givenUnversionedProfile_whenDecode_thenUpgradesWithoutChangingID() throws {
        let profile = try Profile.Builder(name: "unversioned").build()
        var object = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder.shared().encode(profile.asTaggedProfile)
        ) as? [String: Any])
        object.removeValue(forKey: "version")
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)

        let decoded = try AppImportExport.dummy.profile(fromString: encoded)

        #expect(decoded.id == profile.id)
        #expect(decoded.version == Profile.Builder.currentVersion)
    }

    @Test
    func givenCurrentProfile_whenRoundTrip_thenPreservesProfile() throws {
        let profile = try Profile.Builder(name: "current", modules: Array(newKnownModules().dropLast())).build()
        let sut = AppImportExport.dummy
        let decoded = try sut.profile(fromString: sut.string(fromProfile: profile))
        #expect(decoded == profile)
    }

    @Test
    func givenInvalidProfile_whenLegacyDecodingFails_thenThrowsABIFallbackError() {
        #expect(throws: ABI.AppError.self) {
            try AppImportExport.dummy.profile(fromString: "invalid")
        }
    }

    @Test(arguments: [2, 3])
    @MainActor
    func givenLegacyProvider_whenImportEditAndExport_thenPreservesPayloadAndActiveID(version: Int) throws {
        let moduleID = UUID()
        let provider: JSON = .object([
            "id": .string(moduleID.uuidString),
            "providerId": .string("mullvad"),
            "providerModuleType": .string("WireGuard"),
            "authentication": .object([
                "credentials": .object(["username": .string("legacy-user"), "password": .string("legacy-password")]),
                "token": .object(["accessToken": .string("legacy-token"), "expiryDate": .number(1_700_000_000_000)])
            ]),
            "moduleOptions": .object(["WireGuard": .string("e30=")]),
            "entity": .object([
                "server": .object([
                    "metadata": .object([
                        "providerId": .string("mullvad"),
                        "categoryName": .string("default"),
                        "countryCode": .string("SE")
                    ]),
                    "serverId": .string("legacy-server"),
                    "hostname": .string("vpn.example.com")
                ]),
                "preset": .object([
                    "providerId": .string("mullvad"),
                    "presetId": .string("default"),
                    "description": .string("Default"),
                    "moduleType": .string("WireGuard"),
                    "templateData": .string("e30=")
                ])
            ])
        ])
        let ip = IPModule.Builder(mtu: 1280).build()
        let tagged = TaggedProfile(
            id: UUID(), name: "Legacy provider",
            modules: [.Custom(CustomModule(innerType: .Provider, json: provider)), .IP(ip)],
            activeModulesIds: [moduleID, ip.id]
        )
        var object = try #require(JSONSerialization.jsonObject(with: ABI.encode(tagged)) as? [String: Any])
        if version == 2 {
            var legacyProvider = provider
            legacyProvider["authentication"]?["token"]?["expiryDate"] = .number(
                Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSinceReferenceDate
            )
            object["modules"] = [
                ["moduleType": "Provider", "payload": try JSONSerialization.jsonObject(with: ABI.encode(legacyProvider))],
                ["moduleType": "IP", "payload": try JSONSerialization.jsonObject(with: ABI.encode(ip))]
            ]
        }
        let string = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let sut = AppImportExport.dummy
        let profile = try sut.profile(fromString: string)
        #expect(profile.modules.map(\.id) == [moduleID, ip.id])
        #expect(profile.activeModulesIds == [moduleID, ip.id])
        #expect(!profile.isFinal)
        #expect(profile.features == [.routing])

        var providerOnly = profile.builder()
        providerOnly.activeModulesIds = [moduleID]
        #expect(try providerOnly.build().features.isEmpty)

        let editor = ProfileEditor(profile: profile)
        editor.profile.name = "Renamed"
        let edited = try editor.buildAndUpdate()
        let exported = try ABI.decodeJSON(TaggedProfile.self, from: sut.string(fromProfile: edited))
        #expect(exported.name == "Renamed")
        #expect(exported.activeModulesIds == tagged.activeModulesIds)
        #expect(exported.modules == tagged.modules)
        let roundTrip = try sut.profile(fromString: sut.string(fromProfile: edited))
        #expect(roundTrip == edited)
        #expect(roundTrip.features == [.routing])
    }

    @Test(arguments: [false, true])
    func givenCustomModule_whenImporting_thenOnlyKnownActiveModulesRequireFeatures(withRouting: Bool) throws {
        let custom = CustomModule(innerType: .Undefined, json: .object(["legacy": .string("payload")]))
        let ip = IPModule.Builder(mtu: 1280).build()
        let tagged = TaggedProfile(
            id: UUID(), name: "Custom module",
            modules: [.Custom(custom), .IP(ip)],
            activeModulesIds: withRouting ? [custom.id, ip.id] : [custom.id]
        )
        let profile = try AppImportExport.dummy.profile(fromString: ABI.encodeJSON(tagged))

        #expect(profile.activeModules.contains { $0.moduleType == .Custom })
        #expect(profile.features == (withRouting ? [.routing] : []))
    }

    @Test
    func givenModule_whenExport_thenUsesABIExporter() throws {
        let sut = AppImportExport(
            configBlock: { [] },
            importModule: { _, _ in throw ABI.AppError.importError() },
            exportModule: { _ in "exported" }
        )

        let encoded = try sut.exportedModule(from: OnDemandModule.Builder().build())

        #expect(encoded == "exported")
    }

    @Test
    func givenBinaryFile_whenImportProfile_thenThrowsBinaryFile() throws {
        let sut = AppImportExport(
            configBlock: { [] },
            importModule: { _, _ in throw ABI.AppError.importError() },
            exportModule: { _ in "" }
        )
        let url = URL.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension("bin")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        var didThrowBinaryFile = false
        do {
            _ = try sut.importedProfile(from: .file(url), passphrase: nil)
        } catch ABI.AppError.binaryFile {
            didThrowBinaryFile = true
        } catch {
            throw error
        }
        #expect(didThrowBinaryFile)
    }
}

private extension AppImportExportTests {
    func legacyString(_ profile: Profile, version: Int) throws -> String {
        if version == 3 {
            return try JSONEncoder.shared().encodeJSON(profile.asTaggedProfile)
        }
        let encoder = JSONEncoder(userInfo: [.legacySwiftEncoding: true])
        var object = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder.shared().encode(profile.asTaggedProfile)
        ) as? [String: Any])
        object["modules"] = try profile.modules.map { module -> [String: Any] in
            let encodable = try #require(module as? any Encodable)
            let data = try encoder.encode(encodable)
            if version == 1 {
                return ["id": module.moduleType.rawValue, "data": data.base64EncodedString()]
            }
            return ["moduleType": module.moduleType.rawValue,
                    "payload": try JSONSerialization.jsonObject(with: data)]
        }
        if version == 1 {
            object["userInfo"] = try profile.userInfo.map {
                try JSONEncoder.shared().encode($0).base64EncodedString()
            }
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        return version == 1 ? data.base64EncodedString() : String(decoding: data, as: UTF8.self)
    }

    func newKnownModules() throws -> [Module] {
        let dnsModule = try DNSModule.Builder(servers: ["1.1.1.1"]).build()
        let ipModule = IPModule.Builder(mtu: 1280).build()
        let httpProxyModule = try HTTPProxyModule.Builder(
            address: "1.1.1.1",
            port: 8080
        ).build()
        let onDemandModule = OnDemandModule.Builder().build()
        var openVPNConfiguration = OpenVPN.Configuration.Builder()
        openVPNConfiguration.ca = OpenVPN.CryptoContainer(pem: "ca is required")
        openVPNConfiguration.cipher = .aes128cbc
        openVPNConfiguration.remotes = [
            try ExtendedEndpoint("vpn.example.com", EndpointProtocol(.tcp, 443))
        ]
        let openVPNModule = try OpenVPNModule.Builder(
            configurationBuilder: openVPNConfiguration
        ).build()
        var wireGuardConfiguration = WireGuard.Configuration.Builder(privateKey: "")
        wireGuardConfiguration.peers = [WireGuard.RemoteInterface.Builder(publicKey: "")]
        let wireGuardModule = try WireGuardModule.Builder(
            configurationBuilder: wireGuardConfiguration
        ).build()
        return [
            dnsModule,
            httpProxyModule,
            ipModule,
            onDemandModule,
            openVPNModule,
            wireGuardModule
        ]
    }
}

// MARK: - Phase 7: WireGuard QR payload import

extension AppImportExportTests {
    @Test
    func givenWgQuickContents_whenImportedProfile_thenParsesWireGuardModule() throws {
        let privateKey = Data((0..<32).map { _ in UInt8(0x11) }).base64EncodedString()
        let peerKey = Data((0..<32).map { _ in UInt8(0x22) }).base64EncodedString()
        let contents = """
        [Interface]
        PrivateKey = \(privateKey)
        Address = 10.0.0.2/32

        [Peer]
        PublicKey = \(peerKey)
        Endpoint = vpn.example.com:51820
        """

        let profile = try AppImportExport.dummy.importedProfile(
            from: .contents(filename: "qr.txt", data: contents),
            passphrase: nil
        )

        #expect(profile.modules.first?.moduleType == .WireGuard)
    }
}

// MARK: - Phase 10: unified migration import (format detection + routing)

extension AppImportExportTests {
    private static let wgQuickContents = """
    [Interface]
    PrivateKey = \(Data((0..<32).map { _ in UInt8(0x11) }).base64EncodedString())
    Address = 10.0.0.2/32

    [Peer]
    PublicKey = \(Data((0..<32).map { _ in UInt8(0x22) }).base64EncodedString())
    Endpoint = vpn.example.com:51820
    """

    @Test
    func givenWGQuickFile_whenImportedFile_thenDetectedAndImported() throws {
        let result = try AppImportExport.dummy.importedFile(
            from: .contents(filename: "tunnel.conf", data: Self.wgQuickContents),
            passphrase: nil
        )
        #expect(result.format == .wireGuardQuick)
        guard case .imported = result.status else {
            Issue.record("Expected imported, got \(result.status)")
            return
        }
        #expect(result.profile?.modules.first?.moduleType == .WireGuard)
    }

    @Test
    func givenTailscaleFile_whenImportedFile_thenSkippedWithNotes() throws {
        let json = #"{"hostname": "node1", "acls": []}"#
        let result = try AppImportExport.dummy.importedFile(
            from: .contents(filename: "tailscaled.conf", data: json),
            passphrase: nil
        )
        #expect(result.format == .tailscale)
        #expect(result.profile == nil)
        guard case .skipped(let message) = result.status else {
            Issue.record("Expected skipped, got \(result.status)")
            return
        }
        #expect(message.contains("coordination server"))
    }

    @Test
    func givenBackupArchiveFile_whenImportedFile_thenSkippedWithHint() throws {
        let zip = Data([0x50, 0x4b, 0x03, 0x04]) + Data(repeating: 0, count: 32)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("profiles.gtbk")
        try zip.write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        let result = try AppImportExport.dummy.importedFile(
            from: .file(url),
            passphrase: nil
        )
        #expect(result.format == .backupArchive)
        guard case .skipped(let message) = result.status else {
            Issue.record("Expected skipped, got \(result.status)")
            return
        }
        #expect(message.contains("Backup"))
    }

    @Test
    func givenGarbageFile_whenImportedFile_thenFailedResultNotThrow() throws {
        let result = try AppImportExport.dummy.importedFile(
            from: .contents(filename: "garbage.txt", data: "!!garbage!!"),
            passphrase: nil
        )
        guard case .failed = result.status else {
            Issue.record("Expected failed, got \(result.status)")
            return
        }
        #expect(result.profile == nil)
    }

    @Test
    func givenTunnelblickWGPackage_whenImportedFile_thenImported() throws {
        let entries = [
            BackupEntry(name: "config.tblk/tunnel.conf", data: Data(Self.wgQuickContents.utf8))
        ]
        let zipData = try ZipBackupArchiveCoder().encode(entries)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("config.tblk")
        try zipData.write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        let result = try AppImportExport.dummy.importedFile(
            from: .file(url),
            passphrase: nil
        )
        #expect(result.format == .tunnelblick)
        guard case .imported = result.status else {
            Issue.record("Expected imported, got \(result.status)")
            return
        }
        #expect(result.profile?.modules.first?.moduleType == .WireGuard)
    }

    @Test
    func givenHostileTunnelblickPackage_whenImportedFile_thenFailedResultNotThrow() throws {
        // Zip-slip entry: must surface as a failed result, never a crash.
        let entries = [
            BackupEntry(name: "../evil.conf", data: Data("client\ndev tun\n".utf8))
        ]
        let zipData = try ZipBackupArchiveCoder().encode(entries)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("evil.tblk")
        try zipData.write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        let result = try AppImportExport.dummy.importedFile(
            from: .file(url),
            passphrase: nil
        )
        #expect(result.format == .tunnelblick)
        guard case .failed = result.status else {
            Issue.record("Expected failed, got \(result.status)")
            return
        }
    }
}
