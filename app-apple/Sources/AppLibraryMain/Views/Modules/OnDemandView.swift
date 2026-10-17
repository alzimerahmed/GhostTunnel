// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import SwiftUI

struct OnDemandView: View, ModuleDraftEditing {

    @Environment(Theme.self)
    private var theme

    @Environment(\.appConfiguration)
    private var appConfiguration

    @ObservedObject
    var draft: ModuleDraft<OnDemandModule.Builder>

    @State
    private var paywallReason: PaywallReason?

    private let wifi: Wifi

    init(
        draft: ModuleDraft<OnDemandModule.Builder>,
        observer: WifiObserver? = nil
    ) {
        self.draft = draft
        wifi = Wifi(observer: observer ?? CoreLocationWifiObserver())
    }

    var body: some View {
        Group {
            rulesArea
        }
        .moduleView(draft: draft)
        .modifier(ModuleDynamicPaywallModifier(reason: $paywallReason))
    }
}

private extension OnDemandView {
    var allPolicies: [OnDemandModule.Policy] {
        if appConfiguration.bundle.distributionTarget.supportsPaidFeatures {
            return [.any, .excluding, .including]
        } else {
            return [.any]
        }
    }

    @ViewBuilder
    var rulesArea: some View {
        policySection
        if draft.module.policy != .any {
            networkSection
            trustedWiFiExplanation
            wifiSection
        }
    }

    var policySection: some View {
        HStack {
            Picker(selection: $draft.module.policy) {
                ForEach(allPolicies, id: \.self) {
                    Text($0.localizedDescription)
                }
            } label: {
                Text(Strings.Modules.OnDemand.policy)
            }
            .accessibilityLabel(Strings.Modules.OnDemand.policy)
            .frame(maxWidth: .infinity, alignment: .leading)
            PurchaseRequiredView(
                for: draft.module,
                reason: $paywallReason
            )
        }
        .themeContainerWithSingleEntry(footer: policyFooterDescription)
    }

    var policyFooterDescription: String {
        let suffix: String
        switch draft.module.policy {
        case .any:
            suffix = Strings.Modules.OnDemand.Policy.Footer.any

        case .including, .excluding:
            if draft.module.policy == .including {
                suffix = Strings.Modules.OnDemand.Policy.Footer.including
            } else {
                suffix = Strings.Modules.OnDemand.Policy.Footer.excluding
            }

        @unknown default:
            suffix = Strings.Modules.OnDemand.Policy.Footer.any
        }
        return Strings.Modules.OnDemand.Policy.footer(suffix)
    }

    var networkSection: some View {
        Group {
            Toggle(Strings.Modules.OnDemand.mobile, isOn: $draft.module.withMobileNetwork)
            Toggle("\(Strings.Modules.OnDemand.ethernet) (Mac/TV)", isOn: $draft.module.withEthernetNetwork)
        }
        .themeSection(
            header: Strings.Global.Nouns.networks,
            footer: Strings.Modules.OnDemand.Networks.footer
        )
    }

    var wifiSection: some View {
        theme.listSection(
            wifiSectionTitle,
            addTitle: Strings.Modules.OnDemand.Ssid.add,
            originalItems: allSSIDs,
            emptyValue: {
                do {
                    return try await wifi.currentSSID()
                } catch {
                    return ""
                }
            },
            itemLabel: { isEditing, binding in
                if isEditing {
                    Text(trimmedSSID(binding.wrappedValue).isEmpty
                        ? AppLibraryMainLocalization.string("modules.on_demand.trusted_wifi.empty_ssid", fallback: "Wi-Fi network")
                        : binding.wrappedValue
                    )
                } else {
                    HStack {
                        ThemeTextField("", text: binding, placeholder: Strings.Placeholders.OnDemand.ssid)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(AppLibraryMainLocalization.string(
                                "modules.on_demand.trusted_wifi.ssid_name",
                                fallback: "Wi-Fi network name"
                            ))
                        Spacer()
                        Toggle("", isOn: isSSIDOn(binding.wrappedValue))
                            .disabled(trimmedSSID(binding.wrappedValue).isEmpty)
                            .accessibilityLabel(trimmedSSID(binding.wrappedValue).isEmpty
                                ? AppLibraryMainLocalization.string("modules.on_demand.trusted_wifi.empty_ssid", fallback: "Wi-Fi network")
                                : binding.wrappedValue
                            )
                            .accessibilityHint(trimmedSSID(binding.wrappedValue).isEmpty
                                ? AppLibraryMainLocalization.string(
                                    "modules.on_demand.trusted_wifi.empty_ssid_hint",
                                    fallback: "Enter a Wi-Fi network name before setting its rule."
                                )
                                : wifiToggleHint
                            )
                    }
                    .labelsHidden()
                }
            }
        )
    }

