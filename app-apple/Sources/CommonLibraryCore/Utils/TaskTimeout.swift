// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

public struct TaskTimeoutError: Error {
}

/// Runs `block` with a hard wall-clock bound of `timeout` seconds.
///
/// Unlike a task-group race, this never awaits the losing child: the probe
/// child is cancelled and forgotten, so an uninterruptible call (e.g.
/// `getaddrinfo` on a detached task) cannot stall the caller past the
/// timeout. The orphaned task finishes (or leaks) in the background; the
/// caller is always unblocked within `timeout`.
public func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    _ block: @escaping @Sendable () async throws -> T
) async throws -> T {
    let box = TimeoutBox<T>()
    return try await withCheckedThrowingContinuation { continuation in
        box.store(continuation)
        let workTask = Task.detached(priority: .utility) {
            do {
                let value = try await block()
                box.resumeIfFirst(returning: value)
            } catch {
                box.resumeIfFirst(throwing: error)
            }
        }
        // Structured (not detached) so a cancelled caller unblocks
        // immediately with CancellationError instead of waiting.
        let timeoutTask = Task(priority: .utility) {
            do {
                try await Task.sleep(for: .seconds(timeout))
            } catch {
                box.resumeIfFirst(throwing: error)
                return
            }
            workTask.cancel()
            box.resumeIfFirst(throwing: TaskTimeoutError())
        }
        // If work wins the race, stop the sleeper early.
        Task(priority: .utility) {
            try? await workTask.value
            timeoutTask.cancel()
        }
    }
}

/// Resumes a continuation exactly once, from whichever racer finishes first.
private final class TimeoutBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var continuation: CheckedContinuation<T, Error>!

    func store(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        defer {
            lock.unlock()
        }
        self.continuation = continuation
    }

    func resumeIfFirst(returning value: T) {
        resumeIfFirst {
            $0.resume(returning: value)
        }
    }

    func resumeIfFirst(throwing error: Error) {
        resumeIfFirst {
            $0.resume(throwing: error)
        }
    }

    private func resumeIfFirst(_ body: (CheckedContinuation<T, Error>) -> Void) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !resumed else {
            return
        }
        resumed = true
        body(continuation)
    }
}
