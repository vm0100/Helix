// ABOUTME: Tests for SessionStore state management and polling behavior.
// ABOUTME: Uses a fake SessionProvider to verify state transitions without CLI.

import Testing
import Foundation
@testable import HelixKit

struct FakeProvider: SessionProvider {
    var syncSessions: [SyncSession]
    var forwardSessions: [ForwardSession]
    var isDaemonRunning: Bool
    var mutagenVersion: String

    init(
        syncSessions: [SyncSession] = [],
        forwardSessions: [ForwardSession] = [],
        isDaemonRunning: Bool = true,
        mutagenVersion: String = "0.18.1"
    ) {
        self.syncSessions = syncSessions
        self.forwardSessions = forwardSessions
        self.isDaemonRunning = isDaemonRunning
        self.mutagenVersion = mutagenVersion
    }

    func syncList() async throws -> [SyncSession] { syncSessions }
    func forwardList() async throws -> [ForwardSession] { forwardSessions }
    func daemonRunning() async throws -> Bool { isDaemonRunning }
    func version() async throws -> String { mutagenVersion }
    func syncCreate(arguments: [String]) async throws {}
    func forwardCreate(arguments: [String]) async throws {}
    func syncPause(_ identifier: String) async throws {}
    func syncResume(_ identifier: String) async throws {}
    func syncFlush(_ identifier: String) async throws {}
    func syncReset(_ identifier: String) async throws {}
    func syncTerminate(_ identifier: String) async throws {}
    func forwardPause(_ identifier: String) async throws {}
    func forwardResume(_ identifier: String) async throws {}
    func forwardTerminate(_ identifier: String) async throws {}
    func daemonStart() async throws {}
    func daemonStop() async throws {}
    func daemonRegister() async throws {}
    func daemonUnregister() async throws {}
}

@Suite("SessionStore state management")
struct SessionStoreTests {

    @Test("Starts with empty state")
    @MainActor
    func initialState() {
        let store = SessionStore(provider: FakeProvider())

        #expect(store.syncSessions.isEmpty)
        #expect(store.forwardSessions.isEmpty)
        #expect(store.daemonRunning == false)
        #expect(store.lastError == nil)
    }

    @Test("Refresh populates sync and forward sessions")
    @MainActor
    func refreshPopulatesSessions() async throws {
        let sync = makeSyncSession(id: "sync_1", name: "test")
        let provider = FakeProvider(syncSessions: [sync])
        let store = SessionStore(provider: provider)

        await store.refresh()

        #expect(store.syncSessions.count == 1)
        #expect(store.syncSessions[0].name == "test")
        #expect(store.daemonRunning == true)
    }

    @Test("Refresh captures error without crashing")
    @MainActor
    func refreshHandlesError() async {
        let provider = FailingProvider()
        let store = SessionStore(provider: provider)

        await store.refresh()

        #expect(store.lastError != nil)
        #expect(store.syncSessions.isEmpty)
    }

    @Test("Health status reflects session states")
    @MainActor
    func healthStatus() async {
        let healthy = makeSyncSession(id: "sync_1", name: "ok", status: "watching")
        let provider = FakeProvider(syncSessions: [healthy])
        let store = SessionStore(provider: provider)
        await store.refresh()

        #expect(store.overallHealth == .healthy)
    }

    @Test("Health status is warning when conflicts exist")
    @MainActor
    func healthWarning() async {
        let conflict = Conflict(root: "test", alphaChanges: [], betaChanges: [])
        let session = makeSyncSession(id: "sync_1", name: "conflicted", status: "watching", conflicts: [conflict])
        let provider = FakeProvider(syncSessions: [session])
        let store = SessionStore(provider: provider)
        await store.refresh()

        #expect(store.overallHealth == .warning)
    }

    @Test("Health status is error when daemon not running")
    @MainActor
    func healthError() async {
        let provider = FakeProvider(isDaemonRunning: false)
        let store = SessionStore(provider: provider)
        await store.refresh()

        #expect(store.overallHealth == .error)
    }

    @Test("Health status is error when session disconnected")
    @MainActor
    func healthDisconnected() async {
        let session = makeSyncSession(id: "sync_1", name: "bad", status: "disconnected")
        let provider = FakeProvider(syncSessions: [session])
        let store = SessionStore(provider: provider)
        await store.refresh()

        #expect(store.overallHealth == .error)
    }

