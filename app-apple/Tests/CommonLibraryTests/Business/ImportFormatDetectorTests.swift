// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Foundation
import Testing

struct ImportFormatDetectorTests {
    private let sut = ImportFormatDetector()

    private static let wgQuick = """
    [Interface]
    PrivateKey = \(Data((0..<32).map { _ in UInt8(0x11) }).base64EncodedString())

    [Peer]
    PublicKey = \(Data((0..<32).map { _ in UInt8(0x22) }).base64EncodedString())
    Endpoint = vpn.example.com:51820
    """

    private static let openVPN = """
    client
    dev tun
    proto udp
    remote vpn.example.com 1194
    ca ca.crt
    cert client.crt
    key client.key
    verb 3
    """

    @Test
    func givenWGQuickText_whenDetect_thenWireGuardQuick() {
        #expect(sut.detect(text: Self.wgQuick) == .wireGuardQuick)
        #expect(sut.detect(text: Self.wgQuick.lowercased()) == .wireGuardQuick)
    }

    @Test
    func givenOpenVPNText_whenDetect_thenOpenVPN() {
        #expect(sut.detect(text: Self.openVPN) == .openVPN)
        #expect(sut.detect(text: "<ca>\nMIIB\n</ca>\nremote vpn.example.com 1194\n") == .openVPN)
    }

    @Test
    func givenPartoutProfileJSON_whenDetect_thenPartoutProfile() throws {
        let json = #"{"name": "x", "modules": [], "version": 3}"#
        #expect(sut.detect(text: json) == .partoutProfile)
    }

    @Test
    func givenTailscaleJSON_whenDetect_thenTailscale() {
        #expect(sut.detect(text: #"{"acls": [], "hostname": "node"}"#) == .tailscale)
        #expect(sut.detect(text: #"{"authKey": "secret"}"#) == .tailscale)
        #expect(sut.detect(text: #"{"tagOwners": {}}"#) == .tailscale)
    }

    @Test
    func givenUnrelatedJSON_whenDetect_thenUnknown() {
        #expect(sut.detect(text: #"{"foo": 1}"#) == .unknown)
    }

    @Test
    func givenZipBytes_whenDetect_thenRespectsExtension() {
        let zip = Data([0x50, 0x4b, 0x03, 0x04]) + Data(repeating: 0, count: 32)
        #expect(sut.detect(data: zip, filename: "package.tblk") == .tunnelblick)
        #expect(sut.detect(data: zip, filename: "backup.gtbk") == .backupArchive)
        #expect(sut.detect(data: zip, filename: "mystery.zip") == .unknown)
    }

    @Test
    func givenBinaryData_whenDetect_thenUnknown() {
        #expect(sut.detect(data: Data([0x00, 0x01, 0x02, 0xff]), filename: "x.bin") == .unknown)
    }

    @Test
    func givenEmptyInput_whenDetect_thenUnknown() {
        #expect(sut.detect(data: Data(), filename: "") == .unknown)
        #expect(sut.detect(text: "   \n  ") == .unknown)
    }

    @Test
    func givenOpenVPNWithWGSectionWordInsideComment_whenDetect_thenWgQuickWinsOnlyOnRealSection() {
        // A comment mentioning [Interface] must not be sniffed as wg-quick
        // unless the section header is on its own line.
        let text = "# see [interface] docs\nclient\ndev tun\nremote a 1194\n"
        #expect(sut.detect(text: text) == .openVPN)
    }

    @Test
    func givenHugeJSON_whenDetect_thenBoundedAndUnknown() {
        let huge = "{\"x\":\"" + String(repeating: "a", count: 2_000_000) + "\"}"
        #expect(sut.detect(text: huge) == .unknown)
    }
}
