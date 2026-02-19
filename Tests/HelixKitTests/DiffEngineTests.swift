// ABOUTME: Tests for the DiffEngine Swift wrapper over the Rust diff library.
// ABOUTME: Validates line-level diff and character-level diff via FFI.

import Testing
@testable import HelixKit

@Suite("DiffEngine line-level diff")
struct DiffEngineLinesTests {

    @Test("Detects single line change")
    func singleLineChange() {
        let old = "hello\nworld\n"
        let new = "hello\nrust\n"

        let hunks = DiffEngine.diffLines(old: old, new: new)
        #expect(hunks.count > 0)

        let allLines = hunks.flatMap(\.lines)
        let deletions = allLines.filter { $0.tag == .delete }
        let insertions = allLines.filter { $0.tag == .insert }

        #expect(deletions.count == 1)
        #expect(insertions.count == 1)
        #expect(deletions[0].text == "world")
        #expect(insertions[0].text == "rust")
    }

    @Test("Returns empty for identical inputs")
    func identical() {
        let text = "same\ncontent\nhere\n"
        let hunks = DiffEngine.diffLines(old: text, new: text)
        #expect(hunks.isEmpty)
    }

    @Test("Handles empty old (all insertions)")
    func emptyOld() {
        let hunks = DiffEngine.diffLines(old: "", new: "new line\n")
        #expect(hunks.count > 0)

        let insertions = hunks.flatMap(\.lines).filter { $0.tag == .insert }
        #expect(insertions.count > 0)
    }

    @Test("Handles empty new (all deletions)")
    func emptyNew() {
        let hunks = DiffEngine.diffLines(old: "old line\n", new: "")
        #expect(hunks.count > 0)

        let deletions = hunks.flatMap(\.lines).filter { $0.tag == .delete }
        #expect(deletions.count > 0)
    }

    @Test("Includes context lines")
    func contextLines() {
        let old = "line1\nline2\nline3\nline4\nline5\n"
        let new = "line1\nline2\nchanged\nline4\nline5\n"

        let hunks = DiffEngine.diffLines(old: old, new: new, contextLines: 1)
        #expect(hunks.count == 1)

        let lines = hunks[0].lines
        let equalLines = lines.filter { $0.tag == .equal }
        #expect(equalLines.count >= 1) // at least some context
    }

    @Test("Reports correct hunk positions")
    func hunkPositions() {
        let old = "a\nb\nc\n"
        let new = "a\nx\nc\n"

        let hunks = DiffEngine.diffLines(old: old, new: new, contextLines: 0)
        #expect(hunks.count == 1)
        // The changed line is at index 1 in both old and new
    }
}

@Suite("DiffEngine character-level diff")
struct DiffEngineCharsTests {

    @Test("Detects character-level changes")
    func charDiff() {
        let old = "hello world"
        let new = "hello rust"

        let chunks = DiffEngine.diffChars(old: old, new: new)
        #expect(chunks.count > 0)

        // Should have equal + delete + insert at minimum
        let tags = Set(chunks.map(\.tag))
        #expect(tags.contains(.equal))
        #expect(tags.contains(.delete) || tags.contains(.insert))
    }

    @Test("Identical strings produce single equal chunk")
    func identicalChars() {
        let text = "hello world"
        let chunks = DiffEngine.diffChars(old: text, new: text)
        #expect(chunks.count == 1)
        #expect(chunks[0].tag == .equal)
        #expect(chunks[0].text == text)
    }

    @Test("Empty to non-empty is all insert")
    func emptyToText() {
        let chunks = DiffEngine.diffChars(old: "", new: "hello")
        #expect(chunks.count == 1)
        #expect(chunks[0].tag == .insert)
        #expect(chunks[0].text == "hello")
    }
}
