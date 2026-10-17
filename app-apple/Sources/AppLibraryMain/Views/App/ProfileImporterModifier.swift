// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import CommonLibrary
import SwiftUI

struct ProfileImporterModifier: ViewModifier {
    @Environment(\.appImportExport)
    private var appImportExport

    let profileObservable: ProfileObservable

    @Binding
    var isPresented: Bool

    let errorHandler: ErrorHandler

    @State
    private var importer = ProfileImporter()

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true,
                onCompletion: handleResult
            )
            .onReceive(AppPipe.importer) {
                handleResult(.success($0))
            }
            .alert(
                Strings.Views.App.Toolbar.importFile,
                isPresented: $importer.isPresentingPassphrase,
                presenting: importer.nextURL,
                actions: actions,
                message: message
            )
            .sheet(isPresented: Binding(
                // Single-presentation rule: only present the results sheet
                // once the file importer has dismissed (Phase 10 review).
                get: { !isPresented && importer.isPresentingResults },
                set: { importer.isPresentingResults = $0 }
            )) {
                ImportResultsView(results: importer.results) {
                    importer.dismissResults()
                }
            }
    }
}

private extension ProfileImporterModifier {
    @ViewBuilder
    func actions(for url: URL) -> some View {
        SecureField(
            Strings.Placeholders.secret,
            text: $importer.currentPassphrase
        )
        Button(Strings.Alerts.Import.Passphrase.ok) {
            Task {
                try await importer.reImport(url: url, block: doImport)
            }
        }
        Button(Strings.Global.Actions.cancel, role: .cancel) {
            importer.cancelImport()
        }
    }

    func message(for url: URL) -> some View {
        Text(Strings.Alerts.Import.Passphrase.message(url.lastPathComponent))
    }

    func doImport(url: URL, passphrase: String?) async throws -> AppImportExport.FileImportResult {
        let result = try appImportExport.importedFile(
            from: .file(url),
            passphrase: passphrase
        )
        if let profile = result.profile {
            try await profileObservable.saveImported(profile)
        }
        return result
    }

    func handleResult(_ result: Result<[URL], Error>) {
        Task.detached {
            do {
                let urls = try result.get()
                try await importer.tryImport(urls: urls, block: doImport)
            } catch {
                await errorHandler.handle(
                    error,
                    title: Strings.Views.App.Toolbar.importFile,
                    message: Strings.Errors.App.Import.generic
                )
            }
        }
    }
}
