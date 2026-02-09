// ABOUTME: Menu bar icon that reflects overall system health via color-coded SF Symbols.
// ABOUTME: Green for healthy, blue for active, orange for warning, red for error.

import SwiftUI
import MutagenKit

struct MenuBarIcon: View {
    let health: HealthStatus

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        switch health {
        case .healthy: "arrow.triangle.2.circlepath"
        case .active: "arrow.triangle.2.circlepath"
        case .warning: "exclamationmark.arrow.triangle.2.circlepath"
        case .error: "xmark.circle"
        case .idle: "arrow.triangle.2.circlepath"
        }
    }

    private var iconColor: Color {
        switch health {
        case .healthy: .green
        case .active: .blue
        case .warning: .orange
        case .error: .red
        case .idle: .secondary
        }
    }
}
