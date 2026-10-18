// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Resolves the App Group defaults shared with the watch widget extension.
/// The group identifier is injected via the target's Info.plist
/// (`AppConfig.groupId`, from `Config.xcconfig`).
enum WatchAppGroup {
    static var defaults: UserDefaults? {
        guard let groupId = Bundle.main.object(forInfoDictionaryKey: "AppConfig.groupId") as? String, !groupId.isEmpty else {
            return nil
        }
        return UserDefaults(suiteName: groupId)
    }
}
