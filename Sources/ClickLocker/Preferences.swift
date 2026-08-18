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

    /// The factory values. Single source for both the UserDefaults registration
    /// and the reset buttons, so a reset can never land on a different value than
    /// a fresh install would.
    enum Defaults {
        static let enabled = false
        static let holdDuration: TimeInterval = 1.0
        static let showCursorRing = true
        static let ringColorHex = "#FFFFFFFF"
        static let ringThickness: Double = 3
        static let ringRadius: Double = 13
        static let ringAppearDelay: TimeInterval = 0.15
        static let ringFadeDuration: TimeInterval = 0.12
        static let ringOutline = true
        static let ringPulseOnLock = true
        static let soundEnabled = true
        static let soundVolume: Double = 0.5
        static let lockSoundName = "Tink"
        static let releaseSoundName = "Pop"
        static let rightButtonEnabled = false
        static let cancelOnMovement = false
        static let movementTolerance: Double = 5
        static let escapeReleases = false
        static let autoReleaseEnabled = false
        static let autoReleaseAfter: TimeInterval = 10
        static let checkForUpdates = true
    }

    /// Range of the Short ↔ Long slider, in seconds.
    static let holdRange: ClosedRange<TimeInterval> = 0.2...2.2

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
        static let ringPulseOnLock = "ringPulseOnLock"
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
        static let checkForUpdates = "checkForUpdates"
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
    var ringPulseOnLock: Bool { didSet { defaults.set(ringPulseOnLock, forKey: Key.ringPulseOnLock) } }
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
    var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: Key.checkForUpdates) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: Defaults.enabled,
            Key.holdDuration: Defaults.holdDuration,
            Key.showCursorRing: Defaults.showCursorRing,
            Key.ringColorHex: Defaults.ringColorHex,
            Key.ringThickness: Defaults.ringThickness,
            Key.ringRadius: Defaults.ringRadius,
            Key.ringAppearDelay: Defaults.ringAppearDelay,
            Key.ringFadeDuration: Defaults.ringFadeDuration,
            Key.ringOutline: Defaults.ringOutline,
            Key.ringPulseOnLock: Defaults.ringPulseOnLock,
            Key.soundEnabled: Defaults.soundEnabled,
            Key.soundVolume: Defaults.soundVolume,
            Key.lockSoundName: Defaults.lockSoundName,
            Key.releaseSoundName: Defaults.releaseSoundName,
            Key.rightButtonEnabled: Defaults.rightButtonEnabled,
            Key.cancelOnMovement: Defaults.cancelOnMovement,
            Key.movementTolerance: Defaults.movementTolerance,
            Key.escapeReleases: Defaults.escapeReleases,
            Key.autoReleaseEnabled: Defaults.autoReleaseEnabled,
            Key.autoReleaseAfter: Defaults.autoReleaseAfter,
            Key.checkForUpdates: Defaults.checkForUpdates,
        ])

        enabled = defaults.bool(forKey: Key.enabled)
        holdDuration = defaults.double(forKey: Key.holdDuration)
        showCursorRing = defaults.bool(forKey: Key.showCursorRing)
        ringColorHex = defaults.string(forKey: Key.ringColorHex) ?? Defaults.ringColorHex
        ringThickness = defaults.double(forKey: Key.ringThickness)
        ringRadius = defaults.double(forKey: Key.ringRadius)
        ringAppearDelay = defaults.double(forKey: Key.ringAppearDelay)
        ringFadeDuration = defaults.double(forKey: Key.ringFadeDuration)
        ringOutline = defaults.bool(forKey: Key.ringOutline)
        ringPulseOnLock = defaults.bool(forKey: Key.ringPulseOnLock)
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        soundVolume = defaults.double(forKey: Key.soundVolume)
        lockSoundName = defaults.string(forKey: Key.lockSoundName) ?? Defaults.lockSoundName
        releaseSoundName = defaults.string(forKey: Key.releaseSoundName) ?? Defaults.releaseSoundName
        rightButtonEnabled = defaults.bool(forKey: Key.rightButtonEnabled)
        cancelOnMovement = defaults.bool(forKey: Key.cancelOnMovement)
        movementTolerance = defaults.double(forKey: Key.movementTolerance)
        escapeReleases = defaults.bool(forKey: Key.escapeReleases)
        autoReleaseEnabled = defaults.bool(forKey: Key.autoReleaseEnabled)
        autoReleaseAfter = defaults.double(forKey: Key.autoReleaseAfter)
        checkForUpdates = defaults.bool(forKey: Key.checkForUpdates)
    }

    /// Puts every setting back to its factory value.
    ///
    /// Two things are deliberately left alone: whether the lock is switched on,
    /// and the login item. Those are not taste, they are "is it running" — and a
    /// reset that turns the app off underneath you is unpleasant.
    func restoreFactorySettings() {
        holdDuration = Defaults.holdDuration
        showCursorRing = Defaults.showCursorRing
        ringColorHex = Defaults.ringColorHex
        ringThickness = Defaults.ringThickness
        ringRadius = Defaults.ringRadius
        ringAppearDelay = Defaults.ringAppearDelay
        ringFadeDuration = Defaults.ringFadeDuration
        ringOutline = Defaults.ringOutline
        ringPulseOnLock = Defaults.ringPulseOnLock
        soundEnabled = Defaults.soundEnabled
        soundVolume = Defaults.soundVolume
        lockSoundName = Defaults.lockSoundName
        releaseSoundName = Defaults.releaseSoundName
        rightButtonEnabled = Defaults.rightButtonEnabled
        cancelOnMovement = Defaults.cancelOnMovement
        movementTolerance = Defaults.movementTolerance
        escapeReleases = Defaults.escapeReleases
        autoReleaseEnabled = Defaults.autoReleaseEnabled
        autoReleaseAfter = Defaults.autoReleaseAfter
        checkForUpdates = Defaults.checkForUpdates
    }

    var ringStyle: RingStyle {
        RingStyle(
            color: NSColor.fromHex(ringColorHex) ?? .white,
            thickness: ringThickness,
            radius: ringRadius,
            outline: ringOutline,
            pulseOnLock: ringPulseOnLock,
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
