// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import Foundation
import Observation

/// Watches the macOS "Alternate pointer actions" accessibility feature
/// (System Settings → Accessibility → Pointer Control → Alternate Control
/// Methods). While it is on, the user is driving the pointer another way, so
/// ClickLatch stands down entirely rather than fighting it.
///
/// There is no notification for this, and the value lives in another process's
/// preferences, so it is read on a poll — the same approach the Accessibility
/// permission uses.
@MainActor
@Observable
final class AlternatePointerActions {

    // The UI calls it "Alternate pointer actions"; the stored key kept its older
    // internal name. Both are injectable so the read-and-poll mechanism can be
    // exercised against a throwaway domain, without ever touching the real system
    // setting — which ClickLatch only reads, never writes.
    private let domain: CFString
    private let key: CFString

    private(set) var isActive: Bool

    @ObservationIgnored private var pollTimer: Timer?

    init(
        domain: String = "com.apple.universalaccess",
        key: String = "alternateMouseButtonsEnabled"
    ) {
        self.domain = domain as CFString
        self.key = key as CFString
        isActive = false
        isActive = read()
    }

    func refresh() {
        let current = read()
        if current != isActive { isActive = current }
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Synchronising first forces a re-read from the other process rather than a
    /// cached copy, so a change is seen within one poll.
    private func read() -> Bool {
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let value = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? NSNumber)?.boolValue ?? false
    }
}
