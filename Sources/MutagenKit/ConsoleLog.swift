// ABOUTME: Observable log buffer for displaying commands and results in an in-app console.
// ABOUTME: Capped at 500 entries to prevent unbounded memory growth.

import Foundation

public struct ConsoleEntry: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let level: ConsoleLevel
}

public enum ConsoleLevel {
    case info
    case command
    case error
}

@MainActor
@Observable
public final class ConsoleLog {
    public static let shared = ConsoleLog()
    public private(set) var entries: [ConsoleEntry] = []

    private static let maxEntries = 500

    public func log(_ message: String, level: ConsoleLevel = .info) {
        entries.append(ConsoleEntry(timestamp: Date(), message: message, level: level))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    public func clear() {
        entries.removeAll()
    }
}
