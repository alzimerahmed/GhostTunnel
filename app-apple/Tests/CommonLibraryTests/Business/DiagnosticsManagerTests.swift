// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

@testable import CommonLibraryCore
import Foundation
import Testing

@MainActor
struct DiagnosticsManagerTests {
    private static let wgPrivateKey = "iJmQ7vB3xkYR8nT2wLzVpQ1cF6dH9sA4eK0uJ5gX7yM="

    private static let wgPresharedKey = "8fJ2kL9pQ3rT5vW7xY1zA4bC6dE8fG0hJ2kL4mN6oP8="

    private static let hexKey = String(repeating: "a1b2", count: 16)

    // MARK: Log sanitization

    @Test
    func givenPEMBlock_whenSanitized_thenWholeBlockIsRedacted() {
        let lines = [
            "loading certificate",
            "-----BEGIN PRIVATE KEY-----",
            Self.wgPrivateKey,
            "-----END PRIVATE KEY-----",
            "done"
        ]
        let sanitized = LogSanitizer.sanitize(lines)
        #expect(sanitized[0] == "loading certificate")
        #expect(sanitized[1] == "[REDACTED PEM BLOCK]")
        #expect(sanitized[2] == "[REDACTED PEM BLOCK]")
        #expect(sanitized[3] == "[REDACTED PEM BLOCK]")
        #expect(sanitized[4] == "done")
    }

    @Test
    func givenSecretAssignment_whenSanitized_thenValueIsRedacted() {
        let lines = [
            "PrivateKey = \(Self.wgPrivateKey)",
            "password: hunter2",
            "auth-token=abc123def",
            "psk = \(Self.wgPresharedKey)"
        ]
        let sanitized = LogSanitizer.sanitize(lines).joined(separator: "\n")
        #expect(!sanitized.contains(Self.wgPrivateKey))
        #expect(!sanitized.contains("hunter2"))
        #expect(!sanitized.contains("abc123def"))
        #expect(!sanitized.contains(Self.wgPresharedKey))
        #expect(sanitized.contains("[REDACTED]"))
    }

    @Test
    func givenBareKeyMaterial_whenSanitized_thenKeysAreRedacted() {
        let lines = [
            "peer key \(Self.wgPrivateKey) in handshake",
            "hex key \(Self.hexKey) here"
        ]
        let sanitized = LogSanitizer.sanitize(lines).joined(separator: "\n")
        #expect(!sanitized.contains(Self.wgPrivateKey))
        #expect(!sanitized.contains(Self.hexKey))
        #expect(sanitized.contains("[REDACTED KEY]"))
    }

    @Test
    func givenAuthorizationHeaders_whenSanitized_thenValuesAreRedacted() {
        let lines = [
            "request header authorization: Bearer abc123def456",
            "response authorization=Bearer xyz789",
            "auth_user_pass = myuser:mypass"
        ]
        let sanitized = LogSanitizer.sanitize(lines).joined(separator: "\n")
        #expect(!sanitized.contains("abc123def456"))
        #expect(!sanitized.contains("xyz789"))
        #expect(!sanitized.contains("myuser:mypass"))
        #expect(sanitized.contains("[REDACTED]"))
    }

    @Test
    func givenAuthUserPassMarker_whenSanitized_thenFollowingLineIsRedacted() {
        let lines = [
            "parsing options",
            "--auth-user-pass",
            "myuser",
            "mypass",
            "next option"
        ]
        let sanitized = LogSanitizer.sanitize(lines)
        #expect(sanitized[1] == "--auth-user-pass")
        #expect(sanitized[2] == "[REDACTED CREDENTIALS]")
        #expect(sanitized[3] != "[REDACTED CREDENTIALS]")
        #expect(sanitized[4] == "next option")
    }

    @Test
    func givenOrdinaryLogLines_whenSanitized_thenUnchanged() {
        let lines = [
            "Connect to profile ABC-123...",
            "status=active onDemand=false",
            "received=1024 sent=2048"
        ]
        #expect(LogSanitizer.sanitize(lines) == lines)
    }

    // MARK: Debug bundle

