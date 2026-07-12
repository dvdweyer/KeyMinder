// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

// MARK: - SettingsWindowController

/// Opens (or focuses) a single settings window. The instance is released when
/// the window closes, so a fresh one is created the next time.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private static var instance: SettingsWindowController?

    /// Pre-measured natural heights for each tab (0=General, 1=Popup, 2=Ignored, 3=Developer),
    /// capped at 85 % of the available screen height.
    private var tabHeights: [CGFloat] = [0, 0, 0, 0]

    static func show() {
        let isNew = instance == nil
        if isNew { instance = SettingsWindowController() }
        NSApp.activate()
        instance?.window?.makeKeyAndOrderFront(nil)
        instance?.window?.orderFrontRegardless()
        if isNew { DockIconManager.shared.windowOpened() }
    }

    private init() {
        let screenH = (NSScreen.main?.visibleFrame.height ?? 900) * 0.85
        let m = SettingsModel()

        // Measure each tab independently (no-ScrollView tabs give exact heights;
        // the Ignored tab has a ScrollView so it gets capped at screenH via min()).
        // Add 24 pt buffer to all tabs: sizeThatFits slightly underestimates due to
        // rounding, padding inset overhead, and ScrollView wrapper costs.
        let genRaw = NSHostingController(rootView: GeneralSettingsBody(model: m))
            .sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude)).height + 24
        let popupRaw = NSHostingController(rootView: PopupSettingsBody(model: m))
            .sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude)).height + 24
        let ignoredRaw = NSHostingController(rootView: IgnoredSettingsBody(
                showAddIgnoredAppSheet: .constant(false),
                showAddMenuSheet: .constant(false),
                showAddGlobalSheet: .constant(false),
                showAddAppSheet: .constant(false)
            )).sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude)).height + 24
        let developerRaw = NSHostingController(rootView: DeveloperSettingsBody(model: m))
            .sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude)).height + 24

        let tabBarH: CGFloat = 44   // tab picker (≈32 pt) + divider (1 pt) + padding

        tabHeights = [
            min(genRaw      + tabBarH, screenH).rounded(),
            min(popupRaw    + tabBarH, screenH).rounded(),
            min(ignoredRaw  + tabBarH, screenH).rounded(),
            min(developerRaw + tabBarH, screenH).rounded()
        ]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: tabHeights[0]),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        window.title = String(localized: "KeyMinder Settings")
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(model: m, onTabChange: { [weak self] tab in
            self?.resize(to: tab)
        }))
    }

    required init?(coder: NSCoder) { nil }

    private func resize(to tab: Int) {
        guard let w = window, tab < tabHeights.count else { return }
        let newH = tabHeights[tab]
        var f = w.frame
        f.origin.y -= newH - f.height   // keep top of window fixed
        f.size.height = newH
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            w.animator().setFrame(f, display: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.instance = nil
        DockIconManager.shared.windowClosed()
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

    var requireFilterForAllMenuItems: Bool = UserDefaults.standard.requireFilterForAllMenuItems {
        didSet { UserDefaults.standard.requireFilterForAllMenuItems = requireFilterForAllMenuItems }
    }

    var hideLargeSubmenus: Bool = UserDefaults.standard.hideLargeSubmenus {
        didSet { UserDefaults.standard.hideLargeSubmenus = hideLargeSubmenus }
    }

    var showSystemShortcuts: Bool = UserDefaults.standard.showSystemShortcuts {
        didSet { UserDefaults.standard.showSystemShortcuts = showSystemShortcuts }
    }

    var showDeactivatedSystemShortcuts: Bool = UserDefaults.standard.showDeactivatedSystemShortcuts {
        didSet { UserDefaults.standard.showDeactivatedSystemShortcuts = showDeactivatedSystemShortcuts }
    }

    var showThirdPartyShortcuts: Bool = UserDefaults.standard.showThirdPartyShortcuts {
        didSet { UserDefaults.standard.showThirdPartyShortcuts = showThirdPartyShortcuts }
    }

    var automaticUpdatesEnabled: Bool = UserDefaults.standard.automaticUpdatesEnabled {
        didSet { UserDefaults.standard.automaticUpdatesEnabled = automaticUpdatesEnabled }
    }

    var debugLoggingEnabled: Bool = UserDefaults.standard.debugLoggingEnabled {
        didSet { UserDefaults.standard.debugLoggingEnabled = debugLoggingEnabled }
    }

    var receiveBetaUpdates: Bool = UserDefaults.standard.receiveBetaUpdates {
        didSet {
            UserDefaults.standard.receiveBetaUpdates = receiveBetaUpdates
            NotificationCenter.default.post(name: .receiveBetaUpdatesChanged, object: nil)
        }
    }

    var receiveAlphaUpdates: Bool = UserDefaults.standard.receiveAlphaUpdates {
        didSet {
            UserDefaults.standard.receiveAlphaUpdates = receiveAlphaUpdates
            NotificationCenter.default.post(name: .receiveAlphaUpdatesChanged, object: nil)
        }
    }

    var popupDisplayMode: PopupDisplayMode = UserDefaults.standard.popupDisplayMode {
        didSet { UserDefaults.standard.popupDisplayMode = popupDisplayMode }
    }

    private(set) var menuBarIconStyle: MenuBarIconStyle = UserDefaults.standard.menuBarIconStyle {
        didSet {
            UserDefaults.standard.menuBarIconStyle = menuBarIconStyle
            NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
        }
    }

    private(set) var appIconVariant: AppIconVariant = UserDefaults.standard.appIconVariant {
        didSet {
            UserDefaults.standard.appIconVariant = appIconVariant
            appIconVariant.apply()
        }
    }

    var matchAppIconToTrigger: Bool = UserDefaults.standard.matchAppIconToTrigger {
        didSet {
            UserDefaults.standard.matchAppIconToTrigger = matchAppIconToTrigger
            if matchAppIconToTrigger && doubleTapEnabled {
                appIconVariant = doubleTapModifier.appIconVariant
            }
        }
    }

    var showConflictIndicator: Bool = UserDefaults.standard.showConflictIndicator {
        didSet { UserDefaults.standard.showConflictIndicator = showConflictIndicator }
    }

    var wrapLongSections: Bool = UserDefaults.standard.wrapLongSections {
        didSet { UserDefaults.standard.wrapLongSections = wrapLongSections }
    }

    var alwaysShowFavourites: Bool = UserDefaults.standard.alwaysShowFavourites {
        didSet { UserDefaults.standard.alwaysShowFavourites = alwaysShowFavourites }
    }

    var iCloudSyncEnabled: Bool = UserDefaults.standard.iCloudSyncEnabled {
        didSet {
            UserDefaults.standard.iCloudSyncEnabled = iCloudSyncEnabled
            if iCloudSyncEnabled {
                if SettingsSync.shared.wouldApplyRemote() {
                    showingICloudConflictAlert = true
                } else {
                    SettingsSync.shared.start()
                }
            } else {
                SettingsSync.shared.stop()
            }
        }
    }

    var showingICloudConflictAlert = false

    func confirmICloudWithRemote() {
        SettingsSync.shared.start()
    }

    func confirmICloudWithLocal() {
        SettingsSync.shared.startWithLocalPriority()
    }

    func cancelICloudEnable() {
        iCloudSyncEnabled = false
    }

    var showingClearICloudAlert = false

    func clearICloudData() {
        SettingsSync.shared.clearICloudData()
        iCloudSyncEnabled = false
    }

    var doubleTapEnabled: Bool = UserDefaults.standard.doubleTapEnabled {
        didSet {
            UserDefaults.standard.doubleTapEnabled = doubleTapEnabled
            applyDoubleTap()
            syncIcons()
        }
    }

    var doubleTapModifier: DoubleTapModifier = UserDefaults.standard.doubleTapModifier {
        didSet {
            UserDefaults.standard.doubleTapModifier = doubleTapModifier
            applyDoubleTap()
            syncIcons()
        }
    }

    private func applyDoubleTap() {
        if doubleTapEnabled {
            DoubleTapTrigger.shared.start(modifier: doubleTapModifier)
        } else {
            DoubleTapTrigger.shared.stop()
        }
    }

    private func syncIcons() {
        if doubleTapEnabled {
            menuBarIconStyle = doubleTapModifier.menuBarIconStyle
            if matchAppIconToTrigger { appIconVariant = doubleTapModifier.appIconVariant }
        } else {
            menuBarIconStyle = .keyboard
        }
    }

    private var eventMonitor: Any?

    // MARK: Actions

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        registrationFailed = false
        HotkeyManager.shared.unregister()
        DoubleTapTrigger.shared.stop()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.handleKey(event) }
            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        removeMonitor()
        if let hk = hotkey { HotkeyManager.shared.register(hk) }
        applyDoubleTap()
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

// MARK: - TabPickerView

/// Icon-only segmented control backed by NSSegmentedControl.
/// Each segment shows only its SF Symbol; the tab label appears as a tooltip on hover.
private struct TabPickerView: NSViewRepresentable {
    struct Tab {
        let label: String
        let systemImage: String
    }

    let tabs: [Tab]
    @Binding var selection: Int

    func makeNSView(context: Context) -> NSSegmentedControl {
        let images = tabs.compactMap {
            NSImage(systemSymbolName: $0.systemImage, accessibilityDescription: $0.label)
        }
        let ctrl = NSSegmentedControl(images: images,
                                      trackingMode: .selectOne,
                                      target: context.coordinator,
                                      action: #selector(Coordinator.changed(_:)))
        for (i, tab) in tabs.enumerated() {
            ctrl.setToolTip(tab.label, forSegment: i)
        }
        ctrl.selectedSegment = selection
        return ctrl
    }

    func updateNSView(_ ctrl: NSSegmentedControl, context: Context) {
        if ctrl.selectedSegment != selection { ctrl.selectedSegment = selection }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: TabPickerView
        init(_ parent: TabPickerView) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            parent.selection = sender.selectedSegment
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    var onTabChange: (Int) -> Void = { _ in }
    @State private var model: SettingsModel
    @State private var selectedTab = 0

    @MainActor
    init(model: SettingsModel, onTabChange: @escaping (Int) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onTabChange = onTabChange
    }

    fileprivate static let tabs: [TabPickerView.Tab] = [
        .init(label: String(localized: "General"),   systemImage: "gearshape"),
        .init(label: String(localized: "Popup"),     systemImage: "list.bullet.rectangle.portrait"),
        .init(label: String(localized: "Ignored"),   systemImage: "eye.slash"),
        .init(label: String(localized: "Developer"), systemImage: "hammer"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabPickerView(tabs: Self.tabs, selection: $selectedTab)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider()
            tabContent
        }
        .frame(width: 420)
        .onChange(of: selectedTab) { _, tab in onTabChange(tab) }
        .onDisappear { model.stopRecording() }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: GeneralSettingsView(model: model)
        case 1: PopupSettingsView(model: model)
        case 2: IgnoredSettingsView()
        default: DeveloperSettingsView(model: model)
        }
    }
}

// MARK: - GeneralSettingsView

/// Scrolls `GeneralSettingsBody` so content taller than the window (e.g. on a
/// smaller display, where `SettingsWindowController` clamps the tab height to
/// 85% of the screen) stays reachable instead of being clipped.
private struct GeneralSettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        ScrollView {
            GeneralSettingsBody(model: model)
        }
    }
}

