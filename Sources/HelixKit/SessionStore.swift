// ABOUTME: Observable state container for all mutagen sessions.
// ABOUTME: Polls CLI periodically and exposes typed session arrays for SwiftUI binding.

import Foundation

public enum GitRepoStatus: Sendable, Equatable {
    case symmetric   // Both or neither have .git
    case alphaOnly   // Only alpha has .git
    case betaOnly    // Only beta has .git
    case unknown     // Transport error
}

public struct GitRepoCheck: Sendable, Equatable {
    public let status: GitRepoStatus
    public let subpath: String  // Relative path from sync root ("" for root)

    public init(status: GitRepoStatus, subpath: String = "") {
        self.status = status
        self.subpath = subpath
    }
}

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
        let alphaURL = appendingSubpath(to: session.alpha.endpointURL, subpath: conflict.root)
        let betaURL = appendingSubpath(to: session.beta.endpointURL, subpath: conflict.root)

        async let alphaStat = try? fileTransport.stat(endpoint: alphaURL)
        async let betaStat = try? fileTransport.stat(endpoint: betaURL)

        return (alpha: await alphaStat, beta: await betaStat)
    }

    public func resolveConflict(
        session: SyncSession,
        conflict: Conflict,
        winner: ConflictWinner
    ) async {
        let alphaURL = appendingSubpath(to: session.alpha.endpointURL, subpath: conflict.root)
        let betaURL = appendingSubpath(to: session.beta.endpointURL, subpath: conflict.root)

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

    // MARK: - Git Repo Detection

    public func gitRepoStatus(for session: SyncSession) async -> GitRepoCheck {
        let alphaGit = appendingSubpath(to: session.alpha.endpointURL, subpath: ".git")
        let betaGit = appendingSubpath(to: session.beta.endpointURL, subpath: ".git")

        async let alphaResult = try? fileTransport.directoryExists(endpoint: alphaGit)
        async let betaResult = try? fileTransport.directoryExists(endpoint: betaGit)

        guard let alphaHas = await alphaResult, let betaHas = await betaResult else {
            return GitRepoCheck(status: .unknown)
        }

        switch (alphaHas, betaHas) {
        case (true, true): return GitRepoCheck(status: .symmetric)
        case (true, false): return GitRepoCheck(status: .alphaOnly)
        case (false, true): return GitRepoCheck(status: .betaOnly)
        case (false, false): return await scanSubdirectoriesForGit(session: session)
        }
    }

    private func scanSubdirectoriesForGit(session: SyncSession) async -> GitRepoCheck {
        async let alphaOutput = try? fileTransport.run(
            on: session.alpha.endpointURL,
            command: "find . -maxdepth 2 -name .git -type d 2>/dev/null"
        )
        async let betaOutput = try? fileTransport.run(
            on: session.beta.endpointURL,
            command: "find . -maxdepth 2 -name .git -type d 2>/dev/null"
        )

        let alphaPaths = parseGitDirs(await alphaOutput ?? "")
        let betaPaths = parseGitDirs(await betaOutput ?? "")

        let alphaOnly = alphaPaths.subtracting(betaPaths).sorted()
        let betaOnly = betaPaths.subtracting(alphaPaths).sorted()

        if let first = alphaOnly.first {
            return GitRepoCheck(status: .alphaOnly, subpath: first)
        }
        if let first = betaOnly.first {
            return GitRepoCheck(status: .betaOnly, subpath: first)
        }
        return GitRepoCheck(status: .symmetric)
    }

    private func parseGitDirs(_ output: String) -> Set<String> {
        var result = Set<String>()
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix("/.git") else { continue }
            let parent = String(trimmed.dropLast(5))
            if parent == "." {
                result.insert("")
            } else if parent.hasPrefix("./") {
                result.insert(String(parent.dropFirst(2)))
            } else {
                result.insert(parent)
            }
        }
        return result
    }

    // MARK: - Git Auto-Fix

    public func gitSourceInfo(
        for session: SyncSession,
        gitCheck: GitRepoCheck
    ) async -> (remoteURL: String?, branch: String?) {
        guard gitCheck.status == .alphaOnly || gitCheck.status == .betaOnly else { return (nil, nil) }

        let sourceBase = gitCheck.status == .alphaOnly
            ? session.alpha.endpointURL
            : session.beta.endpointURL
        let sourceEndpoint = gitCheck.subpath.isEmpty
            ? sourceBase
            : appendingSubpath(to: sourceBase, subpath: gitCheck.subpath)

        let remoteURL = (try? await fileTransport.run(
            on: sourceEndpoint, command: "git config --get remote.origin.url"
        ))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = (try? await fileTransport.run(
            on: sourceEndpoint, command: "git rev-parse --abbrev-ref HEAD"
        ))?.trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            remoteURL: remoteURL?.isEmpty == true ? nil : remoteURL,
            branch: branch?.isEmpty == true ? nil : branch
        )
    }

    public func fixGitMismatch(session: SyncSession, gitCheck: GitRepoCheck) async -> Bool {
        guard gitCheck.status == .alphaOnly || gitCheck.status == .betaOnly else { return false }

        let sourceBase = gitCheck.status == .alphaOnly
            ? session.alpha.endpointURL
            : session.beta.endpointURL
        let targetBase = gitCheck.status == .alphaOnly
            ? session.beta.endpointURL
            : session.alpha.endpointURL
        let sourceEndpoint = gitCheck.subpath.isEmpty ? sourceBase : appendingSubpath(to: sourceBase, subpath: gitCheck.subpath)
        let targetEndpoint = gitCheck.subpath.isEmpty ? targetBase : appendingSubpath(to: targetBase, subpath: gitCheck.subpath)

        let remoteURL: String
        let branch: String
        do {
            remoteURL = try await fileTransport.run(on: sourceEndpoint, command: "git config --get remote.origin.url").trimmingCharacters(in: .whitespacesAndNewlines)
            branch = try await fileTransport.run(on: sourceEndpoint, command: "git rev-parse --abbrev-ref HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = "Could not read git info: \(error.localizedDescription)"
            return false
        }

        guard !remoteURL.isEmpty, !branch.isEmpty else {
            lastError = "No git remote or branch found on the source endpoint"
            return false
        }

        do {
            _ = try await fileTransport.run(on: targetEndpoint, command: "git init")
            _ = try await fileTransport.run(on: targetEndpoint, command: "git remote add origin '\(remoteURL)'")
            _ = try await fileTransport.run(on: targetEndpoint, command: "git fetch origin")
            _ = try await fileTransport.run(on: targetEndpoint, command: "git reset --mixed 'origin/\(branch)'")
            lastError = nil
            return true
        } catch {
            lastError = "Git init failed: \(error.localizedDescription)"
            return false
        }
    }

    private func appendingSubpath(to endpoint: EndpointURL, subpath: String) -> EndpointURL {
        switch endpoint {
        case .local(let path):
            return .local(path: (path as NSString).appendingPathComponent(subpath))
        case .ssh(let user, let host, let port, let path):
            return .ssh(user: user, host: host, port: port, path: (path as NSString).appendingPathComponent(subpath))
        case .docker(let container, let path):
            return .docker(container: container, path: (path as NSString).appendingPathComponent(subpath))
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
