// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppLibrary
import CommonLibrary
import Foundation

// iOS side of the watch companion channel (Phase 14). Compiled into the app
// target only (platformFilter ios in project.pbxproj).

@preconcurrency import WatchConnectivity

/// Executes watch requests against the app context. Kept separate from the
/// `WCSessionDelegate` plumbing so the decision logic is readable and the
/// session class stays free of app state.
@MainActor
final class WatchMessageHandler {
    private let context: AppContextProtocol

    init(context: AppContextProtocol) {
        self.context = context
    }

    func handle(_ message: WatchTunnelMessage) async -> WatchTunnelMessage {
        switch message {
        case .requestStatus:
            return .status(currentStatus())
        case .connect(let profileId):
            return await connect(profileId: profileId)
        case .disconnect(let profileId):
            return await disconnect(profileId: profileId)
        case .status, .failure:
            // The watch never sends these; answer honestly instead of
            // pretending the request succeeded.
            return .failure("Unexpected message from watch")
        }
    }

    // MARK: Status

    private func currentStatus() -> WatchTunnelStatus {
        let store = TunnelWidgetStatusStore(defaults: context.appConfiguration.makeTunnelDefaults())
        // The store is kept fresh by the tunnel status notifier
        // (AppContext+Production.swift); fall back to live state when the app
        // has not written it yet.
        let state = store.load() ?? TunnelWidgetState(profiles: context.tunnelObservable.activeProfiles)
        return WatchTunnelStatus(state: state)
    }

    // MARK: Actions

    private func connect(profileId id: String) async -> WatchTunnelMessage {
        guard let profileId = Profile.ID(uuidString: id) else {
            return .failure("Invalid profile id")
        }
        guard let profile = context.profileObservable.profile(withId: profileId) else {
            return .failure("Profile not found")
        }
        do {
            try await context.tunnelObservable.connect(to: profile)
            return .status(currentStatus())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func disconnect(profileId id: String) async -> WatchTunnelMessage {
        guard let profileId = Profile.ID(uuidString: id) else {
            return .failure("Invalid profile id")
        }
        do {
            try await context.tunnelObservable.disconnect(from: profileId)
            return .status(currentStatus())
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

/// `WCSession` bridge on the iPhone. Delegate callbacks arrive on the
/// session's private queue; every app-state access hops to `@MainActor`.
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    private let handler: WatchMessageHandler

    init(context: AppContextProtocol) {
        handler = WatchMessageHandler(context: context)
    }

    func activate() {
        guard WCSession.isSupported() else {
            pspLog(.core, .info, "Watch: WatchConnectivity not supported")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: WCSessionDelegate (session's private queue)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        // Nothing to do: the watch requests status after its own activation.
        if let error {
            pspLog(.core, .error, "Watch: session activation failed: \(error)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        // Multiple-watch support (iOS 9.3+): nothing to release here.
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so the next paired watch can communicate.
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let incoming = WatchTunnelMessage(dictionary: message) else {
            replyHandler(WatchTunnelMessage.failure("Unrecognized message").encodedDictionary() ?? [:])
            return
        }
        Task { @MainActor [handler] in
            let response = await handler.handle(incoming)
            replyHandler(response.encodedDictionary() ?? [:])
        }
    }
}
