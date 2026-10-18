// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import SwiftUI
import WidgetKit

// Glanceable complication: reads the last status the watch app synced from
// the phone (App Group store). Display-only — connect/disconnect lives in the
// watch app, which owns the WatchConnectivity session.

struct TunnelStatusEntry: TimelineEntry {
    let date: Date

    /// `nil` when the phone has not synced a status yet.
    let status: WatchTunnelStatus?
}

struct TunnelStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> TunnelStatusEntry {
        TunnelStatusEntry(date: Date(), status: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TunnelStatusEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TunnelStatusEntry>) -> Void) {
        // Single entry; the watch app reloads timelines whenever it syncs a
        // new status. The periodic refresh is a fallback for missed reloads.
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func entry() -> TunnelStatusEntry {
        let status = WatchAppGroup.defaults.flatMap {
            WatchStatusStore(defaults: $0).load()
        }
        return TunnelStatusEntry(date: Date(), status: status)
    }
}

struct TunnelStatusEntryView: View {
    let entry: TunnelStatusEntry

    @Environment(\.widgetFamily)
    private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("GhostTunnel")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(color)
                        .lineLimit(1)
                    if let profileName = entry.status?.profileName {
                        Text(profileName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            default:
                // accessoryCircular / accessoryInline / accessoryCorner
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var statusText: String {
        switch entry.status?.kind {
        case .connected: "On"
        case .connecting: "Connecting…"
        case .disconnecting: "Disconnecting…"
        case .disconnected: "Off"
        case nil: "—"
        }
    }

    private var accessibilityText: String {
        switch entry.status?.kind {
        case .connected: "Tunnel connected"
        case .connecting: "Tunnel connecting"
        case .disconnecting: "Tunnel disconnecting"
        case .disconnected: "Tunnel disconnected"
        case nil: "No tunnel status"
        }
    }

    private var color: Color {
        switch entry.status?.kind {
        case .connected: .green
        case .connecting, .disconnecting: .yellow
        case .disconnected, nil: .secondary
        }
    }
}

struct TunnelComplicationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhostTunnelTunnelStatus", provider: TunnelStatusProvider()) { entry in
            TunnelStatusEntryView(entry: entry)
        }
        .configurationDisplayName("Tunnel status")
        .description("Shows the last tunnel status synced from your iPhone.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}
