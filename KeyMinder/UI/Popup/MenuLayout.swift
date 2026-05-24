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

    /// Partitions sections into at most `columns` contiguous slices (preserving
    /// menu-bar order) so the tallest column is as short as possible — the
    /// classic "split an ordered array into k parts minimising the largest part
    /// sum", solved by binary-searching the per-column capacity.
    ///
    /// May return *fewer* than `columns` slices when that already minimises the
    /// max (e.g. an oversized section that can't usefully share a column); never
    /// returns empty slices.
    static func distribute(_ sections: [MenuSection], columns: Int) -> [[MenuSection]] {
        let k = max(1, columns)
        guard !sections.isEmpty else { return [] }
        guard k > 1 else { return [sections] }

        let weights = sections.map { height(of: $0) + sectionSpacing }
        let capacity = minimalCapacity(weights, maxColumns: k)
        return pack(sections, weights: weights, capacity: capacity)
    }

    /// Chooses the fewest columns in `1...maxColumns` whose optimal partition
    /// keeps every column within `maxColumnHeight`. Falls back to `maxColumns`
    /// when no count fits — e.g. a single section taller than the screen, which
    /// must scroll regardless of how many columns are used.
    static func columnCount(for sections: [MenuSection],
                            maxColumns: Int,
                            maxColumnHeight: CGFloat) -> Int {
        guard !sections.isEmpty else { return 1 }
        let cap = max(1, maxColumns)
        for k in 1...cap where tallestColumnHeight(distribute(sections, columns: k)) <= maxColumnHeight {
            return k
        }
        return cap
    }

    // MARK: - Contiguous partitioning

    /// Greedy left-to-right fill at a fixed `capacity`: starts a new column when
    /// adding the next section would exceed it, except a single section larger
    /// than `capacity` simply occupies its own column. Order preserved; no empty
    /// columns.
    private static func pack(_ sections: [MenuSection],
                             weights: [CGFloat],
                             capacity: CGFloat) -> [[MenuSection]] {
        var result:  [[MenuSection]] = []
        var current: [MenuSection]   = []
        var currentHeight: CGFloat   = 0
        for (i, section) in sections.enumerated() {
            let w = weights[i]
            if !current.isEmpty, currentHeight + w > capacity {
                result.append(current)
                current = []
                currentHeight = 0
            }
            current.append(section)
            currentHeight += w
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Number of columns the greedy packer needs at `capacity` (allocation-free,
    /// for use inside the binary search).
    private static func columnsNeeded(_ weights: [CGFloat], capacity: CGFloat) -> Int {
        var columns = 1
        var currentHeight: CGFloat = 0
        for w in weights {
            if currentHeight > 0, currentHeight + w > capacity {
                columns += 1
                currentHeight = w
            } else {
                currentHeight += w
            }
        }
        return columns
    }

    /// Smallest per-column capacity for which the greedy packer needs `≤ k`
    /// columns. Binary-searched in `[largest single weight, total weight]`;
    /// feasibility is monotonic in capacity, so this finds the optimal max.
    private static func minimalCapacity(_ weights: [CGFloat], maxColumns k: Int) -> CGFloat {
        var lo = weights.max() ?? 0
        var hi = max(lo, weights.reduce(0, +))
        while hi - lo > 0.5 {
            let mid = (lo + hi) / 2
            if columnsNeeded(weights, capacity: mid) <= k {
                hi = mid
            } else {
                lo = mid
            }
        }
        return hi
    }

    /// The tallest column's estimated height, used to size the panel.
    static func tallestColumnHeight(_ columns: [[MenuSection]]) -> CGFloat {
        columns.map { column in
            column.reduce(CGFloat(0)) { $0 + height(of: $1) + sectionSpacing }
        }.max() ?? 0
    }
}
