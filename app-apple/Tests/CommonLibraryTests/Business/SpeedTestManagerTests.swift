// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Partout
import Testing

struct SpeedTestManagerTests {
    // MARK: Mock probe

    /// Records concurrency and per-host latency/failure behavior.
    private actor MockProbe: LatencyProbe {
        private var inFlight = 0
        private var _maxInFlight = 0
        private var _probedHosts: [String] = []

        let latenciesByHost: [String: TimeInterval]
        let failingHosts: Set<String>
        let delay: TimeInterval

        init(
            latenciesByHost: [String: TimeInterval] = [:],
            failingHosts: Set<String> = [],
            delay: TimeInterval = 0.01
        ) {
            self.latenciesByHost = latenciesByHost
            self.failingHosts = failingHosts
            self.delay = delay
        }

        var maxInFlight: Int {
            _maxInFlight
        }

        var probedHosts: [String] {
            _probedHosts
        }

        func probe(host: String, port: UInt16, usesTCP: Bool) async throws -> TimeInterval {
            inFlight += 1
            _maxInFlight = max(_maxInFlight, inFlight)
            defer {
                inFlight -= 1
            }
            try await Task.sleep(for: .seconds(delay))
            _probedHosts.append(host)
            if failingHosts.contains(host) {
                throw LatencyProbeError.resolutionFailed(-1)
            }
            return latenciesByHost[host] ?? 0.1
        }
    }

    private func target(_ id: String, host: String = "host", port: UInt16 = 1194, usesTCP: Bool = true) -> ProbeTarget {
        ProbeTarget(id: id, host: host, port: port, usesTCP: usesTCP)
    }

    // MARK: Scheduling

    @Test
    func givenTargets_whenRun_thenResultsMatchInputOrder() async {
        let probe = MockProbe()
        let scheduler = ProbeScheduler(probe: probe, maxConcurrent: 2, timeout: 5)
        let targets = [
            target("a"),
            target("b"),
            target("c")
        ]
        let results = await scheduler.run(targets)
        #expect(results.map(\.target.id) == ["a", "b", "c"])
        #expect(await probe.probedHosts.count == 3)
        #expect(results.allSatisfy(\.isSuccess))
    }

    @Test
    func givenManyTargets_whenRun_thenConcurrencyIsBounded() async {
        let probe = MockProbe(delay: 0.05)
        let scheduler = ProbeScheduler(probe: probe, maxConcurrent: 2, timeout: 5)
        let targets = (0..<8).map { target("t\($0)") }
        _ = await scheduler.run(targets)
        #expect(await probe.maxInFlight <= 2)
    }

    @Test
    func givenFailingHost_whenRun_thenResultHasErrorAndNoLatency() async {
        let probe = MockProbe(failingHosts: ["bad"])
        let scheduler = ProbeScheduler(probe: probe)
        let results = await scheduler.run([target("ok"), target("bad", host: "bad")])
        #expect(results[0].isSuccess)
        #expect(!results[1].isSuccess)
        #expect(results[1].latency == nil)
        #expect(results[1].error != nil)
    }

    @Test
    func givenEmptyTargets_whenRun_thenNoResults() async {
        let scheduler = ProbeScheduler(probe: MockProbe())
        let results = await scheduler.run([])
        #expect(results.isEmpty)
    }

    // MARK: Fastest selection

    @Test
    func givenResults_whenFastest_thenLowestLatencyWins() {
        let results = [
            ProbeResult(target: target("a"), latency: 0.3),
            ProbeResult(target: target("b"), latency: 0.1),
            ProbeResult(target: target("c"), latency: 0.2)
        ]
        #expect(SpeedTestManager.fastest(in: results)?.target.id == "b")
    }

    @Test
    func givenFailedProbes_whenFastest_thenFailuresAreExcluded() {
        let results = [
            ProbeResult(target: target("a"), latency: nil, error: "timeout"),
            ProbeResult(target: target("b"), latency: 0.5)
        ]
        #expect(SpeedTestManager.fastest(in: results)?.target.id == "b")
    }

    @Test
    func givenNoSuccessfulProbes_whenFastest_thenNil() {
        let results = [
            ProbeResult(target: target("a"), latency: nil, error: "timeout")
        ]
        #expect(SpeedTestManager.fastest(in: results) == nil)
        #expect(SpeedTestManager.fastest(in: []) == nil)
    }

    // MARK: Reordering

