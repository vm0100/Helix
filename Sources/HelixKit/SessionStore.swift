// ABOUTME: Observable state container for all mutagen sessions.
// ABOUTME: Polls CLI periodically and exposes typed session arrays for SwiftUI binding.

import Foundation

public enum HealthStatus: Sendable {
    case healthy
    case active
    case warning
    case error
    case idle
}

@MainActor
@Observable
public final class SessionStore {
    public private(set) var syncSessions: [SyncSession] = []
    public private(set) var forwardSessions: [ForwardSession] = []
    public private(set) var daemonRunning = false
    public private(set) var daemonAutoStart = false
    public private(set) var mutagenVersion: String?
    public private(set) var lastError: String?
    public var pendingSessionSelection: String?

    private var provider: any SessionProvider
    private var pollingTask: Task<Void, Never>?
    private let fileTransport: FileTransport

    public init(provider: any SessionProvider, fileTransport: FileTransport = FileTransport()) {
        self.provider = provider
        self.fileTransport = fileTransport
    }

    public func replaceProvider(_ provider: any SessionProvider) {
        self.provider = provider
    }

    public var totalSessionCount: Int {
        syncSessions.count + forwardSessions.count
    }

    public var totalConflictCount: Int {
        syncSessions.reduce(0) { $0 + ($1.conflicts?.count ?? 0) }
    }

    public var overallHealth: HealthStatus {
        if !daemonRunning {
            return .error
        }
        if syncSessions.isEmpty && forwardSessions.isEmpty {
            return .idle
        }
        let hasDisconnected = syncSessions.contains { $0.status == "disconnected" }
            || forwardSessions.contains { $0.source.connected == false || $0.destination.connected == false }
        if hasDisconnected {
            return .error
        }
        let hasConflicts = totalConflictCount > 0
        let hasHalted = syncSessions.contains { $0.status == "halted" }
        if hasConflicts || hasHalted {
            return .warning
        }
        let hasActive = syncSessions.contains {
            ["scanning", "staging", "transitioning", "saving"].contains($0.status)
        }
        if hasActive {
            return .active
        }
        return .healthy
    }

