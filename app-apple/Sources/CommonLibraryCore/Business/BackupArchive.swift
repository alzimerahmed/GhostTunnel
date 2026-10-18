// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Compression
import Foundation

/// A single named file inside a backup archive.
public struct BackupEntry: Sendable, Equatable {
    public let name: String

    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// Abstract archive I/O for profile backups. Abstracted so that archive
/// round-trip logic is unit-testable without touching the real filesystem.
public protocol BackupArchiveCoding: Sendable {
    func encode(_ entries: [BackupEntry]) throws -> Data

    func decode(_ data: Data) throws -> [BackupEntry]
}

/// Minimal ZIP archive coder using only "stored" (uncompressed) entries.
///
/// The ZIP container is chosen for portability (any OS can open it) and is
/// implemented by hand to avoid a third-party dependency. Confidentiality is
/// NOT provided by this coder: encrypted backups wrap the output of
/// `encode(_:)` in `BackupCrypto` (AES-GCM), see `BackupManager`.
///
/// Decoding also accepts "deflate" (method 8) entries via the system
/// Compression framework — Phase 10 needs this to read real-world Tunnelblick
/// `.tblk` packages, which are deflated ZIPs. Decompression is bounded
/// (incremental, capped at `maxEntrySize`) so a hostile archive cannot
/// trigger an unbounded allocation (zip bomb).
public struct ZipBackupArchiveCoder: BackupArchiveCoding {
    /// Upper bound for a single decoded entry, also the decompression cap.
    public let maxEntrySize: Int

    public init(maxEntrySize: Int = Self.defaultMaxEntrySize) {
        self.maxEntrySize = maxEntrySize
    }

    public static let defaultMaxEntrySize = 64 * 1_024 * 1_024

    /// Default cap on the number of decoded entries (zip-bomb guard).
    public static let defaultMaxEntries = 1_024

    /// Default cap on the cumulative decoded size (zip-bomb guard).
    public static let defaultMaxTotalSize = 256 * 1_024 * 1_024

    // MARK: Coding

    public func encode(_ entries: [BackupEntry]) throws -> Data {
        var body = Data()
        var central = Data()
        var offset: UInt32 = 0
        var count: UInt16 = 0

        for entry in entries {
            guard count < UInt16.max else {
                throw BackupError.tooManyEntries
            }
            let nameData = Data(entry.name.utf8)
            guard nameData.count <= UInt16.max, entry.data.count <= UInt32.max else {
                throw BackupError.oversizedEntry
            }
            let crc = CRC32.checksum(of: entry.data)
            let size = UInt32(entry.data.count)

            var local = Data()
            local.appendLE(UInt32(0x0403_4b50)) // local file header signature
            local.appendLE(UInt16(20)) // version needed to extract
            local.appendLE(UInt16(0)) // flags
            local.appendLE(UInt16(0)) // method: stored
            local.appendLE(UInt16(0)) // modification time
            local.appendLE(UInt16(0)) // modification date
            local.appendLE(crc)
            local.appendLE(size)
            local.appendLE(size)
            local.appendLE(UInt16(nameData.count))
            local.appendLE(UInt16(0)) // extra length
            local.append(nameData)
            local.append(entry.data)

            var directory = Data()
            directory.appendLE(UInt32(0x0201_4b50)) // central directory signature
            directory.appendLE(UInt16(20)) // version made by
            directory.appendLE(UInt16(20)) // version needed to extract
            directory.appendLE(UInt16(0)) // flags
            directory.appendLE(UInt16(0)) // method: stored
            directory.appendLE(UInt16(0)) // modification time
            directory.appendLE(UInt16(0)) // modification date
            directory.appendLE(crc)
            directory.appendLE(size)
            directory.appendLE(size)
            directory.appendLE(UInt16(nameData.count))
            directory.appendLE(UInt16(0)) // extra length
            directory.appendLE(UInt16(0)) // comment length
            directory.appendLE(UInt16(0)) // disk number start
            directory.appendLE(UInt16(0)) // internal attributes
            directory.appendLE(UInt32(0)) // external attributes
            directory.appendLE(offset)
            directory.append(nameData)

            body.append(local)
            central.append(directory)
            offset += UInt32(local.count)
            count += 1
        }

        var eocd = Data()
        eocd.appendLE(UInt32(0x0605_4b50)) // end of central directory signature
        eocd.appendLE(UInt16(0)) // disk number
        eocd.appendLE(UInt16(0)) // disk with central directory
        eocd.appendLE(count)
        eocd.appendLE(count)
        eocd.appendLE(UInt32(central.count))
        eocd.appendLE(offset)
        eocd.appendLE(UInt16(0)) // comment length

        return body + central + eocd
    }