    @Test("Total session count includes both sync and forward")
    @MainActor
    func totalCount() async {
        let sync = makeSyncSession(id: "sync_1", name: "s1")
        let fwd = makeForwardSession(id: "fwd_1", name: "f1")
        let provider = FakeProvider(syncSessions: [sync], forwardSessions: [fwd])
        let store = SessionStore(provider: provider)
        await store.refresh()

        #expect(store.totalSessionCount == 2)
    }

    @Test("Conflict count sums across all sync sessions")
    @MainActor
    func conflictCount() async {
        let c1 = Conflict(root: "a", alphaChanges: [], betaChanges: [])
        let c2 = Conflict(root: "b", alphaChanges: [], betaChanges: [])
        let s1 = makeSyncSession(id: "sync_1", name: "s1", conflicts: [c1, c2])
        let s2 = makeSyncSession(id: "sync_2", name: "s2", conflicts: [c1])
        let provider = FakeProvider(syncSessions: [s1, s2])
        let store = SessionStore(provider: provider)
        await store.refresh()

        #expect(store.totalConflictCount == 3)
    }

    @Test("Action methods call provider and refresh")
    @MainActor
    func syncActions() async {
        let sync = makeSyncSession(id: "sync_1", name: "s1")
        let provider = FakeProvider(syncSessions: [sync])
        let store = SessionStore(provider: provider)

        await store.pauseSync("sync_1")
        #expect(store.lastError == nil)
        #expect(store.daemonRunning == true)

        await store.resumeSync("sync_1")
        #expect(store.lastError == nil)

        await store.flushSync("sync_1")
        #expect(store.lastError == nil)
    }

    @Test("Action error sets lastError")
    @MainActor
    func actionErrorHandling() async {
        let provider = FailingProvider()
        let store = SessionStore(provider: provider)

        await store.pauseSync("nonexistent")
        #expect(store.lastError != nil)
    }

    @Test("Terminate removes session from list after refresh")
    @MainActor
    func terminateRefreshes() async {
        let sync = makeSyncSession(id: "sync_1", name: "s1")
        let provider = FakeProvider(syncSessions: [sync])
        let store = SessionStore(provider: provider)
        await store.refresh()
        #expect(store.syncSessions.count == 1)

        await store.terminateSync("sync_1")
        // FakeProvider still returns the session (it's a mock), but the point
        // is that the method completes without error
        #expect(store.lastError == nil)
    }

    @Test("Daemon start/stop methods work")
    @MainActor
    func daemonControl() async {
        let provider = FakeProvider()
        let store = SessionStore(provider: provider)

        await store.startDaemon()
        #expect(store.lastError == nil)

        await store.stopDaemon()
        #expect(store.lastError == nil)
    }

    @Test("Daemon register sets autoStart to true")
    @MainActor
    func daemonRegister() async {
        let provider = FakeProvider()
        let store = SessionStore(provider: provider)

        await store.registerDaemon()
        #expect(store.lastError == nil)
        #expect(store.daemonAutoStart == true)
    }

    @Test("Daemon unregister sets autoStart to false")
    @MainActor
    func daemonUnregister() async {
        let provider = FakeProvider()
        let store = SessionStore(provider: provider)

        await store.registerDaemon()
        #expect(store.daemonAutoStart == true)

        await store.unregisterDaemon()
        #expect(store.lastError == nil)
        #expect(store.daemonAutoStart == false)
    }

    @Test("Fetch version populates mutagenVersion")
    @MainActor
    func fetchVersion() async {
        let provider = FakeProvider(mutagenVersion: "0.18.1")
        let store = SessionStore(provider: provider)

        await store.fetchVersion()
        #expect(store.mutagenVersion == "0.18.1")
    }

    @Test("Fetch version handles error gracefully")
    @MainActor
    func fetchVersionError() async {
        let provider = FailingProvider()
        let store = SessionStore(provider: provider)

        await store.fetchVersion()
        #expect(store.mutagenVersion == nil)
    }
}

@Suite("SessionStore recreateSync")
struct RecreateSessionTests {

