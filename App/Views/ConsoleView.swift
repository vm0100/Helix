// ABOUTME: In-app console panel that displays log entries from ConsoleLog in real-time.
// ABOUTME: Auto-scrolls to bottom, color-codes by level, and provides a clear button.

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
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button("Clear") {
                    console.clear()
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(console.entries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(Self.timestampFormatter.string(from: entry.timestamp))
                                    .foregroundStyle(.tertiary)
                                Text(entry.message)
                                    .foregroundStyle(color(for: entry.level))
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: console.entries.count) {
                    if let last = console.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(.background)
    }

    private func color(for level: ConsoleLevel) -> Color {
        switch level {
        case .info: .secondary
        case .command: .blue
        case .error: .red
        }
    }
}