/// Extracted without `ScrollView` so `SettingsWindowController` can measure its
/// natural height reliably (matches `IgnoredSettingsBody`'s pattern).
private struct GeneralSettingsBody: View {
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

            Toggle("Check for updates automatically", isOn: $model.automaticUpdatesEnabled)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Sync settings with iCloud", isOn: $model.iCloudSyncEnabled)
                    .help("Syncs favourites, ignore rules, and appearance across your Macs. The global shortcut and trigger key are kept per-Mac.")
                    .confirmationDialog(
                        "iCloud Has Existing Settings",
                        isPresented: $model.showingICloudConflictAlert,
                        titleVisibility: .visible
                    ) {
                        Button("Use iCloud", role: .destructive) { model.confirmICloudWithRemote() }
                        Button("Keep Local Settings") { model.confirmICloudWithLocal() }
                        Button("Cancel", role: .cancel) { model.cancelICloudEnable() }
                    } message: {
                        Text("iCloud has settings from another Mac. Which settings should take effect on this Mac?")
                    }
                ExperimentalBadge()
            }

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
                            (Text(mod.symbol + " ") + Text(mod.label)).tag(mod)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 130)
                }
            }

            if model.doubleTapEnabled {
                Toggle("Match app icon to trigger key", isOn: $model.matchAppIconToTrigger)
            }

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

            Divider()

            Text("Popup Display")
                .font(.headline)

            Text("Which screen the popup appears on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Popup Display", selection: $model.popupDisplayMode) {
                ForEach(PopupDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Divider()

            Text("Backup & Restore")
                .font(.headline)

            Text("Save your settings to a file, or restore them from a previous export.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Export Settings…") { exportSettings() }
                Button("Import Settings…") { importSettings() }
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
    }

    private func exportSettings() {
        guard let data = try? SettingsPorter.export() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "KeyMinder Settings.keymindersettings"
        panel.allowedContentTypes = [UTType(filenameExtension: "keymindersettings") ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = String(localized: "Export Failed")
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "keymindersettings") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        do {
            try SettingsPorter.apply(data)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Import Failed"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
            return
        }
        FavouritesStore.shared.reload()
        IgnoreListStore.shared.reload()
        ThemeSettings.shared.reload()
        UserDefaults.standard.appIconVariant.apply()
        NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
        NotificationCenter.default.post(name: .receiveBetaUpdatesChanged, object: nil)
        NotificationCenter.default.post(name: .receiveAlphaUpdatesChanged, object: nil)
        let alert = NSAlert()
        alert.messageText = String(localized: "Settings Imported")
        alert.informativeText = String(localized: "Relaunch KeyMinder to apply all changes.")
        alert.addButton(withTitle: String(localized: "Relaunch Now"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [Bundle.main.bundlePath]
            try? task.run()
            NSApplication.shared.terminate(nil)
        }
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

// MARK: - PopupSettingsView

/// Scrolls `PopupSettingsBody` so content taller than the window (e.g. on a
/// smaller display, where `SettingsWindowController` clamps the tab height to
/// 85% of the screen) stays reachable instead of being clipped.
private struct PopupSettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        ScrollView {
            PopupSettingsBody(model: model)
        }
    }
}

/// Extracted without `ScrollView` so `SettingsWindowController` can measure its
/// natural height reliably (matches `IgnoredSettingsBody`'s pattern).
private struct PopupSettingsBody: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            Text("Popup Content")
                .font(.headline)

            Toggle("Show all menu entries", isOn: $model.showAllMenuItems)

            if model.showAllMenuItems {
                Toggle("Only show when searching", isOn: $model.requireFilterForAllMenuItems)
                    .padding(.leading, 20)
                    .foregroundStyle(.secondary)

                Toggle("Hide large submenus without shortcuts", isOn: $model.hideLargeSubmenus)
                    .padding(.leading, 20)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 6) {
                    Text("⚠️")
                        .font(.caption)
                    (Text("In apps with many menu entries (e.g., browser history), the popup may take ")
                        + Text("several seconds").bold()
                        + Text(" to appear."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
                .padding(.leading, 20)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Show system shortcuts", isOn: $model.showSystemShortcuts)
                ExperimentalBadge()
            }

            if model.showSystemShortcuts {
                Toggle("Show deactivated system shortcuts", isOn: $model.showDeactivatedSystemShortcuts)
                    .padding(.leading, 20)
                    .foregroundStyle(.secondary)
            }

            Toggle("Show registered app shortcuts", isOn: $model.showThirdPartyShortcuts)
                .help("Apps can register their global shortcuts at ~/Library/Application Support/KeyMinder/Integrations/<BundleID>.json")

            Toggle("Always show favorites", isOn: $model.alwaysShowFavourites)
                .help("Pinned shortcuts always appear, even when the search or modifier filter doesn't match them.")

            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Wrap long menus across columns", isOn: $model.wrapLongSections)
                ExperimentalBadge()
            }

            Text("A long menu that doesn't fit in one column continues in the next, with the menu name repeated.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
    }
}

// MARK: - ExperimentalBadge

private struct ExperimentalBadge: View {
    var body: some View {
        Text("experimental")
            .font(.caption)
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - IgnoredSettingsView

private struct IgnoredSettingsView: View {
    @State private var showAddIgnoredAppSheet = false
    @State private var showAddMenuSheet = false
    @State private var showAddGlobalSheet = false
    @State private var showAddAppSheet = false

    var body: some View {
        ScrollView {
            IgnoredSettingsBody(
                showAddIgnoredAppSheet: $showAddIgnoredAppSheet,
                showAddMenuSheet: $showAddMenuSheet,
                showAddGlobalSheet: $showAddGlobalSheet,
                showAddAppSheet: $showAddAppSheet
            )
        }
        .sheet(isPresented: $showAddIgnoredAppSheet) { AddIgnoredAppSheet() }
        .sheet(isPresented: $showAddMenuSheet) { AddIgnoredMenuSheet() }
        .sheet(isPresented: $showAddGlobalSheet) { AddGlobalRuleSheet() }
        .sheet(isPresented: $showAddAppSheet) { AddAppRuleSheet() }
    }
}

/// Inner content of the Ignored tab — extracted without ScrollView so
/// SettingsWindowController can measure its natural height reliably.
private struct IgnoredSettingsBody: View {
    @Binding var showAddIgnoredAppSheet: Bool
    @Binding var showAddMenuSheet: Bool
    @Binding var showAddGlobalSheet: Bool
    @Binding var showAddAppSheet: Bool

    @Bindable private var store = IgnoreListStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

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

            Text("Ignored Menus")
                .font(.headline)

            Text("Menus listed here are hidden from the popup. The Apple menu () is ignored by default.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.ignoredMenuTitles.isEmpty {
                Text("No ignored menus")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                IgnoreRulesBox(titles: store.ignoredMenuTitles) { title in
                    if let idx = store.ignoredMenuTitles.firstIndex(of: title) {
                        store.removeIgnoredMenu(at: IndexSet(integer: idx))
                    }
                }
            }

            Button("Add Menu…") { showAddMenuSheet = true }
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
}

// MARK: - DeveloperSettingsView

/// Scrolls `DeveloperSettingsBody` so content taller than the window (e.g. on a
/// smaller display, where `SettingsWindowController` clamps the tab height to
/// 85% of the screen) stays reachable instead of being clipped.
private struct DeveloperSettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        ScrollView {
            DeveloperSettingsBody(model: model)
        }
    }
}

/// Extracted without `ScrollView` so `SettingsWindowController` can measure its
/// natural height reliably (matches `IgnoredSettingsBody`'s pattern).
private struct DeveloperSettingsBody: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            Text("Updates")
                .font(.headline)

            Toggle("Receive beta releases", isOn: $model.receiveBetaUpdates)

            Text("Get early access to new features before the public release. Beta builds may be less stable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Receive alpha releases", isOn: $model.receiveAlphaUpdates)
                ExperimentalBadge()
            }

            Text("Experimental builds for active testers. Expect rough edges and occasional instability.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Developer")
                .font(.headline)

            Toggle("Enable debug logging", isOn: $model.debugLoggingEnabled)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Show conflict indicator", isOn: $model.showConflictIndicator)
                ExperimentalBadge()
            }

            Divider()

            Text("iCloud")
                .font(.headline)

            Button("Clear iCloud Settings…", role: .destructive) {
                model.showingClearICloudAlert = true
            }
            .confirmationDialog(
                "Clear iCloud Settings?",
                isPresented: $model.showingClearICloudAlert,
                titleVisibility: .visible
            ) {
                Button("Clear iCloud Settings", role: .destructive) { model.clearICloudData() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Removes all KeyMinder settings from iCloud. This affects every Mac in your Apple account — if another Mac is currently running KeyMinder, it may re-upload its settings immediately. iCloud sync will be turned off; re-enable it manually in General settings.")
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
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
            .compactMap { app -> (bundleID: String, name: String)? in
                guard app.activationPolicy == .regular,
                      let id = app.bundleIdentifier, let name = app.localizedName,
                      IgnoreListStore.shared.ignoredApps[id] == nil else { return nil }
                return (bundleID: id, name: name)
            }
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

// MARK: - AddIgnoredMenuSheet

private struct AddIgnoredMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ignore Menu")
                .font(.headline)

            Text("Enter the menu name exactly as it appears in the menu bar (e.g. \"File\", \"View\", \"Help\"). The Apple menu is identified by \"Apple\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Menu name", text: $title)
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
        IgnoreListStore.shared.addIgnoredMenu(title)
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
                    let isWildcard = title.contains("*") || title.contains("?")
                    Text(title)
                        .font(isWildcard ? .body.monospaced() : .body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isWildcard {
                        Text("wildcard")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(.primary.opacity(0.07))
                            )
                    }
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

            Text("Enter a command title to hide from the popup in all apps. Use * as a wildcard — e.g. *Window* hides any command containing 'Window'.")
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
            .compactMap { app -> (bundleID: String, name: String)? in
                guard app.activationPolicy == .regular,
                      let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (bundleID: id, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add App-Specific Rule")
                .font(.headline)

            Text("Hide a command in one app only. Use * as a wildcard — e.g. *Window* hides any command containing 'Window'.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

// MARK: - UserDefaults: automatic updates + release channels

extension UserDefaults {
    private static let automaticUpdatesKey = "SUEnableAutomaticChecks"

    var automaticUpdatesEnabled: Bool {
        get { object(forKey: Self.automaticUpdatesKey) as? Bool ?? true }
        set { set(newValue, forKey: Self.automaticUpdatesKey) }
    }

    private static let receiveBetaUpdatesKey = "receiveBetaUpdates"

    var receiveBetaUpdates: Bool {
        get { bool(forKey: Self.receiveBetaUpdatesKey) }
        set { set(newValue, forKey: Self.receiveBetaUpdatesKey) }
    }

    private static let receiveAlphaUpdatesKey = "receiveAlphaUpdates"

    var receiveAlphaUpdates: Bool {
        get { bool(forKey: Self.receiveAlphaUpdatesKey) }
        set { set(newValue, forKey: Self.receiveAlphaUpdatesKey) }
    }

}

extension Notification.Name {
    static let receiveBetaUpdatesChanged  = Notification.Name("org.afaik.KeyMinder.receiveBetaUpdatesChanged")
    static let receiveAlphaUpdatesChanged = Notification.Name("org.afaik.KeyMinder.receiveAlphaUpdatesChanged")
    static let menuBarIconStyleChanged    = Notification.Name("org.afaik.KeyMinder.menuBarIconStyleChanged")
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
