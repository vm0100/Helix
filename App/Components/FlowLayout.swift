// ABOUTME: Wrapping horizontal layout that flows children into multiple rows.
// ABOUTME: Uses the Layout protocol for tag/chip-style content that adapts to container width.

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { total, row in
            total + row.height + (total > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        var subviewIndex = 0

        for row in rows {
            var x = bounds.minX
            for _ in 0..<row.count {
                let size = subviews[subviewIndex].sizeThatFits(.unspecified)
                subviews[subviewIndex].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
                subviewIndex += 1
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var count: Int
        var height: CGFloat
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var currentRowCount = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = currentRowCount > 0 ? size.width + spacing : size.width

            if currentRowWidth + needed > maxWidth && currentRowCount > 0 {
                rows.append(Row(count: currentRowCount, height: currentRowHeight))
                currentRowWidth = size.width
                currentRowHeight = size.height
                currentRowCount = 1
            } else {
                currentRowWidth += needed
                currentRowHeight = max(currentRowHeight, size.height)
                currentRowCount += 1
            }
        }

        if currentRowCount > 0 {
            rows.append(Row(count: currentRowCount, height: currentRowHeight))
        }

        return rows
    }
}
