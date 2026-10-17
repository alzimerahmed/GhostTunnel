// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import CommonLibrary
import SwiftUI

/// Per-file import report for the unified migration surface (Phase 10):
/// one section per imported file with its detected format, outcome and any
/// non-fatal parse warnings.
struct ImportResultsView: View {
    private static let l10n = AppLibraryMainLocalization.self

    @Environment(Theme.self)
    private var theme

    let results: [AppImportExport.FileImportResult]

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                    row(for: result)
                }
                Section {
                    EmptyView()
                } footer: {
                    Text(Self.l10n.string(
                        "views.import.results.footer",
                        fallback: "Warnings describe configuration options that were recognized but ignored."
                    ))
                }
            }
            .themeForm()
            .navigationTitle(Self.l10n.string("views.import.results.title", fallback: "Import"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Self.l10n.string("views.import.results.done", fallback: "Done"), action: onDismiss)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for result: AppImportExport.FileImportResult) -> some View {
        Section {
            LabeledContent {
                Text(formatName(result.format))
            } label: {
                Text(result.filename)
                    .themeTruncating()
            }
            switch result.status {
            case .imported(let warnings):
                Label {
                    Text(Self.l10n.string("views.import.status.imported", fallback: "Imported"))
                } icon: {
                    ThemeImage(.marked)
                }
                .foregroundStyle(theme.activeColor)
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .skipped(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(theme.errorColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func formatName(_ format: ImportFormat) -> String {
        switch format {
        case .partoutProfile:
            return Self.l10n.string("views.import.format.partout", fallback: "GhostTunnel profile")
        case .wireGuardQuick:
            return Self.l10n.string("views.import.format.wireguard", fallback: "WireGuard")
        case .openVPN:
            return Self.l10n.string("views.import.format.openvpn", fallback: "OpenVPN")
        case .tunnelblick:
            return Self.l10n.string("views.import.format.tunnelblick", fallback: "Tunnelblick")
        case .tailscale:
            return Self.l10n.string("views.import.format.tailscale", fallback: "Tailscale")
        case .backupArchive:
            return Self.l10n.string("views.import.format.backup", fallback: "Backup archive")
        case .unknown:
            return Self.l10n.string("views.import.format.unknown", fallback: "Unknown")
        }
    }
}
