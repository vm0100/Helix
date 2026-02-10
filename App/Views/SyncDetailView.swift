// ABOUTME: Detailed view for a sync session showing endpoints, configuration, and conflicts.
// ABOUTME: Provides action buttons for pause/resume, flush, reset, and terminate.

import SwiftUI
import HelixKit

struct SyncDetailView: View {
    let session: SyncSession
    let store: SessionStore
    @State private var showTerminateConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showEditSheet = false
    @State private var gitCheck: GitRepoCheck = GitRepoCheck(status: .unknown)
    @State private var isFixingGit = false
    @State private var showManualFix = false
    @State private var sourceRemoteURL: String?
    @State private var sourceBranch: String?
    @AppStorage("dismissedGitMismatches") private var dismissedJSON = "[]"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                endpointsSection
                if (gitCheck.status == .alphaOnly || gitCheck.status == .betaOnly) && !isGitMismatchDismissed {
                    gitMismatchBanner
                }
                configurationSection
                if let conflicts = session.conflicts, !conflicts.isEmpty {
                    conflictsSection(conflicts)
                }
                dangerZone
            }
            .padding()
        }
        .navigationTitle(session.name ?? session.identifier)
        .confirmationDialog(
            "Reset Session?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task { await store.resetSync(session.identifier) }
            }
        } message: {
            Text("This clears the sync history. Both sides will be re-scanned and current contents treated as the baseline.")
        }
        .confirmationDialog(
            "Terminate Session?",
            isPresented: $showTerminateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Terminate", role: .destructive) {
                Task { await store.terminateSync(session.identifier) }
            }
        } message: {
            Text("This permanently removes the session. It cannot be undone.")
        }
        .sheet(isPresented: $showEditSheet) {
            EditSyncConfigView(session: session, store: store)
        }
        .task(id: session.identifier) {
            gitCheck = await store.gitRepoStatus(for: session)
            if gitCheck.status == .alphaOnly || gitCheck.status == .betaOnly {
                let info = await store.gitSourceInfo(for: session, gitCheck: gitCheck)
                sourceRemoteURL = info.remoteURL
                sourceBranch = info.branch
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.name ?? session.identifier)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()

                actionButtons
            }

            HStack {
                StatusBadge(status: session.status, paused: session.paused)
                Text(StatusBadge(status: session.status, paused: session.paused).label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label((session.mode ?? "two-way-safe").replacingOccurrences(of: "-", with: " ").capitalized, systemImage: "arrow.triangle.2.circlepath")
                if let cycles = session.successfulCycles {
                    Label("\(cycles) cycles", systemImage: "checkmark.circle")
                }
                Label(session.creationTime.prefix(10).description, systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if session.paused {
                Button("Resume") {
                    Task { await store.resumeSync(session.identifier) }
                }
            } else {
                Button("Pause") {
                    Task { await store.pauseSync(session.identifier) }
                }
            }

            Button("Flush") {
                Task { await store.flushSync(session.identifier) }
            }
            .disabled(session.paused)

            Button("Reset") {
                showResetConfirmation = true
            }
        }
        .controlSize(.small)
    }

    // MARK: - Endpoints

    private var endpointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Endpoints")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                EndpointCard(label: "Alpha", endpoint: session.alpha)
                EndpointCard(label: "Beta", endpoint: session.beta)
            }
        }
    }

    // MARK: - Git Mismatch Banner

    private var gitMismatchBanner: some View {
        let hasGitLabel = gitCheck.status == .alphaOnly ? "Alpha" : "Beta"
        let missingGitLabel = gitCheck.status == .alphaOnly ? "Beta" : "Alpha"
        let missingEndpoint = gitCheck.status == .alphaOnly ? session.beta : session.alpha
        let basePath = missingEndpoint.path ?? "<path>"
        let missingPath = gitCheck.subpath.isEmpty ? basePath : (basePath as NSString).appendingPathComponent(gitCheck.subpath)
        let subpathNote = gitCheck.subpath.isEmpty ? "" : " (in \(gitCheck.subpath)/)"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Git Repository Mismatch\(subpathNote)")
                    .font(.headline)
                Spacer()
                Button("Dismiss") { dismissGitMismatch() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(hasGitLabel) has a .git directory, but \(missingGitLabel) does not. This typically happens when .git is excluded from sync (which is correct) but only one side has been initialized as a git repo.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    isFixingGit = true
                    let success = await store.fixGitMismatch(session: session, gitCheck: gitCheck)
                    if success {
                        gitCheck = await store.gitRepoStatus(for: session)
                    }
                    isFixingGit = false
                }
            } label: {
                if isFixingGit {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Initializing git...")
                    }
                } else {
                    Label("Fix Automatically", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isFixingGit)

            DisclosureGroup(isExpanded: $showManualFix) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run these commands on the \(missingGitLabel) endpoint:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let commands = """
                    cd \(missingPath)
                    git init
                    git remote add origin \(sourceRemoteURL ?? "<remote-url>")
                    git fetch origin
                    git reset --mixed origin/\(sourceBranch ?? "<branch>")
                    """

                    Text(commands)
                        .font(.caption2)
                        .monospaced()
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.top, 4)
            } label: {
                Label("How to fix manually", systemImage: "wrench")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { showManualFix.toggle() }
            }
        }
        .padding()
        .background(.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var isGitMismatchDismissed: Bool {
        let dismissed = (try? JSONDecoder().decode(Set<String>.self, from: Data(dismissedJSON.utf8))) ?? []
        return dismissed.contains(session.identifier)
    }

    private func dismissGitMismatch() {
        var dismissed = (try? JSONDecoder().decode(Set<String>.self, from: Data(dismissedJSON.utf8))) ?? []
        dismissed.insert(session.identifier)
        if let data = try? JSONEncoder().encode(dismissed) {
            dismissedJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Configuration")
                    .font(.headline)
                Spacer()
                Button("Edit") {
                    showEditSheet = true
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 0) {
                configRow("Mode", session.mode ?? "two-way-safe")
                configRow("Symlinks", session.symlink.mode ?? "portable")
                configRow("Watch", session.watch.mode ?? "portable")
                configRow("Permissions", session.permissions.mode ?? "portable")
                configRow("Compression", session.compression.algorithm ?? "deflate")
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let paths = session.ignore.paths, !paths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ignore Rules")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(paths, id: \.self) { path in
                            Text(path)
                                .font(.caption2)
                                .monospaced()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.background.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func configRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .monospaced()
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.background.secondary)
    }

    // MARK: - Conflicts

    private func conflictsSection(_ conflicts: [Conflict]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Conflicts (\(conflicts.count))")
                    .font(.headline)
                Spacer()
                Button("Reset Session") {
                    showResetConfirmation = true
                }
                .controlSize(.small)
            }

            resolutionGuidance

            ForEach(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
                ConflictCard(
                    conflict: conflict,
                    session: session,
                    store: store
                )
            }
        }
        .padding()
        .background(.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resolutionGuidance: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                guidanceRow(
                    icon: "arrow.counterclockwise",
                    title: "Reset Session",
                    body: "Re-scans both endpoints and treats the current state as the new baseline. Conflicts are cleared."
                )
                guidanceRow(
                    icon: "pencil",
                    title: "Manually Resolve",
                    body: "Edit or delete the conflicting files on one endpoint, then flush to sync the resolution."
                )
                guidanceRow(
                    icon: "arrow.right",
                    title: "Switch to Two-Way Resolved",
                    body: "Recreate the session with two-way-resolved mode so alpha always wins conflicts automatically."
                )
            }
            .padding(.top, 4)
        } label: {
            Label("How to resolve conflicts", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func guidanceRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(body).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        DisclosureGroup("Danger Zone") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Terminate Session")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Permanently remove this session. This cannot be undone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Terminate", role: .destructive) {
                    showTerminateConfirmation = true
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .foregroundStyle(.red)
    }
}

