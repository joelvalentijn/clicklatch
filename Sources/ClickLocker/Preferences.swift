// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import Foundation
import Observation

/// Every setting, stored in UserDefaults.
///
/// Anything that deviates from Windows is off by default: with those switches
/// untouched the behaviour matches Windows, where only the hold duration decides
/// whether the button locks.
@MainActor
@Observable
final class Preferences {

    /// Range of the Short ↔ Long slider, in seconds.
    static let holdRange: ClosedRange<TimeInterval> = 0.2...2.2
    static let defaultHold: TimeInterval = 1.0

    private enum Key {
        static let enabled = "enabled"
        static let holdDuration = "holdDuration"
        static let showCursorRing = "showCursorRing"
        static let rightButtonEnabled = "rightButtonEnabled"
        static let cancelOnMovement = "cancelOnMovement"
        static let movementTolerance = "movementTolerance"
        static let escapeReleases = "escapeReleases"
        static let autoReleaseEnabled = "autoReleaseEnabled"
        static let autoReleaseAfter = "autoReleaseAfter"
    }

    private let defaults: UserDefaults

    var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    var holdDuration: TimeInterval { didSet { defaults.set(holdDuration, forKey: Key.holdDuration) } }
    var showCursorRing: Bool { didSet { defaults.set(showCursorRing, forKey: Key.showCursorRing) } }
    var rightButtonEnabled: Bool { didSet { defaults.set(rightButtonEnabled, forKey: Key.rightButtonEnabled) } }
    var cancelOnMovement: Bool { didSet { defaults.set(cancelOnMovement, forKey: Key.cancelOnMovement) } }
    var movementTolerance: Double { didSet { defaults.set(movementTolerance, forKey: Key.movementTolerance) } }
    var escapeReleases: Bool { didSet { defaults.set(escapeReleases, forKey: Key.escapeReleases) } }
    var autoReleaseEnabled: Bool { didSet { defaults.set(autoReleaseEnabled, forKey: Key.autoReleaseEnabled) } }
    var autoReleaseAfter: TimeInterval { didSet { defaults.set(autoReleaseAfter, forKey: Key.autoReleaseAfter) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: false,
            Key.holdDuration: Preferences.defaultHold,
            Key.showCursorRing: true,
            Key.rightButtonEnabled: false,
            Key.cancelOnMovement: false,
            Key.movementTolerance: 5.0,
            Key.escapeReleases: false,
            Key.autoReleaseEnabled: false,
            Key.autoReleaseAfter: 10.0,
        ])

        enabled = defaults.bool(forKey: Key.enabled)
        holdDuration = defaults.double(forKey: Key.holdDuration)
        showCursorRing = defaults.bool(forKey: Key.showCursorRing)
        rightButtonEnabled = defaults.bool(forKey: Key.rightButtonEnabled)
        cancelOnMovement = defaults.bool(forKey: Key.cancelOnMovement)
        movementTolerance = defaults.double(forKey: Key.movementTolerance)
        escapeReleases = defaults.bool(forKey: Key.escapeReleases)
        autoReleaseEnabled = defaults.bool(forKey: Key.autoReleaseEnabled)
        autoReleaseAfter = defaults.double(forKey: Key.autoReleaseAfter)
    }

    var engineConfig: EngineConfig {
        EngineConfig(
            holdDuration: holdDuration,
            rightButtonEnabled: rightButtonEnabled,
            cancelOnMovement: cancelOnMovement,
            movementTolerance: movementTolerance,
            escapeReleases: escapeReleases,
            autoReleaseEnabled: autoReleaseEnabled,
            autoReleaseAfter: autoReleaseAfter
        )
    }
}
