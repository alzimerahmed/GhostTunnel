// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import SwiftUI

struct WatchStatusView: View {
    let manager: WatchSessionManager

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.headline)
                .foregroundStyle(color)
            if let profileName = manager.status?.profileName {
                Text(profileName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let error = manager.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            actionButton
        }
    }

    private var actionButton: some View {
        // Single primary action: connect when down, disconnect when up.
        let isUp = manager.status?.kind == .connected || manager.status?.kind == .connecting
        return Button {
            if isUp {
                manager.disconnect()
            } else {
                manager.connect()
            }
        } label: {
            Label(isUp ? "Disconnect" : "Connect", systemImage: "power")
        }
        .disabled(manager.status == nil)
    }

    private var statusText: String {
        switch manager.status?.kind {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .disconnecting: "Disconnecting…"
        case .disconnected: "Disconnected"
        case nil: "No status"
        }
    }

    private var symbol: String {
        switch manager.status?.kind {
        case .connected: "checkmark.shield.fill"
        case .connecting, .disconnecting: "shield.lefthalf.filled"
        case .disconnected, nil: "shield.slash"
        }
    }

    private var color: Color {
        switch manager.status?.kind {
        case .connected: .green
        case .connecting, .disconnecting: .yellow
        case .disconnected, nil: .secondary
        }
    }
}
