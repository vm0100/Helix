// ABOUTME: Side-by-side diff viewer for conflicting files in a sync session.
// ABOUTME: Shows alpha vs beta content with line-level and character-level highlighting.

import SwiftUI
import HelixKit

struct DiffSheet: View {
    let session: SyncSession
    let conflict: Conflict
    let store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var hunks: [DiffHunkResult]?
    @State private var rows: [DiffRow] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 700, idealWidth: 900, minHeight: 400, idealHeight: 600)
        .task { await loadDiff() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.orange)
            Text(conflict.root)
                .font(.headline)
                .monospaced()
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if let error {
            errorView(error)
        } else if rows.isEmpty {
            emptyView
        } else {
            diffView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading diff...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Could not load diff")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Files are identical")
                .font(.headline)
            Text("No differences found between alpha and beta.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Diff View

    private var diffView: some View {
        VStack(spacing: 0) {
            columnHeaders
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row.kind {
                        case .separator:
                            separatorRow
                        case .line(let left, let right):
                            lineRow(left: left, right: right)
                        }
                    }
                }
            }
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Alpha (\(session.alpha.shortLabel))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Divider()
                .frame(height: 20)

            Text("Beta (\(session.beta.shortLabel))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.purple)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .background(.background.secondary)
    }

    private var separatorRow: some View {
        HStack(spacing: 0) {
            Text("...")
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(.background.secondary)
        }
    }

    private func lineRow(left: DiffSide?, right: DiffSide?) -> some View {
        HStack(spacing: 0) {
            sideView(side: left, alignment: .alpha)
            Divider()
            sideView(side: right, alignment: .beta)
        }
    }

    private func sideView(side: DiffSide?, alignment: SideAlignment) -> some View {
        HStack(spacing: 0) {
            // Gutter (line number)
            Text(side.map { "\($0.lineNumber)" } ?? "")
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 4)

            // Content
            if let side {
                if let inlineChunks = side.inlineChunks {
                    inlineHighlightedText(chunks: inlineChunks, tag: side.tag)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(side.text)
                        .font(.caption)
                        .monospaced()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 1)
        .padding(.trailing, 4)
        .background(backgroundColor(for: side?.tag))
    }

    private func inlineHighlightedText(chunks: [InlineChunkResult], tag: DiffTag) -> Text {
        var attributed = AttributedString()
        for chunk in chunks {
            var part = AttributedString(chunk.text)
            switch chunk.tag {
            case .delete:
                part.backgroundColor = .red.opacity(0.3)
            case .insert:
                part.backgroundColor = .green.opacity(0.3)
            case .equal:
                break
            }
            attributed.append(part)
        }
        return Text(attributed)
            .font(.caption)
            .monospaced()
    }

    private func backgroundColor(for tag: DiffTag?) -> Color {
        switch tag {
        case .delete: return .red.opacity(0.08)
        case .insert: return .green.opacity(0.08)
        case .equal, .none: return .clear
        }
    }

    // MARK: - Data Loading

    private func loadDiff() async {
        isLoading = true
        let result = await store.conflictDiff(session: session, conflict: conflict)
        if let result {
            hunks = result
            rows = buildRows(from: result)
        } else {
            error = "Could not read file contents from one or both endpoints."
        }
        isLoading = false
    }
}

// MARK: - Data Model

private enum SideAlignment {
    case alpha, beta
}

struct DiffRow: Identifiable {
    let id = UUID()
    let kind: DiffRowKind
}

enum DiffRowKind {
    case separator
    case line(left: DiffSide?, right: DiffSide?)
}

struct DiffSide {
    let lineNumber: Int
    let text: String
    let tag: DiffTag
    let inlineChunks: [InlineChunkResult]?
}

// MARK: - Row Builder

private func buildRows(from hunks: [DiffHunkResult]) -> [DiffRow] {
    var rows: [DiffRow] = []

    for (hunkIndex, hunk) in hunks.enumerated() {
        if hunkIndex > 0 {
            rows.append(DiffRow(kind: .separator))
        }

        var leftLine = hunk.oldStart + 1
        var rightLine = hunk.newStart + 1
        var pendingDeletes: [LineDiff] = []
        var pendingInserts: [LineDiff] = []

        func flushPending() {
            let pairs = max(pendingDeletes.count, pendingInserts.count)
            for i in 0..<pairs {
                let del = i < pendingDeletes.count ? pendingDeletes[i] : nil
                let ins = i < pendingInserts.count ? pendingInserts[i] : nil

                let inlineChunks: [InlineChunkResult]? = (del != nil && ins != nil)
                    ? DiffEngine.diffChars(old: del!.text, new: ins!.text)
                    : nil

                let delChunks = inlineChunks?.filter { $0.tag != .insert }
                let insChunks = inlineChunks?.filter { $0.tag != .delete }

                let left = del.map { DiffSide(lineNumber: leftLine, text: $0.text, tag: .delete, inlineChunks: delChunks) }
                let right = ins.map { DiffSide(lineNumber: rightLine, text: $0.text, tag: .insert, inlineChunks: insChunks) }

                rows.append(DiffRow(kind: .line(left: left, right: right)))
                if del != nil { leftLine += 1 }
                if ins != nil { rightLine += 1 }
            }
            pendingDeletes.removeAll()
            pendingInserts.removeAll()
        }

        for line in hunk.lines {
            switch line.tag {
            case .equal:
                flushPending()
                let side = DiffSide(lineNumber: leftLine, text: line.text, tag: .equal, inlineChunks: nil)
                let rightSide = DiffSide(lineNumber: rightLine, text: line.text, tag: .equal, inlineChunks: nil)
                rows.append(DiffRow(kind: .line(left: side, right: rightSide)))
                leftLine += 1
                rightLine += 1
            case .delete:
                pendingDeletes.append(line)
            case .insert:
                pendingInserts.append(line)
            }
        }
        flushPending()
    }

    return rows
}