    @Test
    func givenSecretSections_whenBundleBuilt_thenNoKeyMaterialSurvives() {
        let sections = [
            DebugBundleSection(name: "App log", lines: [
                "app started",
                "PrivateKey = \(Self.wgPrivateKey)"
            ]),
            DebugBundleSection(name: "Tunnel state", lines: [
                "profile=xyz status=active",
                "-----BEGIN OPENVPN STATIC KEY V1-----",
                Self.hexKey,
                "-----END OPENVPN STATIC KEY V1-----"
            ])
        ]
        let bundle = DebugBundleBuilder.build(sections: sections)
        #expect(!bundle.contains(Self.wgPrivateKey))
        #expect(!bundle.contains(Self.hexKey))
        #expect(!bundle.contains("BEGIN OPENVPN"))
        #expect(bundle.contains("== App log =="))
        #expect(bundle.contains("== Tunnel state =="))
        #expect(bundle.contains("profile=xyz status=active"))
        #expect(bundle.contains("GhostTunnel debug bundle"))
    }

    @Test
    func givenSections_whenBundleWritten_thenFileExistsWithSanitizedContent() throws {
        let sections = [
            DebugBundleSection(name: "App log", lines: [
                "password: hunter2"
            ])
        ]
        let url = try DebugBundleBuilder.write(sections: sections)
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.contains("hunter2"))
        #expect(content.contains("== App log =="))
    }

    // MARK: Leak test (injected checker)

    private struct MockChecker: LeakTestChecking {
        let ip: String?
        let addresses: [String]?
        var ipError: Error?
        var resolveError: Error?

        func publicIP() async throws -> String {
            if let ipError {
                throw ipError
            }
            return ip ?? "203.0.113.7"
        }

        func resolve(host: String) async throws -> [String] {
            if let resolveError {
                throw resolveError
            }
            return addresses ?? ["2606:4700:4700::1111"]
        }
    }

    @Test
    func givenChecker_whenRun_thenStateDoneWithChecks() async {
        let manager = LeakTestManager(checker: MockChecker(
            ip: "198.51.100.1",
            addresses: ["1.2.3.4"]
        ))
        await manager.run()
        guard case .done(let checks) = manager.state else {
            Issue.record("Expected .done state")
            return
        }
        #expect(checks.count == 3)
        #expect(checks[0].value == "198.51.100.1")
        #expect(checks[0].isSuccess)
        #expect(checks[1].isSuccess)
    }

    @Test
    func givenFailingChecker_whenRun_thenChecksCarryErrors() async {
        struct Boom: Error {}
        let manager = LeakTestManager(checker: MockChecker(
            ip: nil,
            addresses: nil,
            ipError: Boom(),
            resolveError: Boom()
        ))
        await manager.run()
        guard case .done(let checks) = manager.state else {
            Issue.record("Expected .done state")
            return
        }
        #expect(checks.allSatisfy { !$0.isSuccess })
        #expect(checks.allSatisfy { $0.error != nil })
    }

    @Test
    func givenAllChecksFail_whenRun_thenStateIsFailed() async {
        struct Boom: Error {}
        let manager = LeakTestManager(checker: MockChecker(
            ip: nil,
            addresses: nil,
            ipError: Boom(),
            resolveError: Boom()
        ))
        await manager.run()
        guard case .failed(let message) = manager.state else {
            Issue.record("Expected .failed state")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test
    func givenSlowChecker_whenCheckTimeoutElapses_thenChecksCarryTimeoutErrors() async {
        struct SlowChecker: LeakTestChecking {
            func publicIP() async throws -> String {
                try await Task.sleep(for: .seconds(10))
                return "203.0.113.7"
            }

            func resolve(host: String) async throws -> [String] {
                try await Task.sleep(for: .seconds(10))
                return ["1.2.3.4"]
            }
        }
        let manager = LeakTestManager(checker: SlowChecker(), checkTimeout: 0.2)
        await manager.run()
        guard case .failed(let message) = manager.state else {
            Issue.record("Expected .failed state (all checks timed out)")
            return
        }
        #expect(message.contains("timed out"))
    }
}
