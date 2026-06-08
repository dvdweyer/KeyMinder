import Foundation

enum ShortcutExporter {
    /// Returns a Markdown-formatted cheat sheet for all keyed shortcuts in `app`.
    static func markdown(for app: AppShortcuts) -> String {
        var lines: [String] = ["# \(app.appName)", ""]
        for section in app.sections {
            let hasKeyed = section.groups.contains { $0.shortcuts.contains { !$0.keys.isEmpty } }
            guard hasKeyed else { continue }
            lines.append("## \(section.title)")
            for group in section.groups {
                let keyed = group.shortcuts.filter { !$0.keys.isEmpty }
                guard !keyed.isEmpty else { continue }
                if let title = group.title {
                    lines.append("### \(title)")
                }
                for shortcut in keyed {
                    lines.append("`\(shortcut.keys)` — \(shortcut.title)")
                }
            }
            lines.append("")
        }
        // Remove trailing blank line
        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
