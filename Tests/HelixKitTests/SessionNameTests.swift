// ABOUTME: Tests for session name validation shared by the create and rename flows.
// ABOUTME: Covers mutagen's naming rules plus Helix's rejection of duplicate names.

import Testing
@testable import HelixKit

@Suite("Session name syntax validation")
struct SessionNameSyntaxTests {

    @Test("Empty name is allowed — mutagen names are optional")
    func emptyNameAllowed() {
        #expect(SessionName.validate("", existingNames: []) == nil)
    }

    @Test("Letters, numbers, and dashes pass")
    func wellFormedName() {
        #expect(SessionName.validate("web-app-2", existingNames: []) == nil)
    }

    @Test("\"defaults\" is reserved, regardless of case")
    func reservedName() {
        #expect(SessionName.validate("defaults", existingNames: []) == .reserved)
        #expect(SessionName.validate("Defaults", existingNames: []) == .reserved)
    }

    @Test("Name must start with a letter")
    func mustStartWithLetter() {
        #expect(SessionName.validate("2fast", existingNames: []) == .mustStartWithLetter)
        #expect(SessionName.validate("-lead", existingNames: []) == .mustStartWithLetter)
    }

    @Test("Only letters, numbers, and dashes are allowed")
    func invalidCharacter() {
        #expect(SessionName.validate("my_session", existingNames: []) == .invalidCharacter("_"))
        #expect(SessionName.validate("my session", existingNames: []) == .invalidCharacter(" "))
    }
}

@Suite("Session name uniqueness")
struct SessionNameUniquenessTests {

    @Test("Rejects a name another session already holds")
    func rejectsDuplicate() {
        #expect(SessionName.validate("web-app", existingNames: ["api", "web-app"]) == .duplicate)
    }

    @Test("Accepts a name no other session holds")
    func acceptsUnique() {
        #expect(SessionName.validate("web-app", existingNames: ["api", "worker"]) == nil)
    }

    @Test("Comparison is exact — mutagen resolves names without case folding")
    func caseSensitive() {
        #expect(SessionName.validate("Web-app", existingNames: ["web-app"]) == nil)
    }

    @Test("Syntax errors are reported before duplication")
    func syntaxBeatsDuplication() {
        #expect(SessionName.validate("2fast", existingNames: ["2fast"]) == .mustStartWithLetter)
    }
}
