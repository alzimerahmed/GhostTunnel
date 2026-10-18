// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Reads a Tunnelblick `.tblk` configuration set (Phase 10, Feature #19).
///
/// A `.tblk` is either a directory package or a ZIP archive containing a
/// main OpenVPN/WireGuard configuration plus referenced key/cert files.
/// This importer:
/// - unpacks the set (ZIP via `ZipBackupArchiveCoder`, or a directory walk),
/// - validates every entry path against traversal attacks (zip-slip: no
///   absolute paths, no `..` components, no backslashes, no drive letters),
/// - enforces size/count limits (zip-bomb guard),
/// - locates the main config (shallowest `.conf`/`.ovpn` entry),
/// - resolves relative key-file references by inlining them as OpenVPN
///   inline blocks (`<ca>`, `<cert>`, `<key>`, ...) so the standard partout
///   OpenVPN parser can consume the result.
///
/// It never executes anything and never writes outside memory.
public struct TunnelblickImporter: Sendable {
    public struct Contents: Sendable {
        public let mainConfig: String

        public let warnings: [String]
    }

    public init() {
    }

    // MARK: Limits (hostile-input surface)

    public static let maxEntries = 512

    public static let maxTotalSize = 32 * 1_024 * 1_024

    public static let maxEntrySize = 16 * 1_024 * 1_024

    public static let maxConfigSize = 1 * 1_024 * 1_024

    // MARK: API

    /// Read a `.tblk` ZIP archive.
    public func readArchive(data: Data) throws -> Contents {
        let coder = ZipBackupArchiveCoder(maxEntrySize: Self.maxEntrySize)
        // Bound the decode itself (zip-bomb guard): caps are enforced
        // during the entry loop, not only after a full decode.
        let entries = try coder.decode(
            data,
            maxEntries: Self.maxEntries,
            maxTotalSize: Self.maxTotalSize
        )
        return try contents(fromEntries: entries)
    }

    /// Read a `.tblk` directory package (macOS fileImporter can hand out
    /// directory URLs for packages).
    public func readDirectory(at url: URL) throws -> Contents {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ABI.AppError.importError(message: "Unable to read Tunnelblick package")
        }

