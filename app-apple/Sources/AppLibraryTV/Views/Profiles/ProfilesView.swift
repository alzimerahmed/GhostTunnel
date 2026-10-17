// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import SwiftUI

struct ProfilesView: View {
    let profileObservable: ProfileObservable

    let tunnel: TunnelObservable

    let webReceiverObservable: WebReceiverObservable

    /// Connect flow for the detail pane (same handler as the Connection
    /// tab, so paywall/interactive-login behavior is identical).
    let flow: ConnectionFlow?

    @FocusState
    private var detail: Detail?

    @State
    private var errorHandler: ErrorHandler = .default()

    var body: some View {
        HStack {
            masterView
            detailView
        }
        .themeGradient()
        .withErrorHandler(errorHandler)
    }
}

private extension ProfilesView {
    var masterView: some View {
        List {
            importSection
            if profileObservable.hasProfiles {
                profilesSection
            }
        }
        .themeList()
        .frame(maxWidth: .infinity)
    }

    var detailView: some View {
        DetailView(
            detail: detail,
            tunnel: tunnel,
            webReceiverObservable: webReceiverObservable,
            profileObservable: profileObservable,
            errorHandler: errorHandler,
            flow: flow
        )
        .frame(maxWidth: .infinity)
    }

    var importSection: some View {
        webReceiverButton
            .themeSection(header: Strings.Global.Actions.import)
    }

    var webReceiverButton: some View {
        Toggle(Strings.Views.Tv.Profiles.importLocal, isOn: isImporterEnabled)
            .focused($detail, equals: .import)
    }

    var profilesSection: some View {
        ForEach(profileObservable.filteredHeaders, id: \.id, content: row(forHeader:))
            .themeSection(header: Strings.Global.Nouns.profiles)
    }

    func row(forHeader header: ABI.AppProfileHeader) -> some View {
        Button {
            detail = .profile(header.id)
        } label: {
            HStack {
                Text(header.name)
                Spacer()
                ProfileSharingView(
                    flags: header.sharingFlags,
                    isRemoteImportingEnabled: profileObservable.isRemoteImportingEnabled
                )
            }
        }
        .contextMenu {
            Button(Strings.Global.Actions.delete, role: .destructive) {
                deleteProfile(withId: header.id)
            }
        }
        .focused($detail, equals: .profile(header.id))
        .uiAccessibility(.App.ProfileList.profile)
    }
}

private extension ProfilesView {
    var isImporterEnabled: Binding<Bool> {
        Binding {
            webReceiverObservable.isStarted
        } set: {
            if $0 {
                do {
                    try webReceiverObservable.start()
                } catch {
                    pspLog(.core, .error, "Unable to start web receiver: \(error)")
                    errorHandler.handle(error)
                }
            } else {
                webReceiverObservable.stop()
            }
       }
    }

    func deleteProfile(withId profileId: Profile.ID) {
        Task {
            await profileObservable.remove(withId: profileId)
        }
    }
}

// MARK: - Detail

private enum Detail: Hashable {
    case `import`

    case profile(Profile.ID)
}

private struct DetailView: View {
    let detail: Detail?

    let tunnel: TunnelObservable

    let webReceiverObservable: WebReceiverObservable

    let profileObservable: ProfileObservable

    let errorHandler: ErrorHandler

    let flow: ConnectionFlow?

    var body: some View {
        VStack {
            TopSpacer()
            switch detail {
            case .import:
                importView
            case .profile(let profileId):
                profileView(for: profileId)
            default:
                Text(Strings.Views.Tv.Profiles.Detail.profiles)
                    .themeEmptyMessage()
            }
            Spacer()
        }
    }
}

private extension DetailView {
    var importView: some View {
        WebReceiverView(
            webReceiverObservable: webReceiverObservable,
            profileObservable: profileObservable,
            errorHandler: errorHandler
        )
    }

    @ViewBuilder
    func profileView(for profileId: Profile.ID) -> some View {
        if let header = profileObservable.header(withId: profileId) {
            ProfileDetailView(
                header: header,
                tunnel: tunnel,
                errorHandler: errorHandler,
                flow: flow
            )
        } else {
            Text(AppLibraryTVLocalization.string(
                "views.tv.profiles.detail.unavailable",
                fallback: "Profile no longer available"
            ))
            .themeEmptyMessage()
        }
    }
}

/// Detail pane for the profile selected in the master list: connection
/// status, a Connect/Disconnect action, and the profile metadata. Connects
/// from the Profiles tab reuse the same `TunnelToggle` flow as the
/// Connection tab, so paywall/interactive-login handling stays identical.
private struct ProfileDetailView: View {
    @Environment(Theme.self)
    private var theme

    let header: ABI.AppProfileHeader

    let tunnel: TunnelObservable

    let errorHandler: ErrorHandler

    let flow: ConnectionFlow?

    var body: some View {
        VStack(spacing: 20) {
            Text(header.name)
                .font(.title)
                .fontWeight(theme.relevantWeight)
                .multilineTextAlignment(.center)

            ConnectionStatusText(tunnel: tunnel, profileId: header.id)
                .font(.title3)

            TunnelToggle(
                tunnel: tunnel,
                header: header,
                errorHandler: errorHandler,
                flow: flow
            ) { isOn, _ in
                Button(!isOn.wrappedValue ? Strings.Global.Actions.connect : Strings.Global.Actions.disconnect) {
                    isOn.wrappedValue.toggle()
                }
                .frame(maxWidth: 400)
                .fontWeight(theme.relevantWeight)
            }

            if let primaryType = header.localizedDescription(optionalStyle: .primaryType) {
                ListRowView(title: Strings.Global.Nouns.protocol) {
                    Text(primaryType)
                }
                .font(.title3)
            }
        }
        .padding(.horizontal, 100)
        .uiAccessibility(.App.ProfileDetail.profile)
    }
}

// MARK: - Preview

#Preview("Empty") {
    ProfilesView(
        profileObservable: .forPreviews,
        tunnel: .forPreviews,
        webReceiverObservable: .forPreviews,
        flow: nil
    )
    .withMockEnvironment()
    .task {
        await ProfileObservable.forPreviews.removeAll()
    }
}

#Preview("Profiles") {
    ProfilesView(
        profileObservable: .forPreviews,
        tunnel: .forPreviews,
        webReceiverObservable: .forPreviews,
        flow: nil
    )
    .withMockEnvironment()
}
