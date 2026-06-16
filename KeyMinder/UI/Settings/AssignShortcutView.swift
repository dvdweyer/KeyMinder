// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit
import os

// MARK: - AssignShortcutController

/// Opens (or focuses) a single "assign shortcut" window for one menu command.
/// Released when the window closes, so a fresh one is built each time.
@MainActor
final class AssignShortcutController: NSWindowController, NSWindowDelegate {

    private static var instance: AssignShortcutController?

    /// Presents the assign window for `shortcut` in the context of `app`.
    static func show(shortcut: Shortcut, app: AppShortcuts) {
        instance?.close()   // replace any window left open for a different command

        // Build a lookup of every OTHER command's display keys → title so the
        // capture step can warn about conflicts within the same app.
        var existing: [String: String] = [:]
        for section in app.sections {
            for s in section.shortcuts where !s.isSeparator && !s.keys.isEmpty && s.id != shortcut.id {
                existing[s.keys] = s.title
            }
        }

        let model = AssignShortcutModel(
            shortcut: shortcut,
            appName: app.appName,
            appIcon: app.icon,
            bundleID: app.bundleIdentifier,
            existingKeys: existing
        )

        let controller = AssignShortcutController(model: model)
        instance = controller
        model.onClose = { [weak controller] in controller?.close() }

        NSApp.activate()
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
        DockIconManager.shared.windowOpened()
    }

    private let model: AssignShortcutModel

    private init(model: AssignShortcutModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        window.title = String(localized: "Assign Shortcut")
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: AssignShortcutView(model: model))
        model.startRecording()
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        model.stopRecording()
        Self.instance = nil
        DockIconManager.shared.windowClosed()
    }
}

// MARK: - AssignShortcutModel

@MainActor
@Observable
final class AssignShortcutModel {
    let shortcut: Shortcut
    let appName: String
    let appIcon: NSImage?
    let bundleID: String?

    /// Display keys → command title for every other command in the app.
    private let existingKeys: [String: String]

    /// The captured combination in display form (e.g. "⇧⌘N"), or `nil` before capture.
    var capturedDisplay: String?
    /// The captured combination encoded for `NSUserKeyEquivalents` (e.g. "@$n").
    var capturedValue: String?
    /// True while listening for a key press.
    var isRecording = false
    /// Title of another command that already uses the captured keys, if any.
    var conflictTitle: String?
    /// True once an assign/remove has been written — switches the UI to the relaunch hint.
    var applied = false
    /// Whether this command currently has a user-assigned equivalent (drives "Remove").
    var currentlyAssigned: Bool

    var onClose: () -> Void = {}

    private var monitor: Any?

    init(shortcut: Shortcut, appName: String, appIcon: NSImage?, bundleID: String?,
         existingKeys: [String: String]) {
        self.shortcut = shortcut
        self.appName = appName
        self.appIcon = appIcon
        self.bundleID = bundleID
        self.existingKeys = existingKeys
        self.currentlyAssigned = KeyEquivalentWriter.hasEntry(title: shortcut.writeKey, bundleID: bundleID)
    }

    /// The shortcut currently shown on the command, if any.
    var currentDisplay: String { shortcut.keys.isEmpty ? String(localized: "None") : shortcut.keys }

    var canAssign: Bool { capturedValue != nil }

    func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.handle(event) }
            return nil   // swallow while recording
        }
    }

    func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {   // Esc cancels capture, keeps any prior selection
            stopRecording()
            return
        }
        guard let value = KeyEquivalentWriter.value(for: event) else {
            return   // modifier-only or unencodable; keep waiting
        }
        // Display the decoded form so what the user sees matches exactly what gets
        // written (and how it will read back after the target app relaunches).
        let display = SystemShortcutsProvider.formatUserKeyEquivalent(value) ?? value
        capturedValue = value
        capturedDisplay = display
        conflictTitle = existingKeys[display]
        stopRecording()
    }

    func assign() {
        guard let value = capturedValue else { return }
        KeyEquivalentWriter.assign(title: shortcut.writeKey, value: value, bundleID: bundleID)
        currentlyAssigned = true
        applied = true
    }

    func remove() {
        KeyEquivalentWriter.remove(title: shortcut.writeKey, bundleID: bundleID)
        currentlyAssigned = false
        applied = true
    }

    /// Quits and relaunches the target app so the new equivalent takes effect.
    func relaunchApp() {
        defer { onClose() }
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        running.forEach { $0.terminate() }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }
}

// MARK: - AssignShortcutView

struct AssignShortcutView: View {
    @Bindable var model: AssignShortcutModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if model.applied {
                appliedBody
            } else {
                captureBody
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = model.appIcon {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.shortcut.title).font(.headline).lineLimit(1)
                Text(model.appName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    // MARK: Capture state

    private var captureBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current:").foregroundStyle(.secondary)
                Text(verbatim: model.currentDisplay)
                    .font(.system(.body, design: .rounded).weight(.medium))
            }
            .font(.callout)

            recorderBox

            if let conflict = model.conflictTitle {
                Label {
                    Text("Already used by \(conflict)")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(Theme.conflictAccent)
            }

            HStack {
                Button("Cancel") { model.onClose() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.currentlyAssigned {
                    Button("Remove Shortcut") { model.remove() }
                }
                Button("Assign") { model.assign() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAssign)
            }
        }
    }

    private var recorderBox: some View {
        Button {
            model.startRecording()
        } label: {
            HStack {
                Spacer()
                if model.isRecording {
                    Text("Type the new shortcut…").foregroundStyle(.secondary)
                } else if let display = model.capturedDisplay {
                    Text(verbatim: display)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                } else {
                    Text("Click to record").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(model.isRecording ? Color.accentColor : Color.secondary.opacity(0.3),
                                          lineWidth: model.isRecording ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Applied state (relaunch hint)

    private var appliedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Relaunch \(model.appName) for the change to take effect.")
            } icon: {
                Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.tint)
            }
            .font(.callout)

            Text("macOS applies app shortcuts when an app builds its menus, so the change appears after the next launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Done") { model.onClose() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Relaunch \(model.appName)") { model.relaunchApp() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
