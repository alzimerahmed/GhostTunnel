// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Wire format for the watch ↔ phone tunnel channel over WatchConnectivity.
///
/// The watch requests the current status and sends connect/disconnect
/// requests; the phone replies with the latest status or a failure reason.
/// Messages travel as single-entry dictionaries (`payload` → JSON data),
/// because `WCSession` only accepts property-list types.
///
/// This file is compiled into `CommonLibraryApple` (SwiftPM) *and* directly
/// into the watchOS targets (see `project.pbxproj`), so it must stay
/// Foundation-only: no imports or types from other modules. `Kind` therefore
/// mirrors `TunnelWidgetState.Kind` by raw value; the mapping lives in
/// `WatchTunnelStatus+Mapping.swift` (SwiftPM side only).
public enum WatchTunnelMessage: Codable, Equatable, Sendable {
    /// Watch → phone: reply with the current status.
    case requestStatus

    /// Phone → watch: latest glanceable status.
    case status(WatchTunnelStatus)

    /// Watch → phone: connect the given profile.
    case connect(profileId: String)

    /// Watch → phone: disconnect the given profile.
    case disconnect(profileId: String)

    /// Phone → watch: a request could not be fulfilled.
    case failure(String)
}

/// Glanceable status as seen on the watch. Mirrors the phone-side
/// `TunnelWidgetState` payload without depending on it.
public struct WatchTunnelStatus: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case disconnected
        case connecting
        case connected
        case disconnecting
    }

    public var kind: Kind

    /// Profile the phone would act on (active or last used). `nil` when the
    /// phone has no profiles at all.
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

// MARK: - WCSession dictionary serialization

extension WatchTunnelMessage {
    private static let payloadKey = "payload"

    /// Encodes into the dictionary form accepted by `WCSession.sendMessage`.
    /// Returns `nil` when the payload cannot be JSON-encoded (callers surface
    /// that as an error instead of silently sending nothing).
    public func encodedDictionary() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return [Self.payloadKey: data]
    }

    /// Decodes from the dictionary form produced by `encodedDictionary()`.
    public init?(dictionary: [String: Any]) {
        guard let data = dictionary[Self.payloadKey] as? Data else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(WatchTunnelMessage.self, from: data) else {
            return nil
        }
        self = decoded
    }
}

// MARK: - Watch-side persistence

/// Persistence for the latest status received from the phone. On watchOS the
/// watch app writes it and the widget extension (a separate process) reads it
/// through the App Group `UserDefaults`.
public struct WatchStatusStore: Sendable {
    // UserDefaults is thread-safe; wrapped for strict Sendable checking.
    private nonisolated(unsafe) let defaults: UserDefaults

    private static let key = "WatchTunnelStatus"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> WatchTunnelStatus? {
        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }
        return try? JSONDecoder().decode(WatchTunnelStatus.self, from: data)
    }

    public func save(_ status: WatchTunnelStatus) {
        guard let data = try? JSONEncoder().encode(status) else {
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    /// Removes any persisted status (e.g. in tests or on reset).
    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
