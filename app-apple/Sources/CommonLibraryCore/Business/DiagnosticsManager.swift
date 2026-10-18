// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

// MARK: - Log sanitization

/// Redacts key material and secrets from log lines destined for a debug
/// bundle. Deliberately aggressive: a false-positive redaction in a debug log
/// is harmless, a leaked WireGuard private key is not.
public enum LogSanitizer {
    private static let pemBegin = "-----BEGIN"
    private static let pemEnd = "-----END"

    /// `key = value` / `key: value` where the key names a secret.
    private nonisolated(unsafe) static let secretAssignment = /(?i)\b(private[_-]?key|public[_-]?key|password|passphrase|secret|authorization|auth[-_]?token|auth[-_]?user[-_]?pass|token|psk|pre[-_]?shared[_-]?key|static[_-]?key|cookie)\b\s*([=:])\s*\S.*/

    /// An `auth-user-pass` directive line: the credentials follow on the
    /// next line (inline credentials block).
    private nonisolated(unsafe) static let authUserPassMarker = /(?i)\bauth[-_]?user[-_]?pass\b/

    /// Base64-encoded 256-bit keys (WireGuard format: 44 chars ending in `=`).
    private nonisolated(unsafe) static let base64Key = /[A-Za-z0-9+\/]{43}=/

    /// Hex-encoded 256-bit keys.
    private nonisolated(unsafe) static let hexKey = /\b[0-9a-fA-F]{64}\b/

    public static func sanitize(_ lines: [String]) -> [String] {
        var isInsidePEM = false
        var redactNextLine = false
        return lines.map { line in
            if line.contains(pemBegin) {
                isInsidePEM = !line.contains(pemEnd)
                return "[REDACTED PEM BLOCK]"
            }
            if isInsidePEM {
                if line.contains(pemEnd) {
                    isInsidePEM = false
                }
                return "[REDACTED PEM BLOCK]"
            }
            defer {
                // The line after an `auth-user-pass` marker carries the
                // inline credentials.
                redactNextLine = line.firstMatch(of: authUserPassMarker) != nil
            }
            if redactNextLine {
                return "[REDACTED CREDENTIALS]"
            }
            var sanitized = line
                .replacing(secretAssignment) { match in
                    "\(match.1)\(match.2) [REDACTED]"
                }
                .replacing(base64Key) { _ in
                    "[REDACTED KEY]"
                }
                .replacing(hexKey) { _ in
                    "[REDACTED KEY]"
                }
            // A bare PEM body line (no BEGIN/END markers around it).
            if isLikelyPEMBody(sanitized) {
                sanitized = "[REDACTED PEM BLOCK]"
            }
            return sanitized
        }
    }

    private static func isLikelyPEMBody(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 64 && trimmed.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "="
        }
    }
}

// MARK: - Debug bundle

/// One named block of a debug bundle (e.g. "App log", "Tunnel state").
public struct DebugBundleSection: Sendable {
    public let name: String
    public let lines: [String]

    public init(name: String, lines: [String]) {
        self.name = name
        self.lines = lines
    }
}

/// Assembles a sanitized, self-contained debug bundle as plain text. The
/// bundle contains NO key material (enforced by `LogSanitizer`, tested) and
/// never leaves the device unless the user shares it explicitly.
public enum DebugBundleBuilder {
    public static func build(sections: [DebugBundleSection], generatedAt: Date = Date()) -> String {
        var output: [String] = [
            "GhostTunnel debug bundle",
            "Generated: \(generatedAt)",
            "Sanitized: key material redacted",
            ""
        ]
        for section in sections {
            output.append("== \(section.name) ==")
            output.append(contentsOf: LogSanitizer.sanitize(section.lines))
            output.append("")
        }
        return output.joined(separator: "\n")
    }

    /// Writes the bundle to a temporary file and returns its URL for sharing.
    /// The file name includes sub-second precision so two exports in the same
    /// second never overwrite each other.
    public static func write(sections: [DebugBundleSection]) throws -> URL {
        let content = build(sections: sections)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GhostTunnel-debug-\(stamp).txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Leak test

/// One check of the leak test. `value` is what the user compares against
/// their expectation (e.g. the VPN exit IP).
public struct LeakTestCheck: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case publicIP
        case dnsResolution
    }

