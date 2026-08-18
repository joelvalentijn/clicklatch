// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit
import QuartzCore

/// Everything about how the ring looks and how quickly it turns up.
struct RingStyle: Equatable {
    var color: NSColor = .white
    var thickness: CGFloat = 3
    var radius: CGFloat = 13
    var outline = true
    /// How long a button must be held before the ring shows at all.
    var appearDelay: TimeInterval = 0.15
    /// Fade-in and fade-out time; zero means it simply appears.
    var fadeDuration: TimeInterval = 0.12

    /// Room for the ring plus its outline and shadow.
    var windowSize: CGFloat { 2 * (radius + thickness + 6) }
}

/// A ring drawn around the pointer.
///
/// While a button is held it fills up as a progress arc towards the threshold;
/// once locked it is a closed ring. It lives in a borderless, click-through
/// window that follows the pointer, driven by a display link rather than by the
/// event tap — the tap has to stay fast, and this way the arc keeps filling even
/// when the mouse is not moving.
@MainActor
final class CursorOverlay {

    private enum Mode: Equatable {
        case holding(started: Date, target: TimeInterval)
        case locked
    }

    private var panel: NSPanel?
    private var ringView: RingView?
    private var displayLink: CADisplayLink?

    private var style = RingStyle()
    private var mode: Mode = .locked
    /// Whether the ring is wanted right now. Distinct from the window still being
    /// on screen, which stays true throughout a fade-out.
    private var isShowing = false
    /// False while a press is still shorter than `appearDelay`.
    private var revealed = false
    /// Guards against a finished fade-out hiding a window that is visible again.
    private var fadeGeneration = 0

    /// Brings the ring in line with the current state of the lock.
    func update(status: ClickLockStatus, holdDuration: TimeInterval, style: RingStyle, enabled: Bool) {
        applyStyle(style)

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

    func hide(animated: Bool = true) {
        // Clearing these first matters: the display link keeps ticking during the
        // fade-out, and without it the reveal check below would still fire and
        // pull a ring back in that nobody asked for.
        isShowing = false
        revealed = false

        guard let panel, panel.isVisible else {
            stopDisplayLink()
            return
        }
        fade(to: 0, animated: animated, hideWhenDone: true)
    }

    private func show(mode newMode: Mode) {
        let panel = makePanelIfNeeded()
        mode = newMode

        if !isShowing {
            isShowing = true
            revealed = false
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        moveToPointer()
        startDisplayLink()
        refresh()
    }

    private func applyStyle(_ newStyle: RingStyle) {
        guard newStyle != style else { return }
        let resized = newStyle.windowSize != style.windowSize
        style = newStyle
        ringView?.style = newStyle

        if resized, let panel {
            let size = NSSize(width: newStyle.windowSize, height: newStyle.windowSize)
            panel.setContentSize(size)
            ringView?.frame = NSRect(origin: .zero, size: size)
            moveToPointer()
        }
        ringView?.needsDisplay = true
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let frame = NSRect(x: 0, y: 0, width: style.windowSize, height: style.windowSize)
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
        view.style = style
        panel.contentView = view

        self.panel = panel
        ringView = view
        return panel
    }

    /// Animates the window's opacity, or sets it outright when the fade time is
    /// zero. The generation counter keeps a finished fade from acting on a state
    /// that has since moved on.
    private func fade(to alpha: CGFloat, animated: Bool = true, hideWhenDone: Bool = false) {
        guard let panel else { return }
        fadeGeneration += 1
        let generation = fadeGeneration

        guard animated, style.fadeDuration > 0 else {
            panel.alphaValue = alpha
            if hideWhenDone { finishHiding() }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = style.fadeDuration
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated {
                // A newer fade means the state moved on and this one no longer applies.
                guard self.fadeGeneration == generation, hideWhenDone else { return }
                self.finishHiding()
            }
        }
    }

    private func finishHiding() {
        panel?.orderOut(nil)
        stopDisplayLink()
    }

    private func startDisplayLink() {
        guard displayLink == nil, let ringView else { return }
        let link = ringView.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        moveToPointer()
        refresh()
    }

    /// Recomputes how full the arc is and reveals the ring once the press has
    /// lasted longer than the configured delay.
    private func refresh() {
        guard isShowing, let ringView else { return }

        switch mode {
        case .locked:
            // A lock is always worth showing, even if the hold was shorter than
            // the delay.
            if !revealed {
                revealed = true
                fade(to: 1)
            }
            ringView.fraction = 1
            ringView.needsDisplay = true

        case .holding(let started, let target):
            let elapsed = Date().timeIntervalSince(started)
            if !revealed {
                guard elapsed >= style.appearDelay else { return }
                revealed = true
                fade(to: 1)
            }
            ringView.fraction = min(elapsed / max(target, 0.01), 1)
            ringView.needsDisplay = true
        }
    }

    private func moveToPointer() {
        let pointer = NSEvent.mouseLocation
        let half = style.windowSize / 2
        panel?.setFrameOrigin(NSPoint(x: pointer.x - half, y: pointer.y - half))
    }
}

/// Draws the ring itself. Shared with the settings window so the live preview
/// cannot drift away from what actually appears on screen.
final class RingView: NSView {

    var style = RingStyle() { didSet { needsDisplay = true } }
    /// How much of the circle to draw, 0 through 1.
    var fraction: Double = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard fraction > 0 else { return }

        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
            radius: style.radius,
            startAngle: 90,
            endAngle: 90 - 360 * fraction,
            clockwise: true
        )
        path.lineCapStyle = .round

        // A dark stroke underneath plus a soft shadow keeps a light ring readable
        // on a light background.
        if style.outline {
            path.lineWidth = style.thickness + 3
            NSColor.black.withAlphaComponent(0.45).setStroke()
            path.stroke()

            NSGraphicsContext.saveGraphicsState()
            let halo = NSShadow()
            halo.shadowColor = NSColor.black.withAlphaComponent(0.5)
            halo.shadowBlurRadius = 3
            halo.shadowOffset = .zero
            halo.set()
            strokeRing(path)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            strokeRing(path)
        }
    }

    private func strokeRing(_ path: NSBezierPath) {
        path.lineWidth = style.thickness
        style.color.setStroke()
        path.stroke()
    }
}
