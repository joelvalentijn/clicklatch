// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit
import SwiftUI

struct SettingsView: View {

    @State private var model = AppModel.shared

    var body: some View {
        VStack(spacing: 0) {
            // Stays above the tabs: without the permission nothing on any tab works.
            if !model.permission.isTrusted {
                PermissionBanner(permission: model.permission)
                    .padding(12)
                Divider()
            }

            TabView(selection: Binding(
                get: { model.settingsTab },
                set: { model.settingsTab = $0 }
            )) {
                GeneralTab()
                    .tabItem { Label("General", systemImage: "cursorarrow.click") }
                    .tag(SettingsTab.general)
                RingTab()
                    .tabItem { Label("Ring", systemImage: "smallcircle.circle") }
                    .tag(SettingsTab.ring)
                SoundTab()
                    .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
                    .tag(SettingsTab.sound)
                AdvancedTab()
                    .tabItem { Label("Advanced", systemImage: "gearshape") }
                    .tag(SettingsTab.advanced)
                UpdatesTab()
                    .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
                    .tag(SettingsTab.updates)
            }
        }
        .frame(width: 480, height: model.permission.isTrusted ? 560 : 700)
        .onAppear {
            model.permission.refresh()
            model.launchAtLogin.refresh()
        }
    }
}

/// Puts one setting back to its factory value. Greyed out while it already is.
private struct ResetButton<Value: Equatable>: View {

    @Binding var value: Value
    let defaultValue: Value

    var body: some View {
        Button {
            value = defaultValue
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .disabled(value == defaultValue)
        .help("Reset to default")
    }
}

// MARK: - General

private struct GeneralTab: View {

    @State private var model = AppModel.shared

    private var preferences: Preferences { model.preferences }

