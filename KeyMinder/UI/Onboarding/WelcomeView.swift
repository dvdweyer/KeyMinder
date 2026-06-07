import AppKit
import SwiftUI

// MARK: - WelcomeStep

enum WelcomeStep: Int, CaseIterable {
    case intro, permission, trigger, loginItem
}

// MARK: - WelcomeView

struct WelcomeView: View {
    var onTryItNow: () -> Void
    var onDismiss:  () -> Void

    @State private var step: WelcomeStep = .intro
    @State private var goingForward = true
    @State private var model = SettingsModel()
    @State private var permissionGranted = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 0) {
            StepDotsView(current: step.rawValue, total: WelcomeStep.allCases.count)
                .padding(.top, 28)

            ZStack {
                stepContent
                    .transition(slideTransition)
                    .id(step)
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Divider()

            navBar
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
        }
        .frame(width: 420, height: 460)
        .onChange(of: permissionGranted) { _, granted in
            guard granted, step == .permission else { return }
            // Auto-advance after a short pause so the user sees the green
            // checkmark before the step transitions away.
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard step == .permission else { return }
                advance()
            }
        }
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .intro:
            WelcomeIntroStep()
        case .permission:
            WelcomePermissionStep(granted: $permissionGranted)
        case .trigger:
            WelcomeTriggerStep(model: model, onTryItNow: onTryItNow)
        case .loginItem:
            WelcomeLoginStep(model: model)
        }
    }

    // MARK: Navigation

    private var navBar: some View {
        HStack(spacing: 12) {
            if step != .intro {
                Button(action: retreat) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if step == .intro {
                Button("Skip setup", action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
            }

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .intro:
            Button("Get started", action: advance)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .permission:
            Button("Continue", action: advance)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .trigger:
            Button("Next", action: advance)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .loginItem:
            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Transitions

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: goingForward ? .leading  : .trailing).combined(with: .opacity)
        )
    }

    private func advance() {
        guard let next = WelcomeStep(rawValue: step.rawValue + 1) else {
            onDismiss()
            return
        }
        goingForward = true
        withAnimation(.easeInOut(duration: 0.22)) { step = next }
    }

    private func retreat() {
        guard let prev = WelcomeStep(rawValue: step.rawValue - 1) else { return }
        goingForward = false
        withAnimation(.easeInOut(duration: 0.22)) { step = prev }
    }
}

// MARK: - Step A: Intro

private struct WelcomeIntroStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 52))
                .foregroundStyle(ThemeSettings.shared.keyAccent)
                .padding(.top, 4)

            VStack(spacing: 8) {
                Text("Welcome to KeyMinder")
                    .font(.title2).fontWeight(.semibold)

                Text("See every keyboard shortcut for any app — without opening its menus.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                WelcomeBullet(icon: "keyboard",         text: "Instant lookup — just switch to any app")
                WelcomeBullet(icon: "magnifyingglass",  text: "Filter by modifier key or search by name")
                WelcomeBullet(icon: "star",             text: "Pin favourites for one-tap access")
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Step B: Permission

private struct WelcomePermissionStep: View {
    @Binding var granted: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: granted ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(granted ? Color.green : ThemeSettings.shared.keyAccent)
                .animation(.easeInOut(duration: 0.3), value: granted)
                .padding(.top, 4)

            VStack(spacing: 8) {
                Text("Allow access to your apps")
                    .font(.title2).fontWeight(.semibold)

                Text("KeyMinder reads menus via the macOS Accessibility API — the same permission used by screen readers and assistive tools. Your data never leaves your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Live status row
            HStack(spacing: 8) {
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Access granted")
                        .foregroundStyle(.green)
                        .fontWeight(.medium)
                } else {
                    ProgressView().scaleEffect(0.75).frame(width: 16, height: 16)
                    Text("Waiting for permission…")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .animation(.easeInOut(duration: 0.2), value: granted)

            if !granted {
                Button("Grant Access…") {
                    AccessibilityPermission.requestAccess()
                }
                .buttonStyle(.bordered)
            }
        }
        .task {
            while !Task.isCancelled {
                if AXIsProcessTrusted() {
                    granted = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

// MARK: - Step C: Trigger

private struct WelcomeTriggerStep: View {
    @Bindable var model: SettingsModel
    let onTryItNow: () -> Void

    @State private var tried = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set your trigger")
                    .font(.title2).fontWeight(.semibold)
                Text("Choose how you'll open KeyMinder from any app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Global shortcut
            VStack(alignment: .leading, spacing: 8) {
                Text("Global Shortcut")
                    .font(.headline)
                HStack(spacing: 8) {
                    HotkeyBadge(model: model)
                    recordingButtons
                }
                if model.registrationFailed {
                    Text("Shortcut already in use")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // Double-tap trigger
            VStack(alignment: .leading, spacing: 8) {
                Text("Double-tap Modifier")
                    .font(.headline)
                Text("Press a modifier key twice quickly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Divider()

            tryItNowBox
        }
        // Cancel the auto-reset timer if the user leaves this step early.
        .task(id: tried) {
            guard tried else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            tried = false
        }
    }

    private var tryItNowBox: some View {
        HStack(spacing: 12) {
            Image(systemName: tried ? "checkmark.circle.fill" : "play.circle")
                .font(.title3)
                .foregroundStyle(tried ? Color.green : ThemeSettings.shared.keyAccent)
                .animation(.easeInOut(duration: 0.2), value: tried)

            VStack(alignment: .leading, spacing: 2) {
                Text(tried ? "Shortcut works!" : "Try it now")
                    .fontWeight(.medium)
                    .animation(nil, value: tried)
                Text(tried
                     ? "You're all set — click Next to continue."
                     : "Use your trigger while this window is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .animation(nil, value: tried)
            }

            Spacer(minLength: 0)

            if !tried {
                Button("Try") {
                    tried = true
                    onTryItNow()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var recordingButtons: some View {
        if model.isRecording {
            Button("Cancel") { model.stopRecording() }
        } else {
            Button(model.hotkey == nil ? "Record Shortcut…" : "Change…") {
                model.startRecording()
            }
            if model.hotkey != nil {
                Button("Clear") { model.clear() }
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Step D: Login item

private struct WelcomeLoginStep: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .padding(.top, 4)

            VStack(spacing: 8) {
                Text("One last thing")
                    .font(.title2).fontWeight(.semibold)

                Text("Would you like KeyMinder to launch automatically when you log in?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $model.launchAtLogin) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at Login")
                        .fontWeight(.medium)
                    Text("KeyMinder will be ready in your menu bar whenever you need it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                    )
            )

            Text("You can change this any time in Settings → General.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Step progress dots

private struct StepDotsView: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current
                          ? AnyShapeStyle(ThemeSettings.shared.keyAccent)
                          : AnyShapeStyle(Color.primary.opacity(0.15)))
                    .frame(width: i == current ? 18 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.22), value: current)
            }
        }
    }
}

// MARK: - Feature bullet (Step A)

private struct WelcomeBullet: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(ThemeSettings.shared.keyAccent)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
