import SwiftUI

/// Holds the live filter state for one presentation of the shortcuts popup.
/// Owned by `PopupController` so the controller can read/clear the query (for
/// Esc handling) while the SwiftUI view observes it for live updates.
///
/// Filtering never changes the layout: the column distribution is computed once
/// and fixed for the lifetime of the popup. Typing only dims the rows that don't
/// match, so every shortcut stays put in exactly the same place.
@MainActor
@Observable
final class PopupFilterModel {
    /// The full, unfiltered set of shortcuts.
    let app: AppShortcuts
    /// Fixed column distribution — never recomputed while the popup is open.
    let columns: [[MenuSection]]

    var query: String = ""

    init(app: AppShortcuts, columns: [[MenuSection]]) {
        self.app = app
        self.columns = columns
    }

    /// The trimmed query, or empty when no filter is active.
    var activeQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Whether a non-empty filter is active.
    var hasQuery: Bool { !activeQuery.isEmpty }

    /// True when non-shortcut items should be visible: all-entries mode is on
    /// and the user has typed at least two characters in the filter.
    var showsAllItems: Bool {
        app.includesItemsWithoutShortcuts && activeQuery.count >= 2
    }

    /// Number of items that have a key equivalent. Used for the header count
    /// when all-entries mode is active but the 2-character threshold hasn't
    /// been reached, so the displayed count matches what's actually visible.
    var shortcutOnlyCount: Int {
        app.sections.reduce(0) { $0 + $1.shortcuts.filter { !$0.keys.isEmpty }.count }
    }

    /// Number of shortcuts currently matching the filter.
    var matchCount: Int { app.matchCount(activeQuery) }
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
/// header. The layout is fixed: every shortcut stays on screen in the same spot
/// while typing, and rows that don't match the filter fade to a low-contrast
/// grey so the matching ones stand out.
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
            ScrollView(.vertical) { grid }
                .scrollBounceBehavior(.basedOnSize)
        } else {
            grid
        }
    }

    /// The full multi-column grid of section cards, dimming non-matching rows.
    private var grid: some View {
        HStack(alignment: .top, spacing: MenuLayout.columnSpacing) {
            ForEach(Array(model.columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: MenuLayout.sectionSpacing) {
                    ForEach(column) { section in
                        MenuSectionView(section: section, query: model.activeQuery,
                                        showsAllItems: model.showsAllItems,
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
            searchField
        }
    }

    private var countText: Text {
        if model.hasQuery { return Text("\(model.matchCount) of \(model.app.totalCount)") }
        if model.showsAllItems { return Text("\(model.app.totalCount) menu items") }
        let n = model.app.includesItemsWithoutShortcuts
            ? model.shortcutOnlyCount
            : model.app.totalCount
        return Text("\(n) shortcuts")
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
struct MenuSectionView: View {
    let section: MenuSection
    /// Active filter query; empty means no filter (nothing dims).
    var query: String = ""
    /// When true, items without keyboard shortcuts are rendered; when false
    /// they are omitted from the layout entirely.
    var showsAllItems: Bool = false
    var onActivate: (Shortcut) -> Void = { _ in }

    @State private var isExpanded = true

    /// Whether rows are actually visible: expanded by the user, or forced open
    /// because the active query matches something inside this section.
    private var effectivelyExpanded: Bool {
        isExpanded || (!query.isEmpty && section.hasMatch(query))
    }

    /// Whether the whole section is dimmed: a filter is active and nothing in it
    /// matches, so its headers recede along with its rows.
    private var sectionDimmed: Bool {
        !query.isEmpty && !section.hasMatch(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MenuLayout.rowSpacing) {
            // Section header — tappable when in all-entries mode to collapse/expand.
            Button {
                if showsAllItems {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(sectionDimmed ? AnyShapeStyle(Theme.fadedText) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsAllItems {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(sectionDimmed ? AnyShapeStyle(Theme.fadedText) : AnyShapeStyle(.secondary))
                            .rotationEffect(.degrees(effectivelyExpanded ? 0 : -90))
                            .animation(.easeInOut(duration: 0.15), value: effectivelyExpanded)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.sectionHeaderFill, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(showsAllItems ? (effectivelyExpanded ? "Collapse" : "Expand") : "")

            if effectivelyExpanded {
                ForEach(section.groups) { group in
                    // Named groups get a lightweight sub-header above their rows.
                    if let groupTitle = group.title {
                        SubGroupHeader(title: groupTitle,
                                       dimmed: !query.isEmpty && !group.hasMatch(query))
                    }
                    ForEach(group.shortcuts) { shortcut in
                        if !shortcut.keys.isEmpty || showsAllItems {
                            ShortcutRow(shortcut: shortcut, query: query, onActivate: onActivate)
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
    var dimmed: Bool = false

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(dimmed ? AnyShapeStyle(Theme.fadedText) : AnyShapeStyle(.tertiary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .padding(.top, 6)
            .padding(.bottom, 1)
    }
}

/// A single row: right-aligned key glyphs followed by the command name. When a
/// filter is active and this shortcut doesn't match, both the keys and title
/// fade to a low-contrast grey so matching rows stand out.
///
/// Rows with an AX element are clickable: tapping them fires `onActivate` so
/// `PopupController` can dismiss the popup and execute the shortcut.
struct ShortcutRow: View {
    let shortcut: Shortcut
    /// Active filter query; empty means no filter (nothing dims).
    var query: String = ""
    var onActivate: (Shortcut) -> Void = { _ in }

    @State private var hovered = false

    private var dimmed: Bool {
        !query.isEmpty && !shortcut.matches(query)
    }

    private var clickable: Bool { shortcut.axElement != nil }

    var body: some View {
        HStack(spacing: 8) {
            Text(shortcut.keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(dimmed ? Theme.fadedText : Theme.keyAccent)
                .frame(width: Theme.keyColumnWidth, alignment: .trailing)
            Text(shortcut.title)
                .font(.system(size: 12))
                .foregroundStyle(dimmed ? AnyShapeStyle(Theme.fadedText) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(shortcut.title)
            Spacer(minLength: 0)
        }
        .frame(height: MenuLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(clickable && hovered ? 0.07 : 0))
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