// MARK: - Endpoint Card

private struct EndpointCard: View {
    let label: String
    let endpoint: Endpoint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(endpoint.connected == true ? .green : .red)
                    .frame(width: 6, height: 6)
            }

            LabeledContent("Protocol", value: endpoint.protocol_)
            if let user = endpoint.user {
                LabeledContent("User", value: user)
            }
            if let host = endpoint.host {
                LabeledContent("Host", value: host)
            }
            if let path = endpoint.path {
                LabeledContent("Path") {
                    Text(path)
                        .monospaced()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider()

            if let dirs = endpoint.directories, let files = endpoint.files, let size = endpoint.totalFileSize {
                HStack(spacing: 8) {
                    Text("\(dirs) dirs")
                    Text("\(files) files")
                    Text(formatBytes(size))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Conflict Card

private struct ConflictCard: View {
    let conflict: Conflict
    let session: SyncSession
    let store: SessionStore
    @State private var isResolving = false
    @State private var alphaInfo: FileInfo?
    @State private var betaInfo: FileInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .top, spacing: 8) {
                conflictPane(
                    label: "Alpha (\(session.alpha.shortLabel))",
                    color: .blue,
                    changes: conflict.alphaChanges,
                    info: alphaInfo,
                    winner: .alpha
                )
                conflictPane(
                    label: "Beta (\(session.beta.shortLabel))",
                    color: .purple,
                    changes: conflict.betaChanges,
                    info: betaInfo,
                    winner: .beta
                )
            }

            if isResolving {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Resolving...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(8)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task { await loadFileInfo() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(conflict.root)
                .font(.caption)
                .monospaced()
                .fontWeight(.semibold)
            Spacer()
            if session.alpha.protocol_ == "local", let base = session.alpha.path {
                Button {
                    let fullPath = (base as NSString).appendingPathComponent(conflict.root)
                    NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
            Text("\(conflict.alphaChanges.count + conflict.betaChanges.count) changes")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pane

    private func conflictPane(
        label: String,
        color: Color,
        changes: [Change],
        info: FileInfo?,
        winner: ConflictWinner
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                Spacer()
                if let info {
                    Text(formatBytes(info.size))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let info {
                Text(info.modifiedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if changes.isEmpty {
                Text("No changes")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    ChangeLabel(change: change)
                }
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    isResolving = true
                    await store.resolveConflict(session: session, conflict: conflict, winner: winner)
                    isResolving = false
                }
            } label: {
                Label("Keep This Side", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(color)
            .controlSize(.small)
            .disabled(isResolving)
        }
        .padding(8)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func loadFileInfo() async {
        let info = await store.conflictFileInfo(session: session, conflict: conflict)
        alphaInfo = info.alpha
        betaInfo = info.beta
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct ChangeLabel: View {
    let change: Change

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: changeIcon)
                .font(.caption2)
                .foregroundStyle(changeColor)
                .frame(width: 12)

            Text(change.path)
                .font(.caption2)
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(changeVerb)
                .font(.caption2)
                .foregroundStyle(changeColor)
        }
        .padding(.leading, 12)
    }

    private var changeIcon: String {
        if change.old != nil && change.new == nil { return "minus.circle.fill" }
        if change.old == nil && change.new != nil { return "plus.circle.fill" }
        return "arrow.triangle.2.circlepath.circle.fill"
    }

    private var changeColor: Color {
        if change.old != nil && change.new == nil { return .red }
        if change.old == nil && change.new != nil { return .green }
        return .orange
    }

    private var changeVerb: String {
        if let old = change.old, change.new == nil { return "deleted \(old.kind)" }
        if change.old == nil, let new = change.new { return "created \(new.kind)" }
        if let old = change.old, let new = change.new { return "\(old.kind) -> \(new.kind)" }
        return "modified"
    }
}
