// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit

/// Colours travel to UserDefaults as `#RRGGBBAA` text. One place for the
/// conversion, so the drawing code (AppKit) and the colour well (SwiftUI) can
/// never drift apart.
extension NSColor {

    /// Accepts `#RRGGBB` and `#RRGGBBAA`, with or without the leading `#`.
    static func fromHex(_ hex: String) -> NSColor? {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt64(digits, radix: 16)
        else { return nil }

        let hasAlpha = digits.count == 8
        let shift = hasAlpha ? 8 : 0
        let component = { (offset: Int) in
            CGFloat((value >> UInt64(offset + shift)) & 0xFF) / 255
        }

        return NSColor(
            srgbRed: component(16),
            green: component(8),
            blue: component(0),
            alpha: hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        )
    }

    /// Always eight digits, so the alpha survives a round trip.
    var hexString: String {
        // Converting first: a colour from a picker can be in any colour space,
        // and reading components off it directly would trap.
        guard let rgb = usingColorSpace(.sRGB) else { return "#FFFFFFFF" }
        let channel = { (value: CGFloat) in Int((value * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X%02X",
            channel(rgb.redComponent),
            channel(rgb.greenComponent),
            channel(rgb.blueComponent),
            channel(rgb.alphaComponent)
        )
    }
}
