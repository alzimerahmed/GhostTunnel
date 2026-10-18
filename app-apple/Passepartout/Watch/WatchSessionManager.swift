// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation
import Observation
import WidgetKit

@preconcurrency import WatchConnectivity

/// Watch-side session bridge: requests status from the phone, forwards
/// connect/disconnect taps, and persists every received status into the App
/// Group store so the complication can read it in its own process.
///
/// Delegate callbacks arrive on the session's private queue; every state
/// access hops to `@MainActor`.
@MainActor
@Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {
    private(set) var status: WatchTunnelStatus?

    private(set) var lastError: String?

    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else {
            lastError = "WatchConnectivity is not supported"
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        requestStatus()
    }

    // MARK: Actions

    func requestStatus() {
        send(.requestStatus)
    }

    func connect() {
        guard let profileId = status?.profileId else {
            lastError = "No profile to connect"
            return
        }
        send(.connect(profileId: profileId))
    }

    func disconnect() {
        guard let profileId = status?.profileId else {
            lastError = "No profile to disconnect"
            return
        }
        send(.disconnect(profileId: profileId))
    }

    // MARK: Sending

    private func send(_ message: WatchTunnelMessage) {
        guard let session, session.activationState == .activated else {
            lastError = "Not connected to iPhone"
            return
        }
        guard let payload = message.encodedDictionary() else {
            lastError = "Unable to encode message"
            return
        }
        lastError = nil
        session.sendMessage(payload, replyHandler: { [weak self] reply in
            Task { @MainActor [weak self] in
                self?.apply(WatchTunnelMessage(dictionary: reply))
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor [weak self] in
                self?.lastError = error.localizedDescription
            }
        })
    }

    // MARK: Receiving

    private func apply(_ message: WatchTunnelMessage?) {
        switch message {
        case .status(let status):
            self.status = status
            lastError = nil
            persist(status)
        case .failure(let reason):
            lastError = reason
        case .none, .requestStatus, .connect, .disconnect:
            break
        }
    }

    private func persist(_ status: WatchTunnelStatus) {
        guard let defaults = WatchAppGroup.defaults else {
            return
        }
        WatchStatusStore(defaults: defaults).save(status)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: WCSessionDelegate (session's private queue)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if let error {
            Task { @MainActor [weak self] in
                self?.lastError = error.localizedDescription
            }
        } else if activationState == .activated {
            Task { @MainActor [weak self] in
                self?.requestStatus()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.apply(WatchTunnelMessage(dictionary: message))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // The phone only ever replies to watch requests; acknowledge and
        // process the payload like any proactive push.
        replyHandler([:])
        Task { @MainActor [weak self] in
            self?.apply(WatchTunnelMessage(dictionary: message))
        }
    }
}
