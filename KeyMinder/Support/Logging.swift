// SPDX-License-Identifier: GPL-3.0-or-later
import os
import Foundation

extension Logger {
    static let scraper       = Logger(subsystem: "org.afaik.KeyMinder", category: "scraper")
    static let hotkey        = Logger(subsystem: "org.afaik.KeyMinder", category: "hotkey")
    static let settings      = Logger(subsystem: "org.afaik.KeyMinder", category: "settings")
    static let accessibility = Logger(subsystem: "org.afaik.KeyMinder", category: "accessibility")
}

// MARK: - UserDefaults

extension UserDefaults {
    private static let debugLoggingKey = "debugLoggingEnabled"

    var debugLoggingEnabled: Bool {
        get { bool(forKey: Self.debugLoggingKey) }
        set { set(newValue, forKey: Self.debugLoggingKey) }
    }
}
