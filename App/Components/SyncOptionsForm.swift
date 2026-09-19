// ABOUTME: Form for sync session options (ignore, symlink, compression, watch, staging).
// ABOUTME: Extracted for reuse in both CreateSyncView and EditSyncConfigView.

import SwiftUI

struct SyncOptionsForm: View {
    @Binding var ignoreInput: String
    @Binding var ignoreVCS: Bool
    @Binding var symlinkMode: String
    @Binding var compression: String
    @Binding var watchMode: String
    @Binding var stageMode: String

    @State private var showIgnore = false
    @State private var showSymlink = false
    @State private var showCompression = false
    @State private var showWatch = false
    @State private var showStaging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup(isExpanded: $showIgnore) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("每行一个模式，使用 gitignore 风格语法。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(Self.presets, id: \.self) { preset in
                            IgnorePresetChip(
                                pattern: preset,
                                isActive: ignorePatterns.contains(preset),
                                toggle: { togglePreset(preset) }
                            )
                        }
                    }

                    TextEditor(text: $ignoreInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
                    Toggle("将 .gitignore 规则作为同步忽略模式", isOn: $ignoreVCS)
                }
                .padding(.top, 4)
            } label: {
                tappableLabel("忽略规则") { showIgnore.toggle() }
            }

            DisclosureGroup(isExpanded: $showSymlink) {
                Picker("模式", selection: $symlinkMode) {
                    Text("可移植（安全的相对链接）").tag("portable")
                    Text("忽略（跳过所有符号链接）").tag("ignore")
                    Text("POSIX 原始（所有链接，仅限 POSIX）").tag("posix-raw")
                }
                .padding(.top, 4)
            } label: {
                tappableLabel("符号链接处理") { showSymlink.toggle() }
            }

            DisclosureGroup(isExpanded: $showCompression) {
                Picker("算法", selection: $compression) {
                    Text("无").tag("none")
                    Text("Deflate（zlib）").tag("deflate")
                    Text("Zstandard（更快）").tag("zstandard")
                }
                .padding(.top, 4)
            } label: {
                tappableLabel("压缩") { showCompression.toggle() }
            }

            DisclosureGroup(isExpanded: $showWatch) {
                Picker("模式", selection: $watchMode) {
                    Text("可移植（自动）").tag("portable")
                    Text("强制轮询（不可靠的文件系统）").tag("force-poll")
                    Text("不监视（仅手动刷新）").tag("no-watch")
                }
                .padding(.top, 4)
            } label: {
                tappableLabel("监视模式") { showWatch.toggle() }
            }

            DisclosureGroup(isExpanded: $showStaging) {
                Picker("模式", selection: $stageMode) {
                    Text("Mutagen（位于 ~/.mutagen）").tag("mutagen")
                    Text("邻近（同步根目录旁）").tag("neighboring")
                    Text("内部（同步根目录内）").tag("internal")
                }
                .padding(.top, 4)
            } label: {
                tappableLabel("暂存") { showStaging.toggle() }
            }
        }
    }

    static let presets = [
        "**/.git", "**/node_modules", "**/.venv", "**/__pycache__",
        ".DS_Store", "*.log",
        "**/.idea", "**/.vscode",
        "**/dist", "**/build", "**/target",
    ]

    private var ignorePatterns: Set<String> {
        Set(
            ignoreInput
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    private func togglePreset(_ pattern: String) {
        var patterns = ignoreInput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let index = patterns.firstIndex(of: pattern) {
            patterns.remove(at: index)
        } else {
            patterns.append(pattern)
        }
        ignoreInput = patterns.joined(separator: "\n")
    }

    private func tappableLabel(_ title: String, action: @escaping () -> Void) -> some View {
        Text(title)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

private struct IgnorePresetChip: View {
    let pattern: String
    let isActive: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Text(pattern)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
