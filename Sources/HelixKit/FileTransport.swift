// ABOUTME: Copies files between local, SSH, and Docker endpoints for conflict resolution.
// ABOUTME: Uses cp, scp, and docker-cp with an injectable executor for testability.

import Foundation

public enum FileTransportError: Error {
    case malformedStatOutput(String)
}

public struct FileInfo: Sendable {
    public let size: Int64
    public let modifiedAt: Date
}

public enum ConflictWinner: Sendable {
    case alpha
    case beta
}

public struct FileTransport: Sendable {
    let execute: @Sendable (String, [String]) async throws -> String

    public init() {
        self.execute = { executable, arguments in
            let cmd = "\(executable) \(arguments.joined(separator: " "))"
            await MainActor.run { ConsoleLog.shared.log(cmd, level: .command) }
            do {
                let result = try await runProcess(executablePath: executable, arguments: arguments)
                await MainActor.run { ConsoleLog.shared.log(String(result.prefix(200))) }
                return result
            } catch {
                await MainActor.run { ConsoleLog.shared.log("FAILED: \(error)", level: .error) }
                throw error
            }
        }
    }

    public init(execute: @escaping @Sendable (String, [String]) async throws -> String) {
        self.execute = execute
    }

    // MARK: - Copy

    public func copy(from source: EndpointURL, to destination: EndpointURL) async throws {
        switch (source, destination) {
        case (.local(let src), .local(let dst)):
            _ = try await execute("/bin/cp", ["-Rp", src, dst])

        case (.local(let src), .ssh(let user, let host, let port, let path)):
            _ = try await execute("/usr/bin/scp", scpArgs(port: port, recursive: true, from: src, to: scpRemote(user: user, host: host, path: path)))

        case (.ssh(let user, let host, let port, let path), .local(let dst)):
            _ = try await execute("/usr/bin/scp", scpArgs(port: port, recursive: true, from: scpRemote(user: user, host: host, path: path), to: dst))

        case (.local(let src), .docker(let container, let path)):
            _ = try await execute("/usr/bin/docker", ["cp", src, "\(container):\(path)"])

        case (.docker(let container, let path), .local(let dst)):
            _ = try await execute("/usr/bin/docker", ["cp", "\(container):\(path)", dst])

        case (.ssh(let u1, let h1, let p1, let path1), .ssh(let u2, let h2, let p2, let path2)):
            var args = ["-3", "-r"]
            if let port = p1 ?? p2 {
                args += ["-P", "\(port)"]
            }
            args += [scpRemote(user: u1, host: h1, path: path1), scpRemote(user: u2, host: h2, path: path2)]
            _ = try await execute("/usr/bin/scp", args)

        default:
            // Cross-transport (ssh<->docker, docker<->docker): relay via temp file
            try await copyViaTemp(from: source, to: destination)
        }
    }

    // MARK: - Stat

    public func stat(endpoint: EndpointURL) async throws -> FileInfo {
        let output: String
        switch endpoint {
        case .local(let path):
            output = try await execute("/usr/bin/stat", ["-f", "%z %m", path])
        case .ssh(let user, let host, let port, let path):
            var args: [String] = []
            if let port {
                args += ["-p", "\(port)"]
            }
            // GNU stat uses -c, macOS stat uses -f with different format specifiers
            args += [sshTarget(user: user, host: host), "stat -c '%s %Y' \(path) 2>/dev/null || stat -f '%z %m' \(path)"]
            output = try await execute("/usr/bin/ssh", args)
        case .docker(let container, let path):
            output = try await execute("/usr/bin/docker", ["exec", container, "stat", "-c", "%s %Y", path])
        }
        return try parseStatOutput(output)
    }

    // MARK: - Remove

    public func remove(endpoint: EndpointURL) async throws {
        switch endpoint {
        case .local(let path):
            _ = try await execute("/bin/rm", ["-rf", path])
        case .ssh(let user, let host, let port, let path):
            var args: [String] = []
            if let port {
                args += ["-p", "\(port)"]
            }
            args += [sshTarget(user: user, host: host), "rm -rf '\(path)'"]
            _ = try await execute("/usr/bin/ssh", args)
        case .docker(let container, let path):
            _ = try await execute("/usr/bin/docker", ["exec", container, "rm", "-rf", path])
        }
    }

    // MARK: - Directory Exists

    public func directoryExists(endpoint: EndpointURL) async throws -> Bool {
        do {
            switch endpoint {
            case .local(let path):
                _ = try await execute("/bin/test", ["-d", path])
            case .ssh(let user, let host, let port, let path):
                var args: [String] = []
                if let port { args += ["-p", "\(port)"] }
                args += [sshTarget(user: user, host: host), "test -d '\(path)'"]
                _ = try await execute("/usr/bin/ssh", args)
            case .docker(let container, let path):
                _ = try await execute("/usr/bin/docker", ["exec", container, "test", "-d", path])
            }
            return true
        } catch let error as CLIError where error.exitCode == 1 {
            return false
        }
    }

    // MARK: - Private

    private func copyViaTemp(from source: EndpointURL, to destination: EndpointURL) async throws {
        let tempPath = NSTemporaryDirectory() + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        try await copy(from: source, to: .local(path: tempPath))
        try await copy(from: .local(path: tempPath), to: destination)
    }

    private func scpRemote(user: String?, host: String, path: String) -> String {
        if let user {
            return "\(user)@\(host):\(path)"
        }
        return "\(host):\(path)"
    }

    private func scpArgs(port: Int?, recursive: Bool = false, from: String, to: String) -> [String] {
        var args: [String] = []
        if recursive {
            args.append("-r")
        }
        if let port {
            args += ["-P", "\(port)"]
        }
        args += [from, to]
        return args
    }

    private func sshTarget(user: String?, host: String) -> String {
        if let user {
            return "\(user)@\(host)"
        }
        return host
    }

    private func parseStatOutput(_ raw: String) throws -> FileInfo {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ")
        guard parts.count == 2,
              let size = Int64(parts[0]),
              let mtime = TimeInterval(parts[1]) else {
            throw FileTransportError.malformedStatOutput(trimmed)
        }
        return FileInfo(size: size, modifiedAt: Date(timeIntervalSince1970: mtime))
    }
}
