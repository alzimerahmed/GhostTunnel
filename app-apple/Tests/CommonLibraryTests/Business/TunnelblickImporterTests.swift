// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Compression
import Foundation
import Testing

struct TunnelblickImporterTests {
    private let sut = TunnelblickImporter()

    private static let caCert = """
    -----BEGIN CERTIFICATE-----
    MIIBszCCAVmgAwIBAgIUKbGw
    -----END CERTIFICATE-----
    """

    private static let clientKey = """
    -----BEGIN PRIVATE KEY-----
    MIIEvQIBADANBgkqhkiG9w0B
    -----END PRIVATE KEY-----
    """

    private static let openVPNConfig = """
    client
    dev tun
    remote vpn.example.com 1194
    ca ca.crt
    cert client.crt
    key client.key
    tls-auth ta.key 0
    verb 3
    """

    // MARK: Entry-path validation (zip-slip)

    @Test
    func givenEntryPathTraversal_whenReadEntries_thenThrows() {
        for hostile in ["../evil.conf", "/abs/path.conf", "a/../../b.conf", "..\\evil.conf", "C:\\evil.conf", "", ".", "a/./b.conf"] {
            let entries = [
                BackupEntry(name: hostile, data: Data(Self.openVPNConfig.utf8))
            ]
            #expect(throws: (any Error).self) {
                _ = try sut.contents(fromEntries: entries)
            }
        }
    }

    @Test
    func givenSafeEntryPaths_whenReadEntries_thenSucceeds() throws {
        let entries = [
            BackupEntry(name: "config.tblk/client.ovpn", data: Data(Self.openVPNConfig.utf8)),
            BackupEntry(name: "config.tblk/ca.crt", data: Data(Self.caCert.utf8)),
            BackupEntry(name: "config.tblk/client.key", data: Data(Self.clientKey.utf8)),
            BackupEntry(name: "config.tblk/ta.key", data: Data("secret-material\n".utf8))
        ]
        let contents = try sut.contents(fromEntries: entries)
        #expect(contents.mainConfig.contains("<ca>"))
        #expect(contents.mainConfig.contains("<key>"))
        #expect(contents.mainConfig.contains("<tls-auth>"))
        #expect(contents.mainConfig.contains("key-direction 0"))
        #expect(!contents.mainConfig.contains("ca ca.crt"))
    }

    @Test
    func givenMissingKeyFile_whenReadEntries_thenWarnsAndKeepsLine() throws {
        let entries = [
            BackupEntry(name: "client.ovpn", data: Data(Self.openVPNConfig.utf8))
        ]
        let contents = try sut.contents(fromEntries: entries)
        #expect(contents.mainConfig.contains("ca ca.crt"))
        #expect(contents.warnings.contains { $0.contains("ca.crt") })
    }

    @Test
    func givenNoConfigEntry_whenReadEntries_thenThrows() {
        let entries = [BackupEntry(name: "readme.txt", data: Data("hi".utf8))]
        #expect(throws: (any Error).self) {
            _ = try sut.contents(fromEntries: entries)
        }
    }

    @Test
    func givenWireGuardConfInPackage_whenReadEntries_thenPassesThroughUnmodified() throws {
        let wg = """
        [Interface]
        PrivateKey = \(base64Key(0x11))

        [Peer]
        PublicKey = \(base64Key(0x22))
        """
        let entries = [BackupEntry(name: "tunnel.conf", data: Data(wg.utf8))]
        let contents = try sut.contents(fromEntries: entries)
        #expect(contents.mainConfig == wg)
    }

    @Test
    func givenTooManyEntries_whenReadEntries_thenThrows() {
        let entries = (0..<TunnelblickImporter.maxEntries + 1).map {
            BackupEntry(name: "f\($0).txt", data: Data())
        }
        #expect(throws: (any Error).self) {
            _ = try sut.contents(fromEntries: entries)
        }
    }

    @Test
    func givenOversizedTotal_whenReadEntries_thenThrows() {
        let entries = [
            BackupEntry(name: "a.conf", data: Data(count: TunnelblickImporter.maxTotalSize + 1))
        ]
        #expect(throws: (any Error).self) {
            _ = try sut.contents(fromEntries: entries)
        }
    }

    // MARK: ZIP round-trips (stored + deflate)

    @Test
    func givenStoredZip_whenReadArchive_thenParsesConfig() throws {
        let entries = [
            BackupEntry(name: "client.ovpn", data: Data(Self.openVPNConfig.utf8)),
            BackupEntry(name: "ca.crt", data: Data(Self.caCert.utf8))
        ]
        let zipData = try ZipBackupArchiveCoder().encode(entries)
        let contents = try sut.readArchive(data: zipData)
        #expect(contents.mainConfig.contains("<ca>"))
    }

    @Test
    func givenDeflatedZip_whenReadArchive_thenInflatesAndParsesConfig() throws {
        let entries = [
            BackupEntry(name: "client.ovpn", data: Data(Self.openVPNConfig.utf8)),
            BackupEntry(name: "ca.crt", data: Data(Self.caCert.utf8)),
            BackupEntry(name: "client.key", data: Data(Self.clientKey.utf8))
        ]
        let zipData = try Self.deflatedZip(from: entries)
        let contents = try sut.readArchive(data: zipData)
        #expect(contents.mainConfig.contains("<ca>"))
        #expect(contents.mainConfig.contains("<key>"))
    }

    @Test
    func givenDeflateBomb_whenReadArchive_thenThrowsInsteadOfExploding() throws {
        // Highly compressible payload far above the per-entry cap.
        let bomb = Data(repeating: 0x41, count: TunnelblickImporter.maxEntrySize * 2)
        let zipData = try Self.deflatedZip(from: [
            BackupEntry(name: "client.ovpn", data: bomb)
        ])
        #expect(throws: (any Error).self) {
            _ = try sut.readArchive(data: zipData)
        }
    }

    @Test
    func givenTruncatedZip_whenReadArchive_thenThrows() {
        #expect(throws: (any Error).self) {
            _ = try sut.readArchive(data: Data([0x50, 0x4b, 0x03, 0x04, 0x00]))
        }
    }

    // MARK: Directory package

    @Test
    func givenDirectoryPackage_whenReadDirectory_thenParsesConfig() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appending(component: "gt-tblk-\(UUID().uuidString)")
            .appendingPathComponent("config.tblk")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: base.deletingLastPathComponent())
        }
        try Data(Self.openVPNConfig.utf8).write(to: base.appendingPathComponent("client.ovpn"))
        try Data(Self.caCert.utf8).write(to: base.appendingPathComponent("ca.crt"))

        let contents = try sut.readDirectory(at: base)
        #expect(contents.mainConfig.contains("<ca>"))
    }

    // MARK: Helpers

    private func base64Key(_ seed: UInt8) -> String {
        Data((0..<32).map { _ in seed }).base64EncodedString()
    }

    /// Build a ZIP whose entries use method 8 (raw deflate via the system
    /// Compression framework), exercising the Phase 10 decode path.
    private static func deflatedZip(from entries: [BackupEntry]) throws -> Data {
        var body = Data()
        var central = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let deflated = Self.deflate(entry.data)
            let crc = CRC32.checksum(of: entry.data)
            let compressedSize = UInt32(deflated.count)
            let uncompressedSize = UInt32(entry.data.count)

            var local = Data()
            local.appendLE(UInt32(0x0403_4b50))
            local.appendLE(UInt16(20))
            local.appendLE(UInt16(0))
            local.appendLE(UInt16(8)) // deflate
            local.appendLE(UInt16(0))
            local.appendLE(UInt16(0))
            local.appendLE(crc)
            local.appendLE(compressedSize)
            local.appendLE(uncompressedSize)
            local.appendLE(UInt16(nameData.count))
            local.appendLE(UInt16(0))
            local.append(nameData)
            local.append(deflated)

            var directory = Data()
            directory.appendLE(UInt32(0x0201_4b50))
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(8))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(crc)
            directory.appendLE(compressedSize)
            directory.appendLE(uncompressedSize)
            directory.appendLE(UInt16(nameData.count))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt32(0))
            directory.appendLE(offset)
            directory.append(nameData)

            body.append(local)
            central.append(directory)
            offset += UInt32(local.count)
        }

        var eocd = Data()
        eocd.appendLE(UInt32(0x0605_4b50))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt32(central.count))
        eocd.appendLE(offset)
        eocd.appendLE(UInt16(0))

        return body + central + eocd
    }

    private static func deflate(_ data: Data) -> Data {
        let destCapacity = max(data.count, 64)
        let dest = UnsafeMutablePointer<UInt8>.allocate(capacity: destCapacity)
        defer {
            dest.deallocate()
        }
        let written = data.withUnsafeBytes { src in
            compression_encode_buffer(
                dest, destCapacity,
                src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        return Data(bytes: dest, count: written)
    }
}
