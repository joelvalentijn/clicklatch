// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import Foundation
import Observation

/// Ties settings, permissions, the engine and the pointer ring together. One
/// shared instance, so the menu bar and the settings window show the same thing.
@MainActor
@Observable
final class AppModel {

    static let shared = AppModel()

    let preferences: Preferences
    let permission: AccessibilityPermission
    let launchAtLogin: LaunchAtLogin
    private(set) var status = ClickLockStatus()

    @ObservationIgnored private var engine: ClickLockEngine!
    @ObservationIgnored private let overlay = CursorOverlay()

    private init() {
        preferences = Preferences()
        permission = AccessibilityPermission()
        launchAtLogin = LaunchAtLogin()

        engine = ClickLockEngine { status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.status = status
                self.updateOverlay()
            }
        }

        permission.startPolling()
        observeChanges()
        sync()
    }

    /// The lock only runs when it is switched on *and* the permission is there.
    var isRunning: Bool { preferences.enabled && permission.isTrusted }

    /// Switches the lock on, asking for the permission first if it is missing.
    func setEnabled(_ enabled: Bool) {
        if enabled && !permission.isTrusted {
            permission.request()
        }
        preferences.enabled = enabled
    }

    func shutDown() {
        overlay.hide()
        engine.shutDown()
        permission.stopPolling()
    }

    /// Short description of the current state, used in the menu and the window.
    var statusText: String {
        if !permission.isTrusted {
            return "Accessibility permission missing"
        }
        if let failure = status.failure {
            return failure
        }
        if !preferences.enabled {
            return "Off"
        }
        switch status.phase {
        case .idle: return "On — waiting for a click"
        case .pressed: return "Holding the button…"
        case .locked: return "Locked — click to release"
        }
    }

    private func sync() {
        engine.update(config: preferences.engineConfig, running: isRunning)
        updateOverlay()
    }

    private func updateOverlay() {
        overlay.update(
            status: status,
            holdDuration: preferences.holdDuration,
            enabled: isRunning && preferences.showCursorRing
        )
    }

    /// Keeps the engine and the ring in step with the settings and the permission.
    private func observeChanges() {
        withObservationTracking {
            _ = preferences.enabled
            _ = preferences.showCursorRing
            _ = preferences.engineConfig
            _ = permission.isTrusted
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sync()
                self.observeChanges()
            }
        }
    }
}
