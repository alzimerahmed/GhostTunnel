// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import AppAccessibility
import CommonLibrary
import SwiftUI

struct DiagnosticsView: View {
    @Environment(Theme.self)
    private var theme

    @Environment(AppFormatter.self)
    private var appFormatter

    @Environment(IAPObservable.self)
    private var iapObservable

    @Environment(\.appConfiguration)
    private var appConfiguration

    @Environment(ConfigObservable.self)
    private var configObservable

    let profileObservable: ProfileObservable

    let tunnel: TunnelObservable

    var availableTunnelLogs: (() async -> [ABI.LogEntry])?

    @State
    private var logsPrivateData = false

    @State
    private var tunnelLogs: [ABI.LogEntry] = []

    @State
    var isPresentingUnableToEmail = false

    @State
    private var isExportingDebugBundle = false

    @State
    private var debugBundleURL: URL?

    var body: some View {
        Form {
            if iapObservable.isBeta {
                BetaSection()
            }
            liveLogSection
            leakTestSection
            speedTestSection
            debugBundleSection
            togglesSection
            profilesSection
            if appConfiguration.bundle.distributionTarget.supportsAppGroups {
                tunnelLogsSection
            }
            if canReportIssue {
                reportIssueSection
            }
        }
        .task {
            tunnelLogs = await computedTunnelLogs()
        }
        .themeForm()
        .alert(Strings.Views.Diagnostics.ReportIssue.title, isPresented: $isPresentingUnableToEmail) {
            Button(Strings.Global.Nouns.ok, role: .cancel) {
                isPresentingUnableToEmail = false
            }
        } message: {
            Text(Strings.Views.Diagnostics.Alerts.ReportIssue.email)
        }
    }
}

private extension DiagnosticsView {
    var liveLogSection: some View {
        Group {
            navLink(
                Strings.Views.Diagnostics.Rows.app,
                to: .appLog(title: Strings.Views.Diagnostics.Rows.app)
            )
            navLink(
                Strings.Views.Diagnostics.Rows.tunnel,
                to: .tunnelLog(title: Strings.Views.Diagnostics.Rows.tunnel, url: nil)
            )
        }
        .themeSection(header: Strings.Views.Diagnostics.Sections.live)
    }

    var togglesSection: some View {
        Group {
            ExtensiveLoggingToggle()
            LogsPrivateDataToggle()
        }
        .themeContainer()
    }

    var leakTestSection: some View {
        NavigationLink(
            localizedString("views.diagnostics.leak_test.title", fallback: "Leak test"),
            value: DiagnosticsRoute.leakTest
        )
        .themeSection(header: localizedString(
            "views.diagnostics.sections.leak_test",
            fallback: "Leak test"
        ))
    }

    var speedTestSection: some View {
        NavigationLink(
            localizedString("views.diagnostics.speed_test.title", fallback: "Speed test"),
            value: DiagnosticsRoute.speedTest
        )
        .themeSection(header: localizedString(
            "views.diagnostics.sections.speed_test",
            fallback: "Speed test"
        ))
    }

    var debugBundleSection: some View {
        Group {
            if let debugBundleURL {
#if !os(tvOS)
                ShareLink(item: debugBundleURL) {
                    Label {
                        Text(localizedString(
                            "views.diagnostics.debug_bundle.export",
                            fallback: "Export debug bundle"
                        ))
                    } icon: {
                        ThemeImage(.share)
                    }
                }
#endif
            } else {
                Button {
                    exportDebugBundle()
                } label: {
                    Text(localizedString(
                        "views.diagnostics.debug_bundle.export",
                        fallback: "Export debug bundle"
                    ))
                }
                .disabled(isExportingDebugBundle)
            }
            Text(localizedString(
                "views.diagnostics.debug_bundle.subtitle",
                fallback: "Sanitized logs and tunnel state. Key material is redacted; nothing is sent anywhere unless you share the file."
            ))
            .font(.footnote)
            .foregroundStyle(theme.valueColor)
        }
        .themeSection(
            header: localizedString("views.diagnostics.sections.debug_bundle", fallback: "Debug bundle")
        )
    }

    func localizedString(_ key: String, fallback: String) -> String {
        AppLibraryMainLocalization.string(key, fallback: fallback)
    }

