// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import SwiftUI
import WidgetKit

@main
struct WidgetsExtension: WidgetBundle {
    var body: some Widget {
        TunnelStatusWidget()
        if #available(iOS 18.0, *) {
            TunnelControlWidget()
        }
    }
}
