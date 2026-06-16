// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum ShortcutExporter {
    /// Returns a Markdown-formatted cheat sheet for all keyed shortcuts in `app`.
    static func markdown(for app: AppShortcuts) -> String {
        var lines: [String] = ["# \(md(app.appName))", ""]
        for section in app.sections {
            let hasKeyed = section.groups.contains { $0.shortcuts.contains { !$0.keys.isEmpty } }
            guard hasKeyed else { continue }
            lines.append("## \(md(section.title))")
            for group in section.groups {
                let keyed = group.shortcuts.filter { !$0.keys.isEmpty }
                guard !keyed.isEmpty else { continue }
                if let title = group.title {
                    lines.append("### \(md(title))")
                }
                for shortcut in keyed {
                    lines.append("\(codeSpan(shortcut.keys)) — \(md(shortcut.title))")
                }
            }
            lines.append("")
        }
        // Remove trailing blank line
        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Escapes Markdown special characters in inline text (headers, plain text spans).
    private static func md(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\\", "`", "*", "_", "[", "]", "<", ">", "!", "#", "|":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }

    /// Wraps `keys` in a Markdown code span, using double-backtick delimiters when
    /// the keys string itself contains a backtick (CommonMark §6.1 fenced code spans).
    private static func codeSpan(_ keys: String) -> String {
        keys.contains("`") ? "`` \(keys) ``" : "`\(keys)`"
    }
}
