// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit

/// Plays a short system sound when the button locks and when it lets go.
///
/// `NSSound` is used rather than `AudioServicesPlaySystemSound` because it is the
/// only one of the two with a volume control.
@MainActor
final class SoundFeedback {

    private var cache: [String: NSSound] = [:]

    /// The same list macOS itself shows: every sound file in the standard sound
    /// folders, by name.
    static func availableSounds() -> [String] {
        let extensions: Set<String> = ["aiff", "aif", "caf", "wav", "m4a"]
        let folders = [
            "/System/Library/Sounds",
            "/Library/Sounds",
            NSHomeDirectory() + "/Library/Sounds",
        ]

        var names = Set<String>()
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for file in files where extensions.contains((file as NSString).pathExtension.lowercased()) {
                names.insert((file as NSString).deletingPathExtension)
            }
        }
        return names.sorted()
    }

    /// Reuses one `NSSound` per name and restarts it, so clicking in quick
    /// succession cuts the previous sound off instead of stacking sounds up.
    func play(named name: String, volume: Double) {
        guard let sound = sound(named: name) else { return }
        sound.stop()
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
    }

    private func sound(named name: String) -> NSSound? {
        if let cached = cache[name] { return cached }
        guard let sound = NSSound(named: name) else { return nil }
        cache[name] = sound
        return sound
    }
}
