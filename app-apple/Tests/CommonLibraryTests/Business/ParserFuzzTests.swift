// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Foundation
import Testing

/// Phase 10: parsers are a hostile-input surface. These property-style tests
/// feed deterministic pseudo-random, truncated and malformed inputs into
/// every new parser and assert the invariant: throw or succeed, NEVER crash
/// or hang. All randomness is seeded so failures are reproducible in CI.
struct ParserFuzzTests {
    // MARK: Deterministic PRNG (SplitMix64)

    private struct SeededRandom: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9e37_79b9_7f4a_7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
            z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
            return z ^ (z >> 31)
        }
    }

    // MARK: ImportFormatDetector

    @Test(arguments: [1, 2, 3, 4, 5])
    func givenRandomBytes_whenDetectFormat_thenNeverCrashes(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        for _ in 0..<200 {
            let length = Int.random(in: 0..<4_096, using: &rng)
            var bytes = Data(count: length)
            _ = bytes.withUnsafeMutableBytes { buffer in
                for offset in buffer.indices {
                    buffer[offset] = UInt8.random(in: 0...255, using: &rng)
                }
            }
            _ = ImportFormatDetector().detect(data: bytes, filename: "fuzz-\(seed).dat")
        }
    }

    @Test(arguments: [6, 7, 8])
    func givenTruncatedWGQuick_whenDetectAndParse_thenNeverCrashes(seed: UInt64) throws {
        let valid = """
        [Interface]
        PrivateKey = \(Data((0..<32).map { _ in UInt8(0x11) }).base64EncodedString())
        Address = 10.0.0.2/32

        [Peer]
        PublicKey = \(Data((0..<32).map { _ in UInt8(0x22) }).base64EncodedString())
        Endpoint = vpn.example.com:51820
        """
        let data = Data(valid.utf8)
        var rng = SeededRandom(seed: seed)
        let detector = ImportFormatDetector()
        let parser = WireGuardQuickParser()

        // Every prefix must be handled (throw or succeed, never crash).
        for length in 0...data.count {
            _ = detector.detect(data: data.prefix(length), filename: "x.conf")
            if let text = String(data: data.prefix(length), encoding: .utf8) {
                _ = try? parser.parseOutcome(fromContents: text)
            }
        }
        // Random byte flips must not crash either.
        for _ in 0..<100 {
            var mutated = data
            let index = Int.random(in: 0..<mutated.count, using: &rng)
            mutated[index] = UInt8.random(in: 0...255, using: &rng)
            if let text = String(data: mutated, encoding: .utf8) {
                _ = try? parser.parseOutcome(fromContents: text)
            }
            _ = detector.detect(data: mutated, filename: "x.conf")
        }
    }

    @Test(arguments: [9, 10])
    func givenRandomEntryNames_whenTunnelblickEntries_thenZipSlipAlwaysRejected(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let hostileFragments = ["..", ".", "/", "\\", ":", "", "a/../..", "/abs", "C:"]
        for _ in 0..<300 {
            var name = ""
            let parts = Int.random(in: 1...5, using: &rng)
            for _ in 0..<parts {
                name += hostileFragments.randomElement(using: &rng)!
                name += "/"
            }
            name += "config.conf"
            let entries = [BackupEntry(name: name, data: Data("x".utf8))]
            do {
                _ = try TunnelblickImporter().contents(fromEntries: entries)
                #expect(TunnelblickImporter.isValidEntryPath(name))
            } catch {
                // Rejected: acceptable unless the path was actually safe.
                #expect(!TunnelblickImporter.isValidEntryPath(name))
            }
        }
    }

    @Test(arguments: [11, 12])
    func givenRandomBytes_whenTunnelblickArchive_thenNeverCrashes(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        for _ in 0..<50 {
            let length = Int.random(in: 0..<2_048)
            var bytes = Data(count: length)
            _ = bytes.withUnsafeMutableBytes { buffer in
                for offset in buffer.indices {
                    buffer[offset] = UInt8.random(in: 0...255, using: &rng)
                }
            }
            _ = try? TunnelblickImporter().readArchive(data: bytes)
        }
    }

    @Test(arguments: [13, 14])
    func givenRandomJSONMutations_whenTailscaleParse_thenNeverCrashes(seed: UInt64) throws {
        let valid = #"{"hostname": "n1", "acls": [], "dns": {"resolvers": ["1.1.1.1"]}}"#
        let data = Data(valid.utf8)
        var rng = SeededRandom(seed: seed)
        let sut = TailscaleConfigParser()
        for _ in 0..<200 {
            var mutated = data
            let index = Int.random(in: 0..<mutated.count, using: &rng)
            mutated[index] = UInt8.random(in: 0...255, using: &rng)
            _ = try? sut.parse(data: mutated)
        }
        // Truncations of valid JSON must never crash.
        for length in 0...data.count {
            _ = try? sut.parse(data: data.prefix(length))
        }
    }

    @Test
    func givenZipBomb_whenDecode_thenBounded() throws {
        // A stored-entry header claiming a huge size must be rejected by the
        // bounds checks, not trusted.
        var zip = Data()
        zip.append(Data([0x50, 0x4b, 0x03, 0x04])) // local header signature
        zip.append(Data(repeating: 0xff, count: 64)) // garbage fields
        #expect(throws: (any Error).self) {
            _ = try ZipBackupArchiveCoder().decode(zip)
        }
    }
}
