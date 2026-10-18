// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import SwiftUI

struct PreferencesAdvancedView: View {
    @Environment(ConfigObservable.self)
    private var configObservable

    @Environment(IAPObservable.self)
    private var iapObservable

    @Environment(\.appConfiguration)
    private var appConfiguration

    @Binding
    var experimental: ABI.ExperimentalPreferences

    var body: some View {
        Form {
            configSection
            frontierSection
        }
        .themeForm()
    }
}

private enum ConfigFlagPreference: String, CaseIterable, Identifiable {
    case remote
    case enable
    case disable

    var id: Self {
        self
    }
}

private extension PreferencesAdvancedView {
    static let flags: [ABI.ConfigFlag] = [
        .experimentalDaemon_202610,
        .experimentalDaemonOpenVPN_202610,
        .experimentalDaemonWireGuard_202610
    ]

    var canOverride: Bool {
        iapObservable.isBeta || appConfiguration.bundle.distributionTarget == .developerID
    }

    var visibleFlags: [ABI.ConfigFlag] {
        let flags = Self.flags
        return flags
    }

    @ViewBuilder
    var configSection: some View {
        if canOverride {
            overrideSection
        } else {
            remoteSection
        }
    }

    var overrideSection: some View {
        ForEach(visibleFlags, id: \.rawValue) { flag in
            configPicker(for: flag)
        }
        .themeSection(
            footer: Strings.Views.Preferences.Advanced.Override.footer
        )
    }

    var remoteSection: some View {
        ForEach(visibleFlags, id: \.rawValue) { flag in
            configToggle(for: flag)
        }
        .themeSection(
            header: Strings.Global.Actions.allow,
            footer: Strings.Views.Preferences.Advanced.Remote.footer
        )
    }

    // MARK: - Frontier features (Phase 15 scaffolding)

    /// Upstream-dependent features (multi-hop, post-quantum WireGuard,
    /// WireGuard obfuscation, per-app split tunneling on macOS). The section
    /// is entirely hidden while all flags are OFF; each row is a non-interactive
    /// seam that lights up when the flag is enabled via UserDefaults override
    /// (`FeatureFlags.<rawValue>` = true) AND the upstream `partout` capability
    /// lands. When that happens, each row becomes the navigation entry point
    /// for the feature's editor UI.
    @ViewBuilder
    var frontierSection: some View {
        let flags = FeatureFlags(defaults: .standard)
        if flags.isAnyEnabled {
            ForEach(FeatureFlag.allCases.filter { flags.isEnabled($0) }, id: \.rawValue) { flag in
                VStack(alignment: .leading) {
                    Text(flag.rawValue)
                    Text(Strings.Unlocalized.pendingUpstream)
                        .themeSubtitle()
                }
            }
            .themeSection(
                header: Strings.Unlocalized.frontierFeatures,
                footer: Strings.Unlocalized.pendingUpstream
            )
        }
    }

    func configPicker(for flag: ABI.ConfigFlag) -> some View {
        Picker(selection: preferenceBinding(for: flag)) {
            ForEach(ConfigFlagPreference.allCases) { pref in
                Text(pref.localizedDescription)
                    .tag(pref)
            }
        } label: {
            flagView(for: flag)
        }
    }

    func configToggle(for flag: ABI.ConfigFlag) -> some View {
        Toggle(isOn: isAllowedBinding(for: flag)) {
            flagView(for: flag)
        }
    }

    func isAllowedBinding(for flag: ABI.ConfigFlag) -> Binding<Bool> {
        Binding {
            experimental.isAllowed(flag)
        } set: {
            experimental.setAllowed(flag, isAllowed: $0)
        }
    }

    func preferenceBinding(for flag: ABI.ConfigFlag) -> Binding<ConfigFlagPreference> {
        Binding {
            experimental.preference(for: flag)
        } set: {
            experimental.setPreference($0, for: flag)
        }
    }

    func flagView(for flag: ABI.ConfigFlag) -> some View {
        VStack(alignment: .leading) {
            Text(flag.localizedDescription)
            Text(configObservable.isActive(flag) ? Strings.Global.Nouns.enabled : Strings.Global.Nouns.disabled)
                .themeSubtitle()
        }
    }

}

private extension ABI.ExperimentalPreferences {
    func isAllowed(_ flag: ABI.ConfigFlag) -> Bool {
        !ignoredConfigFlags.contains(flag)
    }

    mutating func setAllowed(_ flag: ABI.ConfigFlag, isAllowed: Bool) {
        if isAllowed {
            unignore(flag)
        } else {
            ignore(flag)
        }
    }

    func preference(for flag: ABI.ConfigFlag) -> ConfigFlagPreference {
        if ignoredConfigFlags.contains(flag) {
            return .disable
        }
        if enabledConfigFlags.contains(flag) {
            return .enable
        }
        return .remote
    }

    mutating func setPreference(_ preference: ConfigFlagPreference, for flag: ABI.ConfigFlag) {
        unignore(flag)
        disable(flag)

        switch preference {
        case .enable:
            enable(flag)
        case .disable:
            ignore(flag)
        case .remote:
            break
        }
    }
}

// MARK: - Localization

private extension ABI.ConfigFlag {
    var localizedDescription: String {
        rawValue
    }
}

private extension ConfigFlagPreference {
    var localizedDescription: String {
        switch self {
        case .remote:
            return Strings.Views.Preferences.Advanced.Override.Picker.remote
        case .enable:
            return Strings.Global.Actions.enable
        case .disable:
            return Strings.Global.Actions.disable
        }
    }
}
