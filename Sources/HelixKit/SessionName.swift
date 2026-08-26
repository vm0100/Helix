// ABOUTME: Validation for user-supplied session names, shared by create and rename flows.
// ABOUTME: Enforces mutagen's naming rules plus Helix's own uniqueness requirement.

import Foundation

/// Why a session name was rejected.
///
/// Mutagen permits duplicate names, but resolves sessions by name
/// (`mutagen sync pause my-session`), so a duplicate makes every
/// name-addressed command ambiguous. Helix rejects them up front.
public enum SessionNameError: Equatable, Sendable {
    case reserved
    case mustStartWithLetter
    case invalidCharacter(Character)
    case duplicate

    public var message: String {
        switch self {
        case .reserved:
            return "\"defaults\" is reserved"
        case .mustStartWithLetter:
            return "Must start with a letter"
        case .invalidCharacter(let character):
            return "Invalid character: '\(character)' — only letters, numbers, and dashes allowed"
        case .duplicate:
            return "A session with this name already exists"
        }
    }
}

public enum SessionName {

    /// Returns the reason `name` is unusable, or nil if it is valid.
    ///
    /// An empty name is valid: mutagen names are optional.
    /// - Parameter existingNames: names already taken within the same session kind.
    ///   Callers renaming a session must omit that session's own name.
    public static func validate(_ name: String, existingNames: [String]) -> SessionNameError? {
        guard !name.isEmpty else { return nil }

        if name.lowercased() == "defaults" {
            return .reserved
        }
        if let first = name.first, !first.isLetter {
            return .mustStartWithLetter
        }
        if let bad = name.first(where: { !$0.isLetter && !$0.isNumber && $0 != "-" }) {
            return .invalidCharacter(bad)
        }
        if existingNames.contains(name) {
            return .duplicate
        }
        return nil
    }
}
