// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import Foundation

enum AppLibraryMainLocalization {
    static func string(_ key: String, fallback: String) -> String {
        AppStrings.bundle.localizedString(forKey: key, value: fallback, table: "Localizable")
    }
}
