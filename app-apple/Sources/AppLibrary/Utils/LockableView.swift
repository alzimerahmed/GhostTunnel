// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

#if !os(tvOS)

import CommonLibrary
import SwiftUI

public struct LockableView<Content: View, LockedContent: View>: View {

    @Environment(\.scenePhase)
    private var scenePhase

    // unobserved here, observed in LockedContentWrapper
    private let lock: AppLockManager

    private let locksInBackground: Bool

    private let content: () -> Content

    private let lockedContent: () -> LockedContent

    private let unlockBlock: () async -> Bool

    @MainActor
    public init(
        locksInBackground: Bool,
        content: @escaping () -> Content,
        lockedContent: @escaping () -> LockedContent,
        unlockBlock: @escaping () async -> Bool
    ) {
        lock = AppLockManager.shared
        lock.isEnabled = locksInBackground
        self.locksInBackground = locksInBackground
        self.content = content
        self.lockedContent = lockedContent
        self.unlockBlock = unlockBlock
    }

    public var body: some View {
        debugChanges()
        return ZStack {
            content()
            if locksInBackground {
                LockedContentWrapperView(
                    lock: lock,
                    content: lockedContent
                )
            }
        }
        .onChange(of: scenePhase, onScenePhase)
    }
}

// MARK: -

@MainActor
private extension LockableView {
    func onScenePhase() {
        switch scenePhase {
        case .active:
            if lock.scenePhaseDidChange(.active) {
                Task {
                    guard await unlockBlock() else {
                        return
                    }
                    lock.completeUnlock(true)
                }
            }

        case .inactive:
            lock.scenePhaseDidChange(.inactive)

        case .background:
            lock.scenePhaseDidChange(.background)

        default:
            break
        }
    }
}

// MARK: -

private struct LockedContentWrapperView<Content>: View where Content: View {
    let lock: AppLockManager

    @ViewBuilder
    let content: Content

    var body: some View {
        if lock.state != .unlocked {
            content
        }
    }
}

#endif