    /// Decode a ZIP archive. `maxEntries` and `maxTotalSize` bound the
    /// decode itself (checked cumulatively during the entry loop) so a
    /// hostile archive cannot exhaust memory before callers apply their own
    /// limits — the Phase 7 backup/restore path uses the defaults, while
    /// Tunnelblick import passes its tighter caps.
    public func decode(_ data: Data) throws -> [BackupEntry] {
        try decode(data, maxEntries: Self.defaultMaxEntries, maxTotalSize: Self.defaultMaxTotalSize)
    }

    public func decode(
        _ data: Data,
        maxEntries: Int = Self.defaultMaxEntries,
        maxTotalSize: Int = Self.defaultMaxTotalSize
    ) throws -> [BackupEntry] {
        let eocdOffset = try endOfCentralDirectoryOffset(in: data)
        let count = Int(data.u16LE(at: eocdOffset + 10))
        guard count <= maxEntries else {
            throw BackupError.tooManyEntries
        }
        let centralSize = Int(data.u32LE(at: eocdOffset + 12))
        let centralOffset = Int(data.u32LE(at: eocdOffset + 16))
        guard centralOffset >= 0, centralSize >= 0,
              centralOffset + centralSize <= data.count else {
            throw BackupError.corruptedArchive
        }

        var entries: [BackupEntry] = []
        var totalSize = 0
        var cursor = centralOffset
        for _ in 0..<count {
            guard cursor + 46 <= data.count,
                  data.u32LE(at: cursor) == 0x0201_4b50 else {
                throw BackupError.corruptedArchive
            }
            let crc = data.u32LE(at: cursor + 16)
            let compressedSize = Int(data.u32LE(at: cursor + 20))
            let uncompressedSize = Int(data.u32LE(at: cursor + 24))
            let nameLength = Int(data.u16LE(at: cursor + 28))
            let extraLength = Int(data.u16LE(at: cursor + 30))
            let commentLength = Int(data.u16LE(at: cursor + 32))
            let localOffset = Int(data.u32LE(at: cursor + 42))
            guard cursor + 46 + nameLength <= data.count else {
                throw BackupError.corruptedArchive
            }
            guard let name = String(
                data: data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength)),
                encoding: .utf8
            ) else {
                throw BackupError.corruptedArchive
            }

            let (content, method) = try entryContent(
                in: data,
                at: localOffset,
                crc: crc,
                size: compressedSize
            )
            // Stored entries must declare matching sizes; deflated entries
            // legitimately differ (compressed vs uncompressed) and are
            // instead bounded by the per-entry decompression cap.
            switch method {
            case 0:
                guard compressedSize == uncompressedSize else {
                    throw BackupError.corruptedArchive
                }
            case 8:
                guard uncompressedSize <= maxEntrySize else {
                    throw BackupError.corruptedArchive
                }
            default:
                throw BackupError.corruptedArchive
            }
            totalSize += content.count
            guard totalSize <= maxTotalSize else {
                throw BackupError.tooLargeArchive
            }
            entries.append(BackupEntry(name: name, data: content))
            let stride = 46 + nameLength + extraLength + commentLength
            guard cursor + stride <= data.count else {
                throw BackupError.corruptedArchive
            }
            cursor += stride
        }
        return entries
    }
}

