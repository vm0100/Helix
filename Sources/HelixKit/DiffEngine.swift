// ABOUTME: Swift wrapper over the helix-diff Rust library's C-ABI.
// ABOUTME: Converts C heap-allocated structs to Swift value types with automatic memory management.

import Foundation
import CHelixDiff

// MARK: - Swift Types

public enum DiffTag: Sendable {
    case equal
    case delete
    case insert
}

public struct LineDiff: Sendable {
    public let tag: DiffTag
    public let text: String
}

public struct DiffHunkResult: Sendable {
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [LineDiff]
}

public struct InlineChunkResult: Sendable {
    public let tag: DiffTag
    public let text: String
}

// MARK: - Engine

public enum DiffEngine {

    /// Computes a line-level diff between two strings using the histogram algorithm.
    public static func diffLines(old: String, new: String, contextLines: UInt32 = 3) -> [DiffHunkResult] {
        old.withCString { oldPtr in
            new.withCString { newPtr in
                guard let resultPtr = helix_diff_lines(
                    oldPtr, UInt32(old.utf8.count),
                    newPtr, UInt32(new.utf8.count),
                    contextLines
                ) else {
                    return []
                }
                defer { helix_diff_free(resultPtr) }

                let result = resultPtr.pointee
                guard result.hunk_count > 0, let hunksPtr = result.hunks else {
                    return []
                }

                var hunks: [DiffHunkResult] = []
                hunks.reserveCapacity(Int(result.hunk_count))

                for i in 0..<Int(result.hunk_count) {
                    let hunk = hunksPtr[i]
                    var lines: [LineDiff] = []
                    lines.reserveCapacity(Int(hunk.line_count))

                    if let linesPtr = hunk.lines {
                        for j in 0..<Int(hunk.line_count) {
                            let line = linesPtr[j]
                            let tag = tagFromByte(line.tag)
                            let text = stringFromCPtr(line.text, length: line.text_len)
                            lines.append(LineDiff(tag: tag, text: text))
                        }
                    }

                    hunks.append(DiffHunkResult(
                        oldStart: Int(hunk.old_start),
                        oldCount: Int(hunk.old_count),
                        newStart: Int(hunk.new_start),
                        newCount: Int(hunk.new_count),
                        lines: lines
                    ))
                }
                return hunks
            }
        }
    }

    /// Computes a character-level diff between two strings for inline highlighting.
    public static func diffChars(old: String, new: String) -> [InlineChunkResult] {
        old.withCString { oldPtr in
            new.withCString { newPtr in
                guard let resultPtr = helix_diff_chars(
                    oldPtr, UInt32(old.utf8.count),
                    newPtr, UInt32(new.utf8.count)
                ) else {
                    return []
                }
                defer { helix_inline_free(resultPtr) }

                let result = resultPtr.pointee
                guard result.chunk_count > 0, let chunksPtr = result.chunks else {
                    return []
                }

                var chunks: [InlineChunkResult] = []
                chunks.reserveCapacity(Int(result.chunk_count))

                for i in 0..<Int(result.chunk_count) {
                    let chunk = chunksPtr[i]
                    let tag = tagFromByte(chunk.tag)
                    let text = stringFromCPtr(chunk.text, length: chunk.text_len)
                    chunks.append(InlineChunkResult(tag: tag, text: text))
                }
                return chunks
            }
        }
    }

    // MARK: - Private

    private static func tagFromByte(_ byte: UInt8) -> DiffTag {
        switch byte {
        case 1: return .delete
        case 2: return .insert
        default: return .equal
        }
    }

    private static func stringFromCPtr(_ ptr: UnsafeMutablePointer<CChar>?, length: UInt32) -> String {
        guard let ptr else { return "" }
        let len = Int(length)
        return ptr.withMemoryRebound(to: UInt8.self, capacity: len) { bytes in
            String(bytes: UnsafeBufferPointer(start: bytes, count: len), encoding: .utf8) ?? ""
        }
    }
}
