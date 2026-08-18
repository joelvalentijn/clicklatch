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
    @ObservationIgnored private let sound = SoundFeedback()

    private init() {
        preferences = Preferences()
        permission = AccessibilityPermission()
        launchAtLogin = LaunchAtLogin()

        engine = ClickLockEngine { status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previousPhase = self.status.phase
                self.status = status
                self.updateOverlay()
                self.playSound(from: previousPhase, to: status.phase)
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
            style: preferences.ringStyle,
            enabled: isRunning && preferences.showCursorRing
        )
    }

    /// Only a real change into or out of `.locked` makes a sound — not repeated
    /// status messages carrying the same phase, and not the state at startup.
    private func playSound(from previous: ClickLockPhase, to current: ClickLockPhase) {
        guard preferences.soundEnabled, isRunning, previous != current else { return }
        if current == .locked {
            sound.play(named: preferences.lockSoundName, volume: preferences.soundVolume)
        } else if previous == .locked {
            sound.play(named: preferences.releaseSoundName, volume: preferences.soundVolume)
        }
    }

    /// Used by the preview buttons in the settings window.
    func previewSound(named name: String) {
        sound.play(named: name, volume: preferences.soundVolume)
    }

    /// Keeps the engine and the ring in step with the settings and the permission.
    private func observeChanges() {
        withObservationTracking {
            _ = preferences.enabled
            _ = preferences.showCursorRing
            _ = preferences.ringStyle   // reads every ring setting, so all of them are tracked
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
