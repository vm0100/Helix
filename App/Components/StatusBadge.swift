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
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
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
        if paused { return "Paused" }
        return status.capitalized
    }
}
