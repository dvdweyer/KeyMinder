import CoreGraphics

/// Distributes menu sections into balanced columns (a simple masonry layout) and
/// estimates sizes so the panel can be sized before SwiftUI lays anything out.
enum MenuLayout {
    static let columnWidth: CGFloat = 264
    static let columnSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let rowHeight: CGFloat = 21
    static let rowSpacing: CGFloat = 2
    static let headerHeight: CGFloat = 26
    /// Estimated height of a sub-group label (submenu title, smaller than the
    /// section header). Includes its built-in top padding (~6 pt) + text row.
    static let subGroupHeaderHeight: CGFloat = 22

    /// Estimated rendered height of one section card.
    static func height(of section: MenuSection) -> CGFloat {
        var h = headerHeight
        for group in section.groups {
            if group.title != nil { h += subGroupHeaderHeight }
            let rows = CGFloat(group.shortcuts.count)
            h += rows * rowHeight + max(0, rows - 1) * rowSpacing
        }
        return h
    }

    /// Greedy bin-packing: each section goes into the currently shortest column.
    static func distribute(_ sections: [MenuSection], columns: Int) -> [[MenuSection]] {
        let count = max(1, columns)
        var result = Array(repeating: [MenuSection](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)
        for section in sections {
            let target = heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0
            result[target].append(section)
            heights[target] += height(of: section) + sectionSpacing
        }
        return result.filter { !$0.isEmpty }
    }

    /// Chooses a column count that keeps each column under `maxColumnHeight`
    /// while never exceeding `maxColumns`.
    static func columnCount(for sections: [MenuSection],
                            maxColumns: Int,
                            maxColumnHeight: CGFloat) -> Int {
        let total = sections.reduce(CGFloat(0)) { $0 + height(of: $1) + sectionSpacing }
        let needed = Int((total / max(1, maxColumnHeight)).rounded(.up))
        return min(max(maxColumns, 1), max(1, needed))
    }

    /// The tallest column's estimated height, used to size the panel.
    static func tallestColumnHeight(_ columns: [[MenuSection]]) -> CGFloat {
        columns.map { column in
            column.reduce(CGFloat(0)) { $0 + height(of: $1) + sectionSpacing }
        }.max() ?? 0
    }
}
