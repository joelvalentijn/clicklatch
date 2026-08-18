// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit
import ApplicationServices
import Observation

/// Tracks whether the app holds the Accessibility permission. Without it no
/// process is allowed to alter mouse events, so the lock cannot work.
@MainActor
@Observable
final class AccessibilityPermission {

    private(set) var isTrusted = AXIsProcessTrusted()

    @ObservationIgnored private var pollTimer: Timer?

    /// Asks for the permission; macOS then shows its own dialog with a button to
    /// System Settings. Only the user can actually grant it.
    func request() {
        // kAXTrustedCheckOptionPrompt is a global var and therefore off limits
        // under Swift 6; the key itself is fixed.
        let options = ["AXTrustedCheckOptionPrompt": true]
        isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        startPolling()
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    /// Opens the pane that holds the checkbox.
    func openSystemSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
        startPolling()
    }

    /// The system does not announce changes to the permission, so we look for
    /// them ourselves.
    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.isTrusted {
                    self.isTrusted = trusted
                }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
