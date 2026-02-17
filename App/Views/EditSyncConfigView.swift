// ABOUTME: Sheet for editing a sync session's configuration via terminate + recreate.
// ABOUTME: Pre-fills from the current session, shows warning about the destructive operation.

import SwiftUI
import HelixKit

struct EditSyncConfigView: View {
    let session: SyncSession
    let store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var labels: [String: String]
    @State private var syncMode: String
    @State private var ignoreInput: String
    @State private var ignoreVCS: Bool
    @State private var symlinkMode: String
    @State private var compression: String
    @State private var watchMode: String
    @State private var stageMode: String
    @State private var isApplying = false

    init(session: SyncSession, store: SessionStore) {
        self.session = session
        self.store = store
        _labels = State(initialValue: session.labels ?? [:])
        _syncMode = State(initialValue: session.mode ?? "two-way-safe")
        _ignoreInput = State(initialValue: (session.ignore.paths ?? []).joined(separator: "\n"))
        _ignoreVCS = State(initialValue: false)
        _symlinkMode = State(initialValue: session.symlink.mode ?? "portable")
        _compression = State(initialValue: session.compression.algorithm ?? "none")
        _watchMode = State(initialValue: session.watch.mode ?? "portable")
        _stageMode = State(initialValue: "mutagen")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    endpointSummary

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tag sessions for filtering and batch operations.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            LabelEditor(labels: $labels)
                        }
                        .padding(.top, 4)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Labels")
                            if !labels.isEmpty {
                                Text("\(labels.count)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    }

                    Text("Synchronization Mode")
                        .font(.headline)
                    SyncModePicker(selectedMode: $syncMode)
                    SyncOptionsForm(
                        ignoreInput: $ignoreInput,
                        ignoreVCS: $ignoreVCS,
                        symlinkMode: $symlinkMode,
                        compression: $compression,
                        watchMode: $watchMode,
                        stageMode: $stageMode
                    )
                    warningBanner
                }
                .padding()
            }

            Divider()
            actionButtons
        }
        .frame(width: 560, height: 560)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Edit Configuration")
                .font(.headline)
            Text(session.name ?? session.identifier)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: - Endpoints (read-only)

    private var endpointSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Endpoints")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                endpointLabel("Alpha", session.alpha.endpointURL.formatted)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                endpointLabel("Beta", session.beta.endpointURL.formatted)
            }
        }
    }

    private func endpointLabel(_ label: String, _ url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(url)
                .font(.caption)
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Warning

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Session will be recreated")
                    .fontWeight(.medium)
                Text("Mutagen does not support editing sessions in place. Applying changes will terminate the current session and create a new one. Sync history and cycle count will be reset.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(12)
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 300, alignment: .trailing)
            }

            Button("Apply Changes") {
                Task { await applyChanges() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isApplying || !hasChanges)
        }
        .padding()
    }

    // MARK: - Change Detection

    private var hasChanges: Bool {
        let currentLabels = session.labels ?? [:]
        let currentMode = session.mode ?? "two-way-safe"
        let currentIgnore = (session.ignore.paths ?? []).joined(separator: "\n")
        let currentSymlink = session.symlink.mode ?? "portable"
        let currentCompression = session.compression.algorithm ?? "none"
        let currentWatch = session.watch.mode ?? "portable"

        return labels != currentLabels
            || syncMode != currentMode
            || ignoreInput != currentIgnore
            || symlinkMode != currentSymlink
            || compression != currentCompression
            || watchMode != currentWatch
            || stageMode != "mutagen"
            || ignoreVCS
    }

    // MARK: - Apply

    private var options: SyncCreateOptions {
        var opts = SyncCreateOptions(from: session)
        opts.labels = labels
        opts.mode = syncMode
        opts.ignorePaths = ignorePaths
        opts.ignoreVCS = ignoreVCS
        if symlinkMode != "portable" { opts.symlinkMode = symlinkMode } else { opts.symlinkMode = nil }
        if compression != "none" { opts.compression = compression } else { opts.compression = nil }
        if watchMode != "portable" { opts.watchMode = watchMode } else { opts.watchMode = nil }
        if stageMode != "mutagen" { opts.stageMode = stageMode } else { opts.stageMode = nil }
        return opts
    }

    private var ignorePaths: [String] {
        ignoreInput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func applyChanges() async {
        isApplying = true
        await store.recreateSync(
            session,
            options: options,
            alpha: session.alpha.endpointURL.formatted,
            beta: session.beta.endpointURL.formatted
        )
        isApplying = false
        if store.lastError == nil {
            dismiss()
        }
    }
}
