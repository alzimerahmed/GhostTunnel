// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import CommonLibrary
import Foundation

@MainActor @Observable
final class ProfileImporter {
    typealias ImportBlock = @Sendable (URL, String?) async throws -> AppImportExport.FileImportResult

    var isPresentingPassphrase = false

    var currentPassphrase = ""

    // MARK: Phase 10 — per-file results report

    private(set) var results: [AppImportExport.FileImportResult] = []

    var isPresentingResults = false

    private(set) var urlsRequiringPassphrase: [URL] = []

    var nextURL: URL? {
        urlsRequiringPassphrase.first
    }

    func tryImport(
        urls: [URL],
        block: @escaping ImportBlock
    ) async throws {
        var withPassphrase: [URL] = []
        var newResults: [AppImportExport.FileImportResult] = []

        for url in urls {
            do {
                let result = try await importURL(
                    url,
                    withPassphrase: nil,
                    block: block
                )
                newResults.append(result)
            } catch {
                let appError = ABI.AppError(error)
                switch appError {
                case .partout(let error) where error.isOpenVPNPassphraseRequired:
                    withPassphrase.append(url)
                    continue
                default:
                    // Phase 10: a parse failure is a per-file result, not a
                    // batch abort — the report shows what failed and why.
                    pspLog(.core, .fault, "Unable to import URL: \(error)")
                    newResults.append(.init(
                        filename: url.lastPathComponent,
                        format: .unknown,
                        status: .failed(message: String(describing: appError))
                    ))
                }
            }
        }

        urlsRequiringPassphrase = withPassphrase
        appendResults(newResults)
        if !urlsRequiringPassphrase.isEmpty {
            scheduleNextImport()
        }
    }

    func reImport(
        url: URL,
        block: @escaping ImportBlock
    ) async throws {
        do {
            let result = try await importURL(
                url,
                withPassphrase: currentPassphrase,
                block: block
            )
            urlsRequiringPassphrase.removeFirst()
            appendResults([result])
            scheduleNextImport()
        } catch {
            scheduleNextImport()
            throw error
        }
    }

    func cancelImport() {
        urlsRequiringPassphrase.removeFirst()
        scheduleNextImport()
    }

    func dismissResults() {
        results = []
        isPresentingResults = false
    }
}

private extension ProfileImporter {
    func appendResults(_ newResults: [AppImportExport.FileImportResult]) {
        results.append(contentsOf: newResults)
        let needsReport = newResults.contains { result in
            switch result.status {
            case .imported(let warnings):
                return !warnings.isEmpty
            case .skipped, .failed:
                return true
            }
        }
        if needsReport {
            isPresentingResults = true
        }
    }

    func scheduleNextImport() {
        guard !urlsRequiringPassphrase.isEmpty else {
            return
        }
        Task {
            // XXX: re-present same alert after artificial delay
            try? await Task.sleep(for: .milliseconds(500))
            currentPassphrase = ""
            isPresentingPassphrase = true
        }
    }

    func importURL(
        _ url: URL,
        withPassphrase passphrase: String?,
        block: @escaping ImportBlock
    ) async throws -> AppImportExport.FileImportResult {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await block(url, passphrase)
    }
}