    var trustedWiFiExplanation: some View {
        Text(AppLibraryMainLocalization.string("modules.on_demand.trusted_wifi.explanation", fallback: "With “Including,” the VPN connects only on enabled Wi-Fi, mobile, or Ethernet networks. With “Excluding,” it connects everywhere except enabled Wi-Fi, mobile, or Ethernet networks."))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    func trimmedSSID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var wifiSectionTitle: String {
        switch draft.module.policy {
        case .excluding:
            return AppLibraryMainLocalization.string("modules.on_demand.trusted_wifi.title", fallback: "Trusted Wi-Fi networks")
        case .including:
            return AppLibraryMainLocalization.string("modules.on_demand.trusted_wifi.included_title", fallback: "VPN-enabled Wi-Fi networks")
        case .any:
            return Strings.Unlocalized.wifi
        @unknown default:
            return Strings.Unlocalized.wifi
        }
    }

    var wifiToggleHint: String {
        switch draft.module.policy {
        case .excluding:
            return AppLibraryMainLocalization.string(
                "modules.on_demand.trusted_wifi.excluded_hint",
                fallback: "Selected networks are trusted and excluded from the VPN. The VPN connects on other networks."
            )
        case .including:
            return AppLibraryMainLocalization.string(
                "modules.on_demand.trusted_wifi.included_hint",
                fallback: "The VPN connects on selected networks and disconnects elsewhere."
            )
        case .any:
            return AppLibraryMainLocalization.string(
                "modules.on_demand.trusted_wifi.toggle_hint",
                fallback: "Choose whether this Wi-Fi network is included in the on-demand rule."
            )
        @unknown default:
            return AppLibraryMainLocalization.string(
                "modules.on_demand.trusted_wifi.toggle_hint",
                fallback: "Choose whether this Wi-Fi network is included in the on-demand rule."
            )
        }
    }
}

private extension OnDemandView {
    var allSSIDs: Binding<[String]> {
        .init {
            draft.module.withSSIDs.keys.sorted()
        } set: { newValue in
            draft.module.withSSIDs.forEach {
                guard newValue.contains($0.key) else {
                    draft.module.withSSIDs.removeValue(forKey: $0.key)
                    return
                }
            }
            newValue.forEach {
                guard draft.module.withSSIDs[$0] == nil else {
                    return
                }
                draft.module.withSSIDs[$0] = false
            }
        }
    }

    var onSSIDs: Binding<Set<String>> {
        .init {
            Set(draft.module.withSSIDs.filter {
                $0.value
            }.map(\.key))
        } set: { newValue in
            draft.module.withSSIDs.forEach {
                guard newValue.contains($0.key) else {
                    if draft.module.withSSIDs[$0.key] != nil {
                        draft.module.withSSIDs[$0.key] = false
                    } else {
                        draft.module.withSSIDs.removeValue(forKey: $0.key)
                    }
                    return
                }
            }
            newValue.forEach {
                guard !(draft.module.withSSIDs[$0] ?? false) else {
                    return
                }
                draft.module.withSSIDs[$0] = true
            }
        }
    }

    func isSSIDOn(_ ssid: String) -> Binding<Bool> {
        .init {
            draft.module.withSSIDs[ssid] ?? false
        } set: {
            draft.module.withSSIDs[ssid] = $0
        }
    }
}

private extension OnDemandView {
    func requestSSID(_ text: Binding<String>) {
        Task { @MainActor in
            let ssid = try await wifi.currentSSID()
            if !draft.module.withSSIDs.keys.contains(ssid) {
                text.wrappedValue = ssid
            }
        }
    }
}

// MARK: - Previews

#Preview {
    var module = OnDemandModule.Builder()
    module.policy = .excluding
    module.withMobileNetwork = true
    module.withSSIDs = [
        "One": true,
        "Two": false,
        "Three": false
    ]
    return module.preview()
//    return module.preview {
//        OnDemandView(
//            draft: $1[$0],
//            parameters: .init(
//                registry: Registry(),
//                editor: $1,
//                impl: nil
//            ),
//            observer: MockWifi()
//        )
//    }
}

private final class MockWifi: WifiObserver {
    func currentSSID() async throws -> String {
        ""
    }
}
