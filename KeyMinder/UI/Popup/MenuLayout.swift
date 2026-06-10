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
    ///
    /// `MenuSectionView` is a `VStack(spacing: rowSpacing)` whose children are:
    /// the section header, then for each group an optional sub-group header
    /// followed by one row per shortcut.  The VStack inserts `rowSpacing` between
    /// *every* adjacent pair, so the gap count is (total elements − 1), not
    /// (rows − 1) per group.
    static func height(of section: MenuSection) -> CGFloat {
        var namedGroupCount = 0
        var totalShortcuts  = 0
        for group in section.groups {
            if group.title != nil { namedGroupCount += 1 }
            totalShortcuts += group.shortcuts.count
        }
        // Elements inside the VStack:
        //   1 section header + namedGroupCount sub-headers + totalShortcuts rows
        let elementCount = 1 + namedGroupCount + totalShortcuts
        let gaps = max(0, elementCount - 1)

        return headerHeight
            + CGFloat(namedGroupCount) * subGroupHeaderHeight
            + CGFloat(totalShortcuts)  * rowHeight
            + CGFloat(gaps)            * rowSpacing
    }

    // MARK: - Section splitting

    /// Splits sections that exceed `maxHeight` into continuation pieces with the
    /// same title, so the section header is repeated when a long menu wraps into
    /// the next column. Sections at or below `maxHeight` are returned unchanged.
    static func split(_ sections: [MenuSection], maxHeight: CGFloat) -> [MenuSection] {
        guard maxHeight > headerHeight else { return sections }
        return sections.flatMap { section in
            height(of: section) <= maxHeight ? [section] : splitSection(section, maxHeight: maxHeight)
        }
    }

    /// Splits one oversized section into pieces, each ≤ `maxHeight`, by greedily
    /// packing whole groups. When a single group exceeds `maxHeight` its shortcuts
    /// are split further, repeating the group title on the continuation piece.
    private static func splitSection(_ section: MenuSection, maxHeight: CGFloat) -> [MenuSection] {
        var result: [MenuSection] = []
        var pieceGroups: [ShortcutGroup] = []

        for group in section.groups {
            let candidate = pieceGroups + [group]
            if height(of: MenuSection(title: section.title, groups: candidate)) <= maxHeight {
                pieceGroups = candidate
            } else if height(of: MenuSection(title: section.title, groups: [group])) > maxHeight {
                // Even alone this group exceeds maxHeight — flush current piece,
                // then split the group's shortcuts into sub-chunks.
                if !pieceGroups.isEmpty {
                    result.append(MenuSection(title: section.title, groups: pieceGroups))
                    pieceGroups = []
                }
                let chunks = splitGroup(group, sectionTitle: section.title, maxHeight: maxHeight)
                for chunk in chunks.dropLast() {
                    result.append(MenuSection(title: section.title, groups: [chunk]))
                }
                if let last = chunks.last { pieceGroups = [last] }
            } else {
                // Group fits alone but not with current piece — flush and start fresh.
                result.append(MenuSection(title: section.title, groups: pieceGroups))
                pieceGroups = [group]
            }
        }
        if !pieceGroups.isEmpty {
            result.append(MenuSection(title: section.title, groups: pieceGroups))
        }
        return result.isEmpty ? [section] : result
    }

    /// Splits a group's shortcuts into the largest sub-sequences that each fit
    /// within `maxHeight` when the group is the sole content of a section.
    private static func splitGroup(_ group: ShortcutGroup, sectionTitle: String,
                                   maxHeight: CGFloat) -> [ShortcutGroup] {
        var chunks: [ShortcutGroup] = []
        var current: [Shortcut] = []
        for shortcut in group.shortcuts {
            let test = current + [shortcut]
            let testH = height(of: MenuSection(title: sectionTitle,
                                               groups: [ShortcutGroup(title: group.title, shortcuts: test)]))
            if testH <= maxHeight {
                current = test
            } else {
                if !current.isEmpty { chunks.append(ShortcutGroup(title: group.title, shortcuts: current)) }
                current = [shortcut]
            }
        }
        if !current.isEmpty { chunks.append(ShortcutGroup(title: group.title, shortcuts: current)) }
        return chunks.isEmpty ? [group] : chunks
    }

    // MARK: - Column distribution

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
        // Enough columns for one menu each: spread them out (preserving menu-bar
        // order) instead of letting the balancer merge short menus together.
        if k >= sections.count { return sections.map { [$0] } }

        let weights = sections.map { height(of: $0) + sectionSpacing }
        let capacity = minimalCapacity(weights, maxColumns: k)
        return pack(sections, weights: weights, capacity: capacity)
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
}
