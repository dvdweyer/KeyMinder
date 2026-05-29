import os

extension Logger {
    static let scraper       = Logger(subsystem: "org.afaik.KeyMinder", category: "scraper")
    static let hotkey        = Logger(subsystem: "org.afaik.KeyMinder", category: "hotkey")
    static let settings      = Logger(subsystem: "org.afaik.KeyMinder", category: "settings")
    static let accessibility = Logger(subsystem: "org.afaik.KeyMinder", category: "accessibility")
}
