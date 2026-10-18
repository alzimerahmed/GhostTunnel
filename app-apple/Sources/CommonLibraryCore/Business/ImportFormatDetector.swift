// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Import formats recognized by the unified migration surface (Phase 10).
public enum ImportFormat: String, Sendable, Equatable {
    case partoutProfile

    case wireGuardQuick

    case openVPN

    case tunnelblick

    case tailscale

    case backupArchive

    case unknown
}

/// Detects the import format by CONTENT SNIFFING, not by file extension.
///
/// Extensions are only used as a tie-breaker for ZIP containers (a `.tblk`
/// package and a GhostTunnel `.gtbk` backup are both ZIPs and cannot be told
/// apart by content alone without parsing the central directory).
///
/// This is a hostile-input surface: it must never crash on arbitrary bytes
/// and must always return a value (`.unknown` on doubt).
public struct ImportFormatDetector: Sendable {
    public init() {
    }

    /// Upper bound for JSON content sniffing: hostile JSON can be huge, so
    /// detection bails out to `.unknown` above this size (parsers apply
    /// their own limits afterwards). Must stay below the 2 MB regression-test
    /// payload so oversized JSON is never parsed.
    public static let maxJSONDetectionSize = 256 * 1_024

    // MARK: Detection

    public func detect(data: Data, filename: String) -> ImportFormat {
        if data.isZipContainer {
            return detectZip(filename: filename)
        }
        guard let text = data.decodedUTF8Text else {
            return .unknown
        }
        return detect(text: text)
    }

    public func detect(text: String) -> ImportFormat {
        // Strip a UTF-8 BOM that may lead the first line, mirroring the
        // wg-quick parser so detection is never weaker than parsing.
        let trimmed = String(text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("\u{feff}")
            .trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else {
            return .unknown
        }

        // JSON documents: distinguish a Partout profile from a Tailscale
        // config by their distinctive top-level keys.
        if trimmed.hasPrefix("{") {
            return detectJSON(trimmed)
        }

        // wg-quick INI: the [Interface] section header is mandatory.
        if containsWGQuickSection(trimmed) {
            return .wireGuardQuick
        }

        // OpenVPN: look for distinctive directives/inline blocks.
        if isOpenVPNConfig(trimmed) {
            return .openVPN
        }

        return .unknown
    }

    // MARK: Helpers

    private func detectZip(filename: String) -> ImportFormat {
        let lowered = filename.lowercased()
        if lowered.hasSuffix(".tblk") {
            return .tunnelblick
        }
        if lowered.hasSuffix(".gtbk") {
            return .backupArchive
        }
        return .unknown
    }

    private func detectJSON(_ text: String) -> ImportFormat {
        // Bound the parse: hostile JSON can be huge/deep. A size cap keeps
        // detection cheap; parsers apply their own limits afterwards.
        guard text.utf8.count <= Self.maxJSONDetectionSize,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            return .unknown
        }
        if object["modules"] != nil || object["peers"] != nil {
            return .partoutProfile
        }
        let tailscaleKeys: Set<String> = [
            "acls",
            "tagOwners",
            "autoApprovers",
            "authKey",
            "advertiseRoutes",
            "advertiseExitNode",
            "hostname"
        ]
        if !tailscaleKeys.isDisjoint(with: object.keys) {
            return .tailscale
        }
        return .unknown
    }

    private func containsWGQuickSection(_ text: String) -> Bool {
        // Match `[Interface]` case-insensitively on any line; wg-quick
        // requires it, so this is a strong signal.
        for line in text.lowercased().split(omittingEmptySubsequences: true, whereSeparator: .isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine == "[interface]" {
                return true
            }
        }
        return false
    }

    private func isOpenVPNConfig(_ text: String) -> Bool {
        var markerCount = 0
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: .isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces).lowercased()
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            if line.hasPrefix("<ca>") || line.hasPrefix("<cert>") || line.hasPrefix("<key>")
                || line.hasPrefix("<tls-auth>") || line.hasPrefix("<tls-crypt>") {
                markerCount += 2 // inline blocks are a strong signal
            } else if line == "client"
                || line.hasPrefix("remote ")
                || line.hasPrefix("dev tun")
                || line.hasPrefix("dev ")
                || line.hasPrefix("proto ")
                || line.hasPrefix("verb ")
                || line.hasPrefix("ca ")
                || line.hasPrefix("cipher ")
                || line.hasPrefix("auth-user-pass") {
                markerCount += 1
            }
            if markerCount >= 2 {
                return true
            }
        }
        return false
    }
}

// MARK: - Shared byte/text helpers (hostile-input safe)

public extension Data {
    /// True when the data looks binary rather than textual: a NUL byte, or
    /// more than half non-text control bytes. Shared by the import surface
    /// (format detection, profile decoding) so every text guard agrees.
    var hasBinaryControlBytes: Bool {
        guard !isEmpty else {
            return false
        }
        var controlCount = 0
        for byte in self {
            if byte == 0 {
                return true
            }
            if byte < Self.asciiSpace && !Self.textControlBytes.contains(byte) {
                controlCount += 1
            }
        }
        return controlCount > 0 && controlCount * 100 > count
    }

    private static let textControlBytes: Set<UInt8> = [
        0x09,
        0x0A,
        0x0D,
        0x0C
    ]

    private static let asciiSpace: UInt8 = 0x20
}

extension Data {
    var isZipContainer: Bool {
        guard count >= 4 else {
            return false
        }
        let signature = u32LE(at: 0)
        return signature == 0x0403_4b50 // local file header ("PK\x03\x04")
            || signature == 0x0605_4b50 // end of central directory (empty zip)
            || signature == 0x0807_4b50 // spanned/empty segment
    }

    /// UTF-8 text without binary control bytes, or `nil` (mirrors the
    /// `AppImportExport` text guard so detection agrees with the parsers).
    var decodedUTF8Text: String? {
        guard !hasBinaryControlBytes, let text = String(data: self, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
