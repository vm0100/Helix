// ABOUTME: Codable model for mutagen forward sessions parsed from JSON.
// ABOUTME: Represents the state of a network forwarding session including source/destination endpoints.

import Foundation

public struct ForwardSession: Codable, Identifiable, Hashable, Sendable {
    public var id: String { identifier }

    public let identifier: String
    public let version: Int
    public let creationTime: String
    public let creatingVersion: String
    public let name: String?
    public let labels: [String: String]?
    public let paused: Bool
    public let source: ForwardEndpoint
    public let destination: ForwardEndpoint
    public let sourceEndpoint: String?
    public let destinationEndpoint: String?
    public let socket: SocketConfig?
}

public struct ForwardEndpoint: Codable, Hashable, Sendable {
    public let protocol_: String
    public let user: String?
    public let host: String?
    public let port: Int?
    public let connected: Bool?

    enum CodingKeys: String, CodingKey {
        case protocol_ = "protocol"
        case user, host, port, connected
    }
}

public struct SocketConfig: Codable, Hashable, Sendable {
    public let overwriteMode: String?
    public let owner: String?
    public let group: String?
    public let permissionMode: String?
}