    func exportDebugBundle() {
        isExportingDebugBundle = true
        Task {
            defer {
                isExportingDebugBundle = false
            }
            var sections: [DebugBundleSection] = []
            let appLogLines = pspLogCurrent(appConfiguration.constants.log)
            sections.append(DebugBundleSection(name: "App log", lines: appLogLines))
            let tunnelLogLines = await tunnel.currentLog()
            sections.append(DebugBundleSection(name: "Tunnel log (current)", lines: tunnelLogLines))
            sections.append(DebugBundleSection(name: "Tunnel state", lines: tunnelStateLines))
            debugBundleURL = try? DebugBundleBuilder.write(sections: sections)
        }
    }

    var tunnelStateLines: [String] {
        tunnel.activeProfiles.values.map { info in
            var line = "profile=\(info.id) status=\(info.status.rawValue) onDemand=\(info.onDemand)"
            if let transfer = info.transfer {
                line += " received=\(transfer.received) sent=\(transfer.sent)"
            }
            return line
        }
    }

    var profilesSection: some View {
        activeHeaders
            .nilIfEmpty
            .map {
                ForEach($0) { header in
                    NavigationLink(header.name, value: DiagnosticsRoute.profile(header))
                }
                .themeSection(header: Strings.Views.Diagnostics.Sections.activeProfiles)
            }
    }

    var tunnelLogsSection: some View {
        Group {
            Button(Strings.Views.Diagnostics.Rows.removeTunnelLogs) {
                withAnimation(theme.animation(for: .diagnostics), removeTunnelLogs)
            }
            .disabled(tunnelLogs.isEmpty)

            ForEach(tunnelLogs, id: \.date, content: logView)
                .onDelete(perform: removeTunnelLogs)
        }
        .themeSection(header: Strings.Views.Diagnostics.Sections.tunnel)
        .themeAnimation(on: tunnelLogs, category: .diagnostics)
    }

    var reportIssueSection: some View {
        Section {
            ReportIssueButton(
                title: Strings.Views.Diagnostics.ReportIssue.title,
                tunnel: tunnel,
                purchasedProducts: iapObservable.purchasedProducts,
                isUnableToEmail: $isPresentingUnableToEmail
            )
        }
    }

    func logView(for item: ABI.LogEntry) -> some View {
        ThemeRemovableItemRow(isEditing: true) {
            let dateString = appFormatter.string(from: item.date)
            navLink(dateString, to: .tunnelLog(title: dateString, url: item.url))
        } removeAction: {
            removeTunnelLog(at: item.url)
        }
    }

    func navLink(_ title: String, to value: DiagnosticsRoute) -> some View {
        NavigationLink(title, value: value)
    }
}

private extension DiagnosticsView {
    var activeHeaders: [ABI.AppProfileHeader] {
        tunnel.activeProfiles
            .values
            .compactMap {
                profileObservable.header(withId: $0.id)
            }
            .sorted()
    }

    var canReportIssue: Bool {
        AppCommandLine.contains(.withReportIssue) ||
            iapObservable.isEligibleForFeedback ||
            appConfiguration.bundle.distributionTarget.canAlwaysReportIssue ||
            configObservable.isUsingExperimentalFeatures
    }

    func computedTunnelLogs() async -> [ABI.LogEntry] {
        await (availableTunnelLogs ?? defaultTunnelLogs)()
    }

    func defaultTunnelLogs() async -> [ABI.LogEntry] {
        let url = appConfiguration.urlForTunnelLog
        return await Task.detached {
            pspLogEntriesAvailable(at: url)
        }.value
    }

    func removeTunnelLog(at url: URL) {
        guard let firstIndex = tunnelLogs.firstIndex(where: { $0.url == url }) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
        tunnelLogs.remove(at: firstIndex)
    }

    func removeTunnelLogs(at offsets: IndexSet) {
        offsets.forEach {
            try? FileManager.default.removeItem(at: tunnelLogs[$0].url)
        }
        tunnelLogs.remove(atOffsets: offsets)
    }

    func removeTunnelLogs() {
        pspLogEntriesPurge(at: appConfiguration.urlForTunnelLog)
        Task {
            tunnelLogs = await computedTunnelLogs()
        }
    }
}

#Preview {
    DiagnosticsView(profileObservable: .forPreviews, tunnel: .forPreviews) {
        [
            .init(date: Date(), url: URL(fileURLWithPath: "one.com")),
            .init(date: Date().addingTimeInterval(-60), url: URL(fileURLWithPath: "two.com")),
            .init(date: Date().addingTimeInterval(-600), url: URL(fileURLWithPath: "three.com"))
        ]
    }
    .withMockEnvironment()
}