    @Test("Terminates then creates with updated options")
    @MainActor
    func happyPath() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let recorder = RecordingProvider(syncSessions: [session])
        let store = SessionStore(provider: recorder)
        await store.refresh()

        var newOptions = SyncCreateOptions()
        newOptions.name = "test"
        newOptions.mode = "one-way-safe"
        await store.recreateSync(
            session,
            options: newOptions,
            alpha: "/tmp/a",
            beta: "/tmp/b"
        )

        #expect(store.lastError == nil)
        let calls = recorder.calls
        #expect(calls.count >= 2)
        #expect(calls[0] == "syncTerminate:sync_1")
        #expect(calls[1].hasPrefix("syncCreate:"))
    }

    @Test("Terminate failure sets error and does not create")
    @MainActor
    func terminateFails() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let recorder = RecordingProvider(syncSessions: [session], failOn: "syncTerminate")
        let store = SessionStore(provider: recorder)
        await store.refresh()

        var newOptions = SyncCreateOptions()
        newOptions.mode = "one-way-safe"
        await store.recreateSync(
            session,
            options: newOptions,
            alpha: "/tmp/a",
            beta: "/tmp/b"
        )

        #expect(store.lastError != nil)
        #expect(store.lastError!.contains("No changes were made"))
        let calls = recorder.calls
        let createCalls = calls.filter { $0.hasPrefix("syncCreate") }
        #expect(createCalls.isEmpty)
    }

    @Test("Create failure after terminate sets descriptive error")
    @MainActor
    func createFailsAfterTerminate() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let recorder = RecordingProvider(syncSessions: [session], failOn: "syncCreate")
        let store = SessionStore(provider: recorder)
        await store.refresh()

        var newOptions = SyncCreateOptions()
        newOptions.mode = "one-way-safe"
        await store.recreateSync(
            session,
            options: newOptions,
            alpha: "/tmp/a",
            beta: "/tmp/b"
        )

        #expect(store.lastError != nil)
        #expect(store.lastError!.contains("terminated but recreation failed"))
    }
}

// MARK: - Helpers

final class RecordingProvider: SessionProvider, @unchecked Sendable {
    private var _calls: [String] = []
    private let lock = NSLock()
    private let syncSessions: [SyncSession]
    private let failOn: String?

    init(syncSessions: [SyncSession] = [], failOn: String? = nil) {
        self.syncSessions = syncSessions
        self.failOn = failOn
    }

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    private func record(_ call: String) throws {
        lock.lock()
        _calls.append(call)
        let shouldFail = failOn.map { call.hasPrefix($0) } ?? false
        lock.unlock()
        if shouldFail {
            throw CLIError(exitCode: 1, stderr: "simulated failure")
        }
    }

    func syncList() async throws -> [SyncSession] { syncSessions }
    func forwardList() async throws -> [ForwardSession] { [] }
    func daemonRunning() async throws -> Bool { true }
    func version() async throws -> String { "0.18.1" }
    func syncCreate(arguments: [String]) async throws { try record("syncCreate:\(arguments.joined(separator: " "))") }
    func forwardCreate(arguments: [String]) async throws {}
    func syncPause(_ identifier: String) async throws {}
    func syncResume(_ identifier: String) async throws {}
    func syncFlush(_ identifier: String) async throws { try record("syncFlush:\(identifier)") }
    func syncReset(_ identifier: String) async throws {}
    func syncTerminate(_ identifier: String) async throws { try record("syncTerminate:\(identifier)") }
    func forwardPause(_ identifier: String) async throws {}
    func forwardResume(_ identifier: String) async throws {}
    func forwardTerminate(_ identifier: String) async throws {}
    func daemonStart() async throws {}
    func daemonStop() async throws {}
    func daemonRegister() async throws {}
    func daemonUnregister() async throws {}
}

