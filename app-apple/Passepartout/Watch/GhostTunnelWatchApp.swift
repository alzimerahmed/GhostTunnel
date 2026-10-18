// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import SwiftUI

@main
struct GhostTunnelWatchApp: App {
    @State
    private var sessionManager = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchStatusView(manager: sessionManager)
                .task {
                    sessionManager.activate()
                }
        }
    }
}
