// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import Foundation

/// Localization helper for tvOS-specific strings. New user-facing strings
/// use the `string(key, fallback:)` pattern (see Phase 8/9/10 precedent) so
/// that no generated SwiftGen output is hand-edited; keys live in
/// `AppStrings/Resources/en.lproj/Localizable.strings`.
public enum AppLibraryTVLocalization {
    public static func string(_ key: String, fallback: String) -> String {
        AppStrings.bundle.localizedString(forKey: key, value: fallback, table: "Localizable")
    }
}
