// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import ApplicationServices
@testable import KeyMinder

final class CustomShortcutsBridgeTests: XCTestCase {

    func testRequestDataMatchesCustomShortcutsFormat() throws {
        let data = try CustomShortcutsBridge.requestData(
            appName: "TextEdit", bundleID: "com.apple.TextEdit",
            title: "Bigger", parents: ["Format", "Font"],
            date: Date(timeIntervalSince1970: 1_693_932_177.657),
            timeZone: TimeZone(secondsFromGMT: 7200)!,
            creator: "org.afaik.KeyMinder")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["kind"] as? String, "request")
        XCTAssertEqual(json["creator"] as? String, "org.afaik.KeyMinder")
        XCTAssertEqual(json["dateCreated"] as? String, "2023-09-05T18:42:57.657+0200")

        let apps = try XCTUnwrap(json["applications"] as? [[String: Any]])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0]["localizedName"] as? String, "TextEdit")
        XCTAssertEqual(apps[0]["bundleIdentifier"] as? String, "com.apple.TextEdit")
        let items = try XCTUnwrap(apps[0]["shortcuts"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["title"] as? String, "Bigger")
        XCTAssertEqual(items[0]["parents"] as? [String], ["Format", "Font"])
    }

    func testCanEditRequiresMenuItemWithPath() {
        let element = AXUIElementCreateApplication(getpid())
        let menuItem = Shortcut(title: "Bigger", keys: "⌘+", axElement: element,
                                isDisabled: false, parents: ["Format", "Font"])
        XCTAssertTrue(CustomShortcutsBridge.canEdit(menuItem))

        let noPath = Shortcut(title: "Bigger", keys: "⌘+", axElement: element, isDisabled: false)
        XCTAssertFalse(CustomShortcutsBridge.canEdit(noPath))

        // Synthetic shortcuts (system, registry, user key equivalents) have no AX element.
        XCTAssertFalse(CustomShortcutsBridge.canEdit(Shortcut(title: "Bigger", keys: "⌘+")))
        XCTAssertFalse(CustomShortcutsBridge.canEdit(.separator()))
    }

    func testRequestsDirectory() {
        XCTAssertTrue(CustomShortcutsBridge.requestsDirectory.path.hasSuffix(
            "Library/Application Support/com.houdah.CustomShortcuts/EditRequests"))
    }
}
