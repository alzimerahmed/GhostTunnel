// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Foundation
import Partout
import Testing

/// Phase 10: the wg-quick parser now covers the full wg-quick directive
/// superset — recognized-but-unsupported directives produce warnings instead
/// of being silently dropped.
struct WireGuardQuickParserSupersetTests {
    private let sut = WireGuardQuickParser()

    private static func base64Key(_ seed: UInt8) -> String {
        Data((0..<32).map { _ in seed }).base64EncodedString()
    }

    private static let privateKey = base64Key(0x11)

    private static let peerKey = base64Key(0x22)

    private static let fullSuperset = """
    [Interface]
    PrivateKey = \(base64Key(0x11))
    Address = 10.0.0.2/32
    DNS = 1.1.1.1
    MTU = 1420
    Table = off
    FwMark = 0x1234
    SaveConfig = true
    PreUp = echo up
    PostUp = echo post-up
    PreDown = echo pre-down
    PostDown = echo post-down
    ListenPort = 51820

    [Peer]
    PublicKey = \(base64Key(0x22))
    AllowedIPs = 0.0.0.0/0
    Endpoint = vpn.example.com:51820
    """

    @Test
    func givenFullSuperset_whenParse_thenSucceedsWithWarnings() throws {
        let outcome = try sut.parseOutcome(fromContents: Self.fullSuperset)
        #expect(outcome.builder.interface.privateKey == Self.privateKey)
        #expect(outcome.builder.interface.mtu == 1420)

        let warnings = outcome.warnings
        #expect(warnings.contains { $0.contains("table") })
        #expect(warnings.contains { $0.contains("fwmark") })
        #expect(warnings.contains { $0.contains("saveconfig") })
        #expect(warnings.contains { $0.contains("PreUp/PostUp") })
        #expect(warnings.contains { $0.contains("ListenPort") })
    }

    @Test
    func givenFullSuperset_whenBuildModule_thenSucceeds() throws {
        let outcome = try sut.parseOutcome(fromContents: Self.fullSuperset)
        let module = try WireGuardModule.Builder(configurationBuilder: outcome.builder).build()
        #expect(module.moduleType == .WireGuard)
    }

    @Test
    func givenMinimalConfig_whenParse_thenNoWarnings() throws {
        let contents = """
        [Interface]
        PrivateKey = \(Self.privateKey)

        [Peer]
        PublicKey = \(Self.peerKey)
        """
        let outcome = try sut.parseOutcome(fromContents: contents)
        #expect(outcome.warnings.isEmpty)
    }

    @Test
    func givenUnknownPeerOption_whenParse_thenWarnsAndContinues() throws {
        let contents = """
        [Interface]
        PrivateKey = \(Self.privateKey)

        [Peer]
        PublicKey = \(Self.peerKey)
        FutureOption = whatever
        """
        let outcome = try sut.parseOutcome(fromContents: contents)
        #expect(outcome.warnings.contains { $0.contains("FutureOption") })
        #expect(outcome.builder.peers.count == 1)
    }

    @Test
    func givenCRLFAndBOM_whenParse_thenSucceeds() throws {
        let contents = "\u{feff}[Interface]\r\nPrivateKey = \(Self.privateKey)\r\n\r\n[Peer]\r\nPublicKey = \(Self.peerKey)\r\n"
        let outcome = try sut.parseOutcome(fromContents: contents)
        #expect(outcome.builder.interface.privateKey == Self.privateKey)
    }

    @Test
    func givenMissingPrivateKey_whenParse_thenThrows() {
        #expect(throws: (any Error).self) {
            _ = try sut.parseOutcome(fromContents: "[Interface]\nAddress = 10.0.0.2/32\n")
        }
    }

    @Test
    func givenInvalidBase64Key_whenParse_thenThrows() {
        let contents = """
        [Interface]
        PrivateKey = not-base64!!

        [Peer]
        PublicKey = \(Self.peerKey)
        """
        #expect(throws: (any Error).self) {
            _ = try sut.parseOutcome(fromContents: contents)
        }
    }

    @Test
    func givenDuplicatePeerKeys_whenParse_thenThrows() {
        let contents = """
        [Interface]
        PrivateKey = \(Self.privateKey)

        [Peer]
        PublicKey = \(Self.peerKey)

        [Peer]
        PublicKey = \(Self.peerKey)
        """
        #expect(throws: (any Error).self) {
            _ = try sut.parseOutcome(fromContents: contents)
        }
    }

    @Test
    func givenNoPeers_whenParse_thenThrows() {
        let contents = "[Interface]\nPrivateKey = \(Self.privateKey)\n"
        #expect(throws: (any Error).self) {
            _ = try sut.parseOutcome(fromContents: contents)
        }
    }

    @Test
    func givenHugeLine_whenParse_thenThrowsWithoutHanging() {
        let hugeValue = String(repeating: "A", count: 1_000_000)
        let contents = "[Interface]\nPrivateKey = \(hugeValue)\n"
        #expect(throws: (any Error).self) {
            _ = try sut.parseOutcome(fromContents: contents)
        }
    }

    @Test
    func givenManyPeers_whenParse_thenAllPeersParsed() throws {
        var contents = "[Interface]\nPrivateKey = \(Self.privateKey)\n\n"
        for index in 0..<500 {
            contents += "[Peer]\nPublicKey = \(base64Key(UInt8(index % 255)))\nAllowedIPs = 10.0.\(index).0/24\n\n"
        }
        let outcome = try sut.parseOutcome(fromContents: contents)
        #expect(outcome.builder.peers.count == 500)
    }
}