    var body: some View {
        Form {
            Section("Click lock") {
                Toggle("Enable click lock", isOn: Binding(
                    get: { preferences.enabled },
                    set: { model.setEnabled($0) }
                ))

                Text("""
                    Lets you select text or drag things without holding the mouse button down. \
                    Hold the button briefly to lock it, and click again to release.
                    """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("How long do you want to hold the mouse button?") {
                HStack(spacing: 10) {
                    Text("Short")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { preferences.holdDuration },
                            set: { preferences.holdDuration = $0 }
                        ),
                        in: Preferences.holdRange
                    )
                    Text("Long")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Threshold") {
                    HStack {
                        Text("\(Int((preferences.holdDuration * 1000).rounded())) ms")
                            .monospacedDigit()
                        ResetButton(
                            value: Binding(
                                get: { preferences.holdDuration },
                                set: { preferences.holdDuration = $0 }
                            ),
                            defaultValue: Preferences.Defaults.holdDuration
                        )
                    }
                }
            }

            Section("Practice") {
                TestPadView()
            }

            Section("Startup") {
                LaunchAtLoginRow(launchAtLogin: model.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Updates

private struct UpdatesTab: View {

    var body: some View {
        Form {
            Section("Updates") {
                UpdatesRows()
            }

            Section {
                Text("""
                    ClickLocker checks GitHub for a newer release, downloads it and replaces \
                    itself. It only installs a copy signed with the same key as the one running, \
                    so a tampered download cannot take its place.
                    """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdatesRows: View {

    @State private var model = AppModel.shared

    var body: some View {
        LabeledContent("Version") {
            Text(model.updater.currentVersion).monospacedDigit()
        }

        Toggle("Check for updates automatically", isOn: Binding(
            get: { model.preferences.checkForUpdates },
            set: { model.preferences.checkForUpdates = $0 }
        ))

        HStack {
            statusText
                .font(.callout)
                .foregroundStyle(isFailure ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            actionButton
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch model.updater.state {
        case .idle: Text("Not checked yet.")
        case .checking: Text("Checking…")
        case .upToDate: Text("ClickLocker is up to date.")
        case .available(let version): Text("Version \(version) is available.")
        case .downloading(let progress): Text("Downloading… \(Int(progress * 100)) %")
        case .readyToInstall(let version): Text("Version \(version) is ready to install.")
        case .failed(let reason): Text(reason)
        }
    }

    private var isFailure: Bool {
        if case .failed = model.updater.state { return true }
        return false
    }

    @ViewBuilder
    private var actionButton: some View {
        switch model.updater.state {
        case .checking, .downloading:
            ProgressView().controlSize(.small)
        case .available:
            Button("Download") {
                Task { await model.updater.download() }
            }
        case .readyToInstall:
            Button("Install & Restart") {
                model.installUpdate()
            }
            .keyboardShortcut(.defaultAction)
        default:
            Button("Check Now") {
                Task { await model.updater.check() }
            }
        }
    }
}

// MARK: - Ring

private struct RingTab: View {

    @State private var model = AppModel.shared

    private var preferences: Preferences { model.preferences }

    var body: some View {
        Form {
            Section {
                RingPreviewRow(style: preferences.ringStyle)
            }

            Section("Ring") {
                Toggle("Show a ring around the pointer", isOn: Binding(
                    get: { preferences.showCursorRing },
                    set: { preferences.showCursorRing = $0 }
                ))

                HStack {
                    ColorPicker("Colour", selection: Binding(
                        get: { Color(nsColor: NSColor.fromHex(preferences.ringColorHex) ?? .white) },
                        set: { preferences.ringColorHex = NSColor($0).hexString }
                    ), supportsOpacity: true)
                    Spacer()
                    ResetButton(
                        value: Binding(
                            get: { preferences.ringColorHex },
                            set: { preferences.ringColorHex = $0 }
                        ),
                        defaultValue: Preferences.Defaults.ringColorHex
                    )
                }

                LabeledContent("Thickness") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { preferences.ringThickness },
                                set: { preferences.ringThickness = $0 }
                            ),
                            in: Preferences.thicknessRange
                        )
                        Text("\(preferences.ringThickness, format: .number.precision(.fractionLength(1))) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                        ResetButton(
                            value: Binding(
                                get: { preferences.ringThickness },
                                set: { preferences.ringThickness = $0 }
                            ),
                            defaultValue: Preferences.Defaults.ringThickness
                        )
                    }
                }

                LabeledContent("Size") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { preferences.ringRadius },
                                set: { preferences.ringRadius = $0 }
                            ),
                            in: Preferences.radiusRange
                        )
                        Text("\(Int(preferences.ringRadius.rounded())) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                        ResetButton(
                            value: Binding(
                                get: { preferences.ringRadius },
                                set: { preferences.ringRadius = $0 }
                            ),
                            defaultValue: Preferences.Defaults.ringRadius
                        )
                    }
                }

                Toggle("Dark outline and shadow", isOn: Binding(
                    get: { preferences.ringOutline },
                    set: { preferences.ringOutline = $0 }
                ))
                Text("Keeps a light ring readable on a light background. Turn it off for a "
                     + "cleaner look on dark screens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Swell briefly when locking", isOn: Binding(
                    get: { preferences.ringPulseOnLock },
                    set: { preferences.ringPulseOnLock = $0 }
                ))
                Text("A short thickening at the moment the button locks, so you catch it out of "
                     + "the corner of your eye.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("How fast it appears") {
                LabeledContent("Delay") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { preferences.ringAppearDelay },
                                set: { preferences.ringAppearDelay = $0 }
                            ),
                            in: Preferences.appearDelayRange
                        )
                        Text("\(Int((preferences.ringAppearDelay * 1000).rounded())) ms")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                        ResetButton(
                            value: Binding(
                                get: { preferences.ringAppearDelay },
                                set: { preferences.ringAppearDelay = $0 }
                            ),
                            defaultValue: Preferences.Defaults.ringAppearDelay
                        )
                    }
                }
                Text("How long you have to hold before the ring turns up at all. Raise it if "
                     + "ordinary clicks make it flash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent("Fade") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { preferences.ringFadeDuration },
                                set: { preferences.ringFadeDuration = $0 }
                            ),
                            in: Preferences.fadeDurationRange
                        )
                        Text(preferences.ringFadeDuration < 0.005
                             ? "off"
                             : "\(Int((preferences.ringFadeDuration * 1000).rounded())) ms")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                        ResetButton(
                            value: Binding(
                                get: { preferences.ringFadeDuration },
                                set: { preferences.ringFadeDuration = $0 }
                            ),
                            defaultValue: Preferences.Defaults.ringFadeDuration
                        )
                    }
                }
                Text("How gently it fades in and out. At zero it simply appears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// Shows the real ring view, mid-press on dark and locked on light, so the
/// preview can never drift away from what appears on screen.
private struct RingPreviewRow: View {

    let style: RingStyle

    var body: some View {
        HStack(spacing: 12) {
            tile(background: Color(white: 0.12), fraction: 0.65, caption: "Holding")
            tile(background: Color(white: 0.94), fraction: 1, caption: "Locked")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func tile(background: Color, fraction: Double, caption: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(background)
                RingPreview(style: style, fraction: fraction)
                    .frame(width: style.windowSize, height: style.windowSize)
            }
            .frame(height: 88)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RingPreview: NSViewRepresentable {

    let style: RingStyle
    let fraction: Double

    func makeNSView(context: Context) -> RingView {
        RingView(frame: NSRect(x: 0, y: 0, width: style.windowSize, height: style.windowSize))
    }

    func updateNSView(_ view: RingView, context: Context) {
        view.style = style
        view.fraction = fraction
        view.needsDisplay = true
    }
}

// MARK: - Sound

private struct SoundTab: View {

    @State private var model = AppModel.shared
    @State private var sounds = SoundFeedback.availableSounds()

    private var preferences: Preferences { model.preferences }

    var body: some View {
        Form {
            Section("Sound") {
                Toggle("Play a sound when locking and releasing", isOn: Binding(
                    get: { preferences.soundEnabled },
                    set: { preferences.soundEnabled = $0 }
                ))

                LabeledContent("Volume") {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { preferences.soundVolume },
                                set: { preferences.soundVolume = $0 }
                            ),
                            in: 0...1
                        )
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                        Text("\(Int((preferences.soundVolume * 100).rounded())) %")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                        ResetButton(
                            value: Binding(
                                get: { preferences.soundVolume },
                                set: { preferences.soundVolume = $0 }
                            ),
                            defaultValue: Preferences.Defaults.soundVolume
                        )
                    }
                }
            }

            Section("Sounds") {
                soundRow(
                    title: "When locking",
                    selection: Binding(
                        get: { preferences.lockSoundName },
                        set: { preferences.lockSoundName = $0 }
                    ),
                    defaultName: Preferences.Defaults.lockSoundName
                )
                soundRow(
                    title: "When releasing",
                    selection: Binding(
                        get: { preferences.releaseSoundName },
                        set: { preferences.releaseSoundName = $0 }
                    ),
                    defaultName: Preferences.Defaults.releaseSoundName
                )
            }
            .disabled(!preferences.soundEnabled)
        }
        .formStyle(.grouped)
    }

    private func soundRow(
        title: String,
        selection: Binding<String>,
        defaultName: String
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Picker("", selection: selection) {
                    ForEach(names(including: selection.wrappedValue), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                Button {
                    model.previewSound(named: selection.wrappedValue)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Preview")
                ResetButton(value: selection, defaultValue: defaultName)
            }
        }
    }

    /// Keeps a stored name that no longer exists on this Mac selectable, instead
    /// of silently showing an empty menu.
    private func names(including current: String) -> [String] {
        sounds.contains(current) ? sounds : [current] + sounds
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {

    @State private var model = AppModel.shared
    @State private var confirmingReset = false

    private var preferences: Preferences { model.preferences }

    var body: some View {
        Form {
            Section("Buttons") {
                Toggle("Lock the right mouse button as well", isOn: Binding(
                    get: { preferences.rightButtonEnabled },
                    set: { preferences.rightButtonEnabled = $0 }
                ))
                Text("Windows only locks the primary button. Context menus may behave "
                     + "unexpectedly with this on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Safety nets") {
                Toggle("Don't lock if the mouse moves while holding", isOn: Binding(
                    get: { preferences.cancelOnMovement },
                    set: { preferences.cancelOnMovement = $0 }
                ))
                if preferences.cancelOnMovement {
                    LabeledContent("Slack") {
                        HStack {
                            Stepper(
                                value: Binding(
                                    get: { preferences.movementTolerance },
                                    set: { preferences.movementTolerance = $0 }
                                ),
                                in: 1...50,
                                step: 1
                            ) {
                                Text("\(Int(preferences.movementTolerance)) points")
                                    .monospacedDigit()
                            }
                            ResetButton(
                                value: Binding(
                                    get: { preferences.movementTolerance },
                                    set: { preferences.movementTolerance = $0 }
                                ),
                                defaultValue: Preferences.Defaults.movementTolerance
                            )
                        }
                    }
                }

                Toggle("Escape releases a lock", isOn: Binding(
                    get: { preferences.escapeReleases },
                    set: { preferences.escapeReleases = $0 }
                ))
                if preferences.escapeReleases {
                    Text("This routes key presses past the app; only Escape is examined, "
                         + "everything else passes through untouched and nothing is stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Release the lock automatically", isOn: Binding(
                    get: { preferences.autoReleaseEnabled },
                    set: { preferences.autoReleaseEnabled = $0 }
                ))
                if preferences.autoReleaseEnabled {
                    LabeledContent("After") {
                        HStack {
                            Stepper(
                                value: Binding(
                                    get: { preferences.autoReleaseAfter },
                                    set: { preferences.autoReleaseAfter = $0 }
                                ),
                                in: 2...120,
                                step: 1
                            ) {
                                Text("\(Int(preferences.autoReleaseAfter)) seconds")
                                    .monospacedDigit()
                            }
                            ResetButton(
                                value: Binding(
                                    get: { preferences.autoReleaseAfter },
                                    set: { preferences.autoReleaseAfter = $0 }
                                ),
                                defaultValue: Preferences.Defaults.autoReleaseAfter
                            )
                        }
                    }
                }
            }

            Section {
                Button("Restore Factory Settings…", role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog(
                    "Restore every setting to its factory value?",
                    isPresented: $confirmingReset
                ) {
                    Button("Restore Factory Settings", role: .destructive) {
                        preferences.restoreFactorySettings()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Appearance, sound and behaviour all go back to how they arrived. "
                         + "Whether the lock is switched on and whether ClickLocker opens at "
                         + "login are left as they are.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shared rows

private struct LaunchAtLoginRow: View {

    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Toggle("Open at login", isOn: Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        ))

        if launchAtLogin.requiresApproval {
            VStack(alignment: .leading, spacing: 6) {
                Text("macOS still needs your approval before ClickLocker may start "
                     + "automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Login Items…") { launchAtLogin.openLoginItemsSettings() }
            }
        }

        if let error = launchAtLogin.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Text("Login items work most reliably when the app lives in your Applications "
                 + "folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PermissionBanner: View {

    let permission: AccessibilityPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility permission not granted yet", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Without it no program is allowed to alter mouse clicks. Switch on "
                 + "ClickLocker under Privacy & Security → Accessibility.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Ask…") { permission.request() }
                Button("Open System Settings") { permission.openSystemSettings() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
