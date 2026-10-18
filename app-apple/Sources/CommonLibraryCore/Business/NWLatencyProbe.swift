// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Darwin
import Foundation
import Network

/// Default `LatencyProbe` built on Apple frameworks only (no third-party
/// dependencies):
///
/// - TCP endpoints: `NWConnection` TCP handshake timing (connect → `.ready`).
///   No application payload is sent to the endpoint.
/// - UDP endpoints: DNS resolution timing of the host via `getaddrinfo`
///   (`dnssd`-free, Foundation/Darwin only). UDP has no reliable app-layer
///   handshake without speaking the tunnel protocol, so DNS latency is the
///   documented proxy metric (ADR-007 in docs/research.md).
public struct NWLatencyProbe: LatencyProbe {
    public init() {
    }

    public func probe(host: String, port: UInt16, usesTCP: Bool) async throws -> TimeInterval {
        if usesTCP {
            return try await tcpHandshakeLatency(host: host, port: port)
        }
        return try await dnsResolutionLatency(host: host)
    }

    // MARK: TCP handshake

    private func tcpHandshakeLatency(host: String, port: UInt16) async throws -> TimeInterval {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw LatencyProbeError.invalidPort
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let finisher = Finisher { result in
                    connection.cancel()
                    continuation.resume(with: result)
                }
                let start = Date()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        finisher.finish(.success(Date().timeIntervalSince(start)))
                    case .failed(let error):
                        finisher.finish(.failure(error))
                    case .cancelled:
                        finisher.finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .utility))
            }
        } onCancel: {
            connection.cancel()
        }
    }

    // MARK: DNS resolution

    private func dnsResolutionLatency(host: String) async throws -> TimeInterval {
        let start = Date()
        _ = try await Self.resolve(host: host)
        return Date().timeIntervalSince(start)
    }

    /// Resolves `host` off the main thread, returning textual addresses.
    static func resolve(host: String) async throws -> [String] {
        guard !host.isEmpty else {
            throw LatencyProbeError.emptyHost
        }
        return try await Task.detached(priority: .utility) {
            var info: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, nil, nil, &info)
            guard status == 0, let first = info else {
                throw LatencyProbeError.resolutionFailed(status)
            }
            defer {
                freeaddrinfo(first)
            }
            var addresses: [String] = []
            var cursor: UnsafeMutablePointer<addrinfo>? = first
            while let current = cursor {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    current.pointee.ai_addr,
                    current.pointee.ai_addrlen,
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    addresses.append(String(cString: buffer))
                }
                cursor = current.pointee.ai_next
            }
            guard !addresses.isEmpty else {
                throw LatencyProbeError.resolutionFailed(status)
            }
            return addresses
        }.value
    }
}

public enum LatencyProbeError: Error {
    case emptyHost
    case invalidPort
    case resolutionFailed(Int32)
}

/// Once-only result gate, safe to call from any queue/actor.
private final class Finisher: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let handler: @Sendable (Result<TimeInterval, Error>) -> Void

    init(handler: @escaping @Sendable (Result<TimeInterval, Error>) -> Void) {
        self.handler = handler
    }

    func finish(_ result: Result<TimeInterval, Error>) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !finished else {
            return
        }
        finished = true
        handler(result)
    }
}
