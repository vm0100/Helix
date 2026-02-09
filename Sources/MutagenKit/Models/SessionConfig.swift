// ABOUTME: Codable models for mutagen session configuration sections.
// ABOUTME: Covers ignore rules, symlinks, watching, permissions, and compression settings.

import Foundation

public struct IgnoreConfig: Codable, Hashable, Sendable {
    public let paths: [String]?
    public let syntax: String?
}

public struct SymlinkConfig: Codable, Hashable, Sendable {
    public let mode: String?
}

public struct WatchConfig: Codable, Hashable, Sendable {
    public let mode: String?
    public let pollingInterval: Int?
}

public struct PermissionsConfig: Codable, Hashable, Sendable {
    public let mode: String?
    public let defaultFileMode: String?
    public let defaultDirectoryMode: String?
    public let defaultOwner: String?
    public let defaultGroup: String?
}

public struct CompressionConfig: Codable, Hashable, Sendable {
    public let algorithm: String?
}
