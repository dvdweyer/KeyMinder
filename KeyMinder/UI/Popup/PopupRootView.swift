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

    var showOnlyFavourites: Bool = false {
        didSet {
            guard oldValue != showOnlyFavourites else { return }
            selectedIndex = nil
            updateVisibleShortcuts()
        }
    }

    /// Modifier glyphs toggled on via the UI buttons — persist until untoggled.
    private var toggledModifiers: Set<Character> = [] {
        didSet {
            guard oldValue != toggledModifiers else { return }
            selectedIndex = nil
            updateVisibleShortcuts()
        }
    }

    /// Modifier glyphs currently held as physical keys — set by `PopupController`
    /// from `flagsChanged` events and cleared when keys are released.
    var heldModifiers: Set<Character> = [] {
        didSet {
            guard oldValue != heldModifiers else { return }
            selectedIndex = nil
            updateVisibleShortcuts()
        }
    }

    /// Union of toggled and held modifiers — the effective filter applied to shortcuts.
    var modifierFilter: Set<Character> { toggledModifiers.union(heldModifiers) }

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

    /// When true the popup fits all shortcuts without scrolling, so filtering
    /// dims non-matching rows rather than hiding them (layout stays stable).
    let fitsWithoutScrolling: Bool

    init(app: AppShortcuts, columns: [[MenuSection]], fitsWithoutScrolling: Bool = false) {
        self.app = app
        self.columns = columns
        self.fitsWithoutScrolling = fitsWithoutScrolling
        updateVisibleShortcuts()
    }

    private func updateVisibleShortcuts() {
        let appID = app.bundleIdentifier ?? app.appName
        let ignoreStore = IgnoreListStore.shared
        // When showWhenFiltering is on the scraper returned all items; hide ignored ones
        // until the user types a query (then they're intentionally revealed).
        let hiddenTitles: Set<String> = (ignoreStore.isEnabled && ignoreStore.showWhenFiltering && activeQuery.isEmpty)
            ? ignoreStore.ignoredTitles(for: app.bundleIdentifier)
            : []
        var result: [Shortcut] = []
        for column in columns {
            for section in column {
                for group in section.groups {
                    for shortcut in group.shortcuts
                        where (!shortcut.keys.isEmpty || showsAllItems)
                            && shortcut.matches(activeQuery)
                            && shortcut.matchesModifierFilter(modifierFilter)
                            && (!showOnlyFavourites || FavouritesStore.shared.isFavourite(shortcut, appID: appID))
                            && (hiddenTitles.isEmpty || !hiddenTitles.contains(shortcut.title.localizedLowercase)) {
                        result.append(shortcut)
                    }
                }
            }
        }
        visibleShortcuts = result
    }

    func toggleFavourite(_ shortcut: Shortcut) {
        let appID = app.bundleIdentifier ?? app.appName
        FavouritesStore.shared.toggle(shortcut, appID: appID)
        if showOnlyFavourites { selectedIndex = nil }
        updateVisibleShortcuts()
    }

    func toggleModifier(_ mod: Character) {
        if toggledModifiers.contains(mod) {
            toggledModifiers.remove(mod)
        } else {
            toggledModifiers.insert(mod)
        }
    }

    /// Clears only the toggled (persistent) modifier filter. Used by Esc so that
    /// physically-held keys remain active until the user releases them.
    func clearToggledModifiers() { toggledModifiers = [] }

    /// The trimmed query, or empty when no filter is active.
    var activeQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Whether a non-empty text filter is active.
    var hasQuery: Bool { !activeQuery.isEmpty }

    /// Whether any modifier filter is active (toggled or held).
    var hasModifierFilter: Bool { !modifierFilter.isEmpty }

    /// Whether the persistent (toggled) modifier filter is non-empty. Used by the
    /// Esc handler so that Esc clears toggled state rather than dismissing when
    /// only physical keys are held (those clear themselves on release).
    var hasToggledModifiers: Bool { !toggledModifiers.isEmpty }

    /// True when non-shortcut items should be visible: all-entries mode is on
    /// and the user has typed at least two characters in the filter.
    var showsAllItems: Bool {
        app.includesItemsWithoutShortcuts && activeQuery.count >= 2
    }

    /// Count of items currently displayable (passing the keys/showsAllItems gate and
    /// the favourites filter when active).
    var displayableCount: Int {
        let appID = app.bundleIdentifier ?? app.appName
        let ignoreStore = IgnoreListStore.shared
        let hiddenTitles: Set<String> = (ignoreStore.isEnabled && ignoreStore.showWhenFiltering)
            ? ignoreStore.ignoredTitles(for: app.bundleIdentifier)
            : []
        return app.sections.reduce(0) { total, section in
            total + section.shortcuts.filter {
                (!$0.keys.isEmpty || showsAllItems) &&
                (!showOnlyFavourites || FavouritesStore.shared.isFavourite($0, appID: appID)) &&
                (hiddenTitles.isEmpty || !hiddenTitles.contains($0.title.localizedLowercase))
            }.count
        }
    }

    /// Count of displayable items matching all active filters (text query + modifier filter
    /// + favourites filter when active).
    var matchCount: Int {
        let appID = app.bundleIdentifier ?? app.appName
        return app.sections.reduce(0) { total, section in
            total + section.shortcuts.filter {
                (!$0.keys.isEmpty || showsAllItems)
                    && $0.matches(activeQuery)
                    && $0.matchesModifierFilter(modifierFilter)
                    && (!showOnlyFavourites || FavouritesStore.shared.isFavourite($0, appID: appID))
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
                                        showOnlyFavourites: model.showOnlyFavourites,
                                        appID: model.app.bundleIdentifier ?? model.app.appName,
                                        dimMode: model.fitsWithoutScrolling,
                                        selectedShortcutID: model.selectedShortcut?.id,
                                        onActivate: onActivate,
                                        onToggleFavourite: { model.toggleFavourite($0) })
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
        let appID = model.app.bundleIdentifier ?? model.app.appName
        return HStack(spacing: 3) {
            ForEach(mods, id: \.glyph) { item in
                let ch = item.glyph.first!
                ModifierToggle(glyph: ch, isActive: model.modifierFilter.contains(ch)) {
                    model.toggleModifier(ch)
                }
                .accessibilityLabel(item.label)
            }
            if FavouritesStore.shared.hasFavourites(for: appID) {
                FavouritesToggle(isActive: model.showOnlyFavourites) {
                    model.showOnlyFavourites.toggle()
                }
            }
        }
    }

    private var countText: Text {
        let n = model.displayableCount
        if model.hasQuery || model.hasModifierFilter { return Text("\(model.matchCount) of \(n)") }
        if model.showsAllItems { return Text("\(n) menu items") }
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
    let text: LocalizedStringKey
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
/// In normal mode the card is absent when no rows match. In dim mode every keyed
/// row is always rendered; non-matching rows are dimmed and non-interactive.
struct MenuSectionView: View {
    let section: MenuSection
    /// Active filter query; empty means no filter (all rows visible).
    var query: String = ""
    /// When true, items without keyboard shortcuts are rendered; when false
    /// they are omitted from the layout entirely.
    var showsAllItems: Bool = false
    /// Exact modifier set to match; empty means no modifier filter.
    var modifierFilter: Set<Character> = []
    /// When true, only pinned shortcuts are shown.
    var showOnlyFavourites: Bool = false
    /// App identifier for favourites lookup. Empty string disables star buttons.
    var appID: String = ""
    /// When true, non-matching rows are dimmed instead of hidden (stable layout).
    var dimMode: Bool = false
    var selectedShortcutID: UUID? = nil
    var onActivate: (Shortcut) -> Void = { _ in }
    var onToggleFavourite: (Shortcut) -> Void = { _ in }

    private func passesGate(_ shortcut: Shortcut) -> Bool {
        !shortcut.keys.isEmpty || showsAllItems
    }

    private func matchesFilter(_ shortcut: Shortcut) -> Bool {
        shortcut.matches(query) && shortcut.matchesModifierFilter(modifierFilter)
    }

    /// Whether a row should be rendered at all.
    private func isShown(_ shortcut: Shortcut) -> Bool {
        guard passesGate(shortcut) else { return false }
        if showOnlyFavourites && !FavouritesStore.shared.isFavourite(shortcut, appID: appID) { return false }
        return dimMode ? true : matchesFilter(shortcut)
    }

    /// Whether a row should be dimmed (dim mode only; always false in normal mode).
    private func isDimmed(_ shortcut: Shortcut) -> Bool {
        dimMode && !matchesFilter(shortcut)
    }

    private func groupHasContent(_ group: ShortcutGroup) -> Bool {
        group.shortcuts.contains { isShown($0) }
    }

    private var hasVisibleContent: Bool {
        section.groups.contains { groupHasContent($0) }
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
                    if groupHasContent(group) {
                        if let groupTitle = group.title {
                            SubGroupHeader(title: groupTitle)
                        }
                        ForEach(group.shortcuts) { shortcut in
                            if isShown(shortcut) {
                                ShortcutRow(shortcut: shortcut,
                                            appID: appID,
                                            selected: selectedShortcutID == shortcut.id,
                                            dimmed: isDimmed(shortcut),
                                            onActivate: onActivate,
                                            onToggleFavourite: { onToggleFavourite(shortcut) })
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
///
/// In normal mode every rendered row is a filter match, so it is always
/// interactive. In dim mode non-matching rows are rendered with `dimmed: true`,
/// which fades the text and disables hover, tap, and Tab selection.
///
/// Rows with an AX element are clickable: tapping them fires `onActivate` so
/// `PopupController` can dismiss the popup and execute the shortcut.
struct ShortcutRow: View {
    let shortcut: Shortcut
    /// App identifier used to check and toggle favourite status.
    var appID: String = ""
    var selected: Bool = false
    /// True when the row is shown but does not match the active filter (dim mode).
    var dimmed: Bool = false
    var onActivate: (Shortcut) -> Void = { _ in }
    var onToggleFavourite: () -> Void = {}

    @State private var hovered = false

    private var clickable: Bool { shortcut.axElement != nil && !dimmed }
    private var isFavourite: Bool {
        !appID.isEmpty && FavouritesStore.shared.isFavourite(shortcut, appID: appID)
    }
    private var showStar: Bool { !dimmed && !appID.isEmpty && (hovered || isFavourite) }

    var body: some View {
        HStack(spacing: 8) {
            Text(shortcut.keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(dimmed ? Theme.fadedText : ThemeSettings.shared.keyAccent)
                .frame(width: Theme.keyColumnWidth, alignment: .trailing)
            Text(shortcut.title)
                .font(.system(size: 12))
                .foregroundStyle(dimmed ? Theme.fadedText : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(shortcut.title)
            Spacer(minLength: 0)
            Button(action: onToggleFavourite) {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(isFavourite ? ThemeSettings.shared.keyAccent : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .opacity(showStar ? 1 : 0)
            .allowsHitTesting(showStar)
            .accessibilityHidden(true)
        }
        .frame(height: MenuLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    selected ? Color.accentColor.opacity(0.2) :
                    Color.primary.opacity(clickable && hovered ? 0.07 : 0)
                )
        )
        .onHover { hovered = $0 }
        .onTapGesture { if clickable { onActivate(shortcut) } }
        // Collapse the two Text children into one VoiceOver element so the
        // screen reader speaks "New Conversation, Shift Command N" rather than
        // announcing the raw glyph string "⇧⌘N" and the title separately.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shortcut.title), \(spokenKeys(shortcut.keys))")
        .accessibilityAddTraits(clickable ? .isButton : [])
        .accessibilityAction(named: Text(isFavourite ? "Remove from favourites" : "Add to favourites")) {
            if !dimmed && !appID.isEmpty { onToggleFavourite() }
        }
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
                .foregroundStyle(isActive ? Color.white : ThemeSettings.shared.keyAccent)
                .frame(width: 22, height: 22)
                .background(isActive ? ThemeSettings.shared.keyAccent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(ThemeSettings.shared.keyAccent.opacity(isActive ? 1.0 : 0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityValue(isActive ? "on" : "off")
    }
}

// MARK: - Favourites filter toggle

private struct FavouritesToggle: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "star.fill" : "star")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? Color.white : ThemeSettings.shared.keyAccent)
                .frame(width: 22, height: 22)
                .background(isActive ? ThemeSettings.shared.keyAccent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(ThemeSettings.shared.keyAccent.opacity(isActive ? 1.0 : 0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Favourites")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityValue(isActive ? "on" : "off")
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
