// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppIntents
import AppLibrary
import CommonLibrary
import Foundation
import Partout
#if canImport(WidgetKit)
import WidgetKit
#endif

private func reloadWidgets() {
#if canImport(WidgetKit)
    WidgetCenter.shared.reloadAllTimelines()
#endif
}

// MARK: - Toggle (last-used profile)

/// Toggles the VPN on the last-used profile: connects when disconnected,
/// disconnects otherwise. Used by widgets, Control Center, and Shortcuts.
public struct ToggleTunnelIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle VPN"

    public static let description = IntentDescription(
        "Connects to the last-used profile, or disconnects if already connected."
    )

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let context = try QuickConnectContext()
        try await context.toggle()
        reloadWidgets()
        return .result()
    }
}

// ControlConfigurationIntent is unavailable before OS 18 on every platform,
// tvOS included; without the tvOS clause this conformance fails to compile
// when the package builds AppIntentsLibrary for tvOS (declared in
// Package.swift). macOS has no ControlConfigurationIntent conformance here
// (Control Center controls are iOS/tvOS only).
#if os(iOS) || os(tvOS)
@available(iOS 18.0, tvOS 18.0, *)
extension ToggleTunnelIntent: ControlConfigurationIntent {}
#endif

// MARK: - Connect to a specific profile

public struct ConnectProfileIntent: AppIntent {
    public static let title: LocalizedStringResource = "Connect VPN"

    public static let description = IntentDescription(
        "Connects to the selected profile."
    )

    @Parameter(title: "Profile")
    public var profile: ProfileEntity

    public init() {}

    public init(profile: ProfileEntity) {
        self.profile = profile
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard let profileId = Profile.ID(uuidString: profile.id) else {
            throw ABI.AppError.notFound
        }
        let context = try QuickConnectContext()
        try await context.connect(profileId: profileId)
        reloadWidgets()
        return .result()
    }
}

// MARK: - Disconnect

public struct DisconnectTunnelIntent: AppIntent {
    public static let title: LocalizedStringResource = "Disconnect VPN"

    public static let description = IntentDescription(
        "Disconnects the active profile, if any."
    )

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let context = try QuickConnectContext()
        if let activeId = TunnelWidgetStatusStore(
            defaults: context.appConfiguration.makeTunnelDefaults()
        ).load()?.profileId.flatMap(Profile.ID.init(uuidString:)) {
            try await context.disconnect(profileId: activeId)
        }
        reloadWidgets()
        return .result()
    }
}

// MARK: - Profile entity

public struct ProfileEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Profile")

    public static let defaultQuery = ProfileEntityQuery()

    public let id: String

    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var displayRepresentation: DisplayRepresentation {
        .init(title: "\(name)")
    }
}

public struct ProfileEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [ProfileEntity] {
        try await allEntities().filter {
            identifiers.contains($0.id)
        }
    }

    public func suggestedEntities() async throws -> [ProfileEntity] {
        try await allEntities()
    }

    public func defaultResult() async throws -> ProfileEntity? {
        try await allEntities().first
    }

    private func allEntities() async throws -> [ProfileEntity] {
        let context = try await QuickConnectContext()
        try await context.profileManager.observeLocal()
        let profiles = await context.profileManager.allProfiles()
        return profiles.map {
            ProfileEntity(id: $0.id.uuidString, name: $0.name)
        }
    }
}

// MARK: - Shortcuts provider

public struct TunnelAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleTunnelIntent(),
            phrases: [
                "Toggle \(.applicationName)",
                "Connect \(.applicationName)"
            ],
            shortTitle: "Connect VPN",
            systemImageName: "globe"
        )
    }
}
