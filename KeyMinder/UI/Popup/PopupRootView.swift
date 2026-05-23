import SwiftUI

/// Root SwiftUI view hosted inside the floating panel. Renders the scraped
/// shortcuts as a multi-column, menu-grouped grid, or an onboarding/empty state.
struct PopupRootView: View {
    let content: PopupContent
    /// Precomputed column distribution (only used for `.shortcuts`).
    let columns: [[MenuSection]]
    let size: CGSize
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
        .frame(width: size.width, height: size.height, alignment: .top)
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
            } else {
                ScrollView(.vertical) {
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
                .scrollBounceBehavior(.basedOnSize)
            }
        }
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

/// One menu's section card: a header bar plus its shortcut rows.
struct MenuSectionView: View {
    let section: MenuSection

    var body: some View {
        VStack(alignment: .leading, spacing: MenuLayout.rowSpacing) {
            Text(section.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.sectionHeaderFill, in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 2)

            ForEach(section.shortcuts) { shortcut in
                ShortcutRow(shortcut: shortcut)
            }
        }
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
