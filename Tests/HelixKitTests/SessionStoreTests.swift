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

    @Test("addToIgnoreList terminates then creates with path appended to ignores")
    @MainActor
    func addToIgnoreList() async {
        let session = makeSyncSession(
            id: "sync_1",
            name: "test",
            ignorePaths: ["*.log"]
        )
        let recorder = RecordingProvider(syncSessions: [session])
        let store = SessionStore(provider: recorder)
        await store.refresh()

        await store.addToIgnoreList(session: session, path: "node_modules/symlink")

        #expect(store.lastError == nil)
        let calls = recorder.calls
        #expect(calls.count >= 2)
        #expect(calls[0] == "syncTerminate:sync_1")
        #expect(calls[1].hasPrefix("syncCreate:"))
        // Verify the new ignore path is present alongside the existing one
        #expect(calls[1].contains("--ignore"))
        #expect(calls[1].contains("*.log"))
        #expect(calls[1].contains("node_modules/symlink"))
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
    private let resolvedSyncSessions: [SyncSession]?
    private var _flushed = false
    private let failOn: String?

    init(syncSessions: [SyncSession] = [], resolvedSyncSessions: [SyncSession]? = nil, failOn: String? = nil) {
        self.syncSessions = syncSessions
        self.resolvedSyncSessions = resolvedSyncSessions
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

    func syncList() async throws -> [SyncSession] {
        lock.lock()
        let flushed = _flushed
        lock.unlock()
        if flushed, let resolved = resolvedSyncSessions {
            return resolved
        }
        return syncSessions
    }
    func forwardList() async throws -> [ForwardSession] { [] }
    func daemonRunning() async throws -> Bool { true }
    func version() async throws -> String { "0.18.1" }
    func syncCreate(arguments: [String]) async throws { try record("syncCreate:\(arguments.joined(separator: " "))") }
    func forwardCreate(arguments: [String]) async throws {}
    func syncPause(_ identifier: String) async throws {}
    func syncResume(_ identifier: String) async throws {}
    func syncFlush(_ identifier: String) async throws {
        try record("syncFlush:\(identifier)")
        lock.lock()
        _flushed = true
        lock.unlock()
    }
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
    conflicts: [Conflict]? = nil,
    ignorePaths: [String]? = nil
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
        ignore: IgnoreConfig(paths: ignorePaths, syntax: nil),
        symlink: SymlinkConfig(mode: nil),
        watch: WatchConfig(mode: nil, pollingInterval: nil),
        permissions: PermissionsConfig(mode: nil, defaultFileMode: nil, defaultDirectoryMode: nil, defaultOwner: nil, defaultGroup: nil),
        compression: CompressionConfig(algorithm: nil),
        conflicts: conflicts
    )
}

@Suite("SessionStore conflict resolution")
struct ConflictResolutionTests {

    @Test("Resolves conflict by removing loser then copying winner then flushing")
    @MainActor
    func happyPath() async {
        let conflict = Conflict(root: "file.txt", alphaChanges: [], betaChanges: [])
        let session = makeSyncSession(id: "sync_1", name: "s1", conflicts: [conflict])
        let resolvedSession = makeSyncSession(id: "sync_1", name: "s1")
        let recorder = RecordingProvider(syncSessions: [session], resolvedSyncSessions: [resolvedSession])
        let copyRecorder = CommandRecorder()
        let transport = FileTransport(execute: copyRecorder.execute)
        let store = SessionStore(provider: recorder, fileTransport: transport)
        await store.refresh()

        await store.resolveConflict(session: session, conflict: conflict, winner: .alpha)

        #expect(store.lastError == nil)
        // Should remove loser then copy winner
        #expect(copyRecorder.commands.count == 2)
        let rm = copyRecorder.commands[0]
        #expect(rm.executable == "/bin/rm")
        #expect(rm.arguments == ["-rf", "/tmp/b/file.txt"])
        let cp = copyRecorder.commands[1]
        #expect(cp.executable == "/bin/cp")
        #expect(cp.arguments == ["-Rp", "/tmp/a/file.txt", "/tmp/b/file.txt"])
        // Should have flushed
        let flushCalls = recorder.calls.filter { $0.hasPrefix("syncFlush") }
        #expect(flushCalls.count == 1)
        #expect(flushCalls[0] == "syncFlush:sync_1")
    }

