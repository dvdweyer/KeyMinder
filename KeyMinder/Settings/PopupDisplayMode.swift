// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// MARK: - PopupDisplayMode

/// Which screen the popup appears on.
enum PopupDisplayMode: Int, CaseIterable {
    case activeAppWindow = 0
    case mouseCursor     = 1
    case mainDisplay     = 2

    var label: String {
        switch self {
        case .activeAppWindow: return "Active App's Screen"
        case .mouseCursor:     return "Screen with Mouse Cursor"
        case .mainDisplay:     return "Main Display"
        }
    }
}

// MARK: - UserDefaults

extension UserDefaults {
    private static let popupDisplayModeKey = "popupDisplayMode"

    var popupDisplayMode: PopupDisplayMode {
        get { PopupDisplayMode(rawValue: integer(forKey: Self.popupDisplayModeKey)) ?? .activeAppWindow }
        set { set(newValue.rawValue, forKey: Self.popupDisplayModeKey) }
    }
}
