// ABOUTME: Async wrapper for running shell processes with stdout/stderr capture.
// ABOUTME: Shared by CLI (mutagen commands) and FileTransport (cp/scp/docker-cp).

import Foundation

public func runProcess(executablePath: String, arguments: [String]) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { process in
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                continuation.resume(throwing: CLIError(
                    exitCode: process.terminationStatus,
                    stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            } else {
                continuation.resume(returning: stdout)
            }
        }

        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