    public let kind: Kind
    public let label: String
    public let value: String?
    public let error: String?

    public var id: String {
        label
    }

    public var isSuccess: Bool {
        error == nil && value != nil
    }

    public init(kind: Kind, label: String, value: String?, error: String? = nil) {
        self.kind = kind
        self.label = label
        self.value = value
        self.error = error
    }
}

/// Performs the leak test. Injectable for tests.
public protocol LeakTestChecking: Sendable {
    /// Fetches the public IP via a documented public checker endpoint.
    func publicIP() async throws -> String

    /// Resolves a host via the system resolver.
    func resolve(host: String) async throws -> [String]
}

/// Local-only leak test manager. Results are displayed in-app and never
/// persisted or transmitted anywhere beyond the check requests themselves
/// (public IP via documented public checkers, DNS via the system resolver).
/// NO telemetry.
@MainActor @Observable
public final class LeakTestManager {
    public enum State: Equatable {
        case idle
        case running
        case done([LeakTestCheck])
        case failed(String)
    }

    public private(set) var state: State = .idle

    /// Wall-clock bound for each check (DNS resolution is uninterruptible).
    public static let defaultCheckTimeout: TimeInterval = 10

    /// Hosts checked for DNS resolution. A stable, well-known anycast host is
    /// used so the user can eyeball whether answers look like VPN-side DNS.
    public static let dnsCheckHosts = ["one.one.one.one", "www.cloudflare.com"]

    private let checker: any LeakTestChecking

    private let checkTimeout: TimeInterval

    public init(
        checker: any LeakTestChecking = URLSessionLeakTestChecker(),
        checkTimeout: TimeInterval = LeakTestManager.defaultCheckTimeout
    ) {
        self.checker = checker
        self.checkTimeout = checkTimeout
    }

    public func run() async {
        state = .running
        var checks: [LeakTestCheck] = []
        do {
            let ip = try await withTimeout(checkTimeout) {
                try await self.checker.publicIP()
            }
            checks.append(LeakTestCheck(
                kind: .publicIP,
                label: "Public IP",
                value: ip
            ))
        } catch {
            checks.append(LeakTestCheck(
                kind: .publicIP,
                label: "Public IP",
                value: nil,
                error: Self.describe(error)
            ))
        }
        for host in Self.dnsCheckHosts {
            do {
                let addresses = try await withTimeout(checkTimeout) {
                    try await self.checker.resolve(host: host)
                }
                checks.append(LeakTestCheck(
                    kind: .dnsResolution,
                    label: host,
                    value: addresses.prefix(3).joined(separator: ", ")
                ))
            } catch {
                checks.append(LeakTestCheck(
                    kind: .dnsResolution,
                    label: host,
                    value: nil,
                    error: Self.describe(error)
                ))
            }
        }
        // Every check failed: surface a failure state rather than a list of
        // errors (e.g. no network at all).
        if checks.allSatisfy({ !$0.isSuccess }) {
            state = .failed(
                checks.compactMap(\.error).first ?? "All leak test checks failed."
            )
            return
        }
        state = .done(checks)
    }

    private static func describe(_ error: Error) -> String {
        if error is TaskTimeoutError {
            return "The check timed out."
        }
        return error.localizedDescription
    }
}

/// Default checker: public IP via documented public checker endpoints
/// (`https://api.ipify.org`, fallback `https://ipv4.icanhazip.com` — both
/// return only the caller's IP over HTTPS, no accounts, no identifiers sent).
/// These are third-party public services used only at the user's explicit
/// request from the Diagnostics screen.
public struct URLSessionLeakTestChecker: LeakTestChecking {
    private static let ipEndpoints = [
        "https://api.ipify.org",
        "https://ipv4.icanhazip.com"
    ]

    public init() {
    }

    public func publicIP() async throws -> String {
        var lastError: Error?
        for endpoint in Self.ipEndpoints {
            do {
                guard let url = URL(string: endpoint) else {
                    throw URLError(.badURL)
                }
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (data, _) = try await URLSession.shared.data(for: request)
                let ip = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let ip, !ip.isEmpty, ip.count <= 45 else {
                    throw URLError(.badServerResponse)
                }
                return ip
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    public func resolve(host: String) async throws -> [String] {
        try await NWLatencyProbe.resolve(host: host)
    }
}
