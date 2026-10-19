// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppIntentsLibrary
import SwiftUI
import WidgetKit

/// Control Center toggle (iOS 18+). The iOS 17 baseline is unaffected:
/// this file is only compiled into the Widgets extension and the whole
/// struct is availability-gated.
@available(iOS 18.0, *)
struct TunnelControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ghosttunnel.TunnelControl") {
            ControlWidgetButton(action: ToggleTunnelIntent()) {
                Label(
                    "Toggle VPN",
                    systemImage: "globe"
                )
            }
        }
        .displayName("GhostTunnel")
    }
}
