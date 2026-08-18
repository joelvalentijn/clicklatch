// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit
import Observation
import ServiceManagement

/// Registers the app as a login item.
///
/// macOS itself is the source of truth here — there is deliberately no stored
/// preference that could drift away from what the system actually does.
@MainActor
@Observable
final class LaunchAtLogin {

    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }

    /// The user switched it on, but still has to approve it in System Settings.
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Usually means the app runs from a temporary or unstable location.
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        )!
        NSWorkspace.shared.open(url)
    }
}
