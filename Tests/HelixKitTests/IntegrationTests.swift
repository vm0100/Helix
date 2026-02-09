// ABOUTME: Integration tests that verify CLI parsing against the live mutagen daemon.
// ABOUTME: These tests require mutagen to be installed and running.

import Testing
import Foundation
@testable import HelixKit

@Suite("Live CLI integration", .enabled(if: ProcessInfo.processInfo.environment["MUTAGEN_INTEGRATION"] != nil))
struct IntegrationTests {

    @Test("Live syncList returns real session data")
    func liveSyncList() async throws {
        let cli = CLI()
        let sessions = try await cli.syncList()

        #expect(!sessions.isEmpty, "Expected at least one sync session")

        let session = sessions[0]
        #expect(session.identifier.hasPrefix("sync_"))
        #expect(!session.status.isEmpty)
        #expect(session.alpha.protocol_ == "ssh" || session.alpha.protocol_ == "local")
    }

    @Test("Live forwardList returns (possibly empty) array")
    func liveForwardList() async throws {
        let cli = CLI()
        let sessions = try await cli.forwardList()

        // May be empty, but should not throw
        #expect(sessions.count >= 0)
    }

    @Test("Live version returns semver string")
    func liveVersion() async throws {
        let cli = CLI()
        let version = try await cli.version()

        #expect(version.contains("."), "Expected version with dots: \(version)")
    }

    @Test("Live daemonRunning returns true when daemon is active")
    func liveDaemonRunning() async throws {
        let cli = CLI()
        let running = try await cli.daemonRunning()

        #expect(running == true)
    }

    @Test("SessionStore refresh populates from live daemon")
    @MainActor
    func liveSessionStore() async throws {
        let cli = CLI()
        let store = SessionStore(provider: cli)

        await store.refresh()

        #expect(store.daemonRunning == true)
        #expect(!store.syncSessions.isEmpty, "Expected live sync sessions")
        #expect(store.lastError == nil)

        // Verify the claude-sessions session specifically
        let claudeSession = store.syncSessions.first { $0.name == "claude-sessions" }
        #expect(claudeSession != nil, "Expected claude-sessions sync session")

        if let session = claudeSession {
            #expect(session.mode == "two-way-safe")
            #expect(session.alpha.protocol_ == "ssh")
            #expect(session.beta.protocol_ == "local")
            #expect((session.conflicts?.count ?? 0) == 5, "Expected 5 conflicts")
        }
    }
}