        var entries: [BackupEntry] = []
        var totalSize = 0
        for case let fileURL as URL in enumerator {
            guard entries.count < Self.maxEntries else {
                throw ABI.AppError.importError(message: Strings.tooManyEntries)
            }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else {
                continue
            }
            let relativePath = fileURL.path(relativeTo: url)
            guard Self.isValidEntryPath(relativePath) else {
                throw ABI.AppError.importError(message: Strings.unsafeEntryPath(relativePath))
            }
            let size = values?.fileSize ?? 0
            totalSize += size
            guard totalSize <= Self.maxTotalSize else {
                throw ABI.AppError.importError(message: Strings.archiveTooLarge)
            }
            guard size <= Self.maxEntrySize else {
                throw ABI.AppError.importError(message: Strings.entryTooLarge(relativePath))
            }
            guard let data = try? Data(contentsOf: fileURL) else {
                throw ABI.AppError.importError(message: Strings.unreadableEntry(relativePath))
            }
            entries.append(BackupEntry(name: relativePath, data: data))
        }
        guard !entries.isEmpty else {
            throw ABI.AppError.importError(message: Strings.emptyPackage)
        }
        return try contents(fromEntries: entries)
    }

    // MARK: Core

    func contents(fromEntries entries: [BackupEntry]) throws -> Contents {
        guard entries.count <= Self.maxEntries else {
            throw ABI.AppError.importError(message: Strings.tooManyEntries)
        }
        var warnings: [String] = []
        var totalSize = 0
        for entry in entries {
            guard Self.isValidEntryPath(entry.name) else {
                throw ABI.AppError.importError(message: Strings.unsafeEntryPath(entry.name))
            }
            totalSize += entry.data.count
            guard totalSize <= Self.maxTotalSize else {
                throw ABI.AppError.importError(message: Strings.archiveTooLarge)
            }
        }

        // Main config: shallowest .conf/.ovpn entry (Tunnelblick keeps the
        // main config at the package root or in a subfolder).
        let configEntries = entries
            .filter { Self.isConfigFilename($0.name) }
            .sorted { $0.name.count < $1.name.count }
        guard let main = configEntries.first else {
            throw ABI.AppError.importError(message: Strings.noMainConfig)
        }
        if configEntries.count > 1 {
            warnings.append(Strings.multipleConfigs(configEntries.count))
        }
        guard main.data.count <= Self.maxConfigSize,
              let configText = main.data.decodedUTF8Text else {
            throw ABI.AppError.importError(message: Strings.invalidMainConfig)
        }

        // Nested .tblk sets are not recursed into.
        if entries.contains(where: { $0.name.lowercased().hasSuffix(".tblk") }) {
            warnings.append(Strings.nestedPackage)
        }

        let resolved = Self.isWireGuardConfig(configText)
            ? configText
            : Self.inlineFileReferences(in: configText, entries: entries, warnings: &warnings)
        return Contents(mainConfig: resolved, warnings: warnings)
    }

    /// Replace `ca/cert/key/dh/tls-auth/tls-crypt/crl-verify <file>` lines
    /// with inline blocks built from the referenced archive entries.
    static func inlineFileReferences(
        in config: String,
        entries: [BackupEntry],
        warnings: inout [String]
    ) -> String {
        var output: [String] = []
        for rawLine in config.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let (directive, argument) = Self.fileDirective(in: line) else {
                output.append(String(rawLine))
                continue
            }
            var inlineArgument = argument
            // `tls-auth file direction` keeps only the file argument here;
            // the direction becomes a separate key-direction line.
            var extraLine: String?
            if directive == "tls-auth" {
                let parts = argument.split(separator: " ").map(String.init)
                if parts.count > 1 {
                    extraLine = "key-direction \(parts[1])"
                }
                inlineArgument = parts.first ?? argument
            }
            guard let entry = Self.entry(named: inlineArgument, in: entries) else {
                warnings.append(Strings.missingKeyFile(inlineArgument))
                output.append(String(rawLine))
                continue
            }
            guard let pem = entry.data.decodedUTF8Text else {
                warnings.append(Strings.binaryKeyFile(inlineArgument))
                output.append(String(rawLine))
                continue
            }
            // Hostile-input guard: a key file is inlined verbatim into the
            // config, so it could otherwise break out of the inline block
            // and inject OpenVPN directives. Reject anything that is not a
            // plain PEM-like body (no angle brackets, no directive lines).
            guard Self.isSafeInlineKeyFile(pem) else {
                warnings.append(Strings.unsafeKeyFile(inlineArgument))
                output.append(String(rawLine))
                continue
            }
            let block = Self.inlineBlocks[directive] ?? directive
            output.append("<\(block)>")
            output.append(contentsOf: pem
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
                .map(String.init))
            output.append("</\(block)>")
            if let extraLine {
                output.append(extraLine)
            }
        }
        return output.joined(separator: "\n")
    }

    // MARK: Helpers

    static let inlineBlocks: [String: String] = [
        "ca": "ca",
        "cert": "cert",
        "key": "key",
        "dh": "dh",
        "tls-auth": "tls-auth",
        "tls-crypt": "tls-crypt",
        "crl-verify": "crl-verify"
    ]

    /// Ordered directive list (dict key order is nondeterministic; the
    /// longest-prefix-relevant directives are checked in a stable order).
    static let fileDirectives: [String] = [
        "ca",
        "cert",
        "key",
        "dh",
        "tls-auth",
        "tls-crypt",
        "crl-verify"
    ]

    /// Directives whose argument is a file path, and how many extra
    /// arguments they may carry.
    static func fileDirective(in line: String) -> (directive: String, argument: String)? {
        let lowered = line.lowercased()
        for directive in fileDirectives {
            guard lowered.hasPrefix("\(directive) ") else {
                continue
            }
            var argument = String(line.dropFirst(directive.count + 1))
                .trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes.
            if argument.hasPrefix("\""), argument.hasSuffix("\""), argument.count >= 2 {
                argument = String(argument.dropFirst().dropLast())
            }
            guard !argument.isEmpty else {
                return nil
            }
            return (directive, argument)
        }
        return nil
    }

    static func entry(named argument: String, in entries: [BackupEntry]) -> BackupEntry? {
        let cleaned = argument.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        // 1. Exact relative-path match.
        if let exact = entries.first(where: { $0.name == cleaned }) {
            return exact
        }
        // 2. Relative reference resolved against the package root
        //    (e.g. "sub/ca.crt" matches "package/sub/ca.crt").
        if let byPath = entries.first(where: { $0.name.hasSuffix("/\(cleaned)") }) {
            return byPath
        }
        // 3. Basename equality anywhere in the set (Tunnelblick layouts
        //    vary). Exact basename comparison — never a loose suffix, so
        //    "ca.crt" cannot match "evilca.crt".
        let base = (cleaned as NSString).lastPathComponent
        return entries.first { ($0.name as NSString).lastPathComponent == base }
    }

    /// Guard for content inlined into the OpenVPN config: reject anything
    /// containing inline-block delimiters/angle brackets or a line that
    /// looks like an OpenVPN directive, so a hostile key file cannot inject
    /// configuration (e.g. `</key>` + `remote attacker.example 443`).
    static func isSafeInlineKeyFile(_ text: String) -> Bool {
        if text.contains("<") || text.contains(">") {
            return false
        }
        let directives: Set<String> = [
            "client",
            "ca",
            "cert",
            "key",
            "dh",
            "tls-auth",
            "tls-crypt",
            "crl-verify",
            "remote",
            "proto",
            "dev",
            "verb",
            "auth-user-pass",
            "key-direction",
            "route",
            "ifconfig",
            "script-security",
            "up",
            "down"
        ]
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces).lowercased()
            guard !line.isEmpty else {
                continue
            }
            if line.hasPrefix("-----begin ") || line.hasPrefix("-----end ") {
                continue // PEM markers
            }
            let token = line.split(separator: " ").first.map(String.init) ?? line
            if directives.contains(token) {
                return false
            }
        }
        return true
    }

    static func isConfigFilename(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasSuffix(".conf") || lowered.hasSuffix(".ovpn")
    }

    static func isWireGuardConfig(_ text: String) -> Bool {
        text.lowercased().split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }).contains {
            $0.trimmingCharacters(in: .whitespaces) == "[interface]"
        }
    }

    /// Zip-slip guard: reject absolute paths, `..` components, backslashes,
    /// drive letters, and empty names.
    static func isValidEntryPath(_ name: String) -> Bool {
        guard !name.isEmpty, !name.contains("\\"), !name.contains(":") else {
            return false
        }
        guard !name.hasPrefix("/") else {
            return false
        }
        var seenComponent = false
        for component in name.split(separator: "/") {
            if component == ".." || component == "." {
                return false
            }
            seenComponent = true
        }
        return seenComponent
    }

    enum Strings {
        static let tooManyEntries = "Tunnelblick package has too many files"
        static let archiveTooLarge = "Tunnelblick package is too large"
        static let emptyPackage = "Tunnelblick package is empty"
        static let noMainConfig = "No .conf/.ovpn configuration found in Tunnelblick package"
        static let invalidMainConfig = "Main Tunnelblick configuration is invalid"
        static let nestedPackage = "Nested .tblk packages were ignored"
        static func unsafeEntryPath(_ path: String) -> String {
            "Unsafe file path in package: \(path)"
        }
        static func entryTooLarge(_ path: String) -> String {
            "File too large in package: \(path)"
        }
        static func unreadableEntry(_ path: String) -> String {
            "Unable to read file in package: \(path)"
        }
        static func multipleConfigs(_ count: Int) -> String {
            "Multiple configurations found (\(count)); used the top-level one"
        }
        static func missingKeyFile(_ name: String) -> String {
            "Referenced key file not found in package: \(name)"
        }
        static func binaryKeyFile(_ name: String) -> String {
            "Referenced key file is not a text (PEM) file: \(name)"
        }
        static func unsafeKeyFile(_ name: String) -> String {
            "Referenced key file contains unsafe content and was not inlined: \(name)"
        }
    }
}

private extension URL {
    func path(relativeTo base: URL) -> String {
        var path = absoluteString
        let baseString = base.absoluteString
        if path.hasPrefix(baseString) {
            path.removeFirst(baseString.count)
        }
        return path.hasPrefix("/") ? String(path.dropFirst()) : path
    }
}