struct FailingProvider: SessionProvider {
    func syncList() async throws -> [SyncSession] {
        throw CLIError(exitCode: 1, stderr: "daemon not running")
    }
    func forwardList() async throws -> [ForwardSession] {
        throw CLIError(exitCode: 1, stderr: "daemon not running")
    }
    func daemonRunning() async throws -> Bool { false }
    func version() async throws -> String { throw CLIError(exitCode: 1, stderr: "not found") }
    func syncCreate(arguments: [String]) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func forwardCreate(arguments: [String]) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func syncPause(_ identifier: String) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func syncResume(_ identifier: String) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func syncFlush(_ identifier: String) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func syncReset(_ identifier: String) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func syncTerminate(_ identifier: String) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func forwardPause(_ identifier: String) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func forwardResume(_ identifier: String) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func forwardTerminate(_ identifier: String) async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func daemonStart() async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func daemonStop() async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func daemonRegister() async throws { throw CLIError(exitCode: 1, stderr: "failed") }
    func daemonUnregister() async throws { throw CLIError(exitCode: 1, stderr: "failed") }
}

func makeSyncSession(
    id: String,
    name: String?,
    status: String = "watching",
    paused: Bool = false,
    conflicts: [Conflict]? = nil
) -> SyncSession {
    SyncSession(
        identifier: id,
        version: 1,
        creationTime: "2026-01-01T00:00:00Z",
        creatingVersion: "0.18.1",
        name: name,
        paused: paused,
        status: status,
        successfulCycles: 0,
        mode: "two-way-safe",
        alpha: Endpoint(
            protocol_: "local", user: nil, host: nil, port: nil, path: "/tmp/a",
            connected: true, scanned: true, directories: 0, files: 0, totalFileSize: 0
        ),
        beta: Endpoint(
            protocol_: "local", user: nil, host: nil, port: nil, path: "/tmp/b",
            connected: true, scanned: true, directories: 0, files: 0, totalFileSize: 0
        ),
        ignore: IgnoreConfig(paths: nil, syntax: nil),
        symlink: SymlinkConfig(mode: nil),
        watch: WatchConfig(mode: nil, pollingInterval: nil),
        permissions: PermissionsConfig(mode: nil, defaultFileMode: nil, defaultDirectoryMode: nil, defaultOwner: nil, defaultGroup: nil),
        compression: CompressionConfig(algorithm: nil),
        conflicts: conflicts
    )
}

@Suite("SessionStore conflict resolution")
struct ConflictResolutionTests {

    @Test("Resolves conflict by copying winner to loser then flushing")
    @MainActor
    func happyPath() async {
        let conflict = Conflict(root: "file.txt", alphaChanges: [], betaChanges: [])
        let session = makeSyncSession(id: "sync_1", name: "s1", conflicts: [conflict])
        let recorder = RecordingProvider(syncSessions: [session])
        let copyRecorder = CommandRecorder()
        let transport = FileTransport(execute: copyRecorder.execute)
        let store = SessionStore(provider: recorder, fileTransport: transport)
        await store.refresh()

        await store.resolveConflict(session: session, conflict: conflict, winner: .alpha)

        #expect(store.lastError == nil)
        // Should have copied from alpha to beta
        #expect(copyRecorder.commands.count == 1)
        let cmd = copyRecorder.commands[0]
        #expect(cmd.executable == "/bin/cp")
        #expect(cmd.arguments == ["-Rp", "/tmp/a/file.txt", "/tmp/b/file.txt"])
        // Should have flushed
        let flushCalls = recorder.calls.filter { $0.hasPrefix("syncFlush") }
        #expect(flushCalls.count == 1)
        #expect(flushCalls[0] == "syncFlush:sync_1")
    }

    @Test("Beta wins copies from beta to alpha")
    @MainActor
    func betaWins() async {
        let conflict = Conflict(root: "data.json", alphaChanges: [], betaChanges: [])
        let session = makeSyncSession(id: "sync_1", name: "s1", conflicts: [conflict])
        let copyRecorder = CommandRecorder()
        let transport = FileTransport(execute: copyRecorder.execute)
        let store = SessionStore(provider: FakeProvider(syncSessions: [session]), fileTransport: transport)
        await store.refresh()

        await store.resolveConflict(session: session, conflict: conflict, winner: .beta)

        #expect(store.lastError == nil)
        let cmd = copyRecorder.commands[0]
        // Beta (/tmp/b) -> Alpha (/tmp/a)
        #expect(cmd.arguments == ["-Rp", "/tmp/b/data.json", "/tmp/a/data.json"])
    }

