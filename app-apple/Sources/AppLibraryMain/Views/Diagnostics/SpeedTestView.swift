// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import CommonLibrary
import SwiftUI

/// In-app latency test for the endpoints of a multi-server profile (OpenVPN
/// remotes). Probes each endpoint, highlights the fastest, and can reorder
/// the profile's remotes so the fastest endpoint is tried first.
struct SpeedTestView: View {
    private static let l10n = AppLibraryMainLocalization.self

    @Environment(Theme.self)
    private var theme

    let profile: Profile?

    let onSave: (Profile) async throws -> Void

    @State
    private var manager = SpeedTestManager()

    @State
    private var isSaving = false

    @State
    private var saveError: String?

    private var targets: [ProbeTarget] {
        guard let profile else {
            return []
        }
        return profile.modules
            .compactMap { $0 as? OpenVPNModule }
            .flatMap { $0.configuration?.remotes ?? [] }
            .map(\.probeTarget)
    }

    var body: some View {
        Form {
            explanationSection
            actionSection
            resultsSection
        }
        .themeForm()
        .navigationTitle(localized("views.diagnostics.speed_test.title", fallback: "Speed test"))
        .alert(
            localized("views.diagnostics.speed_test.error.title", fallback: "Unable to apply"),
            isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button(Strings.Global.Nouns.ok, role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }
}

private extension SpeedTestView {
    func localized(_ key: String, fallback: String) -> String {
        Self.l10n.string(key, fallback: fallback)
    }

    var explanationSection: some View {
        Text(localized(
            "views.diagnostics.speed_test.subtitle",
            fallback: "Measures the latency of each endpoint in the active profile. Probes connect to the endpoints themselves and send no other data."
        ))
        .font(.footnote)
        .foregroundStyle(theme.valueColor)
        .themeSection(header: localized("views.diagnostics.sections.speed_test", fallback: "Speed test"))
    }

    var actionSection: some View {
        Group {
            Button {
                Task {
                    await manager.test(targets)
                }
            } label: {
                Text(localized("views.diagnostics.speed_test.run", fallback: "Run speed test"))
            }
            .disabled(manager.isRunning || targets.isEmpty)

            if let fastest = SpeedTestManager.fastest(in: manager.results), let profile {
                Button {
                    applyFastest(fastest, to: profile)
                } label: {
                    Text(localized("views.diagnostics.speed_test.apply", fallback: "Use fastest server"))
                }
                .disabled(isSaving)
            }
        }
        .themeContainer()
    }

    @ViewBuilder
    var resultsSection: some View {
        if manager.isRunning {
            ProgressView()
                .themeProgress(if: true)
                .themeSection(header: localized("views.diagnostics.sections.speed_test", fallback: "Speed test"))
        } else if targets.isEmpty {
            Text(localized(
                "views.diagnostics.speed_test.no_endpoints",
                fallback: "The active profile has no multi-server endpoints to test."
            ))
            .foregroundStyle(theme.emptyMessageColor)
            .themeEmptyMessage(fullScreen: false)
        } else if !manager.results.isEmpty {
            ForEach(manager.results, id: \.target.id) { result in
                HStack {
                    Text(result.target.id)
                        .font(.subheadline)
                        .foregroundStyle(theme.titleColor)
                        .themeTruncating()
                    Spacer()
                    if let latency = result.latency {
                        Text(AppFormatter.localizedLatency(latency))
                            .font(.subheadline)
                            .foregroundStyle(isFastest(result) ? theme.activeColor : theme.valueColor)
                    } else {
                        Text(result.error ?? Strings.Global.Nouns.error)
                            .font(.footnote)
                            .foregroundStyle(theme.errorColor)
                            .themeTruncating()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .themeSection(header: localized("views.diagnostics.sections.speed_test", fallback: "Speed test"))
            .themeAnimation(on: manager.results, category: .diagnostics)
        }
    }

    func isFastest(_ result: ProbeResult) -> Bool {
        SpeedTestManager.fastest(in: manager.results)?.target.id == result.target.id
    }

    func applyFastest(_ fastest: ProbeResult, to profile: Profile) {
        isSaving = true
        Task {
            defer {
                isSaving = false
            }
            do {
                var builder = profile.builder()
                try builder.modules.forEach {
                    guard var moduleBuilder = $0.moduleBuilder() as? OpenVPNModule.Builder else {
                        return
                    }
                    let remotes = moduleBuilder.configurationBuilder?.remotes ?? []
                    moduleBuilder.configurationBuilder?.remotes = ExtendedEndpoint.reorderedByLatency(
                        remotes,
                        results: manager.results
                    )
                    builder.saveModule(try moduleBuilder.build())
                }
                try await onSave(try builder.build())
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}

extension AppFormatter {
    static func localizedLatency(_ latency: TimeInterval) -> String {
        if latency < 1.0 {
            String(format: "%.0f ms", latency * 1000)
        } else {
            String(format: "%.2f s", latency)
        }
    }
}
