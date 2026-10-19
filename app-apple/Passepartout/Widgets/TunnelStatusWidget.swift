// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppIntentsLibrary
import AppStrings
import CommonLibrary
import SwiftUI
import WidgetKit

// MARK: - Defaults

/// App Group defaults shared with the app (same `AppConfig.groupId` as the
/// main app's Info.plist, resolved via xcconfig). Returns `nil` when the
/// group identifier is missing or unusable, so the widget can fail visibly
/// instead of silently falling back to `.standard` (which the app never
/// writes widget state to).
private enum WidgetDefaults {
    static var defaults: UserDefaults? {
        let config = Bundle.main.infoDictionary?["AppConfig"] as? [String: String]
        return WidgetAppGroup.defaults(groupId: config?["groupId"])
    }
}

// MARK: - Timeline

struct TunnelStatusEntry: TimelineEntry {
    let date: Date

    let state: TunnelWidgetState

    /// `false` when the App Group defaults are unavailable (misconfigured
    /// group identifier); the view then renders an explicit invalid state.
    var isConfigured: Bool = true
}

struct TunnelStatusProvider: TimelineProvider {
    private let store = WidgetDefaults.defaults.map {
        TunnelWidgetStatusStore(defaults: $0)
    }

    func placeholder(in context: Context) -> TunnelStatusEntry {
        .init(date: Date(), state: TunnelWidgetState(kind: .disconnected))
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (TunnelStatusEntry) -> Void
    ) {
        completion(entry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<TunnelStatusEntry>) -> Void
    ) {
        // The app reloads timelines on every status change, so a single
        // entry with .never policy is enough.
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> TunnelStatusEntry {
        guard let store else {
            // Fail visibly: no App Group access means no trustworthy state.
            return .init(
                date: Date(),
                state: TunnelWidgetState(kind: .disconnected),
                isConfigured: false
            )
        }
        return .init(
            date: Date(),
            state: store.load() ?? TunnelWidgetState(kind: .disconnected)
        )
    }
}

// MARK: - View

private extension TunnelWidgetState.Kind {
    var statusText: String {
        switch self {
        case .connected: Strings.Entities.TunnelStatus.active
        case .connecting: Strings.Entities.TunnelStatus.activating
        case .disconnecting: Strings.Entities.TunnelStatus.deactivating
        case .disconnected: Strings.Entities.TunnelStatus.inactive
        }
    }

    var systemImageName: String {
        switch self {
        case .connected: "globe"
        case .connecting, .disconnecting: "globe.badge.ellipsis"
        case .disconnected: "globe.badge.xmark"
        }
    }
}

struct TunnelStatusEntryView: View {
    let entry: TunnelStatusEntry

    var body: some View {
        if !entry.isConfigured {
            unavailableView
        } else {
            statusView
        }
    }

    /// Rendered when the App Group defaults cannot be resolved, so a
    /// misconfiguration never masquerades as "disconnected".
    private var unavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(verbatim: "Unavailable")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.quaternary, for: .widget)
    }

    private var statusView: some View {
        VStack(spacing: 8) {
            Image(systemName: entry.state.kind.systemImageName)
                .font(.title2)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            Text(verbatim: entry.state.kind.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let profileName = entry.state.profileName {
                Text(profileName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            Button(intent: ToggleTunnelIntent()) {
                Text(verbatim: entry.state.kind == .connected
                    ? Strings.Global.Actions.disconnect
                    : Strings.Global.Actions.connect)
                    .font(.footnote.weight(.semibold))
            }
        }
        .containerBackground(.fill.quaternary, for: .widget)
    }

    private var statusColor: Color {
        switch entry.state.kind {
        case .connected: .green
        case .connecting, .disconnecting: .orange
        case .disconnected: .secondary
        }
    }
}

// MARK: - Widget

struct TunnelStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.ghosttunnel.TunnelStatusWidget",
            provider: TunnelStatusProvider()
        ) { entry in
            TunnelStatusEntryView(entry: entry)
        }
        .configurationDisplayName("GhostTunnel")
        .description(Text(verbatim: "Shows the VPN connection status with a quick toggle."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
