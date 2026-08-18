// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit
import QuartzCore

/// A white ring drawn around the pointer.
///
/// While a button is held the ring fills up as a progress arc towards the
/// threshold; once locked it is a closed ring. It lives in a borderless,
/// click-through window that follows the pointer, driven by a display link
/// rather than by the event tap — the tap has to stay fast, and this way the arc
/// keeps filling even when the mouse is not moving.
@MainActor
final class CursorOverlay {

    enum Mode: Equatable {
        case holding(started: Date, target: TimeInterval)
        case locked
    }

    /// Do not show anything for very short clicks.
    static let minimumVisibleHold: TimeInterval = 0.15

    private let windowSize: CGFloat = 64

    private var panel: NSPanel?
    private var ringView: RingView?
    private var displayLink: CADisplayLink?

    /// Brings the ring in line with the current state of the lock.
    func update(status: ClickLockStatus, holdDuration: TimeInterval, enabled: Bool) {
        guard enabled else {
            hide()
            return
        }

        switch status.phase {
        case .locked:
            show(mode: .locked)
        case .pressed:
            if let started = status.pressStarted {
                show(mode: .holding(started: started, target: holdDuration))
            } else {
                hide()
            }
        case .idle:
            hide()
        }
    }

    func hide() {
        displayLink?.invalidate()
        displayLink = nil
        panel?.orderOut(nil)
    }

    private func show(mode: Mode) {
        let panel = makePanelIfNeeded()
        ringView?.mode = mode
        ringView?.needsDisplay = true

        moveToPointer()
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        startDisplayLink()
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let frame = NSRect(x: 0, y: 0, width: windowSize, height: windowSize)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true      // clicks pass straight through
        panel.level = .screenSaver           // stay on top of everything
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let view = RingView(frame: frame)
        panel.contentView = view

        self.panel = panel
        ringView = view
        return panel
    }

    private func startDisplayLink() {
        guard displayLink == nil, let ringView else { return }
        let link = ringView.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        moveToPointer()
        // The closed ring is static; only a filling arc needs redrawing.
        if case .holding = ringView?.mode {
            ringView?.needsDisplay = true
        }
    }

    private func moveToPointer() {
        let pointer = NSEvent.mouseLocation
        panel?.setFrameOrigin(
            NSPoint(x: pointer.x - windowSize / 2, y: pointer.y - windowSize / 2)
        )
    }
}

private final class RingView: NSView {

    var mode: CursorOverlay.Mode = .locked

    private let radius: CGFloat = 13
    private let lineWidth: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        switch mode {
        case .locked:
            stroke(fraction: 1)
        case .holding(let started, let target):
            let elapsed = Date().timeIntervalSince(started)
            guard elapsed >= CursorOverlay.minimumVisibleHold else { return }
            stroke(fraction: min(elapsed / max(target, 0.01), 1))
        }
    }

    /// Draws the arc twice: a dark stroke underneath plus a soft shadow keeps the
    /// white ring readable on a light background too.
    private func stroke(fraction: Double) {
        guard fraction > 0 else { return }

        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * fraction,
            clockwise: true
        )
        path.lineCapStyle = .round

        path.lineWidth = lineWidth + 3
        NSColor.black.withAlphaComponent(0.45).setStroke()
        path.stroke()

        NSGraphicsContext.saveGraphicsState()
        let halo = NSShadow()
        halo.shadowColor = NSColor.black.withAlphaComponent(0.5)
        halo.shadowBlurRadius = 3
        halo.shadowOffset = .zero
        halo.set()
        path.lineWidth = lineWidth
        NSColor.white.setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
