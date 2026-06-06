import SwiftUI
import AppKit
import os

// MARK: - SettingsWindowController

/// Opens (or focuses) a single settings window. The instance is released when
/// the window closes, so a fresh one is created the next time.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private static var instance: SettingsWindowController?

    /// Called once when the window closes, then cleared. Set by AppDelegate before
    /// the first-launch open so it can trigger the post-setup hint.
    static var onFirstClose: (() -> Void)? = nil

    static func show() {
        if instance == nil { instance = SettingsWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        instance?.window?.makeKeyAndOrderFront(nil)
    }

    private init() {
        let measured = NSHostingController(rootView: SettingsView())
            .sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude))
            .height.rounded()
        let contentHeight = min(max(measured, 300), 700)

        let hosting = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: contentHeight),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        window.title = String(localized: "KeyMinder Settings")
        window.contentView = hosting
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        Self.instance = nil
        Self.onFirstClose?()
        Self.onFirstClose = nil
    }
}

// MARK: - SettingsModel

/// Observable model backing the settings UI. Manages hotkey recording state,
/// UserDefaults persistence, HotkeyManager registration, and the login-item toggle.
@MainActor
@Observable
final class SettingsModel {

    private(set) var hotkey:             GlobalHotkey? = UserDefaults.standard.globalHotkey
    private(set) var isRecording:        Bool = false
    private(set) var registrationFailed: Bool = false

    var launchAtLogin: Bool = LoginItemManager.shared.isEnabled {
        didSet {
            guard launchAtLogin != LoginItemManager.shared.isEnabled else { return }
            do {
                try LoginItemManager.shared.setEnabled(launchAtLogin)
            } catch {
                launchAtLogin = LoginItemManager.shared.isEnabled
                Logger.settings.error("Login item toggle failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    // MARK: Double-tap trigger

    var showAllMenuItems: Bool = UserDefaults.standard.showAllMenuItems {
        didSet { UserDefaults.standard.showAllMenuItems = showAllMenuItems }
    }

    var showSystemShortcuts: Bool = UserDefaults.standard.showSystemShortcuts {
        didSet { UserDefaults.standard.showSystemShortcuts = showSystemShortcuts }
    }

    var showBackgroundApps: Bool = UserDefaults.standard.showBackgroundApps {
        didSet { UserDefaults.standard.showBackgroundApps = showBackgroundApps }
    }

    var debugLoggingEnabled: Bool = UserDefaults.standard.debugLoggingEnabled {
        didSet { UserDefaults.standard.debugLoggingEnabled = debugLoggingEnabled }
    }

    var doubleTapEnabled: Bool = UserDefaults.standard.doubleTapEnabled {
        didSet {
            UserDefaults.standard.doubleTapEnabled = doubleTapEnabled
            applyDoubleTap()
        }
    }

    var doubleTapModifier: DoubleTapModifier = UserDefaults.standard.doubleTapModifier {
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
        registrationFailed = false
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.handleKey(event) }
            return nil
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
        registrationFailed = false
    }

    // MARK: Private

    private func handleKey(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecording()
            return
        }
        if let newHotkey = GlobalHotkey.from(event: event) {
            if HotkeyManager.shared.register(newHotkey) {
                hotkey = newHotkey
                UserDefaults.standard.globalHotkey = newHotkey
            } else {
                registrationFailed = true
            }
            stopRecording()
        }
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
    @State private var model = SettingsModel()

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            AdvancedSettingsView(model: model)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 420)
        .onDisappear { model.stopRecording() }
    }
}

// MARK: - GeneralSettingsView

private struct GeneralSettingsView: View {
    @Bindable var model: SettingsModel

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

