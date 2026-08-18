// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit
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

    static let thicknessRange: ClosedRange<Double> = 1...8
    static let radiusRange: ClosedRange<Double> = 8...30
    static let appearDelayRange: ClosedRange<TimeInterval> = 0...0.5
    static let fadeDurationRange: ClosedRange<TimeInterval> = 0...0.4

    private enum Key {
        static let enabled = "enabled"
        static let holdDuration = "holdDuration"
        static let showCursorRing = "showCursorRing"
        static let ringColorHex = "ringColorHex"
        static let ringThickness = "ringThickness"
        static let ringRadius = "ringRadius"
        static let ringAppearDelay = "ringAppearDelay"
        static let ringFadeDuration = "ringFadeDuration"
        static let ringOutline = "ringOutline"
        static let soundEnabled = "soundEnabled"
        static let soundVolume = "soundVolume"
        static let lockSoundName = "lockSoundName"
        static let releaseSoundName = "releaseSoundName"
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
    var ringColorHex: String { didSet { defaults.set(ringColorHex, forKey: Key.ringColorHex) } }
    var ringThickness: Double { didSet { defaults.set(ringThickness, forKey: Key.ringThickness) } }
    var ringRadius: Double { didSet { defaults.set(ringRadius, forKey: Key.ringRadius) } }
    var ringAppearDelay: TimeInterval { didSet { defaults.set(ringAppearDelay, forKey: Key.ringAppearDelay) } }
    var ringFadeDuration: TimeInterval { didSet { defaults.set(ringFadeDuration, forKey: Key.ringFadeDuration) } }
    var ringOutline: Bool { didSet { defaults.set(ringOutline, forKey: Key.ringOutline) } }
    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }
    var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: Key.soundVolume) } }
    var lockSoundName: String { didSet { defaults.set(lockSoundName, forKey: Key.lockSoundName) } }
    var releaseSoundName: String { didSet { defaults.set(releaseSoundName, forKey: Key.releaseSoundName) } }
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
            Key.ringColorHex: "#FFFFFFFF",
            Key.ringThickness: 3.0,
            Key.ringRadius: 13.0,
            Key.ringAppearDelay: 0.15,
            Key.ringFadeDuration: 0.12,
            Key.ringOutline: true,
            Key.soundEnabled: true,
            Key.soundVolume: 0.5,
            Key.lockSoundName: "Tink",
            Key.releaseSoundName: "Pop",
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
        ringColorHex = defaults.string(forKey: Key.ringColorHex) ?? "#FFFFFFFF"
        ringThickness = defaults.double(forKey: Key.ringThickness)
        ringRadius = defaults.double(forKey: Key.ringRadius)
        ringAppearDelay = defaults.double(forKey: Key.ringAppearDelay)
        ringFadeDuration = defaults.double(forKey: Key.ringFadeDuration)
        ringOutline = defaults.bool(forKey: Key.ringOutline)
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        soundVolume = defaults.double(forKey: Key.soundVolume)
        lockSoundName = defaults.string(forKey: Key.lockSoundName) ?? "Tink"
        releaseSoundName = defaults.string(forKey: Key.releaseSoundName) ?? "Pop"
        rightButtonEnabled = defaults.bool(forKey: Key.rightButtonEnabled)
        cancelOnMovement = defaults.bool(forKey: Key.cancelOnMovement)
        movementTolerance = defaults.double(forKey: Key.movementTolerance)
        escapeReleases = defaults.bool(forKey: Key.escapeReleases)
        autoReleaseEnabled = defaults.bool(forKey: Key.autoReleaseEnabled)
        autoReleaseAfter = defaults.double(forKey: Key.autoReleaseAfter)
    }

    var ringStyle: RingStyle {
        RingStyle(
            color: NSColor.fromHex(ringColorHex) ?? .white,
            thickness: ringThickness,
            radius: ringRadius,
            outline: ringOutline,
            appearDelay: ringAppearDelay,
            fadeDuration: ringFadeDuration
        )
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
