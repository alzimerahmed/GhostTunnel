// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibraryCore
import Foundation
import Partout

/// Pure decision logic for quick-connect surfaces (widgets, Control Center,
/// Shortcuts, menu bar). Given the last known widget state and the available
/// profiles, decides what a single toggle action should do.
public enum QuickConnectPlanner {

    public enum Action: Equatable, Sendable {
        case connect(Profile.ID)
        case disconnect(Profile.ID)
        case none
    }

    public static func action(
        current: TunnelWidgetState?,
        profiles: [ABI.AppProfileHeader],
        lastUsedProfileId: Profile.ID?
    ) -> Action {
        let profileIds = Set(profiles.map(\.id))

        // Tunnel busy with a known profile: toggle it off.
        if let current, [.connecting, .connected].contains(current.kind),
           let activeId = current.profileId.flatMap(Profile.ID.init(uuidString:)),
           profileIds.contains(activeId) {
            return .disconnect(activeId)
        }

        // Otherwise connect to the last-used profile, or the first one.
        let targetId: Profile.ID?
        if let lastUsedProfileId, profileIds.contains(lastUsedProfileId) {
            targetId = lastUsedProfileId
        } else {
            targetId = profiles.last?.id
        }
        guard let targetId else {
            return .none
        }
        return .connect(targetId)
    }
}
