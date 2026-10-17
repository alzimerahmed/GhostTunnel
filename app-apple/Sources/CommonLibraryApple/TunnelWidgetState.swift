// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Glanceable tunnel state shared between the app (writer) and the
/// WidgetKit widgets / Control Center control (readers).
///
/// The state is persisted as JSON in the App Group `UserDefaults`, so any
/// process in the group (app, widget extension, intents extension) can read
/// the latest snapshot without talking to the Network Extension.
public struct TunnelWidgetState: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case disconnected
        case connecting
        case connected
        case disconnecting
    }

    public var kind: Kind

    public var profileId: String?

    public var profileName: String?

    public var lastUpdate: Date

    public init(
        kind: Kind,
        profileId: String? = nil,
        profileName: String? = nil,
        lastUpdate: Date = Date()
    ) {
        self.kind = kind
        self.profileId = profileId
        self.profileName = profileName
        self.lastUpdate = lastUpdate
    }
}

extension TunnelWidgetState {
    public init(profiles: [Profile.ID: ABI.AppTunnelInfo], profileNames: [Profile.ID: String] = [:]) {
        // TODO: #218, must be per-tunnel (first active profile)
        if let info = profiles.values.first(where: { $0.status != .disconnected })
            ?? profiles.values.first {
            self.init(
                kind: Kind(rawValue: info.status.rawValue) ?? .disconnected,
                profileId: info.id.uuidString,
                profileName: profileNames[info.id],
                lastUpdate: Date()
            )
        } else {
            self.init(kind: .disconnected)
        }
    }
}

// MARK: - App Group resolution

/// Resolves the App Group `UserDefaults` shared with the app. Returns `nil`
/// for a missing/empty identifier instead of silently falling back to
/// `.standard`, so readers (widgets, intents extension) can fail visibly.
public enum WidgetAppGroup {
    public static func defaults(groupId: String?) -> UserDefaults? {
        guard let groupId, !groupId.isEmpty else {
            return nil
        }
        return UserDefaults(suiteName: groupId)
    }
}

// MARK: - Store

/// App Group-backed persistence for `TunnelWidgetState`.
public struct TunnelWidgetStatusStore: Sendable {
    private let defaults: UserDefaults

    private static let key = "TunnelWidgetState"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> TunnelWidgetState? {
        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }
        return try? JSONDecoder().decode(TunnelWidgetState.self, from: data)
    }

    public func save(_ state: TunnelWidgetState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    /// Removes any persisted state (e.g. in tests or on reset).
    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
