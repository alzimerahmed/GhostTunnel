// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

// Mapping from the phone-side widget state to the watch wire status. Lives in
// its own file (not `WatchConnectivityMessages.swift`) because it references
// `TunnelWidgetState`, which the watchOS targets do not compile.

extension WatchTunnelStatus {
    /// Builds the status sent to the watch from the phone's shared widget
    /// state. Raw values of both `Kind` enums match by design; an unknown raw
    /// value degrades to `.disconnected` rather than failing the reply.
    public init(state: TunnelWidgetState) {
        self.init(
            kind: Kind(rawValue: state.kind.rawValue) ?? .disconnected,
            profileId: state.profileId,
            profileName: state.profileName,
            lastUpdate: state.lastUpdate
        )
    }
}
