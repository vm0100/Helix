// ABOUTME: Radio-button picker for mutagen sync modes (two-way-safe, two-way-resolved, etc.).
// ABOUTME: Extracted for reuse in both CreateSyncView and EditSyncConfigView.

import SwiftUI

struct SyncModePicker: View {
    @Binding var selectedMode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModeOption(
                mode: "two-way-safe",
                selected: $selectedMode,
                title: "Two-Way Safe",
                description: "Changes sync both directions. Conflicts require manual resolution.",
                hint: "Best for active development on both sides"
            )
            ModeOption(
                mode: "two-way-resolved",
                selected: $selectedMode,
                title: "Two-Way Resolved",
                description: "Changes sync both directions. Alpha wins all conflicts automatically.",
                hint: "Best when one side is authoritative but both change"
            )
            ModeOption(
                mode: "one-way-safe",
                selected: $selectedMode,
                title: "One-Way Safe",
                description: "Alpha to beta only. Detects conflicting changes on beta.",
                hint: "Best for deploying from source to target"
            )
            ModeOption(
                mode: "one-way-replica",
                selected: $selectedMode,
                title: "One-Way Replica",
                description: "Alpha to beta only. Beta always mirrors alpha exactly.",
                hint: "Best for read-only mirrors and backups"
            )
        }
    }
}

struct ModeOption: View {
    let mode: String
    @Binding var selected: String
    let title: String
    let description: String
    let hint: String

    var body: some View {
        Button {
            selected = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected == mode ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected == mode ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
