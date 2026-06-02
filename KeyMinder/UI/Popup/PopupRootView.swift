import SwiftUI

/// Holds the live filter state for one presentation of the shortcuts popup.
/// Owned by `PopupController` so the controller can read/clear the query (for
/// Esc handling) while the SwiftUI view observes it for live updates.
///
/// Column distribution is computed once and fixed for the lifetime of the popup.
/// Filtering hides non-matching rows and collapses empty sections/groups in place,
/// so the horizontal layout never changes.
@MainActor
@Observable
final class PopupFilterModel {
    /// The full, unfiltered set of shortcuts.
    let app: AppShortcuts
    /// Fixed column distribution — never recomputed while the popup is open.
    let columns: [[MenuSection]]

    var query: String = "" {
        didSet {
            guard oldValue != query else { return }
            selectedIndex = nil
            updateVisibleShortcuts()
        }
    }

    var modifierFilter: Set<Character> = [] {
        didSet {
            guard oldValue != modifierFilter else { return }
            selectedIndex = nil
            updateVisibleShortcuts()
        }
    }

    var selectedIndex: Int? = nil

    /// Cached flat list of visible shortcuts in column-layout order (left to right,
    /// top to bottom within each column). Defines the Tab navigation sequence.
    /// Recomputed once per query change; callers may read it multiple times for free.
    private(set) var visibleShortcuts: [Shortcut] = []

    var selectedShortcut: Shortcut? {
        guard let idx = selectedIndex else { return nil }
        return idx < visibleShortcuts.count ? visibleShortcuts[idx] : nil
    }

    func selectNext() {
        let count = visibleShortcuts.count
        guard count > 0 else { return }
        selectedIndex = ((selectedIndex ?? -1) + 1) % count
    }

    func selectPrevious() {
        let count = visibleShortcuts.count
        guard count > 0 else { return }
        selectedIndex = ((selectedIndex ?? count) - 1 + count) % count
    }

    init(app: AppShortcuts, columns: [[MenuSection]]) {
        self.app = app
        self.columns = columns
        updateVisibleShortcuts()
    }

    private func updateVisibleShortcuts() {
        var result: [Shortcut] = []
        for column in columns {
            for section in column {
                for group in section.groups {
                    for shortcut in group.shortcuts
                        where (!shortcut.keys.isEmpty || showsAllItems)
                            && shortcut.matches(activeQuery)
                            && shortcut.matchesModifierFilter(modifierFilter) {
                        result.append(shortcut)
                    }
                }
            }
        }
        visibleShortcuts = result
    }

    func toggleModifier(_ mod: Character) {
        if modifierFilter.contains(mod) {
            modifierFilter.remove(mod)
        } else {
            modifierFilter.insert(mod)
        }
    }

    /// The trimmed query, or empty when no filter is active.
    var activeQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Whether a non-empty text filter is active.
    var hasQuery: Bool { !activeQuery.isEmpty }

    /// Whether a modifier filter is active.
    var hasModifierFilter: Bool { !modifierFilter.isEmpty }

    /// True when non-shortcut items should be visible: all-entries mode is on
    /// and the user has typed at least two characters in the filter.
    var showsAllItems: Bool {
        app.includesItemsWithoutShortcuts && activeQuery.count >= 2
    }

    /// Count of items currently displayable (passing the keys/showsAllItems gate).
    /// Used as both the no-query header count and the "of N" filter denominator,
    /// so the number always reflects what the user can actually see.
    var displayableCount: Int {
        app.sections.reduce(0) { $0 + $1.shortcuts.filter { !$0.keys.isEmpty || showsAllItems }.count }
    }

    /// Count of displayable items matching all active filters (text query + modifier filter).
    var matchCount: Int {
        app.sections.reduce(0) { total, section in
            total + section.shortcuts.filter {
                (!$0.keys.isEmpty || showsAllItems)
                    && $0.matches(activeQuery)
                    && $0.matchesModifierFilter(modifierFilter)
            }.count
        }
    }
}

/// Root SwiftUI view hosted inside the floating panel. Renders the scraped
/// shortcuts as a multi-column, menu-grouped grid, or an onboarding/empty state.
struct PopupRootView: View {
    let content: PopupContent
    /// Filter/layout model — present only for the non-empty `.shortcuts` state.
    var model: PopupFilterModel? = nil
    /// Fixed panel width (content columns + horizontal padding).
    let width: CGFloat
    /// Fixed panel height. `nil` lets the content size itself — used when the
    /// controller measures the natural height before presenting.
    var height: CGFloat? = nil
    /// Whether to wrap the shortcut grid in a `ScrollView`. Disabled during
    /// measurement so the grid reports its true intrinsic height (a ScrollView
    /// has none, so it would collapse).
    var scrolls: Bool = true
    var onGrant: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onActivate: (Shortcut) -> Void = { _ in }

