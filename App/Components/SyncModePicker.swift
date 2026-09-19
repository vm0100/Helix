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
                title: "双向安全",
                description: "变更双向同步，冲突需要手动解决。",
                hint: "适合两端同时进行开发"
            )
            ModeOption(
                mode: "two-way-resolved",
                selected: $selectedMode,
                title: "双向已解决",
                description: "变更双向同步，冲突始终自动以甲端为准。",
                hint: "适合一端权威但两端都会变更的场景"
            )
            ModeOption(
                mode: "one-way-safe",
                selected: $selectedMode,
                title: "单向安全",
                description: "仅从甲端同步到乙端，并检测乙端的冲突变更。",
                hint: "适合从源端部署到目标端"
            )
            ModeOption(
                mode: "one-way-replica",
                selected: $selectedMode,
                title: "单向副本",
                description: "仅从甲端同步到乙端，乙端始终完全镜像甲端。",
                hint: "适合只读镜像和备份"
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
