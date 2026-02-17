// ABOUTME: Color-coded status indicator dot for session health display.
// ABOUTME: Maps mutagen status strings to semantic colors.

import SwiftUI

struct StatusBadge: View {
    let status: String
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    init(status: String, paused: Bool = false) {
        self.status = status
        self.paused = paused
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(breathing ? 0.5 : 1.0)
            .animation(pulseAnimation, value: breathing)
            .onChange(of: status) { breathing = false }
            .onAppear { breathing = isActive }
            .accessibilityLabel(label)
    }

    private var isActive: Bool {
        !paused && !reduceMotion && (status == "watching" || status == "scanning"
            || status == "staging" || status == "transitioning" || status == "saving")
    }

    private var pulseAnimation: Animation? {
        guard isActive else { return nil }
        let duration: Double = status == "watching" ? 3.0 : 1.2
        return .easeInOut(duration: duration).repeatForever(autoreverses: true)
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