    var body: some View {
        Group {
            switch content {
            case .shortcuts(let app):
                shortcutsView(app)
            case .needsPermission:
                PopupOnboardingView(onGrant: onGrant, onOpenSettings: onOpenSettings)
            case .noApp:
                PopupMessageView(text: "No active application", systemImage: "app.dashed")
            }
        }
        .padding(Theme.contentPadding)
        .frame(width: width, height: height, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Shortcuts

    @ViewBuilder
    private func shortcutsView(_ app: AppShortcuts) -> some View {
        if let model, !app.isEmpty {
            FilterableShortcutsView(model: model, scrolls: scrolls, onActivate: onActivate)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    }
                    Text(app.appName).font(.headline)
                    Spacer()
                }
                PopupMessageView(text: "No keyboard shortcuts found for \(app.appName)",
                                 systemImage: "keyboard")
            }
        }
    }
}

/// The shortcuts grid with a live, auto-focused type-to-filter field in its
/// header. Columns are fixed for the lifetime of the popup; filtering hides
/// non-matching rows and collapses empty sections so only relevant content
/// remains visible.
private struct FilterableShortcutsView: View {
    // @Bindable lets us write $model.query (Binding<String>) while also
    // participating in @Observable's fine-grained dependency tracking.
    @Bindable var model: PopupFilterModel
    let scrolls: Bool
    let onActivate: (Shortcut) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            contentView
        }
        // Auto-focus the field so the user can type immediately. Deferred to the
        // next runloop iteration so the panel is key before focus is requested.
        // Task inherits @MainActor from the .onAppear closure, giving identical
        // deferral semantics to DispatchQueue.main.async without Dispatch.
        .onAppear { Task { searchFocused = true } }
    }

    @ViewBuilder
    private var contentView: some View {
        if scrolls {
            ScrollViewReader { proxy in
                ScrollView(.vertical) { grid }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: model.selectedIndex) { _, _ in
                        if let shortcut = model.selectedShortcut {
                            withAnimation(.linear(duration: 0.1)) {
                                proxy.scrollTo(shortcut.id, anchor: .center)
                            }
                        }
                    }
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: MenuLayout.columnSpacing) {
            ForEach(Array(model.columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: MenuLayout.sectionSpacing) {
                    ForEach(column) { section in
                        MenuSectionView(section: section, query: model.activeQuery,
                                        showsAllItems: model.showsAllItems,
                                        modifierFilter: model.modifierFilter,
                                        selectedShortcutID: model.selectedShortcut?.id,
                                        onActivate: onActivate)
                    }
                }
                .frame(width: MenuLayout.columnWidth, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = model.app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(model.app.appName)
                .font(.headline)
            countText
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            modifierButtons
            searchField
        }
    }

    private var modifierButtons: some View {
        let mods: [(glyph: String, label: String)] = [
            ("⌃", "Control"), ("⌥", "Option"), ("⇧", "Shift"), ("⌘", "Command"),
        ]
        return HStack(spacing: 3) {
            ForEach(mods, id: \.glyph) { item in
                let ch = item.glyph.first!
                ModifierToggle(glyph: ch, isActive: model.modifierFilter.contains(ch)) {
                    model.toggleModifier(ch)
                }
                .accessibilityLabel(item.label)
            }
        }
    }

    private var countText: Text {
        let n = model.displayableCount
        if model.hasQuery || model.hasModifierFilter { return Text("\(model.matchCount) of \(n)") }
        let label = model.showsAllItems ? "menu items" : "shortcuts"
        return Text("\(n) \(label)")
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Filter", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .frame(width: 150)
            if model.hasQuery {
                Button {
                    model.query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.sectionHeaderFill, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Centered icon-over-text placeholder used for empty / no-match / no-app states.
struct PopupMessageView: View {
    let text: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One menu's section card: a header bar, then shortcut rows optionally broken
/// up by sub-group labels for items that came from a submenu.
/// The entire card is absent from the layout when no rows pass `isVisible`.
struct MenuSectionView: View {
    let section: MenuSection
    /// Active filter query; empty means no filter (all rows visible).
    var query: String = ""
    /// When true, items without keyboard shortcuts are rendered; when false
    /// they are omitted from the layout entirely.
    var showsAllItems: Bool = false
    /// Exact modifier set to match; empty means no modifier filter.
    var modifierFilter: Set<Character> = []
    var selectedShortcutID: UUID? = nil
    var onActivate: (Shortcut) -> Void = { _ in }

    /// A shortcut is visible when it passes the keys gate, matches the text query,
    /// and its modifier set exactly equals the active modifier filter (if any).
    private func isVisible(_ shortcut: Shortcut) -> Bool {
        (!shortcut.keys.isEmpty || showsAllItems)
            && shortcut.matches(query)
            && shortcut.matchesModifierFilter(modifierFilter)
    }

    private var hasVisibleContent: Bool {
        section.groups.contains { group in group.shortcuts.contains { isVisible($0) } }
    }

    var body: some View {
        if hasVisibleContent {
            VStack(alignment: .leading, spacing: MenuLayout.rowSpacing) {
                Text(section.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.sectionHeaderFill, in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)

                ForEach(section.groups) { group in
                    if group.shortcuts.contains(where: { isVisible($0) }) {
                        if let groupTitle = group.title {
                            SubGroupHeader(title: groupTitle)
                        }
                        ForEach(group.shortcuts) { shortcut in
                            if isVisible(shortcut) {
                                ShortcutRow(shortcut: shortcut,
                                            selected: selectedShortcutID == shortcut.id,
                                            onActivate: onActivate)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A compact label shown above a submenu's shortcuts inside a section card.
/// Visually subordinate to the section header: smaller, tertiary colour, no fill.
private struct SubGroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .padding(.top, 6)
            .padding(.bottom, 1)
    }
}

/// A single row: right-aligned key glyphs followed by the command name.
/// Only rendered for items that pass the visibility gate in `MenuSectionView`,
/// so every visible row is already a match — no dimming needed.
///
/// Rows with an AX element are clickable: tapping them fires `onActivate` so
/// `PopupController` can dismiss the popup and execute the shortcut.
struct ShortcutRow: View {
    let shortcut: Shortcut
    var selected: Bool = false
    var onActivate: (Shortcut) -> Void = { _ in }

    @State private var hovered = false

    private var clickable: Bool { shortcut.axElement != nil }

    var body: some View {
        HStack(spacing: 8) {
            Text(shortcut.keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.keyAccent)
                .frame(width: Theme.keyColumnWidth, alignment: .trailing)
            Text(shortcut.title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(shortcut.title)
            Spacer(minLength: 0)
        }
        .frame(height: MenuLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    selected ? Color.accentColor.opacity(0.2) :
                    Color.primary.opacity(clickable && hovered ? 0.07 : 0)
                )
        )
        .onHover { if clickable { hovered = $0 } }
        .onTapGesture { if clickable { onActivate(shortcut) } }
        // Collapse the two Text children into one VoiceOver element so the
        // screen reader speaks "New Conversation, Shift Command N" rather than
        // announcing the raw glyph string "⇧⌘N" and the title separately.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shortcut.title), \(spokenKeys(shortcut.keys))")
        .accessibilityAddTraits(clickable ? .isButton : [])
    }
}

// MARK: - Modifier filter toggle

private struct ModifierToggle: View {
    let glyph: Character
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(glyph))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isActive ? Color.white : Theme.keyAccent)
                .frame(width: 22, height: 22)
                .background(isActive ? Theme.keyAccent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.keyAccent.opacity(isActive ? 1.0 : 0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - VoiceOver key-string helper

/// Converts a visual shortcut key string (e.g. "⇧⌘N") into a naturally spoken
/// phrase (e.g. "Shift Command N") for use in VoiceOver accessibility labels.
///
/// Mapping rules:
/// - Modifier glyphs: ⌘→Command  ⇧→Shift  ⌥→Option  ⌃→Control
/// - Special keys:    ↩→Return   ⎋→Escape  ⌫→Delete  ⇥→Tab
///                    ↑→Up Arrow ↓→Down Arrow ←→Left Arrow →→Right Arrow
///                    (space)→Space
/// - Fn keys (F followed by digits) are kept intact: "F5", "F12", etc.
/// - All other characters (letters, digits) are passed through uppercased.
private func spokenKeys(_ keys: String) -> String {
    let map: [Character: String] = [
        // Modifiers
        "⌘": "Command", "⇧": "Shift", "⌥": "Option", "⌃": "Control",
        // Special keys
        "↩": "Return",    "⎋": "Escape", "⌫": "Delete",     "⇥": "Tab",
        " ": "Space",
        "↑": "Up Arrow",  "↓": "Down Arrow",
        "←": "Left Arrow", "→": "Right Arrow",
    ]

    var tokens: [String] = []
    var remaining = keys[...]

    while let ch = remaining.first {
        remaining = remaining.dropFirst()

        if let spoken = map[ch] {
            tokens.append(spoken)
        } else if ch == "F", remaining.first?.isNumber == true {
            // Fn key: "F" + one or two digit characters → keep as unit.
            var fn = String(ch)
            while let d = remaining.first, d.isNumber {
                fn.append(d)
                remaining = remaining.dropFirst()
            }
            tokens.append(fn)
        } else {
            tokens.append(String(ch).uppercased())
        }
    }

    return tokens.joined(separator: " ")
}