            if model.registrationFailed {
                Text("Shortcut already in use")
                    .font(.caption)
                    .foregroundStyle(.red)
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

            Divider()

            Text("Popup Content")
                .font(.headline)

            Text("Show all menu entries, not just those with keyboard shortcuts, to help discover available actions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show all menu entries", isOn: $model.showAllMenuItems)

            Toggle("Show system shortcuts", isOn: $model.showSystemShortcuts)

            Toggle("Show shortcuts from running apps (experimental)", isOn: $model.showBackgroundApps)

            Divider()

            Text("Appearance")
                .font(.headline)

            Text("Colour used for keyboard shortcut glyphs in the popup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let ts = ThemeSettings.shared
            HStack(spacing: 10) {
                ColorPicker("Key colour", selection: Binding(
                    get: { ts.keyAccent },
                    set: { ts.setCustomColor($0) }
                ), supportsOpacity: false)
                .labelsHidden()
                .disabled(ts.followsSystemAccent)

                Text("Key colour")

                Spacer()

                if !ts.followsSystemAccent {
                    Button("Reset") { ts.resetToSystem() }
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Follow system accent colour", isOn: Binding(
                get: { ts.followsSystemAccent },
                set: { if $0 { ts.resetToSystem() } else { ts.enableCustom() } }
            ))
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
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

// MARK: - AdvancedSettingsView

private struct AdvancedSettingsView: View {
    @Bindable var model: SettingsModel
    @State private var showAddIgnoredAppSheet = false
    @State private var showAddGlobalSheet = false
    @State private var showAddAppSheet = false

    @Bindable private var store = IgnoreListStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                Text("Developer")
                    .font(.headline)

                Toggle("Enable debug logging", isOn: $model.debugLoggingEnabled)

                Divider()

                Text("Ignored Apps")
                    .font(.headline)

                Text("Apps listed here are skipped entirely — the popup won't open while they're frontmost.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if store.sortedIgnoredAppIDs.isEmpty {
                    Text("No ignored apps")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    IgnoredAppsBox(appIDs: store.sortedIgnoredAppIDs, displayNames: store.ignoredApps) { bundleID in
                        store.removeIgnoredApp(bundleID: bundleID)
                    }
                }

                Button("Add App…") { showAddIgnoredAppSheet = true }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Divider()

                Text("Ignored Commands")
                    .font(.headline)

                Text("Commands listed here are hidden from the popup. If a command opens a submenu, the entire submenu is hidden too.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Hide ignored commands", isOn: $store.isEnabled)

                if store.isEnabled {
                    Toggle("Show when filtering", isOn: $store.showWhenFiltering)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }

                Divider()

                // Global (all apps) rules
                Text("All Apps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if store.globalTitles.isEmpty {
                    Text("No ignored commands")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    IgnoreRulesBox(titles: store.globalTitles) { title in
                        if let idx = store.globalTitles.firstIndex(of: title) {
                            store.removeGlobal(at: IndexSet(integer: idx))
                        }
                    }
                }

                Button("Add Global Rule…") { showAddGlobalSheet = true }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                // Per-app rules
                if !store.sortedAppIDs.isEmpty {
                    Divider()
                    Text("App-Specific")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(store.sortedAppIDs, id: \.self) { bundleID in
                        let titles = store.perApp[bundleID] ?? []
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(store.appDisplayNames[bundleID] ?? bundleID)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Button {
                                    store.removeApp(bundleID)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove all rules for this app")
                            }

                            IgnoreRulesBox(titles: titles) { title in
                                if let idx = titles.firstIndex(of: title) {
                                    store.removeRule(bundleID: bundleID, at: IndexSet(integer: idx))
                                }
                            }
                        }
                    }
                }

                Button("Add App Rule…") { showAddAppSheet = true }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .frame(width: 420, alignment: .topLeading)
        }
        .sheet(isPresented: $showAddIgnoredAppSheet) {
            AddIgnoredAppSheet()
        }
        .sheet(isPresented: $showAddGlobalSheet) {
            AddGlobalRuleSheet()
        }
        .sheet(isPresented: $showAddAppSheet) {
            AddAppRuleSheet()
        }
    }
}

// MARK: - IgnoredAppsBox

private struct IgnoredAppsBox: View {
    let appIDs: [String]
    let displayNames: [String: String]
    let onDelete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(appIDs, id: \.self) { bundleID in
                HStack {
                    Text(displayNames[bundleID] ?? bundleID)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        onDelete(bundleID)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                if bundleID != appIDs.last {
                    Divider().padding(.horizontal, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - AddIgnoredAppSheet

private struct AddIgnoredAppSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBundleID: String = ""

    private var runningApps: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.localizedName != nil }
            .filter { IgnoreListStore.shared.ignoredApps[$0.bundleIdentifier!] == nil }
            .map { (bundleID: $0.bundleIdentifier!, name: $0.localizedName!) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ignore App")
                .font(.headline)

            Text("The popup won't open while this app is frontmost.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if runningApps.isEmpty {
                Text("No apps to add (all running apps are already ignored).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("App")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("App", selection: $selectedBundleID) {
                        Text("Select an app…").tag("")
                        ForEach(runningApps, id: \.bundleID) { app in
                            Text(app.name).tag(app.bundleID)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { addAndDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedBundleID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            if let first = runningApps.first {
                selectedBundleID = first.bundleID
            }
        }
    }

    private func addAndDismiss() {
        guard !selectedBundleID.isEmpty else { return }
        let displayName = runningApps.first { $0.bundleID == selectedBundleID }?.name ?? selectedBundleID
        IgnoreListStore.shared.addIgnoredApp(bundleID: selectedBundleID, displayName: displayName)
        dismiss()
    }
}

// MARK: - IgnoreRulesBox

private struct IgnoreRulesBox: View {
    let titles: [String]
    let onDelete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(titles, id: \.self) { title in
                HStack {
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        onDelete(title)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                if title != titles.last {
                    Divider().padding(.horizontal, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - AddGlobalRuleSheet

private struct AddGlobalRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Ignored Command")
                .font(.headline)

            Text("Enter the exact command title to hide from the popup in all apps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Command title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { addAndDismiss() }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { addAndDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func addAndDismiss() {
        IgnoreListStore.shared.addGlobal(title)
        dismiss()
    }
}

// MARK: - AddAppRuleSheet

private struct AddAppRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var commandTitle = ""
    @State private var selectedBundleID: String = ""
    @FocusState private var titleFocused: Bool

    private var runningApps: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.localizedName != nil }
            .map { (bundleID: $0.bundleIdentifier!, name: $0.localizedName!) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add App-Specific Rule")
                .font(.headline)

            Text("Hide a command in one app only.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if runningApps.isEmpty {
                Text("No apps are currently running.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("App")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("App", selection: $selectedBundleID) {
                        Text("Select an app…").tag("")
                        ForEach(runningApps, id: \.bundleID) { app in
                            Text(app.name).tag(app.bundleID)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Command title")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Command title", text: $commandTitle)
                        .textFieldStyle(.roundedBorder)
                        .focused($titleFocused)
                        .onSubmit { addAndDismiss() }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { addAndDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            if let first = runningApps.first {
                selectedBundleID = first.bundleID
            }
            titleFocused = true
        }
    }

    private var canAdd: Bool {
        !selectedBundleID.isEmpty && !commandTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addAndDismiss() {
        guard canAdd else { return }
        let displayName = runningApps.first { $0.bundleID == selectedBundleID }?.name ?? selectedBundleID
        IgnoreListStore.shared.addRule(bundleID: selectedBundleID, displayName: displayName, title: commandTitle)
        dismiss()
    }
}

// MARK: - HotkeyBadge

/// Pill-shaped badge that shows the current hotkey or a recording prompt.
struct HotkeyBadge: View {
    var model: SettingsModel

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
        labelText
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

    @ViewBuilder
    private var labelText: some View {
        if model.isRecording {
            Text("Type your shortcut…")
        } else if let hk = model.hotkey {
            Text(verbatim: hk.displayString)
        } else {
            Text("Not set")
        }
    }
}
