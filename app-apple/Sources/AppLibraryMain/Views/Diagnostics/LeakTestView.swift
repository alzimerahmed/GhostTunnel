// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import CommonLibrary
import SwiftUI

/// Local-only leak test: shows the device's public IP (via documented public
/// checker endpoints) and system DNS resolution results so the user can
/// verify the tunnel is carrying traffic. Nothing is stored or transmitted
/// beyond the check requests themselves.
struct LeakTestView: View {
    private static let l10n = AppLibraryMainLocalization.self

    @Environment(Theme.self)
    private var theme

    @State
    private var manager = LeakTestManager()

    var body: some View {
        Form {
            explanationSection
            actionSection
            switch manager.state {
            case .idle:
                EmptyView()

            case .running:
                progressSection

            case .done(let checks):
                resultsSection(checks)

            case .failed(let message):
                errorSection(message)
            }
        }
        .themeForm()
        .navigationTitle(localized("views.diagnostics.leak_test.title", fallback: "Leak test"))
    }
}

private extension LeakTestView {
    func localized(_ key: String, fallback: String) -> String {
        Self.l10n.string(key, fallback: fallback)
    }

    var explanationSection: some View {
        Text(localized(
            "views.diagnostics.leak_test.subtitle",
            fallback: "Checks your public IP and DNS resolution from this device only. Results are never stored or sent anywhere."
        ))
        .font(.footnote)
        .foregroundStyle(theme.valueColor)
        .themeSection(header: localized("views.diagnostics.sections.leak_test", fallback: "Leak test"))
    }

    var actionSection: some View {
        Button {
            Task {
                await manager.run()
            }
        } label: {
            Text(localized("views.diagnostics.leak_test.run", fallback: "Run leak test"))
        }
        .disabled(manager.state == .running)
        .themeContainer()
    }

    func displayLabel(for check: LeakTestCheck) -> String {
        switch check.kind {
        case .publicIP:
            localized("views.diagnostics.leak_test.public_ip", fallback: "Public IP")
        case .dnsResolution:
            check.label
        }
    }

    var progressSection: some View {
        ProgressView()
            .themeProgress(if: true)
            .themeSection(header: localized("views.diagnostics.sections.leak_test", fallback: "Leak test"))
    }

    func resultsSection(_ checks: [LeakTestCheck]) -> some View {
        ForEach(checks) { check in
            VStack(alignment: .leading, spacing: 4) {
                Text(displayLabel(for: check))
                    .font(.subheadline)
                    .foregroundStyle(theme.titleColor)
                if let error = check.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(theme.errorColor)
                } else if let value = check.value {
                    Text(value)
                        .font(.body)
                        .foregroundStyle(theme.valueColor)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .themeSection(header: localized("views.diagnostics.sections.leak_test", fallback: "Leak test"))
        .themeAnimation(on: checks, category: .diagnostics)
    }

    func errorSection(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(theme.errorColor)
            .themeSection(header: localized("views.diagnostics.sections.leak_test", fallback: "Leak test"))
    }
}

// TODO: Phase 5 (kill switch) — when it lands, add a kill-switch state row
// here (e.g. "Kill switch: active/inactive") sourced from the Phase 5 APIs.
// Omitted for now rather than building on nonexistent plumbing.