    @Test
    func givenResults_whenOrderedKeys_thenFastestFirstFailuresLast() {
        let results = [
            ProbeResult(target: target("a"), latency: 0.3),
            ProbeResult(target: target("b"), latency: 0.1),
            ProbeResult(target: target("c"), latency: nil, error: "timeout")
        ]
        #expect(SpeedTestManager.orderedKeys(["a", "b", "c"], by: results) == ["b", "a", "c"])
    }

    @Test
    func givenUnprobedKeys_whenOrderedKeys_thenTheyKeepOrderAtEnd() {
        let results = [
            ProbeResult(target: target("b"), latency: 0.1)
        ]
        #expect(SpeedTestManager.orderedKeys(["a", "b", "c"], by: results) == ["b", "a", "c"])
    }

    @Test
    func givenTiesAndFailures_whenOrderedKeys_thenStableOrder() {
        let results = [
            ProbeResult(target: target("a"), latency: 0.1),
            ProbeResult(target: target("b"), latency: 0.1),
            ProbeResult(target: target("c"), latency: nil, error: "x"),
            ProbeResult(target: target("d"), latency: nil, error: "x")
        ]
        #expect(SpeedTestManager.orderedKeys(["a", "b", "c", "d"], by: results) == ["a", "b", "c", "d"])
    }

    @Test
    func givenRemotes_whenReorderedByLatency_thenFastestFirst() throws {
        let remotes = [
            try ExtendedEndpoint("1.2.3.4", .init(.udp, 1194)),
            try ExtendedEndpoint("5.6.7.8", .init(.tcp, 443)),
            try ExtendedEndpoint("9.9.9.9", .init(.udp, 53))
        ]
        let results = [
            ProbeResult(target: remotes[1].probeTarget, latency: 0.05),
            ProbeResult(target: remotes[2].probeTarget, latency: 0.2),
            ProbeResult(target: remotes[0].probeTarget, latency: nil, error: "timeout")
        ]
        let reordered = ExtendedEndpoint.reorderedByLatency(remotes, results: results)
        #expect(reordered[0].address.rawValue == "5.6.7.8")
        #expect(reordered[1].address.rawValue == "9.9.9.9")
        #expect(reordered[2].address.rawValue == "1.2.3.4")
    }

    // MARK: probeKey

    @Test
    func givenSameHostPortWithDifferentSocketTypes_whenProbeKey_thenKeysDiffer() throws {
        let udp = try ExtendedEndpoint("1.2.3.4", .init(.udp, 1194))
        let tcp = try ExtendedEndpoint("1.2.3.4", .init(.tcp, 1194))
        // Regression: same host:port over udp and tcp must be two distinct
        // probe targets, not one colliding key.
        #expect(udp.probeKey != tcp.probeKey)
        #expect(udp.probeTarget.id != tcp.probeTarget.id)
        #expect(udp.probeTarget.usesTCP == false)
        #expect(tcp.probeTarget.usesTCP == true)
    }

    // MARK: Re-entrancy

    @Test
    func givenRunningTest_whenTestRunsAgain_thenOnlyLatestResultsArePublished() async {
        let slowScheduler = ProbeScheduler(probe: MockProbe(delay: 0.5), maxConcurrent: 1, timeout: 5)
        let fastScheduler = ProbeScheduler(probe: MockProbe(delay: 0.01), maxConcurrent: 1, timeout: 5)
        let manager = SpeedTestManager()
        let firstTask = Task {
            await manager.test([target("slow")], scheduler: slowScheduler)
        }
        // Give the first run a head start, then supersede it.
        try? await Task.sleep(for: .seconds(0.05))
        await manager.test([target("fast")], scheduler: fastScheduler)
        _ = await firstTask.result
        #expect(!manager.isRunning)
        #expect(manager.results.count == 1)
        #expect(manager.results.first?.target.id == "fast")
    }

    // MARK: Timeout bounds the wall clock

    @Test
    func givenHungProbe_whenSchedulerTimeoutElapses_thenRunReturnsBounded() async {
        // A probe that ignores cancellation (like getaddrinfo on a detached
        // task): the old task-group-based timeout would hang on it.
        struct UninterruptibleProbe: LatencyProbe {
            func probe(host: String, port: UInt16, usesTCP: Bool) async throws -> TimeInterval {
                try? await Task.sleep(for: .seconds(30))
                return 0.1
            }
        }
        let scheduler = ProbeScheduler(probe: UninterruptibleProbe(), timeout: 0.2)
        let start = Date()
        let results = await scheduler.run([target("hung")])
        let elapsed = Date().timeIntervalSince(start)
        #expect(!results[0].isSuccess)
        #expect(results[0].error != nil)
        #expect(elapsed < 5)
    }
}
