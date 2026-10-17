// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import SwiftUI
import UniformTypeIdentifiers

/// UTType for the `GTBK` backup container (`BackupCrypto.wrap`). Declared
/// as an exported type so the `.gtbk` extension round-trips through
/// `fileExporter`/`fileImporter`.
extension UTType {
    static let ghostTunnelBackup = UTType(
        exportedAs: "com.ghosttunnel.backup",
        conformingTo: .data
    )
}

/// Export/import all profiles to/from a portable backup archive
/// (`BackupManager`). Export is optionally encrypted with a passphrase;
/// unencrypted exports have their secrets redacted.
struct BackupView: View {
    private let profileObservable: ProfileObservable

    @State
    private var passphrase = ""

    @State
    private var isExporting = false

    @State
    private var archiveData: Data?

    @State
    private var isImporting = false

    @State
    private var isWorking = false

    @State
    private var errorHandler: ErrorHandler = .default()

    init(profileObservable: ProfileObservable) {
        self.profileObservable = profileObservable
    }

    var body: some View {
        Form {
            exportSection
            importSection
        }
        .themeForm()
        .fileExporter(
            isPresented: $isExporting,
            document: archiveData.map(BackupFile.init),
            contentType: .ghostTunnelBackup,
            defaultFilename: defaultFilename,
            onCompletion: { _ in }
        )
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.ghostTunnelBackup, .zip, .data]
        ) { result in
            Task {
                await importBackup(from: result)
            }
        }
        .withErrorHandler(errorHandler)
    }
}

// MARK: - Sections

private extension BackupView {
    var exportSection: some View {
        Section {
            ThemeSecureField(
                title: AppLibraryMainLocalization.string("settings.backup.passphrase", fallback: "Passphrase"),
                text: $passphrase,
                placeholder: AppLibraryMainLocalization.string("settings.backup.passphrase.placeholder", fallback: "optional")
            )
            Button(AppLibraryMainLocalization.string("settings.backup.export.button", fallback: "Export Archive")) {
                Task {
                    await exportProfiles()
                }
            }
            .disabled(isWorking)
        } header: {
            Text(AppLibraryMainLocalization.string("settings.backup.export.header", fallback: "Export profiles"))
        } footer: {
            Text(AppLibraryMainLocalization.string("settings.backup.export.footer", fallback: "Export all profiles to a portable archive. Without a passphrase, secrets (private keys, passwords) are removed from the export. With a passphrase, the archive is encrypted with AES-GCM."))
        }
    }

    var importSection: some View {
        Section {
            Button(AppLibraryMainLocalization.string("settings.backup.import.button", fallback: "Import Archive")) {
                isImporting = true
            }
            .disabled(isWorking)
        } header: {
            Text(AppLibraryMainLocalization.string("settings.backup.import.header", fallback: "Import profiles"))
        } footer: {
            Text(AppLibraryMainLocalization.string("settings.backup.import.footer", fallback: "Import profiles from a GhostTunnel backup archive (.gtbk). Enter the passphrase first if the archive is encrypted."))
        }
    }

    var defaultFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: Date())
        return "ghosttunnel-backup-\(stamp)"
    }
}

// MARK: - Actions

private extension BackupView {
    func exportProfiles() async {
        isWorking = true
        defer {
            isWorking = false
        }
        do {
            let profiles = await profileObservable.allProfiles()
            archiveData = try await BackupManager().exportArchive(
                from: profiles,
                passphrase: passphrase.isEmpty ? nil : passphrase
            )
            isExporting = true
        } catch {
            errorHandler.handle(
                Self.userMessage(for: error),
                title: AppLibraryMainLocalization.string("settings.backup.export.button", fallback: "Export Archive")
            )
        }
    }

    func importBackup(from result: Result<URL, Error>) async {
        isWorking = true
        defer {
            isWorking = false
        }
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                throw ABI.AppError.permissionDenied
            }
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            let data = try Data(contentsOf: url)
            let profiles = try await BackupManager().importArchive(
                data,
                passphrase: passphrase.isEmpty ? nil : passphrase
            )
            for profile in profiles {
                try await profileObservable.saveImported(profile)
            }
        } catch {
            errorHandler.handle(
                Self.userMessage(for: error),
                title: AppLibraryMainLocalization.string("settings.backup.import.button", fallback: "Import Archive")
            )
        }
    }

    static func userMessage(for error: Error) -> String {
        guard let backupError = error as? BackupError else {
            return error.localizedDescription
        }
        switch backupError {
        case .emptyPassphrase:
            return AppLibraryMainLocalization.string(
                "settings.backup.errors.empty_passphrase",
                fallback: "This archive is encrypted. Enter its passphrase first."
            )
        case .decryptionFailed:
            return AppLibraryMainLocalization.string(
                "settings.backup.errors.decryption",
                fallback: "Wrong passphrase."
            )
        case .corruptedArchive:
            return AppLibraryMainLocalization.string(
                "settings.backup.errors.corrupted",
                fallback: "Not a valid GhostTunnel backup archive."
            )
        case .emptyBackup:
            return AppLibraryMainLocalization.string(
                "settings.backup.errors.empty",
                fallback: "There are no profiles to export."
            )
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - FileDocument

private struct BackupFile: FileDocument {
    static let readableContentTypes: [UTType] = [.ghostTunnelBackup, .zip, .data]

    static let writableContentTypes: [UTType] = [.ghostTunnelBackup]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
