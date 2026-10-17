// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import CommonLibrary
import Foundation
import Partout
import PartoutRuntime

/// Lightweight application context for App Intents surfaces (Shortcuts,
/// widgets, Control Center). Assembles only the tunnel/profile machinery of
/// `AppContext.forProduction` — no IAP, config, version, or web receiver —
/// so extensions can connect/disconnect without spinning up the full app.
@MainActor
public final class QuickConnectContext {
    public let appConfiguration: ABI.AppConfiguration

    public let preferences: AppPreferencesStore

    public let profileManager: ProfileManager

    public let tunnelObservable: TunnelObservable

    public init() throws {
        let distributionTarget: ABI.DistributionTarget
#if os(macOS)
        distributionTarget = .developerID
#else
        distributionTarget = .appStore
#endif
        let appConfiguration = Resources.newAppConfiguration(
            distributionTarget: distributionTarget,
            buildTarget: .app
        )
        let defaults: UserDefaults = .standard
        let preferences = AppPreferencesStore(
            UserDefaultsAppPreferences(defaults: defaults)
        )

        let logFormatter = appConfiguration.makeLogFormatter()
        let ctx = pspLogRegister(
            for: .app,
            with: appConfiguration,
            preferences: preferences,
            localURL: appConfiguration.urlForAppLog,
            localMapper: logFormatter.localMapper
        )

        let runtime = PartoutRuntime()

        let appImportExport = AppImportExport(
            configBlock: {
                preferences.enabledFlags(of: [])
            },
            importModule: { text, context in
                try runtime.importModule(from: text, context: context)
            },
            exportModule: { module in
                try runtime.exportModule(module)
            }
        )

        // MARK: Persistence (Keychain-backed, as in production)

        let codingPair = appConfiguration.makeKeychainAndNECoder(
            ctx,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            coder: appImportExport
        )
        let mainProfileRepository = KeychainProfileRepository(
            keychain: codingPair.keychain,
            coder: appImportExport,
            bootstrap: nil,
            label: appConfiguration.makeKeychainTitle()
        )
        let tunnelStrategy = appConfiguration.makeNETunnelStrategy(
            ctx,
            coder: codingPair.neCoder,
            source: mainProfileRepository.eventsPublisher
        )

        let tunnelProcessor = appConfiguration.makeAppTunnelProcessor(
            profileRepository: mainProfileRepository,
            extensionInstaller: nil
        )
        let profileProcessor = appConfiguration.makeAppProfileProcessor(iapManager: nil)
        let profileManager = ProfileManager(
            processor: profileProcessor,
            repository: mainProfileRepository,
            backupRepository: nil,
            mirrorsRemoteRepository: false
        )
        let tunnel = PartoutTunnel(
            ctx,
            strategy: tunnelStrategy,
            refreshInterval: Int(appConfiguration.constants.tunnel.refreshInterval * 1000.0),
            environmentFactory: { @Sendable in
                appConfiguration.makeAppTunnelEnvironment(strategy: tunnelStrategy, profileId: $0)
            }
        )
        let tunnelObservable = TunnelObservable(
            tunnel: tunnel,
            preferences: preferences,
            willInstall: tunnelProcessor.willInstall
        )

        self.appConfiguration = appConfiguration
        self.preferences = preferences
        self.profileManager = profileManager
        self.tunnelObservable = tunnelObservable
    }
}

// MARK: - Actions

extension QuickConnectContext {
    /// Loads local profiles, then connects to the given profile.
    public func connect(profileId: Profile.ID) async throws {
        try await withLoadedProfiles {
            guard let profile = await self.profileManager.profile(withId: profileId) else {
                throw ABI.AppError.notFound
            }
            try await self.tunnelObservable.connect(to: profile)
        }
    }

    /// Disconnects the given profile (no-op when not installed).
    public func disconnect(profileId: Profile.ID) async throws {
        try await tunnelObservable.disconnect(from: profileId)
    }

    /// Decides and executes the quick-connect action for the last-used
    /// profile: connect when disconnected, disconnect otherwise.
    public func toggle() async throws {
        let action = try await withLoadedProfiles {
            let lastUsedId = self.preferences[\.lastUsedProfileId]
            let headers = await self.profileManager.allProfiles().map {
                $0.abiHeaderWithBogusFlagsAndRequirements()
            }
            let current = TunnelWidgetStatusStore(defaults: self.appConfiguration.makeTunnelDefaults()).load()
            return QuickConnectPlanner.action(
                current: current,
                profiles: headers,
                lastUsedProfileId: lastUsedId
            )
        }
        switch action {
        case .connect(let profileId):
            try await connect(profileId: profileId)
            saveOptimisticState(.connecting, profileId: profileId)
        case .disconnect(let profileId):
            try await disconnect(profileId: profileId)
            saveOptimisticState(.disconnected, profileId: profileId)
        case .none:
            break
        }
    }
}

private extension QuickConnectContext {
    /// The app may not be running to observe the real tunnel status, so
    /// write an optimistic state that the app will correct on next launch.
    func saveOptimisticState(_ kind: TunnelWidgetState.Kind, profileId: Profile.ID) {
        let store = TunnelWidgetStatusStore(defaults: appConfiguration.makeTunnelDefaults())
        var state = store.load() ?? TunnelWidgetState(kind: kind)
        state.kind = kind
        state.profileId = profileId.uuidString
        state.lastUpdate = Date()
        store.save(state)
    }
}

private extension QuickConnectContext {
    func withLoadedProfiles<T>(_ block: @MainActor () async throws -> T) async throws -> T {
        try await profileManager.observeLocal()
        return try await block()
    }
}