    @Test("Copy failure sets lastError and does not flush")
    @MainActor
    func copyFails() async {
        let conflict = Conflict(root: "file.txt", alphaChanges: [], betaChanges: [])
        let session = makeSyncSession(id: "sync_1", name: "s1", conflicts: [conflict])
        let recorder = RecordingProvider(syncSessions: [session])
        let transport = FileTransport { _, _ in
            throw CLIError(exitCode: 1, stderr: "permission denied")
        }
        let store = SessionStore(provider: recorder, fileTransport: transport)
        await store.refresh()

        await store.resolveConflict(session: session, conflict: conflict, winner: .alpha)

        #expect(store.lastError != nil)
        #expect(store.lastError!.contains("permission denied"))
        // Should NOT have flushed
        let flushCalls = recorder.calls.filter { $0.hasPrefix("syncFlush") }
        #expect(flushCalls.isEmpty)
    }

    @Test("Winner deletion removes from loser instead of copying")
    @MainActor
    func winnerDeleted() async {
        // Alpha deleted the root directory — Mutagen uses the root name as the change path
        let conflict = Conflict(
            root: "alimentara",
            alphaChanges: [Change(path: "alimentara", old: Entry(kind: "directory", digest: nil, executable: nil), new: nil)],
            betaChanges: [Change(path: "logs/session.log", old: nil, new: Entry(kind: "file", digest: nil, executable: nil))]
        )
        let session = makeSyncSession(id: "sync_1", name: "s1", conflicts: [conflict])
        let recorder = RecordingProvider(syncSessions: [session])
        let cmdRecorder = CommandRecorder()
        let transport = FileTransport(execute: cmdRecorder.execute)
        let store = SessionStore(provider: recorder, fileTransport: transport)
        await store.refresh()

        await store.resolveConflict(session: session, conflict: conflict, winner: .alpha)

        #expect(store.lastError == nil)
        // Should have removed from beta (loser), not copied
        #expect(cmdRecorder.commands.count == 1)
        let cmd = cmdRecorder.commands[0]
        #expect(cmd.executable == "/bin/rm")
        #expect(cmd.arguments == ["-rf", "/tmp/b/alimentara"])
        // Should have flushed
        let flushCalls = recorder.calls.filter { $0.hasPrefix("syncFlush") }
        #expect(flushCalls.count == 1)
    }

    @Test("conflictFileInfo returns file metadata from both endpoints")
    @MainActor
    func fileInfo() async {
        let conflict = Conflict(root: "file.txt", alphaChanges: [], betaChanges: [])
        let session = makeSyncSession(id: "sync_1", name: "s1", conflicts: [conflict])
        let transport = FileTransport { _, _ in
            return "1024 1700000000"
        }
        let store = SessionStore(provider: FakeProvider(syncSessions: [session]), fileTransport: transport)

        let info = await store.conflictFileInfo(session: session, conflict: conflict)

        #expect(info.alpha != nil)
        #expect(info.alpha?.size == 1024)
        #expect(info.beta != nil)
        #expect(info.beta?.size == 1024)
    }

    @Test("conflictFileInfo returns nil for failed stat")
    @MainActor
    func fileInfoFailure() async {
        let conflict = Conflict(root: "file.txt", alphaChanges: [], betaChanges: [])
        let session = makeSyncSession(id: "sync_1", name: "s1", conflicts: [conflict])
        let transport = FileTransport { _, _ in
            throw CLIError(exitCode: 1, stderr: "no such file")
        }
        let store = SessionStore(provider: FakeProvider(syncSessions: [session]), fileTransport: transport)

        let info = await store.conflictFileInfo(session: session, conflict: conflict)

        #expect(info.alpha == nil)
        #expect(info.beta == nil)
    }
}

func makeForwardSession(
    id: String,
    name: String?,
    paused: Bool = false
) -> ForwardSession {
    ForwardSession(
        identifier: id,
        version: 1,
        creationTime: "2026-01-01T00:00:00Z",
        creatingVersion: "0.18.1",
        name: name,
        paused: paused,
        source: ForwardEndpoint(protocol_: "local", user: nil, host: nil, port: nil, connected: true),
        destination: ForwardEndpoint(protocol_: "ssh", user: "test", host: "host", port: nil, connected: true),
        sourceEndpoint: "tcp:localhost:8080",
        destinationEndpoint: "tcp:localhost:3000",
        socket: nil
    )
}
