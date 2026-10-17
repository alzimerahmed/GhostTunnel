// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import Foundation

/// Value model for one Top Shelf row. Built by `TopShelfContentBuilder`
/// (pure, unit-tested) and mapped to `TVTopShelfSectionedItem` by the
/// Top Shelf extension (UI/extension glue, statically reviewed only).
public struct TopShelfItemModel: Equatable, Sendable {
    /// Stable identifier: `"profile:<uuid>"` for profile rows.
    public let identifier: String

    public let title: String

    public let subtitle: String?

    /// `ghosttunnel://connect/<uuid>` deep link opened by the app.
    public let url: URL?

    public init(identifier: String, title: String, subtitle: String?, url: URL?) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.url = url
    }
}

/// Pure decision logic for the tvOS Top Shelf extension: which profiles are
/// featured, in which order, and how deep links are shaped/parsed.
///
/// Featured = the last-used profile first (its subtitle carries the live
/// tunnel status), then the remaining profiles alphabetically, capped at
/// `maxItems`. No images, no network, no persistence — everything derives
/// from inputs so the logic is unit-testable without TVServices.
public enum TopShelfContentBuilder {

    /// Deep-link scheme/host shared with the app's `CFBundleURLTypes`
    /// registration (see `Passepartout/App/App.plist`).
    static let deepLinkScheme = "ghosttunnel"

    static let deepLinkHost = "connect"

    /// Top Shelf renders two rows comfortably; keep the shelf uncluttered.
    public static let maxItems = 8

    private init() {}

    /// Builds the Top Shelf rows from the profile headers and the shared
    /// tunnel state.
    public static func items(
        headers: [ABI.AppProfileHeader],
        lastUsedProfileId: Profile.ID?,
        tunnelState: TunnelWidgetState?,
        maxItems: Int = TopShelfContentBuilder.maxItems
    ) -> [TopShelfItemModel] {
        guard !headers.isEmpty else {
            return []
        }
        let byId = Dictionary(uniqueKeysWithValues: headers.map { ($0.id, $0) })
        let alphabetical = headers.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        // Featured profile: last-used if it still exists, else the
        // alphabetically-first profile (same fallback as QuickConnectPlanner).
        let featured: ABI.AppProfileHeader?
        if let lastUsedProfileId, let lastUsed = byId[lastUsedProfileId] {
            featured = lastUsed
        } else {
            featured = alphabetical.first
        }
        let sorted = (featured.map { [$0] } ?? [])
            + alphabetical.filter { $0.id != featured?.id }

        return sorted.prefix(maxItems).map { header in
            let isFeatured = header.id == featured?.id
            return TopShelfItemModel(
                identifier: "profile:\(header.id.uuidString)",
                title: header.name,
                subtitle: isFeatured ? subtitle(for: header.id, tunnelState: tunnelState) : nil,
                url: deepLinkURL(for: header.id)
            )
        }
    }

    /// Deep link opened when the user selects a Top Shelf item. The app
    /// registers the `ghosttunnel` scheme and routes `connect/<uuid>` to a
    /// profile connect (see `AppCoordinator` onOpenURL handling).
    public static func deepLinkURL(for profileId: Profile.ID) -> URL? {
        URL(string: "\(deepLinkScheme)://\(deepLinkHost)/\(profileId.uuidString)")
    }

    /// Parses a deep link back into a profile ID. Returns `nil` for any
    /// foreign URL (wrong scheme/host/malformed UUID) so the app ignores it.
    public static func profileId(fromDeepLink url: URL) -> Profile.ID? {
        guard url.scheme?.lowercased() == deepLinkScheme,
              url.host?.lowercased() == deepLinkHost else {
            return nil
        }
        let uuidString = url.pathComponents.dropFirst().first
        guard let uuidString else {
            return nil
        }
        return Profile.ID(uuidString: uuidString)
    }
}

private extension TopShelfContentBuilder {
    static func subtitle(for profileId: Profile.ID, tunnelState: TunnelWidgetState?) -> String? {
        guard let tunnelState, tunnelState.profileId == profileId.uuidString else {
            return nil
        }
        let l10n = AppLibraryTVLocalization.self
        switch tunnelState.kind {
        case .connected:
            return l10n.string("views.tv.topshelf.status.connected", fallback: "Connected")
        case .connecting:
            return l10n.string("views.tv.topshelf.status.connecting", fallback: "Connecting…")
        case .disconnecting:
            return l10n.string("views.tv.topshelf.status.disconnecting", fallback: "Disconnecting…")
        case .disconnected:
            return nil
        }
    }
}
