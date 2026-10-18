// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary

public struct AppImportExport: Sendable {
    public typealias ConfigBlock = @Sendable () -> Set<ABI.ConfigFlag>

    public typealias ImportProfile = @Sendable (
        _ json: String,
        _ name: String?
    ) throws -> Profile

    public typealias ImportModule = @Sendable (
        _ text: String,
        _ context: ModuleImportContext?
    ) throws -> Module

    public typealias ExportModule = @Sendable (Module) throws -> String

    private let legacyDecoder = LegacyProfileDecoder()

    // ABI proxies
    private let configBlock: ConfigBlock
    private let importModule: ImportModule
    private let exportModule: ExportModule

    public init(
        configBlock: @escaping ConfigBlock,
        importModule: @escaping ImportModule,
        exportModule: @escaping ExportModule
    ) {
        self.configBlock = configBlock
        self.importModule = importModule
        self.exportModule = exportModule
    }
}

extension AppImportExport {
    public func isEnabled(_ flag: ABI.ConfigFlag) -> Bool {
        configBlock().contains(flag)
    }

    public static let dummy = AppImportExport(
        configBlock: { [] },
        importModule: { _, _ in OnDemandModule.Builder().build() },
        exportModule: { _ in "" }
    )

    // MARK: Phase 10 — unified migration import with format detection

    /// Result of importing one file through the unified migration surface.
    public struct FileImportResult: Sendable, Equatable {
        public enum Status: Sendable, Equatable {
            /// Profile imported; warnings are non-fatal parse notes.
            case imported(warnings: [String])

            /// File recognized but not importable (e.g. Tailscale config).
            case skipped(message: String)

            /// Parsing failed.
            case failed(message: String)
        }

        public let filename: String

        public let format: ImportFormat

        public let status: Status

        /// The imported profile, when `status` is `.imported`.
        public let profile: Profile?

        public init(
            filename: String,
            format: ImportFormat,
            status: Status,
            profile: Profile? = nil
        ) {
            self.filename = filename
            self.format = format
            self.status = status
            self.profile = profile
        }
    }

    /// Import one file with content-sniffed format detection. Unlike
    /// `importedProfile`, this does not throw for a parse failure — it
    /// returns a per-file result so the UI can show a batch report. OpenVPN
    /// passphrase-required errors are still rethrown so the existing
    /// passphrase flow can re-queue the file.
    public func importedFile(from input: ABI.ProfileImporterInput, passphrase: String?) throws -> FileImportResult {
        // Hold the security-scoped access across the WHOLE body: the
        // Tunnelblick path re-reads the directory package after `rawData`
        // would have stopped access (Phase 10 review, M1).
        let scope: SecurityScope?
        let name: String
        let data: Data
        switch input {
        case .contents(let filename, let contents):
            scope = nil
            name = filename
            data = Data(contents.utf8)
        case .file(let url):
            name = url.lastPathComponent
            (scope, data) = try SecurityScope.open(url)
        }
        defer {
            scope?.stop()
        }
        let format = ImportFormatDetector().detect(data: data, filename: name)

        do {
            switch format {
            case .partoutProfile, .unknown:
                // Full profile JSON, or an unrecognized text file: run the
                // legacy fallback chain (profile JSON → wg-quick → module).
                let profile = try importedProfile(from: input, passphrase: passphrase)
                return FileImportResult(
                    filename: name,
                    format: format,
                    status: .imported(warnings: []),
                    profile: profile
                )

            case .wireGuardQuick:
                let outcome = try WireGuardQuickParser().parseOutcome(
                    fromContents: String(decoding: data, as: UTF8.self)
                )
                return FileImportResult(
                    filename: name,
                    format: .wireGuardQuick,
                    status: .imported(warnings: outcome.warnings),
                    profile: try wireGuardProfile(name: name, outcome: outcome)
                )

            case .openVPN:
                let module = try importModule(
                    String(decoding: data, as: UTF8.self),
                    openVPNContext(passphrase)
                )
                let profile = try Profile(withName: name, singleModule: module)
                return FileImportResult(
                    filename: name,
                    format: .openVPN,
                    status: .imported(warnings: []),
                    profile: profile
                )

            case .tunnelblick:
                return try importedTunnelblick(
                    name: name,
                    data: data,
                    input: input,
                    passphrase: passphrase
                )

            case .tailscale:
                let result = try TailscaleConfigParser().parse(data: data)
                return FileImportResult(
                    filename: name,
                    format: .tailscale,
                    status: .skipped(message: result.notes.joined(separator: " · "))
                )

            case .backupArchive:
                return FileImportResult(
                    filename: name,
                    format: .backupArchive,
                    status: .skipped(message: Strings.backupHint)
                )
            }
        } catch {
            // Let the passphrase flow handle OpenVPN credentials.
            let appError = ABI.AppError(error)
            if case .partout(let partoutError) = appError, partoutError.isOpenVPNPassphraseRequired {
                throw appError
            }
            return FileImportResult(
                filename: name,
                format: format,
                status: .failed(message: Self.failureMessage(appError))
            )
        }
    }