    public func refresh() async {
        do {
            daemonRunning = try await provider.daemonRunning()
        } catch {
            daemonRunning = false
        }

        guard daemonRunning else {
            lastError = "Daemon not running"
            return
        }

        do {
            async let syncs = provider.syncList()
            async let forwards = provider.forwardList()
            syncSessions = try await syncs
            forwardSessions = try await forwards
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Session Creation

    public func createSync(options: SyncCreateOptions, alpha: String, beta: String) async {
        let args = options.arguments(alpha: alpha, beta: beta)
        await performAction { try await provider.syncCreate(arguments: args) }
    }

    public func createForward(options: ForwardCreateOptions, source: String, destination: String) async {
        let args = options.arguments(source: source, destination: destination)
        await performAction { try await provider.forwardCreate(arguments: args) }
    }

    // MARK: - Sync Edit (Terminate + Recreate)

    public func recreateSync(
        _ session: SyncSession,
        options: SyncCreateOptions,
        alpha: String,
        beta: String
    ) async {
        do {
            try await provider.syncTerminate(session.identifier)
        } catch {
            lastError = "Terminate failed: \(error.localizedDescription). No changes were made."
            return
        }

        let args = options.arguments(alpha: alpha, beta: beta)
        do {
            try await provider.syncCreate(arguments: args)
            lastError = nil
            await refresh()
        } catch {
            lastError = "Session terminated but recreation failed: \(error.localizedDescription). Use Create Session to recreate manually."
        }
    }

    // MARK: - Sync Actions

    public func pauseSync(_ identifier: String) async {
        await performAction { try await provider.syncPause(identifier) }
    }

    public func resumeSync(_ identifier: String) async {
        await performAction { try await provider.syncResume(identifier) }
    }

    public func flushSync(_ identifier: String) async {
        await performAction { try await provider.syncFlush(identifier) }
    }

    public func resetSync(_ identifier: String) async {
        await performAction { try await provider.syncReset(identifier) }
    }

    public func terminateSync(_ identifier: String) async {
        await performAction { try await provider.syncTerminate(identifier) }
    }

    // MARK: - Forward Actions

    public func pauseForward(_ identifier: String) async {
        await performAction { try await provider.forwardPause(identifier) }
    }

    public func resumeForward(_ identifier: String) async {
        await performAction { try await provider.forwardResume(identifier) }
    }

    public func terminateForward(_ identifier: String) async {
        await performAction { try await provider.forwardTerminate(identifier) }
    }

    // MARK: - Daemon

    public func startDaemon() async {
        do {
            try await provider.daemonStart()
            daemonRunning = true
            lastError = nil
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func stopDaemon() async {
        do {
            try await provider.daemonStop()
            daemonRunning = false
            syncSessions = []
            forwardSessions = []
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func registerDaemon() async {
        do {
            try await provider.daemonRegister()
            daemonAutoStart = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func unregisterDaemon() async {
        do {
            try await provider.daemonUnregister()
            daemonAutoStart = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func fetchVersion() async {
        do {
            mutagenVersion = try await provider.version()
        } catch {
            mutagenVersion = nil
        }
    }

    // MARK: - Conflict Resolution

    public func conflictFileInfo(
        session: SyncSession,
        conflict: Conflict
    ) async -> (alpha: FileInfo?, beta: FileInfo?) {
        let alphaURL = appendingConflictRoot(to: session.alpha.endpointURL, root: conflict.root)
        let betaURL = appendingConflictRoot(to: session.beta.endpointURL, root: conflict.root)

        async let alphaStat = try? fileTransport.stat(endpoint: alphaURL)
        async let betaStat = try? fileTransport.stat(endpoint: betaURL)

        return (alpha: await alphaStat, beta: await betaStat)
    }

    public func resolveConflict(
        session: SyncSession,
        conflict: Conflict,
        winner: ConflictWinner
    ) async {
        let alphaURL = appendingConflictRoot(to: session.alpha.endpointURL, root: conflict.root)
        let betaURL = appendingConflictRoot(to: session.beta.endpointURL, root: conflict.root)

        let (winnerURL, loserURL) = switch winner {
        case .alpha: (alphaURL, betaURL)
        case .beta: (betaURL, alphaURL)
        }

        let winnerChanges = winner == .alpha ? conflict.alphaChanges : conflict.betaChanges
        ConsoleLog.shared.log("resolveConflict: \(winner) wins for root '\(conflict.root)'")
        ConsoleLog.shared.log("  winnerURL: \(winnerURL.formatted)")
        ConsoleLog.shared.log("  loserURL: \(loserURL.formatted)")
        ConsoleLog.shared.log("  winnerChanges: \(winnerChanges.map { "path='\($0.path)' old=\($0.old?.kind ?? "nil") new=\($0.new?.kind ?? "nil")" }.joined(separator: ", "))")

        let winnerDeletedRoot = winnerChanges.contains { $0.path == conflict.root && $0.new == nil }
        ConsoleLog.shared.log("  winnerDeletedRoot: \(winnerDeletedRoot)")

        do {
            if winnerDeletedRoot {
                ConsoleLog.shared.log("  action: REMOVE \(loserURL.formatted)")
                try await fileTransport.remove(endpoint: loserURL)
            } else {
                ConsoleLog.shared.log("  action: COPY \(winnerURL.formatted) -> \(loserURL.formatted)")
                try await fileTransport.copy(from: winnerURL, to: loserURL)
            }
            ConsoleLog.shared.log("  transport succeeded")
        } catch {
            ConsoleLog.shared.log("  transport FAILED: \(error.localizedDescription)", level: .error)
            lastError = error.localizedDescription
            return
        }

        do {
            try await provider.syncFlush(session.identifier)
            ConsoleLog.shared.log("  flush succeeded")
            lastError = nil
            await refresh()
        } catch {
            ConsoleLog.shared.log("  flush FAILED: \(error.localizedDescription)", level: .error)
            lastError = error.localizedDescription
        }
    }

    private func appendingConflictRoot(to endpoint: EndpointURL, root: String) -> EndpointURL {
        switch endpoint {
        case .local(let path):
            return .local(path: (path as NSString).appendingPathComponent(root))
        case .ssh(let user, let host, let port, let path):
            return .ssh(user: user, host: host, port: port, path: (path as NSString).appendingPathComponent(root))
        case .docker(let container, let path):
            return .docker(container: container, path: (path as NSString).appendingPathComponent(root))
        }
    }

    // MARK: - Polling

    public func startPolling(interval: TimeInterval = 5.0) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Private

    private func performAction(_ action: @Sendable () async throws -> Void) async {
        do {
            try await action()
            lastError = nil
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
