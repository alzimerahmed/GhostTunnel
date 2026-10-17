// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation
import Observation

/// Lock state of the app user interface.
///
/// - `unlocked`: content is visible and interactive.
/// - `covered`: app is temporarily inactive (e.g. app switcher), content is
///   hidden behind the privacy screen.
/// - `locked`: biometric/passcode authentication is required to reveal content.
public enum AppLockState: Equatable, Sendable {
    case unlocked

    case covered

    case locked
}

/// Scene phase abstraction decoupled from SwiftUI, so that the lock state
/// machine is unit-testable without UI.
public enum AppLockScenePhase: Equatable, Sendable {
    case active

    case inactive

    case background
}

/// Pure lock-state machine backing the App Lock feature (FaceID/passcode gate
/// + privacy screen). No UI dependencies: `LockableView` drives it from
/// `scenePhase` and the `LocalAuthentication` result.
///
/// State transitions (mirrors the historical `Lockable` behavior):
/// - `.background` while enabled: always re-lock.
/// - `.inactive` while unlocked: cover content (privacy screen).
/// - `.active` while disabled: reveal content unconditionally.
/// - `.active` while enabled and `.covered`: reveal without authentication.
/// - `.active` while enabled and `.locked`: caller must run authentication,
///   then report the outcome with `completeUnlock(_:)`.
@MainActor @Observable
public final class AppLockManager {
    public private(set) var state: AppLockState

    public var isEnabled: Bool {
        didSet {
            if !isEnabled {
                state = .unlocked
            }
        }
    }

    /// Shared by all lock-screen surfaces in the app so that they agree on a
    /// single lock state (main screen, modals, ...).
    public static let shared = AppLockManager()

    // For testing/previews
    public init(isEnabled: Bool = false, initialState: AppLockState = .locked) {
        self.isEnabled = isEnabled
        state = initialState
    }

    /// React to a scene phase change.
    ///
    /// - Returns: `true` if the caller must now run biometric/passcode
    ///   authentication to unlock (state was `.locked` on activation).
    @discardableResult
    public func scenePhaseDidChange(_ phase: AppLockScenePhase) -> Bool {
        switch phase {
        case .active:
            guard isEnabled else {
                state = .unlocked
                return false
            }
            switch state {
            case .locked:
                return true
            case .covered, .unlocked:
                state = .unlocked
                return false
            }

        case .inactive:
            if state == .unlocked {
                state = .covered
            }
            return false

        case .background:
            if isEnabled {
                state = .locked
            }
            return false
        }
    }

    /// Report the outcome of the unlock authentication prompt.
    public func completeUnlock(_ success: Bool) {
        guard success, state == .locked else {
            return
        }
        state = .unlocked
    }
}
