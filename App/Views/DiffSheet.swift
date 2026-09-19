// ABOUTME: Side-by-side diff viewer for conflicting files in a sync session.
// ABOUTME: Shows alpha vs beta content with line-level and character-level highlighting.

import SwiftUI
import HelixKit

// MARK: - Window Data

struct DiffRequest: Codable, Hashable {
    let sessionIdentifier: String
    let conflictRoot: String
}

struct DiffWindowContent: View {
    let request: DiffRequest
    let store: SessionStore

    private var session: SyncSession? {
        store.syncSessions.first { $0.identifier == request.sessionIdentifier }
    }

    private var conflict: Conflict? {
        session?.conflicts?.first { $0.root == request.conflictRoot }
    }

    var body: some View {
        if let session, let conflict {
            DiffView(session: session, conflict: conflict, store: store)
                .navigationTitle(conflict.root)
        } else {
            ContentUnavailableView(
                "Conflict Resolved",
                systemImage: "checkmark.circle",
                description: Text("This conflict no longer exists.")
            )
        }
    }
}

// MARK: - Diff View

struct DiffView: View {
    let session: SyncSession
    let conflict: Conflict
    let store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var hunks: [DiffHunkResult]?
    @State private var rows: [DiffRow] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var pendingWinner: ConflictWinner?
    @State private var isResolving = false

    var body: some View {
        content
            .frame(minWidth: 600, minHeight: 400)
            .task { await loadDiff() }
            .alert(
                "Resolve Conflict",
                isPresented: Binding(
                    get: { pendingWinner != nil },
                    set: { if !$0 { pendingWinner = nil } }
                )
            ) {
                Button("Replace", role: .destructive) {
                    guard let winner = pendingWinner else { return }
                    pendingWinner = nil
                    Task {
                        isResolving = true
                        await store.resolveConflict(session: session, conflict: conflict, winner: winner)
                        isResolving = false
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingWinner = nil
                }
            } message: {
            let loserLabel = pendingWinner == .alpha ? "乙端" : "甲端"
            Text("这将永久删除“\(conflict.root)”的\(loserLabel)版本，并替换为选中的一端。")
            }
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
            Divider()
            resolutionBar
        }
    }

    private var resolutionBar: some View {
        HStack(spacing: 0) {
            if isResolving {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Resolving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
            } else {
                Button { pendingWinner = .alpha } label: {
                    Label("保留甲端", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(8)

                Button { pendingWinner = .beta } label: {
                    Label("保留乙端", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .padding(8)
            }
        }
        .background(.background.secondary)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("甲端（\(session.alpha.shortLabel)）")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Divider()
                .frame(height: 20)

            Text("乙端（\(session.beta.shortLabel)）")
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
            error = "无法读取一端或两端的文件内容。"
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
