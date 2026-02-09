// ABOUTME: Codable models for mutagen sync conflicts and their constituent changes.
// ABOUTME: Each conflict has a root path with alpha and beta change sets.

import Foundation

public struct Conflict: Codable, Hashable, Sendable {
    public let root: String
    public let alphaChanges: [Change]
    public let betaChanges: [Change]
}

public struct Change: Codable, Hashable, Sendable {
    public let path: String
    public let old: Entry?
    public let new: Entry?

    enum CodingKeys: String, CodingKey {
        case path
        case old
        case new
    }
}

public struct Entry: Codable, Hashable, Sendable {
    public let kind: String
    public let digest: String?
    public let executable: Bool?
}
