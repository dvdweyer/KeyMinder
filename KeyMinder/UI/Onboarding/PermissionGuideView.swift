// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Step-by-step guide, with screenshots, for giving KeyMinder access on macOS 27.3+
/// (System & App Protection Override). Two paths: all apps, or chosen apps.
///
/// English only for now: the screenshots are from an English system and the strings live
/// in `PermissionGuide.xcstrings`, marked "don't translate" until the guide is localized.
struct PermissionGuideView: View {

    enum Path: Hashable { case allApps, selectedApps }

    @State private var path: Path = .allApps
    @State private var stepIndex = 0
    @State private var granted = AccessibilityPermission.isTrusted

    private var steps: [GuideStep] { path == .allApps ? GuideStep.allApps : GuideStep.selectedApps }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 14)

            Divider()

            stepView(steps[stepIndex], number: stepIndex + 1, of: steps.count)
                .id("\(path)-\(stepIndex)")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 28)
                .padding(.top, 18)

            Divider()

            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
        }
        .frame(width: 620, height: 700)
        .task {
            while !Task.isCancelled {
                granted = AccessibilityPermission.isTrusted
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to give KeyMinder access", tableName: "PermissionGuide")
                .font(.title2).fontWeight(.semibold)
            Text("macOS lets you choose: KeyMinder can read all your apps, or only the apps you pick. Your data never leaves your Mac.",
                 tableName: "PermissionGuide")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker(selection: $path) {
                Text("All Apps (recommended)", tableName: "PermissionGuide").tag(Path.allApps)
                Text("Selected Apps", tableName: "PermissionGuide").tag(Path.selectedApps)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: path) { _, _ in stepIndex = 0 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Step

    private func stepView(_ step: GuideStep, number: Int, of total: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "\(number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(ThemeSettings.shared.keyAccent))
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(step.title), tableName: "PermissionGuide")
                        .font(.headline)
                    Text(LocalizedStringKey(step.detail), tableName: "PermissionGuide")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            screenshot(step.image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let tip = step.tip {
                Label {
                    Text(LocalizedStringKey(tip), tableName: "PermissionGuide")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb")
                }
                .font(.subheadline)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ThemeSettings.shared.keyAccent.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.bottom, 14)
    }

    /// The screenshot at its natural size or smaller (never upscaled), framed by its own edges.
    private func screenshot(_ name: String) -> some View {
        let natural = NSImage(named: "PermissionGuide/\(name)")?.size ?? CGSize(width: 560, height: 400)
        return Image("PermissionGuide/\(name)")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
            .frame(maxWidth: natural.width, maxHeight: natural.height)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .accessibilityHidden(true)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                AccessibilityPermission.openSettings()
            } label: {
                Text("Open System Settings…", tableName: "PermissionGuide")
            }
            .fixedSize()

            if granted {
                Label {
                    Text("Access granted", tableName: "PermissionGuide")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(.green)
                .font(.subheadline.weight(.medium))
                .fixedSize()
            }

            Spacer()

            Button {
                stepIndex -= 1
            } label: {
                Label {
                    Text("Back", tableName: "PermissionGuide")
                } icon: {
                    Image(systemName: "chevron.left")
                }
            }
            .disabled(stepIndex == 0)

            Text(verbatim: "\(stepIndex + 1) / \(steps.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                stepIndex += 1
            } label: {
                Text("Next Step", tableName: "PermissionGuide")
            }
            .buttonStyle(.borderedProminent)
            .disabled(stepIndex + 1 >= steps.count)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Steps

private struct GuideStep {
    let image: String
    // Plain String keys, looked up in PermissionGuide.xcstrings at display time, so the
    // compiler doesn't extract them into Localizable.xcstrings.
    let title: String
    let detail: String
    var tip: String? = nil

    static let openPane = GuideStep(
        image: "s1_pane",
        title: "Click + in System & App Protection Override",
        detail: "Click Open System Settings… below. It opens Privacy & Security → System & App Protection Override.")

    static let addKeyMinder = GuideStep(
        image: "s2_picker",
        title: "Select KeyMinder and click Add",
        detail: "KeyMinder is in the Applications folder.")

    static let allApps: [GuideStep] = [
        openPane,
        addKeyMinder,
        GuideStep(
            image: "s3_override",
            title: "Click Override System Protections",
            detail: "This lets KeyMinder read the menus of every app, now and in the future."),
        GuideStep(
            image: "s7_warning",
            title: "Click OK next to each item",
            detail: "macOS lists everything an app with this access could do. KeyMinder only reads the menus of the active app and runs a menu command when you click it.",
            tip: "Scroll down: the last item is below the first four."),
        GuideStep(
            image: "s8_allow",
            title: "Click Allow System & App Protection Override",
            detail: "Then enter your Mac password."),
        GuideStep(
            image: "s9_done",
            title: "Done",
            detail: "KeyMinder is now listed with “Control your entire Mac and all apps”. Its popup works in every app."),
    ]

    static let selectedApps: [GuideStep] = [
        openPane,
        addKeyMinder,
        GuideStep(
            image: "s3_choose_apps",
            title: "Click Choose Apps",
            detail: "KeyMinder will then only work in the apps you add to its list."),
        GuideStep(
            image: "s4_applist_empty",
            title: "Click + to add apps",
            detail: "The file picker opens in the Applications folder."),
        GuideStep(
            image: "s5_multi",
            title: "Select several apps at once, then click Add",
            detail: "Hold ⌘ and click each app you want. To add every app in the folder, press ⌘A. Then click Add and enter your Mac password.",
            tip: "You can add more apps later the same way: click the ⓘ next to KeyMinder in System & App Protection Override."),
        GuideStep(
            image: "s6_anytime",
            title: "Optional: choose At Any Time",
            detail: "Apps start as Ask First: the first time KeyMinder reads one, macOS asks you, and the permission lasts until the next day. Choose At Any Time for an app so macOS stops asking.",
            tip: "macOS asks for your password each time you change an app to At Any Time. To skip this for every app, use All Apps instead."),
    ]
}

// MARK: - Window

/// Shows `PermissionGuideView` in its own window, next to System Settings. Opened from the
/// wizard's permission step ("Show me how") and from the menu-bar icon's context menu.
@MainActor
final class PermissionGuideWindowController: NSWindowController, NSWindowDelegate {

    private static var current: PermissionGuideWindowController?

    static func show() {
        if let current {
            NSApp.activate()
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = PermissionGuideWindowController()
        current = controller
        DockIconManager.shared.windowOpened()
        NSApp.activate()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Give KeyMinder Access", table: "PermissionGuide")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PermissionGuideView())
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        DockIconManager.shared.windowClosed()
        Self.current = nil
    }
}
