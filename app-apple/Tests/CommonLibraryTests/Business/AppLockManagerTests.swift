// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Testing

@MainActor
struct AppLockManagerTests {
    @Test
    func givenDisabled_whenAnyPhase_thenStaysUnlocked() {
        let sut = AppLockManager(isEnabled: false, initialState: .locked)
        #expect(sut.scenePhaseDidChange(.active) == false)
        #expect(sut.state == .unlocked)
        sut.scenePhaseDidChange(.background)
        #expect(sut.state == .unlocked)
    }

    @Test
    func givenEnabled_whenBackground_thenLocks() {
        let sut = AppLockManager(isEnabled: true, initialState: .unlocked)
        sut.scenePhaseDidChange(.background)
        #expect(sut.state == .locked)
    }

    @Test
    func givenEnabled_whenInactive_thenCovers() {
        let sut = AppLockManager(isEnabled: true, initialState: .unlocked)
        sut.scenePhaseDidChange(.inactive)
        #expect(sut.state == .covered)
    }

    @Test
    func givenCovered_whenActive_thenUnlockedWithoutAuthentication() {
        let sut = AppLockManager(isEnabled: true, initialState: .unlocked)
        sut.scenePhaseDidChange(.inactive)
        #expect(sut.scenePhaseDidChange(.active) == false)
        #expect(sut.state == .unlocked)
    }

    @Test
    func givenLocked_whenActive_thenRequestsAuthentication() {
        let sut = AppLockManager(isEnabled: true, initialState: .locked)
        #expect(sut.scenePhaseDidChange(.active) == true)
        #expect(sut.state == .locked)
        sut.completeUnlock(true)
        #expect(sut.state == .unlocked)
    }

    @Test
    func givenLocked_whenAuthenticationFails_thenStaysLocked() {
        let sut = AppLockManager(isEnabled: true, initialState: .locked)
        sut.scenePhaseDidChange(.active)
        sut.completeUnlock(false)
        #expect(sut.state == .locked)
    }

    @Test
    func givenUnlocked_whenDisabling_thenUnlocks() {
        let sut = AppLockManager(isEnabled: true, initialState: .locked)
        sut.isEnabled = false
        #expect(sut.state == .unlocked)
    }

    @Test
    func givenFullLifecycle_whenCycle_thenReturnsToLocked() {
        let sut = AppLockManager(isEnabled: true, initialState: .unlocked)
        sut.scenePhaseDidChange(.background)
        #expect(sut.scenePhaseDidChange(.active) == true)
        sut.completeUnlock(true)
        sut.scenePhaseDidChange(.inactive)
        sut.scenePhaseDidChange(.active)
        #expect(sut.state == .unlocked)
        sut.scenePhaseDidChange(.background)
        #expect(sut.state == .locked)
    }
}