private extension ZipBackupArchiveCoder {
    func endOfCentralDirectoryOffset(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            throw BackupError.corruptedArchive
        }
        let minStart = max(0, data.count - 22 - Int(UInt16.max))
        var cursor = data.count - 22
        while cursor >= minStart {
            if data.u32LE(at: cursor) == 0x0605_4b50 {
                return cursor
            }
            cursor -= 1
        }
        throw BackupError.corruptedArchive
    }

    func entryContent(
        in data: Data,
        at localOffset: Int,
        crc: UInt32,
        size: Int
    ) throws -> (content: Data, method: UInt16) {
        guard localOffset >= 0, localOffset + 30 <= data.count,
              data.u32LE(at: localOffset) == 0x0403_4b50 else {
            throw BackupError.corruptedArchive
        }
        let method = data.u16LE(at: localOffset + 8)
        let nameLength = Int(data.u16LE(at: localOffset + 26))
        let extraLength = Int(data.u16LE(at: localOffset + 28))
        let dataStart = localOffset + 30 + nameLength + extraLength
        guard size >= 0, dataStart + size <= data.count else {
            throw BackupError.corruptedArchive
        }
        let raw = data.subdata(in: dataStart..<(dataStart + size))
        let content: Data
        switch method {
        case 0:
            content = raw
        case 8:
            content = try DeflateDecoder.inflate(raw, maxOutputSize: maxEntrySize)
        default:
            throw BackupError.corruptedArchive
        }
        guard CRC32.checksum(of: content) == crc else {
            throw BackupError.corruptedArchive
        }
        return (content, method)
    }
}

// MARK: - Raw-deflate decoding (ZIP method 8) via the Compression framework

/// Incremental raw-deflate decoder. ZIP "deflate" entries are raw DEFLATE
/// streams (no zlib header), which is exactly Apple's `COMPRESSION_ZLIB`.
/// Output is produced in bounded chunks and capped, so a lying header or a
/// decompression bomb cannot exhaust memory.
enum DeflateDecoder {
    static func inflate(_ input: Data, maxOutputSize: Int) throws -> Data {
        guard !input.isEmpty, maxOutputSize > 0 else {
            throw BackupError.corruptedArchive
        }
        let chunkSize = 64 * 1_024
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer {
            dstBuffer.deallocate()
        }

        var output = Data()
        try input.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) in
            guard let srcBase = srcRaw.baseAddress else {
                throw BackupError.corruptedArchive
            }
            var stream = compression_stream(
                dst_ptr: dstBuffer,
                dst_size: chunkSize,
                src_ptr: srcBase.assumingMemoryBound(to: UInt8.self),
                src_size: input.count,
                state: nil
            )
            let status = compression_stream_init(
                &stream,
                COMPRESSION_STREAM_DECODE,
                COMPRESSION_ZLIB
            )
            guard status.rawValue == COMPRESSION_STATUS_OK.rawValue else {
                throw BackupError.corruptedArchive
            }
            defer {
                compression_stream_destroy(&stream)
            }

            var reachedEnd = false
            while !reachedEnd {
                stream.dst_ptr = dstBuffer
                stream.dst_size = chunkSize
                let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                let result = compression_stream_process(&stream, flags)
                switch result.rawValue {
                case COMPRESSION_STATUS_OK.rawValue, COMPRESSION_STATUS_END.rawValue:
                    let produced = chunkSize - stream.dst_size
                    let isEnd = result.rawValue == COMPRESSION_STATUS_END.rawValue
                    guard produced > 0 || isEnd else {
                        // No forward progress without end-of-stream.
                        throw BackupError.corruptedArchive
                    }
                    if produced > 0 {
                        guard output.count + produced <= maxOutputSize else {
                            throw BackupError.corruptedArchive
                        }
                        output.append(dstBuffer, count: produced)
                    }
                    if isEnd {
                        reachedEnd = true
                    }
                    if stream.src_size == 0 && !isEnd && produced < chunkSize {
                        // Input exhausted but stream not finalized: with
                        // FINALIZE this means a truncated stream.
                        throw BackupError.corruptedArchive
                    }
                default:
                    throw BackupError.corruptedArchive
                }
            }
        }
        return output
    }
}

// MARK: - CRC-32 (IEEE 802.3, as required by the ZIP format)

enum CRC32 {
    private static let table: [UInt32] = {
        var table: [UInt32] = []
        table.reserveCapacity(256)
        for i in 0..<256 {
            var value = UInt32(i)
            for _ in 0..<8 {
                if value & 1 != 0 {
                    value = 0xedb8_8320 ^ (value >> 1)
                } else {
                    value >>= 1
                }
            }
            table.append(value)
        }
        return table
    }()

    static func checksum(of data: Data) -> UInt32 {
        var checksum: UInt32 = 0xffff_ffff
        for byte in data {
            checksum = table[Int((checksum ^ UInt32(byte)) & 0xff)] ^ (checksum >> 8)
        }
        return checksum ^ 0xffff_ffff
    }
}

// MARK: - Little-endian helpers

extension Data {
    func u16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8(value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8(value >> 24))
    }
}