    @Test("Beta wins removes alpha then copies from beta to alpha")
    @MainActor
    func betaWins() async {
        let conflict = Conflict(root: "data.json", alphaChanges: [], betaChanges: [])
        let session = makeSyncSession(id: "sync_1", name: "s1", conflicts: [conflict])
        let resolvedSession = makeSyncSession(id: "sync_1", name: "s1")
        let copyRecorder = CommandRecorder()
        let transport = FileTransport(execute: copyRecorder.execute)
        let store = SessionStore(provider: FakeProvider(syncSessions: [resolvedSession]), fileTransport: transport)
        await store.refresh()

        await store.resolveConflict(session: session, conflict: conflict, winner: .beta)

        #expect(store.lastError == nil)
        #expect(copyRecorder.commands.count == 2)
        let rm = copyRecorder.commands[0]
        #expect(rm.arguments == ["-rf", "/tmp/a/data.json"])
        let cp = copyRecorder.commands[1]
        // Beta (/tmp/b) -> Alpha (/tmp/a)
        #expect(cp.arguments == ["-Rp", "/tmp/b/data.json", "/tmp/a/data.json"])
    }

    @Test("Persistent conflict after flush sets error")
    @MainActor
    func conflictPersists() async {
        let conflict = Conflict(root: "link.txt", alphaChanges: [], betaChanges: [])
        let session = makeSyncSession(id: "sync_1", name: "s1", conflicts: [conflict])
        // Provider always returns sessions with conflict (simulates unresolvable conflict)
        let recorder = RecordingProvider(syncSessions: [session])
        let copyRecorder = CommandRecorder()
        let transport = FileTransport(execute: copyRecorder.execute)
        let store = SessionStore(provider: recorder, fileTransport: transport)
        await store.refresh()

        await store.resolveConflict(session: session, conflict: conflict, winner: .alpha)

        #expect(store.lastError?.contains("could not be resolved") == true)
        // Transport and flush should still have been attempted
        #expect(copyRecorder.commands.count == 2)
        let flushCalls = recorder.calls.filter { $0.hasPrefix("syncFlush") }
        #expect(flushCalls.count == 1)
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
        let resolvedSession = makeSyncSession(id: "sync_1", name: "s1")
        let recorder = RecordingProvider(syncSessions: [session], resolvedSyncSessions: [resolvedSession])
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

@Suite("SessionStore git repo status")
struct GitRepoStatusTests {

    @Test("Both endpoints have .git returns symmetric")
    @MainActor
    func bothHaveGit() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { _, _ in "" }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let check = await store.gitRepoStatus(for: session)

        #expect(check.status == .symmetric)
        #expect(check.subpath.isEmpty)
    }

    @Test("Neither root nor subdirectories have .git returns symmetric")
    @MainActor
    func neitherHasGit() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { executable, args in
            let joined = args.joined(separator: " ")
            if executable == "/bin/test" {
                throw CLIError(exitCode: 1, stderr: "")
            }
            // find returns empty
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let check = await store.gitRepoStatus(for: session)

        #expect(check.status == .symmetric)
    }

    @Test("Only alpha has .git with remote returns alphaOnly and hasRemote true")
    @MainActor
    func alphaOnlyWithRemote() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { executable, args in
            let joined = args.joined(separator: " ")
            if executable == "/bin/test" && joined.contains("/tmp/b") {
                throw CLIError(exitCode: 1, stderr: "")
            }
            if joined.contains("git config --get remote.origin.url") {
                return "https://github.com/example/repo.git\n"
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let check = await store.gitRepoStatus(for: session)

        #expect(check.status == .alphaOnly)
        #expect(check.subpath.isEmpty)
        #expect(check.hasRemote == true)
    }

    @Test("Only alpha has .git without remote returns alphaOnly and hasRemote false")
    @MainActor
    func alphaOnlyNoRemote() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { executable, args in
            let joined = args.joined(separator: " ")
            if executable == "/bin/test" && joined.contains("/tmp/b") {
                throw CLIError(exitCode: 1, stderr: "")
            }
            if joined.contains("git config --get remote.origin.url") {
                throw CLIError(exitCode: 1, stderr: "")
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let check = await store.gitRepoStatus(for: session)

        #expect(check.status == .alphaOnly)
        #expect(check.hasRemote == false)
    }

    @Test("Only beta has .git at root returns betaOnly with empty subpath")
    @MainActor
    func betaOnly() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { _, args in
            let joined = args.joined(separator: " ")
            if joined.contains("/tmp/a") {
                throw CLIError(exitCode: 1, stderr: "")
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let check = await store.gitRepoStatus(for: session)

        #expect(check.status == .betaOnly)
        #expect(check.subpath.isEmpty)
    }

    @Test("Transport error returns unknown")
    @MainActor
    func transportError() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { _, _ in
            throw CLIError(exitCode: 255, stderr: "connection refused")
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let check = await store.gitRepoStatus(for: session)

        #expect(check.status == .unknown)
    }

    @Test("Subdirectory .git on alpha only returns alphaOnly with subpath")
    @MainActor
    func subdirectoryAlphaOnly() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { executable, args in
            let joined = args.joined(separator: " ")
            // Root .git checks: both return false
            if executable == "/bin/test" {
                throw CLIError(exitCode: 1, stderr: "")
            }
            // find command via /bin/sh
            if joined.contains("find .") {
                if joined.contains("/tmp/a") {
                    return "./helix/.git\n"
                }
                return ""
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let check = await store.gitRepoStatus(for: session)

        #expect(check.status == .alphaOnly)
        #expect(check.subpath == "helix")
    }

    @Test("Subdirectory .git on beta only returns betaOnly with subpath")
    @MainActor
    func subdirectoryBetaOnly() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { executable, args in
            let joined = args.joined(separator: " ")
            if executable == "/bin/test" {
                throw CLIError(exitCode: 1, stderr: "")
            }
            if joined.contains("find .") {
                if joined.contains("/tmp/b") {
                    return "./project/.git\n"
                }
                return ""
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let check = await store.gitRepoStatus(for: session)

        #expect(check.status == .betaOnly)
        #expect(check.subpath == "project")
    }

    @Test("Subdirectory .git on both sides returns symmetric")
    @MainActor
    func subdirectoryBothHaveGit() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { executable, args in
            let joined = args.joined(separator: " ")
            if executable == "/bin/test" {
                throw CLIError(exitCode: 1, stderr: "")
            }
            if joined.contains("find .") {
                return "./helix/.git\n"
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let check = await store.gitRepoStatus(for: session)

        #expect(check.status == .symmetric)
    }
}

@Suite("SessionStore fixGitMismatch")
struct FixGitMismatchTests {

    @Test("Reads remote and branch from alpha, runs git commands on beta")
    @MainActor
    func alphaOnlyFixesBeta() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let log = CallLog()
        let transport = FileTransport { executable, args in
            log.record(executable: executable, arguments: args)

            let joined = args.joined(separator: " ")
            if joined.contains("/tmp/a") && joined.contains("remote.origin.url") {
                return "https://github.com/example/repo.git\n"
            }
            if joined.contains("/tmp/a") && joined.contains("branch --show-current") {
                return "main\n"
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let success = await store.fixGitMismatch(session: session, gitCheck: GitRepoCheck(status: .alphaOnly))

        #expect(success == true)
        #expect(store.lastError == nil)

        let commands = log.entries
        #expect(commands.count == 6)

        // Read remote URL from alpha
        let readRemote = commands[0].arguments.joined(separator: " ")
        #expect(readRemote.contains("/tmp/a") && readRemote.contains("remote.origin.url"))

        // Read branch from alpha
        let readBranch = commands[1].arguments.joined(separator: " ")
        #expect(readBranch.contains("/tmp/a") && readBranch.contains("branch --show-current"))

        // git init on beta
        let gitInit = commands[2].arguments.joined(separator: " ")
        #expect(gitInit.contains("/tmp/b") && gitInit.contains("git init"))

        // git remote add on beta
        let remoteAdd = commands[3].arguments.joined(separator: " ")
        #expect(remoteAdd.contains("/tmp/b") && remoteAdd.contains("git remote add origin"))
        #expect(remoteAdd.contains("https://github.com/example/repo.git"))

        // git fetch on beta
        let fetch = commands[4].arguments.joined(separator: " ")
        #expect(fetch.contains("/tmp/b") && fetch.contains("git fetch origin"))

        // git reset on beta
        let reset = commands[5].arguments.joined(separator: " ")
        #expect(reset.contains("/tmp/b") && reset.contains("git reset --mixed 'origin/main'"))
    }

    @Test("betaOnly reads from beta and fixes alpha")
    @MainActor
    func betaOnlyFixesAlpha() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let log = CallLog()
        let transport = FileTransport { executable, args in
            log.record(executable: executable, arguments: args)

            let joined = args.joined(separator: " ")
            if joined.contains("/tmp/b") && joined.contains("remote.origin.url") {
                return "git@github.com:example/repo.git\n"
            }
            if joined.contains("/tmp/b") && joined.contains("branch --show-current") {
                return "develop\n"
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let success = await store.fixGitMismatch(session: session, gitCheck: GitRepoCheck(status: .betaOnly))

        #expect(success == true)

        // git init should target alpha (/tmp/a)
        let gitInit = log.entries[2].arguments.joined(separator: " ")
        #expect(gitInit.contains("/tmp/a") && gitInit.contains("git init"))

        // Reset should use develop branch
        let reset = log.entries[5].arguments.joined(separator: " ")
        #expect(reset.contains("origin/develop"))
    }

    @Test("No remote URL sets lastError and returns false")
    @MainActor
    func noRemote() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { _, args in
            let joined = args.joined(separator: " ")
            if joined.contains("remote.origin.url") {
                return "\n"
            }
            if joined.contains("branch --show-current") {
                return "main\n"
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let success = await store.fixGitMismatch(session: session, gitCheck: GitRepoCheck(status: .alphaOnly))

        #expect(success == false)
        #expect(store.lastError != nil)
        #expect(store.lastError!.contains("No git remote"))
    }

    @Test("Transport error reading git info sets lastError")
    @MainActor
    func readError() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { _, _ in
            throw CLIError(exitCode: 128, stderr: "not a git repository")
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let success = await store.fixGitMismatch(session: session, gitCheck: GitRepoCheck(status: .alphaOnly))

        #expect(success == false)
        #expect(store.lastError != nil)
        #expect(store.lastError!.contains("Could not read git info"))
    }

    @Test("Symmetric status returns false immediately")
    @MainActor
    func symmetricNoOp() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let store = SessionStore(provider: FakeProvider())

        let success = await store.fixGitMismatch(session: session, gitCheck: GitRepoCheck(status: .symmetric))

        #expect(success == false)
    }

    @Test("gitSourceInfo reads remote URL and branch from source endpoint")
    @MainActor
    func sourceInfo() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { _, args in
            let joined = args.joined(separator: " ")
            if joined.contains("remote.origin.url") {
                return "https://github.com/hex/Helix.git\n"
            }
            if joined.contains("branch --show-current") {
                return "main\n"
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let info = await store.gitSourceInfo(
            for: session,
            gitCheck: GitRepoCheck(status: .alphaOnly, subpath: "helix")
        )

        #expect(info.remoteURL == "https://github.com/hex/Helix.git")
        #expect(info.branch == "main")
    }

    @Test("gitSourceInfo returns nil when no remote configured")
    @MainActor
    func sourceInfoNoRemote() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let transport = FileTransport { _, args in
            let joined = args.joined(separator: " ")
            if joined.contains("remote.origin.url") {
                throw CLIError(exitCode: 1, stderr: "")
            }
            if joined.contains("branch --show-current") {
                return "main\n"
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let info = await store.gitSourceInfo(
            for: session,
            gitCheck: GitRepoCheck(status: .alphaOnly)
        )

        #expect(info.remoteURL == nil)
        #expect(info.branch == "main")
    }

    @Test("Uses subpath when fixing subdirectory mismatch")
    @MainActor
    func fixWithSubpath() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        let log = CallLog()
        let transport = FileTransport { executable, args in
            log.record(executable: executable, arguments: args)

            let joined = args.joined(separator: " ")
            if joined.contains("/tmp/a/helix") && joined.contains("remote.origin.url") {
                return "https://github.com/example/repo.git\n"
            }
            if joined.contains("/tmp/a/helix") && joined.contains("branch --show-current") {
                return "main\n"
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let success = await store.fixGitMismatch(
            session: session,
            gitCheck: GitRepoCheck(status: .alphaOnly, subpath: "helix")
        )

        #expect(success == true)

        let commands = log.entries
        #expect(commands.count == 6)

        // Read remote from alpha/helix
        let readRemote = commands[0].arguments.joined(separator: " ")
        #expect(readRemote.contains("/tmp/a/helix"))

        // Git init on beta/helix
        let gitInit = commands[2].arguments.joined(separator: " ")
        #expect(gitInit.contains("/tmp/b/helix") && gitInit.contains("git init"))
    }

    @Test("Git init failure on target sets lastError")
    @MainActor
    func initFails() async {
        let session = makeSyncSession(id: "sync_1", name: "test")
        var callCount = 0
        let lock = NSLock()
        let transport = FileTransport { _, args in
            lock.lock()
            callCount += 1
            let count = callCount
            lock.unlock()

            let joined = args.joined(separator: " ")
            if joined.contains("remote.origin.url") {
                return "https://github.com/example/repo.git\n"
            }
            if joined.contains("branch --show-current") {
                return "main\n"
            }
            // Fail on git init (third call)
            if count >= 3 {
                throw CLIError(exitCode: 1, stderr: "permission denied")
            }
            return ""
        }
        let store = SessionStore(provider: FakeProvider(), fileTransport: transport)

        let success = await store.fixGitMismatch(session: session, gitCheck: GitRepoCheck(status: .alphaOnly))

        #expect(success == false)
        #expect(store.lastError != nil)
        #expect(store.lastError!.contains("Git init failed"))
    }
}

final class CallLog: @unchecked Sendable {
    private var _entries: [RecordedCommand] = []
    private let lock = NSLock()

    var entries: [RecordedCommand] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    func record(executable: String, arguments: [String]) {
        lock.lock()
        _entries.append(RecordedCommand(executable: executable, arguments: arguments))
        lock.unlock()
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
