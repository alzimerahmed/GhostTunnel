// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import Combine
import CommonLibrary
import SwiftUI

struct DNSView: View, ModuleDraftEditing {
    @Environment(ConfigObservable.self)
    private var configObservable

    @Environment(Theme.self)
    private var theme

    @ObservedObject
    var draft: ModuleDraft<DNSModule.Builder>

    init(draft: ModuleDraft<DNSModule.Builder>) {
        self.draft = draft
    }

    var body: some View {
        debugChanges()
        return Group {
            inheritsSection
            behaviorSection
            filteringResolverSection
            if draft.module.inheritsVPN != true {
                overrideGroup
            }
        }
        .moduleView(draft: draft)
    }
}

private extension DNSView {
    @ViewBuilder
    var filteringResolverSection: some View {
        if let endpoints = configObservable.blocklistCatalog?.dohEndpoints {
            if endpoints.isEmpty {
                Text(AppLibraryMainLocalization.string("modules.dns.filtering.unavailable", fallback: "No filtering DNS resolvers are currently available."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .themeContainerWithSingleEntry()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        draft.module = BlocklistDNSSelection.applyingVPNProvidedDNS(to: draft.module)
                    } label: {
                        HStack {
                            Text(AppLibraryMainLocalization.string("modules.dns.filtering.vpn_dns", fallback: "Use VPN-provided DNS"))
                            Spacer()
                            if draft.module.inheritsVPN {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.module.inheritsVPN ? .isSelected : [])
                    .accessibilityHint(AppLibraryMainLocalization.string("modules.dns.filtering.vpn_dns_hint", fallback: "Uses the DNS servers provided by the VPN."))
                    ForEach(endpoints) { endpoint in
                        let selected = draft.module.protocolType == .https && draft.module.dohURL == endpoint.url.absoluteString && !draft.module.inheritsVPN
                        Button {
                            draft.module = BlocklistDNSSelection.applying(endpoint, to: draft.module)
                        } label: {
                            HStack {
                                Text(endpoint.name)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityHint(AppLibraryMainLocalization.string("modules.dns.filtering.resolver_hint", fallback: "Routes DNS queries through this filtering resolver."))
                    }
                    Text(AppLibraryMainLocalization.string("modules.dns.filtering.disclosure", fallback: "The selected filtering resolver receives your DNS queries. VPN-provided DNS uses the resolver configured by your VPN."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .themeSection(header: AppLibraryMainLocalization.string("modules.dns.filtering.header", fallback: "DNS filtering"))
            }
        }
    }

    var behaviorSection: some View {
        Group {
            routesThroughPicker
                .themeContainerEntry(subtitle: Strings.Modules.Dns.Policy.RouteThroughVpn.footer)
            onlyInDomainsToggle
                .themeContainerEntry(subtitle: Strings.Modules.Dns.Policy.UseOnly.footer)
        }
        .themeContainer()
    }

    var routesThroughPicker: some View {
        Picker(Strings.Modules.Dns.Policy.routeThroughVpn, selection: $draft.module.routesThroughVPN) {
            Text(Strings.Global.Nouns.default)
                .tag(nil as Bool?)
            Text(Strings.Global.Nouns.yes)
                .tag(true as Bool?)
            Text(Strings.Global.Nouns.no)
                .tag(false as Bool?)
        }
    }

    var onlyInDomainsToggle: some View {
        Toggle(Strings.Modules.Dns.Policy.useOnly, isOn: bindingToOnlyInDomains)
            .disabled(!canApplyDomainPolicy)
            .accessibilityHint(canApplyDomainPolicy
                ? Strings.Modules.Dns.Policy.UseOnly.footer
                : AppLibraryMainLocalization.string(
                    "modules.dns.policy.use_only.disabled_hint",
                    fallback: "Available when using cleartext DNS or inheriting VPN DNS."
                ))
    }

    var inheritsSection: some View {
        Toggle(Strings.Modules.Dns.Policy.inheritsVpn, isOn: $draft.module.inheritsVPN)
            .themeContainerWithSingleEntry(footer: Strings.Modules.Dns.Policy.InheritsVpn.footer)
    }

    var overrideGroup: some View {
        Group {
            protocolSection
            serversSection.labelsHidden()
            if draft.module.protocolType == .cleartext {
                domainsSection.labelsHidden()
                firstDomainToggle
            }
        }
    }

    var protocolSection: some View {
        Group {
            Picker(Strings.Global.Nouns.protocol, selection: $draft.module.protocolType) {
                ForEach(Self.allProtocols, id: \.self) {
                    Text($0.localizedDescription)
                }
            }
            switch draft.module.protocolType {
            case .cleartext:
                EmptyView()
            case .https:
                ThemeTextField(Strings.Unlocalized.url, text: $draft.module.dohURL, placeholder: Strings.Unlocalized.Placeholders.dohURL)
                    .labelsHidden()
                    .accessibilityLabel(AppLibraryMainLocalization.string(
                        "modules.dns.filtering.doh_url",
                        fallback: "DNS-over-HTTPS URL"
                    ))
            case .tls:
                ThemeTextField(Strings.Global.Nouns.hostname, text: $draft.module.dotHostname, placeholder: Strings.Unlocalized.Placeholders.dotHostname)
                    .labelsHidden()
                    .accessibilityLabel(AppLibraryMainLocalization.string(
                        "modules.dns.filtering.dot_hostname",
                        fallback: "DNS-over-TLS hostname"
                    ))
            @unknown default:
                EmptyView()
            }
        }
        .themeSection(header: Strings.Modules.Dns.CustomSettings.header)
    }

    var serversSection: some View {
        theme.listSection(
            Strings.Entities.Dns.servers,
            addTitle: Strings.Modules.Dns.Servers.add,
            originalItems: $draft.module.servers,
            itemLabel: {
                if $0 {
                    Text($1.wrappedValue)
                } else {
                    ThemeTextField(
                        "",
                        text: $1,
                        placeholder: Strings.Unlocalized.Placeholders.ipV4DNS,
                        inputType: .ipAddress
                    )
                    .accessibilityLabel(Strings.Entities.Dns.servers)
                }
            }
        )
    }

    var domainsSection: some View {
        theme.listSection(
            Strings.Entities.Dns.domains,
            addTitle: Strings.Modules.Dns.Domains.add,
            originalItems: $draft.module.domains ?? [],
            itemLabel: {
                if $0 {
                    Text($1.wrappedValue)
                } else {
                    ThemeTextField(
                        "",
                        text: $1,
                        placeholder: Strings.Unlocalized.Placeholders.hostname
                    )
                    .accessibilityLabel(Strings.Entities.Dns.domains)
                }
            }
        )
    }

    var firstDomainToggle: some View {
        Toggle(Strings.Modules.Dns.Domains.firstIsPrimary, isOn: $draft.module.isFirstDomainPrimary)
            .themeContainerWithSingleEntry(footer: Strings.Modules.Dns.Domains.FirstIsPrimary.footer)
            .disabled(!hasNonEmptyDomains)
            .accessibilityHint(hasNonEmptyDomains
                ? Strings.Modules.Dns.Domains.FirstIsPrimary.footer
                : AppLibraryMainLocalization.string(
                    "modules.dns.domains.first_is_primary.disabled_hint",
                    fallback: "Add or inherit at least one search domain first."
                ))
    }
}

private extension DNSView {
    static let allProtocols: [DNSProtocol] = [
        .cleartext,
        .https,
        .tls
    ]

    static let allPolicies: [DNSModule.DomainPolicy?] = [
        .matchAndSearch,
        nil
    ]

    var bindingToOnlyInDomains: Binding<Bool> {
        Binding {
            canApplyDomainPolicy ? draft.module.domainPolicy == .matchAndSearch : false
        } set: {
            draft.module.domainPolicy = $0 ? .matchAndSearch : nil
        }
    }

    var canApplyDomainPolicy: Bool {
        draft.module.inheritsVPN == true || draft.module.protocolType == .cleartext
    }

    var hasNonEmptyDomains: Bool {
        draft.module.inheritsVPN == true || draft.module.domains?.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
    }
}

// MARK: - Previews

#Preview {
    var module = DNSModule.Builder()
    module.protocolType = .https
    module.servers = ["1.1.1.1", "2.2.2.2", "3.3.3.3"]
    module.dohURL = "https://doh.com/query"
    module.dotHostname = "tls.com"
    module.domains = ["one.com", "two.net", "three.com"]
    return module.preview()
}
