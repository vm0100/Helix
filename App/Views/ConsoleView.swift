// ABOUTME: In-app console panel that displays log entries from ConsoleLog in real-time.
// ABOUTME: Auto-scrolls to bottom, color-codes by level, dark Tokyo Night-inspired theme.

import SwiftUI
import HelixKit

struct ConsoleView: View {
    private let console = ConsoleLog.shared

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Console")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x7aa2f7))
                Spacer()
                Button("Clear") {
                    console.clear()
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .foregroundStyle(Color(hex: 0x565f89))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: 0x24283b))

            ScrollViewReader { proxy in
                ScrollView {
                    consoleText
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear.frame(height: 0).id("bottom")
                }
                .onChange(of: console.entries.count) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(Color(hex: 0x1a1b26))
    }

    private var consoleText: Text {
        var result = Text("")
        for (index, entry) in console.entries.enumerated() {
            if index > 0 { result = result + Text("\n") }
            result = result
                + Text(Self.timestampFormatter.string(from: entry.timestamp))
                    .foregroundStyle(Color(hex: 0x565f89))
                + Text(" ")
                + Text(entry.message)
                    .foregroundStyle(color(for: entry.level))
        }
        return result
    }

    private func color(for level: ConsoleLevel) -> Color {
        switch level {
        case .info: Color(hex: 0xa9b1d6)
        case .command: Color(hex: 0x7aa2f7)
        case .error: Color(hex: 0xf7768e)
        }
    }
}

// MARK: - Hex Color

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
