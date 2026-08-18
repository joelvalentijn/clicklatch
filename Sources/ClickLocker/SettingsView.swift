// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import SwiftUI

struct SettingsView: View {

    @State private var model = AppModel.shared

    private var preferences: Preferences { model.preferences }

    var body: some View {
        Form {
            if !model.permission.isTrusted {
                Section {
                    PermissionBanner(permission: model.permission)
                }
            }

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
                    Text("\(Int((preferences.holdDuration * 1000).rounded())) ms")
                        .monospacedDigit()
                }
            }

            Section("Practice") {
                TestPadView()
            }

            Section("Startup") {
                LaunchAtLoginRow(launchAtLogin: model.launchAtLogin)
            }

            Section("Options") {
                Toggle(
                    "Show a ring around the pointer",
                    isOn: Binding(
                        get: { preferences.showCursorRing },
                        set: { preferences.showCursorRing = $0 }
                    )
                )
                Text("The ring fills up while you hold the button and closes once the "
                     + "button is locked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    "Lock the right mouse button as well",
                    isOn: Binding(
                        get: { preferences.rightButtonEnabled },
                        set: { preferences.rightButtonEnabled = $0 }
                    )
                )
                Text("Windows only locks the primary button. Context menus may behave "
                     + "unexpectedly with this on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    "Don't lock if the mouse moves while holding",
                    isOn: Binding(
                        get: { preferences.cancelOnMovement },
                        set: { preferences.cancelOnMovement = $0 }
                    )
                )
                if preferences.cancelOnMovement {
                    LabeledContent("Slack") {
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
                    }
                }

                Toggle(
                    "Escape releases a lock",
                    isOn: Binding(
                        get: { preferences.escapeReleases },
                        set: { preferences.escapeReleases = $0 }
                    )
                )
                if preferences.escapeReleases {
                    Text("This routes key presses past the app; only Escape is examined, "
                         + "everything else passes through untouched and nothing is stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(
                    "Release the lock automatically",
                    isOn: Binding(
                        get: { preferences.autoReleaseEnabled },
                        set: { preferences.autoReleaseEnabled = $0 }
                    )
                )
                if preferences.autoReleaseEnabled {
                    LabeledContent("After") {
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
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 700)
        .onAppear {
            model.permission.refresh()
            model.launchAtLogin.refresh()
        }
    }
}

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
        .padding(.vertical, 4)
    }
}