    private func importedTunnelblick(
        name: String,
        data: Data,
        input: ABI.ProfileImporterInput,
        passphrase: String?
    ) throws -> FileImportResult {
        let importer = TunnelblickImporter()
        let contents: TunnelblickImporter.Contents
        if case .file(let url) = input, isDirectoryPackage(url) {
            contents = try importer.readDirectory(at: url)
        } else {
            contents = try importer.readArchive(data: data)
        }

        var warnings = contents.warnings
        let configText = contents.mainConfig
        let profile: Profile
        if ImportFormatDetector().detect(text: configText) == .wireGuardQuick {
            let outcome = try WireGuardQuickParser().parseOutcome(fromContents: configText)
            warnings.append(contentsOf: outcome.warnings)
            profile = try wireGuardProfile(name: name, outcome: outcome)
        } else {
            let module = try importModule(configText, openVPNContext(passphrase))
            profile = try Profile(withName: name, singleModule: module)
        }
        return FileImportResult(
            filename: name,
            format: .tunnelblick,
            status: .imported(warnings: warnings),
            profile: profile
        )
    }

    // MARK: Shared construction helpers (deduped per Phase 10 review)

    private func wireGuardProfile(
        name: String,
        outcome: WireGuardQuickParser.ParseOutcome
    ) throws -> Profile {
        try Profile(
            withName: name,
            singleModule: try WireGuardModule.Builder(
                configurationBuilder: outcome.builder
            ).build()
        )
    }

    private func openVPNContext(_ passphrase: String?) -> ModuleImportContext? {
        passphrase.map { .OpenVPN(passphrase: $0) }
    }

    /// Security-scoped resource access held for the duration of an import.
    private struct SecurityScope {
        let url: URL

        let didStart: Bool

        private init(url: URL) {
            self.url = url
            self.didStart = url.startAccessingSecurityScopedResource()
        }

        /// Start access and read the file, stopping access on read failure
        /// so the scope never leaks.
        static func open(_ url: URL) throws -> (SecurityScope, Data) {
            let scope = SecurityScope(url: url)
            do {
                return (scope, try Data(contentsOf: url))
            } catch {
                scope.stop()
                throw error
            }
        }

        func stop() {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private enum Strings {
        static let backupHint = "This is a GhostTunnel backup archive — use Settings → Backup & Restore to import it"
    }

    public static func failureMessage(_ appError: ABI.AppError) -> String {
        if case .importError(let message) = appError, let message {
            return message
        }
        return String(describing: appError)
    }

    /// True when the URL points at a directory package (e.g. a `.tblk`
    /// folder handed out by the macOS file importer).
    private func isDirectoryPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    public func importedProfile(from input: ABI.ProfileImporterInput, passphrase: String?) throws -> Profile {
        let (name, contents) = try input.decodedPair()

        // Try to decode a full Partout profile first
        do {
            return try profile(fromString: contents)
        } catch {
            pspLog(.core, .debug, "Unable to decode profile for import: \(error)")
        }

        // Fall back to parsing a wg-quick configuration (e.g. QR payload)
        do {
            let wgModule = try WireGuardQuickParser().module(fromContents: contents)
            return try Profile(withName: name, singleModule: wgModule)
        } catch {
            pspLog(.core, .debug, "Not a wg-quick configuration: \(error)")
        }

        // Fall back to parsing a single module
        do {
            let importedModule = try importModule(contents, openVPNContext(passphrase))
            return try Profile(withName: name, singleModule: importedModule)
        } catch {
            pspLog(.core, .error, "Unable to import profile module: \(error)")
            throw error
        }
    }

    public func importedModule(from input: ABI.ProfileImporterInput, context: ModuleImportContext?) throws -> Module {
        let (_, contents) = try input.decodedPair()
        return try importModule(contents, context)
    }

    public func exportedModule(from module: Module) throws -> String {
        try exportModule(module)
    }
}

extension AppImportExport: ProfileCoder {
    public func string(fromProfile profile: Profile) throws -> String {
        try ABI.encodeJSON(profile.asTaggedProfile)
    }

    public func profile(fromString string: String) throws -> Profile {
        if let profile = try? legacyDecoder.profile(fromString: string) {
            return profile
        }
        return try ABI.decodeJSON(TaggedProfile.self, from: string).asProfile()
    }
}

extension AppImportExport {
    public nonisolated func json(fromProfile profile: Profile) throws -> String {
        try string(fromProfile: profile)
    }

    public nonisolated func defaultFilename(for profile: Profile) -> String {
        "\(profile.name).json"
    }

    public nonisolated func writeToFile(_ profile: Profile) throws -> String {
        let string = try string(fromProfile: profile)
        let data = Data(string.utf8)
        let filename = "\(profile.id.uuidString).json"
        let path = FileManager.default.temporaryDirectory
            .appending(component: filename)
            .filePath()
        try data.write(toFile: path)
        return path
    }

    public nonisolated func writeToURL(_ profile: Profile) throws -> URL {
        let path = try writeToFile(profile)
        // Make sure to convert to URL to share actual file content
        return URL(fileURLWithPath: path)
    }
}

private extension ABI.ProfileImporterInput {
    func decodedPair() throws -> (name: String, contents: String) {
        let name: String
        let contents: String
        switch self {
        case .contents(let filename, let data):
            name = filename
            contents = try Self.decodeAsTextOrThrow(Data(data.utf8))
        case .file(let url):
            name = url.lastPathComponent
            contents = try Self.decodeAsTextOrThrow(Data(contentsOf: url))
        }
        return (name, contents)
    }

    static func decodeAsTextOrThrow(_ data: Data) throws -> String {
        guard !data.hasBinaryControlBytes, let text = String(data: data, encoding: .utf8) else {
            throw ABI.AppError.binaryFile
        }
        return text
    }
}

extension Profile {
    public init(withName name: String, singleModule: Module) throws {
        let onDemandModule = OnDemandModule.Builder().build()
        var builder = Profile.Builder()
        builder.name = name
        builder.modules = [singleModule, onDemandModule]
        builder.activeModulesIds = Set(builder.modules.map(\.id))
        self = try builder.build()
    }
}
