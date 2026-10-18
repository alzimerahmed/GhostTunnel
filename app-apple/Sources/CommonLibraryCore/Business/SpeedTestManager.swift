// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation
import Partout

/// A single endpoint to probe for latency.
///
/// `id` is an opaque key chosen by the caller (e.g. `"host:port"` for an
/// OpenVPN remote) so results can be mapped back to domain objects without
/// SpeedTestManager knowing about them.
public struct ProbeTarget: Hashable, Sendable {
    public let id: String
    public let host: String
    public let port: UInt16

    /// TCP endpoints are probed with a TCP handshake; UDP endpoints fall back
    /// to a DNS-resolution timing probe (see ADR-007 in docs/research.md).
    public let usesTCP: Bool

    public init(id: String, host: String, port: UInt16, usesTCP: Bool) {
        self.id = id
        self.host = host
        self.port = port
        self.usesTCP = usesTCP
    }
}

/// The outcome of probing one `ProbeTarget`.
public struct ProbeResult: Equatable, Sendable {
    public let target: ProbeTarget

    /// Round-trip latency in seconds, `nil` when the probe failed.
    public let latency: TimeInterval?

    public let error: String?

    public var isSuccess: Bool {
        latency != nil
    }

    public init(target: ProbeTarget, latency: TimeInterval?, error: String? = nil) {
        self.target = target
        self.latency = latency
        self.error = error
    }
}

/// Measures the latency of one endpoint. Injectable for tests.
public protocol LatencyProbe: Sendable {
    func probe(host: String, port: UInt16, usesTCP: Bool) async throws -> TimeInterval
}

/// Runs a set of probes with bounded concurrency and per-probe timeouts.
/// Results are returned in the same order as the input targets.
public actor ProbeScheduler {
    private let probe: any LatencyProbe
    private let maxConcurrent: Int
    private let timeout: TimeInterval

    public init(probe: any LatencyProbe, maxConcurrent: Int = 4, timeout: TimeInterval = 5.0) {
        self.probe = probe
        self.maxConcurrent = max(1, maxConcurrent)
        self.timeout = timeout
    }

    public func run(_ targets: [ProbeTarget]) async -> [ProbeResult] {
        let probe = self.probe
        let timeout = self.timeout
        var iterator = targets.enumerated().makeIterator()
        return await withTaskGroup(of: (Int, ProbeResult).self) { group in
            // Prime the group with up to `maxConcurrent` probes, then add a
            // new one every time one finishes.
            for _ in 0..<maxConcurrent {
                guard let (index, target) = iterator.next() else {
                    break
                }
                group.addTask {
                    (index, await Self.probed(target, with: probe, timeout: timeout))
                }
            }
            var indexed: [Int: ProbeResult] = [:]
            while let (index, result) = await group.next() {
                indexed[index] = result
                if let (nextIndex, nextTarget) = iterator.next() {
                    group.addTask {
                        (nextIndex, await Self.probed(nextTarget, with: probe, timeout: timeout))
                    }
                }
            }
            return targets.indices.compactMap {
                indexed[$0]
            }
        }
    }

    private static func probed(
        _ target: ProbeTarget,
        with probe: any LatencyProbe,
        timeout: TimeInterval
    ) async -> ProbeResult {
        do {
            let latency = try await withTimeout(timeout) {
                try await probe.probe(host: target.host, port: target.port, usesTCP: target.usesTCP)
            }
            return ProbeResult(target: target, latency: latency)
        } catch is CancellationError {
            return ProbeResult(target: target, latency: nil, error: "cancelled")
        } catch is TaskTimeoutError {
            return ProbeResult(target: target, latency: nil, error: "The connection attempt timed out.")
        } catch {
            return ProbeResult(target: target, latency: nil, error: error.localizedDescription)
        }
    }
}

/// Observable facade over `ProbeScheduler` for SwiftUI.
@MainActor @Observable
public final class SpeedTestManager {
    public private(set) var results: [ProbeResult] = []

    public private(set) var isRunning = false

    private var runId = UUID()


    public init() {
    }

    /// Probes all targets and stores the results. Re-running cancels the
    /// previous run; a superseded run never writes its (stale) results.
    public func test(_ targets: [ProbeTarget], scheduler: ProbeScheduler? = nil) async {
        task?.cancel()
        let effectiveScheduler = scheduler ?? ProbeScheduler(probe: NWLatencyProbe())
        let id = UUID()
        runId = id
        isRunning = true
        let results = await effectiveScheduler.run(targets)
        // Run identity check: only the latest run may publish results or
        // clear `isRunning` (a superseded run must not clobber the newer one).
        guard runId == id else {
            return
        }
        self.results = results
        isRunning = false
    }

    public func cancel() {
        runId = UUID()
        task?.cancel()
    }

    /// The fastest successful probe, if any.
    public nonisolated static func fastest(in results: [ProbeResult]) -> ProbeResult? {
        let successes = results.filter(\.isSuccess)
        guard !successes.isEmpty else {
            return nil
        }
        // `isSuccess` guarantees a non-nil latency.
        return successes.min {
            $0.latency! < $1.latency!
        }
    }

    /// Pure reordering logic: given keys (one per item, same order) and probe
    /// results keyed by `ProbeTarget.id`, returns the keys sorted by latency
    /// (fastest first). Failed and unprobed keys keep their original relative
    /// order at the end. Testable without Partout types.
    public nonisolated static func orderedKeys(_ keys: [String], by results: [ProbeResult]) -> [String] {
        let latencies = Dictionary(
            results.map {
                ($0.target.id, $0.latency)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return keys
            .enumerated()
            .map {
                (index: $0.offset, key: $0.element, latency: latencies[$0.element])
            }
            .sorted {
                let a = $0.latency ?? Double.infinity
                let b = $1.latency ?? Double.infinity
                if a != b {
                    return a < b
                }
                return $0.index < $1.index
            }
            .map(\.key)
    }
}

// MARK: - Partout mapping

extension ExtendedEndpoint {
    var probeKey: String {
        // Socket type is part of the key: the same host:port may be listed
        // twice (udp + tcp) and must yield two distinct probe targets.
        "\(address.rawValue):\(proto.port):\(proto.socketType.rawValue)"
    }

    var probeTarget: ProbeTarget {
        ProbeTarget(
            id: probeKey,
            host: address.rawValue,
            port: proto.port,
            usesTCP: proto.socketType.rawValue.hasPrefix("tcp")
        )
    }

    /// Reorders OpenVPN remotes so the fastest probed endpoint comes first.
    /// Remotes that were not probed (or failed) keep their original order.
    public static func reorderedByLatency(
        _ remotes: [ExtendedEndpoint],
        results: [ProbeResult]
    ) -> [ExtendedEndpoint] {
        let keys = remotes.map(\.probeKey)
        let orderedKeys = SpeedTestManager.orderedKeys(keys, by: results)
        let rank = Dictionary(
            orderedKeys.enumerated().map {
                ($0.element, $0.offset)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return remotes
            .enumerated()
            .map {
                (index: $0.offset, remote: $0.element, rank: rank[$0.element.probeKey] ?? .max)
            }
            .sorted {
                if $0.rank != $1.rank {
                    return $0.rank < $1.rank
                }
                return $0.index < $1.index
            }
            .map(\.remote)
    }
}
