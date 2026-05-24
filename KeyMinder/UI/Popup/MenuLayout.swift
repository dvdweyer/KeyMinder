import CoreGraphics

/// Lays out menu sections into columns, preserving their menu-bar order, and
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

    /// Partitions sections into `columns` contiguous slices, preserving the
    /// original (menu-bar) order. Sections spill into the next column once the
    /// running height exceeds an even share of the total; columns are never
    /// left empty (an oversized single section just fills its column).
    static func distribute(_ sections: [MenuSection], columns: Int) -> [[MenuSection]] {
        let count = max(1, columns)
        guard count > 1, !sections.isEmpty else { return sections.isEmpty ? [] : [sections] }

        let total  = sections.reduce(CGFloat(0)) { $0 + height(of: $1) + sectionSpacing }
        let target = total / CGFloat(count)   // aim for equal-height slices

        var result:        [[MenuSection]] = []
        var currentColumn: [MenuSection]   = []
        var currentHeight: CGFloat         = 0
        var columnsLeft = count

        for section in sections {
            let h = height(of: section) + sectionSpacing
            // Spill when we've hit the target AND a column slot remains AND
            // the current column already has at least one section (so we
            // never push an oversized section into a new, otherwise empty column).
            if currentHeight + h > target, columnsLeft > 1, !currentColumn.isEmpty {
                result.append(currentColumn)
                currentColumn = []
                currentHeight = 0
                columnsLeft  -= 1
            }
            currentColumn.append(section)
            currentHeight += h
        }
        if !currentColumn.isEmpty { result.append(currentColumn) }
        return result
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
