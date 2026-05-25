import SwiftUI
import AppKit
import os

// MARK: - SettingsWindowController

/// Opens (or focuses) a single settings window. The instance is released when
/// the window closes, so a fresh one is created the next time.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private static var instance: SettingsWindowController?

    static func show() {
        if instance == nil { instance = SettingsWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        instance?.window?.makeKeyAndOrderFront(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        window.title = "KeyMinder Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.setFrameAutosaveName("KeyMinder.Settings")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        Self.instance = nil
    }
}

// MARK: - SettingsModel

/// Observable model backing the settings UI. Manages hotkey recording state,
/// UserDefaults persistence, HotkeyManager registration, and the login-item toggle.
@MainActor
final class SettingsModel: ObservableObject {

    @Published private(set) var hotkey:      GlobalHotkey? = UserDefaults.standard.globalHotkey
    @Published private(set) var isRecording: Bool = false

    /// Whether KeyMinder is registered as a login item.
    @Published var launchAtLogin: Bool = LoginItemManager.shared.isEnabled {
        didSet {
            guard launchAtLogin != LoginItemManager.shared.isEnabled else { return }
            do {
                try LoginItemManager.shared.setEnabled(launchAtLogin)
            } catch {
                // Roll back the toggle if the system call fails.
                launchAtLogin = LoginItemManager.shared.isEnabled
                Logger.settings.error("Login item toggle failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Double-tap trigger

    @Published var doubleTapEnabled: Bool = UserDefaults.standard.doubleTapEnabled {
        didSet {
            UserDefaults.standard.doubleTapEnabled = doubleTapEnabled
            applyDoubleTap()
        }
    }

    @Published var doubleTapModifier: DoubleTapModifier = UserDefaults.standard.doubleTapModifier {
        didSet {
            UserDefaults.standard.doubleTapModifier = doubleTapModifier
            applyDoubleTap()
        }
    }

    private func applyDoubleTap() {
        if doubleTapEnabled {
            DoubleTapTrigger.shared.start(modifier: doubleTapModifier)
        } else {
            DoubleTapTrigger.shared.stop()
        }
    }

    private var eventMonitor: Any?

    // MARK: Actions

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        // Local monitor fires for key events in our own windows (settings panel is key).
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // NSEvent callbacks are always on the main thread; silence the concurrency warning.
            MainActor.assumeIsolated { self.handleKey(event) }
            return nil  // consume all key events while recording
        }
    }

    func stopRecording() {
        isRecording = false
        removeMonitor()
    }

    func clear() {
        HotkeyManager.shared.unregister()
        UserDefaults.standard.globalHotkey = nil
        hotkey = nil
    }

    // MARK: Private

    private func handleKey(_ event: NSEvent) {
        // Escape cancels recording.
        if event.keyCode == 53 {
            stopRecording()
            return
        }
        // Any combo with a strong modifier (⌘/⌥/⌃) is accepted.
        if let newHotkey = GlobalHotkey.from(event: event) {
            hotkey = newHotkey
            UserDefaults.standard.globalHotkey = newHotkey
            HotkeyManager.shared.register(newHotkey)
            stopRecording()
        }
        // Keys with only Shift (or no modifier) are silently ignored; recording continues.
    }

    private func removeMonitor() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @StateObject private var model = SettingsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            Text("Global Shortcut")
                .font(.headline)

            Text("Open KeyMinder from any app to see the active keyboard shortcuts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                HotkeyBadge(model: model)
                recordingButtons
            }

            Divider()

            Toggle("Launch at Login", isOn: $model.launchAtLogin)

            Divider()

            Text("Double-tap Trigger")
                .font(.headline)

            Text("Show KeyMinder by quickly pressing and releasing one modifier key twice.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Toggle("Enable", isOn: $model.doubleTapEnabled)
                    .toggleStyle(.switch)
                if model.doubleTapEnabled {
                    Picker("Modifier", selection: $model.doubleTapModifier) {
                        ForEach(DoubleTapModifier.allCases, id: \.self) { mod in
                            Text("\(mod.symbol) \(mod.label)").tag(mod)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 130)
                }
            }
        }
        .padding(20)
        .frame(width: 420, height: 320, alignment: .topLeading)
        .onDisappear { model.stopRecording() }
    }

    @ViewBuilder
    private var recordingButtons: some View {
        if model.isRecording {
            Button("Cancel") { model.stopRecording() }
        } else {
            Button(model.hotkey == nil ? "Record Shortcut…" : "Change…") {
                model.startRecording()
            }
            .keyboardShortcut("r", modifiers: .command)

            if model.hotkey != nil {
                Button("Clear") { model.clear() }
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - HotkeyBadge

/// Pill-shaped badge that shows the current hotkey or a recording prompt.
struct HotkeyBadge: View {
    @ObservedObject var model: SettingsModel

    private var label: String {
        if model.isRecording { return "Type your shortcut…" }
        return model.hotkey?.displayString ?? "Not set"
    }

    private var badgeForeground: Color {
        if model.isRecording { return .orange }
        return model.hotkey != nil ? .primary : .secondary
    }

    private var badgeFill: Color {
        model.isRecording ? .orange.opacity(0.10) : .primary.opacity(0.07)
    }

    private var badgeBorder: Color {
        model.isRecording ? .orange.opacity(0.45) : .primary.opacity(0.14)
    }

    var body: some View {
        Text(label)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 140, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(badgeFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(badgeBorder, lineWidth: 1)
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: model.isRecording)
    }
}
