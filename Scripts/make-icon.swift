#!/usr/bin/env swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld
//
// Draws the app icon and writes Resources/AppIcon.icns.
//
//   swift Scripts/make-icon.swift
//
// The icon is generated rather than checked in as an opaque image so anyone can
// see how it was made and change it. The motif is the app's own: the ring that
// appears around the pointer when the button locks, with the pointer inside it.

import AppKit

// Everything is expressed as a fraction of the canvas, so one drawing serves
// every size from 16 to 1024 points.
enum Layout {
    /// Apple's macOS grid: an 824 pt rounded square on a 1024 pt canvas.
    static let inset: CGFloat = 100 / 1024
    static let cornerRadius: CGFloat = 185.4 / 1024

    static let ringRadius: CGFloat = 0.25
    static let ringStroke: CGFloat = 0.05
    /// Length of the pointer from tip to tail. Kept small enough that the arrow
    /// and its white border sit inside the ring with air around them: tip and
    /// tail run diagonally, so they reach further than the height suggests.
    static let pointerHeight: CGFloat = 0.27
    /// White border around the black arrow, as a fraction of its height.
    static let pointerBorder: CGFloat = 0.16
}

func drawIcon(size: CGFloat, in context: CGContext) {
    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let plate = rect.insetBy(dx: size * Layout.inset, dy: size * Layout.inset)

    // Background: a dark slate plate, because the ring is white and has to carry
    // the icon at 16 pt just as well as at 512.
    let shape = NSBezierPath(
        roundedRect: plate,
        xRadius: size * Layout.cornerRadius,
        yRadius: size * Layout.cornerRadius
    )
    NSGradient(
        colors: [
            NSColor(srgbRed: 0.24, green: 0.26, blue: 0.32, alpha: 1),
            NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1),
        ]
    )?.draw(in: shape, angle: -90)

    // A hairline along the top edge, the usual trick to keep a dark plate from
    // looking flat.
    shape.lineWidth = max(size * 0.004, 0.5)
    NSColor(white: 1, alpha: 0.16).setStroke()
    shape.stroke()

    let centre = CGPoint(x: rect.midX, y: rect.midY)

    // At 16 pt the ring and the arrow together are barely a dozen pixels and turn
    // into a smudge. Below that threshold the ring carries the icon on its own,
    // drawn heavier so it still reads as a ring.
    let tiny = size < 24
    let radius = size * (tiny ? 0.27 : Layout.ringRadius)
    let stroke = max(size * (tiny ? 0.10 : Layout.ringStroke), 1)

    let ring = NSBezierPath(ovalIn: CGRect(
        x: centre.x - radius, y: centre.y - radius,
        width: radius * 2, height: radius * 2
    ))
    ring.lineWidth = stroke
    NSColor.white.setStroke()
    ring.stroke()

    if !tiny {
        drawPointer(size: size, centre: centre, context: context)
    }

    NSGraphicsContext.restoreGraphicsState()
}

/// The classic arrow, sitting inside the ring.
func drawPointer(size: CGFloat, centre: CGPoint, context: CGContext) {
    let height = size * Layout.pointerHeight

    // Unit outline of the arrow, tip at (0, 0), growing down and to the right.
    let outline: [(CGFloat, CGFloat)] = [
        (0, 0), (0, -0.74), (0.20, -0.56), (0.34, -0.86),
        (0.47, -0.80), (0.33, -0.51), (0.56, -0.50),
    ]

    let path = NSBezierPath()
    for (index, point) in outline.enumerated() {
        let location = CGPoint(
            x: centre.x + point.0 * height,
            y: centre.y + point.1 * height
        )
        if index == 0 { path.move(to: location) } else { path.line(to: location) }
    }
    path.close()

    // The macOS pointer is black with a white border, but only where there is
    // room for it. At 32 pt that border works out under one and a half pixels
    // and the black fill sinks into the dark plate, leaving a grey smudge; a
    // plain white arrow reads far better down there.
    let bordered = size >= 64
    let border = bordered ? height * Layout.pointerBorder : 0
    if bordered { path.lineWidth = border }

    // Centre on the ink, not on the path. Those are not the same thing: the tip
    // and the tail are sharp corners, and a mitred join runs the border well
    // past half a line width there. Anchoring on the path bounds left the arrow
    // sitting up and to the right of the ring's centre.
    var ink = path.cgPath.boundingBoxOfPath
    if bordered {
        let stroked = path.cgPath.copy(
            strokingWithWidth: border, lineCap: .butt, lineJoin: .miter, miterLimit: 10
        )
        ink = ink.union(stroked.boundingBoxOfPath)
    }
    path.transform(using: AffineTransform(
        m11: 1, m12: 0, m21: 0, m22: 1,
        tX: centre.x - ink.midX,
        tY: centre.y - ink.midY
    ))

    if bordered {
        // Stroking first and filling over it leaves the border entirely outside
        // the black, the way a cursor looks.
        NSColor.white.setStroke()
        path.stroke()
        NSColor.black.setFill()
        path.fill()
    } else {
        NSColor.white.setFill()
        path.fill()
    }
}

func renderPNG(size: CGFloat) -> Data? {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    drawIcon(size: size, in: context)
    guard let image = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

// MARK: - Writing the iconset

let root = URL(fileURLWithPath: CommandLine.arguments.first.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path
} ?? ".")
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let data = renderPNG(size: variant.size) else {
        print("could not render \(variant.name)")
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = [
    "-c", "icns", iconset.path,
    "-o", resources.appendingPathComponent("AppIcon.icns").path,
]
try convert.run()
convert.waitUntilExit()
guard convert.terminationStatus == 0 else {
    print("iconutil failed")
    exit(1)
}

try? FileManager.default.removeItem(at: iconset)
print("wrote \(resources.appendingPathComponent("AppIcon.icns").path)")
