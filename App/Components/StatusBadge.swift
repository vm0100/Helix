// ABOUTME: Color-coded status indicator dot for session health display.
// ABOUTME: Maps mutagen status strings to semantic colors.

import SwiftUI

struct StatusBadge: View {
    let status: String
    let paused: Bool

    init(status: String, paused: Bool = false) {
        self.status = status
        self.paused = paused
    }

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 8))
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    var color: Color {
        if paused { return .secondary }

        switch status {
        case "watching":
            return .green
        case "scanning", "staging", "transitioning", "saving":
            return .blue
        case "halted":
            return .orange
        case "connecting":
            return .yellow
        case "disconnected":
            return .red
        default:
            return .secondary
        }
    }

    var label: String {
        if paused { return "已暂停" }
        switch status {
        case "watching": return "监视中"
        case "scanning": return "扫描中"
        case "staging": return "暂存中"
        case "transitioning": return "切换中"
        case "saving": return "保存中"
        case "halted": return "已停止"
        case "connecting": return "连接中"
        case "disconnected": return "未连接"
        default: return status
        }
    }
}
