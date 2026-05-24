import SwiftUI

/// Root SwiftUI view hosted inside the floating panel. Renders the scraped
/// shortcuts as a multi-column, menu-grouped grid, or an onboarding/empty state.
struct PopupRootView: View {
    let content: PopupContent
    /// Precomputed column distribution (only used for `.shortcuts`).
    let columns: [[MenuSection]]
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

    var body: some View {
        Group {
            switch content {
            case .shortcuts(let app):
                shortcutsView(app)
            case .needsPermission:
                PopupOnboardingView(onGrant: onGrant, onOpenSettings: onOpenSettings)
            case .noApp:
                messageView("No active application", systemImage: "app.dashed")
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

    private func shortcutsView(_ app: AppShortcuts) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(app)
            if app.isEmpty {
                messageView("No keyboard shortcuts found for \(app.appName)",
                            systemImage: "keyboard")
            } else if scrolls {
                ScrollView(.vertical) { grid }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                grid
            }
        }
    }

    /// The multi-column grid of section cards, without any scroll container.
    private var grid: some View {
        HStack(alignment: .top, spacing: MenuLayout.columnSpacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: MenuLayout.sectionSpacing) {
                    ForEach(column) { section in
                        MenuSectionView(section: section)
                    }
                }
                .frame(width: MenuLayout.columnWidth, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ app: AppShortcuts) -> some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(app.appName)
                .font(.headline)
            Text("\(app.totalCount) shortcuts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func messageView(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: MenuLayout.rowSpacing) {
            // Top-level section header (e.g. "Window")
            Text(section.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.sectionHeaderFill, in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 2)

            ForEach(section.groups) { group in
                // Named groups get a lightweight sub-header above their rows.
                if let groupTitle = group.title {
                    SubGroupHeader(title: groupTitle)
                }
                ForEach(group.shortcuts) { shortcut in
                    ShortcutRow(shortcut: shortcut)
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
struct ShortcutRow: View {
    let shortcut: Shortcut

    var body: some View {
        HStack(spacing: 8) {
            Text(shortcut.keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.keyAccent)
                .frame(width: Theme.keyColumnWidth, alignment: .trailing)
            Text(shortcut.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: MenuLayout.rowHeight)
    }
}
