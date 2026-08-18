// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import CoreGraphics
import Foundation

/// Where the lock currently stands.
enum ClickLockPhase: Sendable, Equatable {
    /// No button held and nothing locked.
    case idle
    /// A button is physically held down; the threshold has not been reached yet.
    case pressed
    /// The button was released but stays down as far as the system is concerned.
    case locked
}

/// Snapshot the engine hands to the interface.
struct ClickLockStatus: Sendable {
    var phase: ClickLockPhase = .idle
    /// When the current press started; `nil` unless a button is being held.
    var pressStarted: Date?
    /// How long the last completed press lasted, in milliseconds.
    var lastHoldMilliseconds: Double?
    /// Whether the event tap is actually running.
    var tapActive = false
    /// Message explaining why the tap could not be installed.
    var failure: String?
}

/// Settings as the engine consumes them. Kept separate from `Preferences` so the
/// values can travel safely from the main thread to the tap thread.
struct EngineConfig: Sendable, Equatable {
    var holdDuration: TimeInterval = 1.0
    var rightButtonEnabled = false
    var cancelOnMovement = false
    var movementTolerance: CGFloat = 5
    var escapeReleases = false
    var autoReleaseEnabled = false
    var autoReleaseAfter: TimeInterval = 10

    /// Only these two decide which events the tap must see, so only they force a
    /// new tap.
    func needsSameTapMask(as other: EngineConfig) -> Bool {
        rightButtonEnabled == other.rightButtonEnabled && escapeReleases == other.escapeReleases
    }
}

/// Reproduces the Windows ClickLock behaviour by rewriting mouse events.
///
/// All event handling runs on a dedicated thread with its own run loop so a busy
/// main thread can never make the tap time out. The main thread talks to it by
/// scheduling blocks on that run loop.
final class ClickLockEngine: @unchecked Sendable {

    private enum State {
        case idle
        case pressed(button: CGMouseButton, downTime: CFAbsoluteTime, origin: CGPoint, moved: Bool)
        case locked(button: CGMouseButton)
        /// The releasing click was handled; its physical mouseUp still has to be swallowed.
        case releasing(button: CGMouseButton)
    }

    private let escapeKeyCode: Int64 = 53

    private let onStatus: @Sendable (ClickLockStatus) -> Void

    private let lock = NSLock()
    private var storedConfig = EngineConfig()
    private var storedRunning = false

    // Everything below is touched on the tap thread only.
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var state: State = .idle
    private var autoReleaseTimer: CFRunLoopTimer?
    private var status = ClickLockStatus()

    private var tapRunLoop: CFRunLoop?
    private let runLoopReady = DispatchSemaphore(value: 0)

    init(onStatus: @escaping @Sendable (ClickLockStatus) -> Void) {
        self.onStatus = onStatus
        startThread()
    }

    // MARK: - Driven from the main thread

    /// Turns the lock on or off and hands over the latest settings.
    func update(config: EngineConfig, running: Bool) {
        let (oldConfig, wasRunning) = lock.withLock {
            let previous = (storedConfig, storedRunning)
            storedConfig = config
            storedRunning = running
            return previous
        }

        let maskChanged = !oldConfig.needsSameTapMask(as: config)
        perform { [weak self] in
            guard let self else { return }
            if !running {
                self.teardownTap()
            } else if !wasRunning || self.tap == nil {
                self.setUpTap()
            } else if maskChanged {
                self.teardownTap()
                self.setUpTap()
            }
        }
    }

    /// Cleans up on quit: remove the tap and let go of any active lock.
    func shutDown() {
        lock.withLock { storedRunning = false }
        perform { [weak self] in
            self?.teardownTap()
        }
    }

    private var config: EngineConfig { lock.withLock { storedConfig } }

    // MARK: - Tap thread

    private func startThread() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            self.runLoopReady.signal()

            // An empty source keeps the run loop alive while there is no tap.
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            if let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, .commonModes)
            }
            CFRunLoopRun()
        }
        thread.name = "com.joelintveld.clicklocker.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        runLoopReady.wait()
    }

    /// Runs a block on the tap thread.
    private func perform(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop = tapRunLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    private func setUpTap() {
        guard tap == nil else { return }
        let current = config

        var mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)

        if current.rightButtonEnabled {
            mask |= (1 << CGEventType.rightMouseDown.rawValue)
                | (1 << CGEventType.rightMouseUp.rawValue)
                | (1 << CGEventType.rightMouseDragged.rawValue)
        }
        // Only listen in on keys while the Escape shortcut is switched on.
        if current.escapeReleases {
            mask |= (1 << CGEventType.keyDown.rawValue)
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: clickLockTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status.tapActive = false
            status.failure = "Could not create an event tap. Grant ClickLocker the Accessibility "
                + "permission in System Settings and try again."
            publish()
            return
        }

        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        tap = newTap
        source = newSource
        state = .idle
        status.tapActive = true
        status.failure = nil
        status.phase = .idle
        status.pressStarted = nil
        publish()
    }

    private func teardownTap() {
        releaseLockIfNeeded()
        cancelAutoRelease()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        source = nil
        state = .idle

        status.tapActive = false
        status.phase = .idle
        status.pressStarted = nil
        publish()
    }

    // MARK: - Event handling (tap thread)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches off a tap that was too slow, without asking.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil

        case .leftMouseDown:
            return handleDown(button: .left, event: event)
        case .rightMouseDown:
            return handleDown(button: .right, event: event)

        case .leftMouseUp:
            return handleUp(button: .left, event: event)
        case .rightMouseUp:
            return handleUp(button: .right, event: event)

        case .leftMouseDragged:
            return handleDragged(button: .left, event: event)
        case .rightMouseDragged:
            return handleDragged(button: .right, event: event)

        case .mouseMoved:
            return handleMoved(event: event)

        case .keyDown:
            return handleKeyDown(event: event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleDown(button: CGMouseButton, event: CGEvent) -> Unmanaged<CGEvent>? {
        if case .locked(let locked) = state, locked == button {
            // The releasing click: turn this very event into the mouseUp we held
            // back, so the app receives it at the right place and time.
            event.type = button == .left ? .leftMouseUp : .rightMouseUp
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            state = .releasing(button: button)
            cancelAutoRelease()
            status.phase = .idle
            status.pressStarted = nil
            publish()
            return Unmanaged.passUnretained(event)
        }

        if case .idle = state {
            state = .pressed(
                button: button,
                downTime: CFAbsoluteTimeGetCurrent(),
                origin: event.location,
                moved: false
            )
            status.phase = .pressed
            status.pressStarted = Date()
            publish()
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleUp(button: CGMouseButton, event: CGEvent) -> Unmanaged<CGEvent>? {
        if case .releasing(let releasing) = state, releasing == button {
            // Belongs to the releasing click; the app already got its mouseUp.
            state = .idle
            return nil
        }

        guard case .pressed(let pressed, let downTime, _, let moved) = state, pressed == button else {
            return Unmanaged.passUnretained(event)
        }

        let current = config
        let held = CFAbsoluteTimeGetCurrent() - downTime
        status.lastHoldMilliseconds = held * 1000
        status.pressStarted = nil

        let blockedByMovement = current.cancelOnMovement && moved
        if held >= current.holdDuration && !blockedByMovement {
            state = .locked(button: button)
            status.phase = .locked
            publish()
            scheduleAutoRelease()
            return nil  // swallow the mouseUp: the button stays logically down
        }

        state = .idle
        status.phase = .idle
        publish()
        return Unmanaged.passUnretained(event)
    }

    private func handleDragged(button: CGMouseButton, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch state {
        case .pressed(let pressed, let downTime, let origin, let moved) where pressed == button:
            if !moved, config.cancelOnMovement {
                let dx = event.location.x - origin.x
                let dy = event.location.y - origin.y
                let tolerance = config.movementTolerance
                if (dx * dx + dy * dy) > (tolerance * tolerance) {
                    state = .pressed(button: button, downTime: downTime, origin: origin, moved: true)
                }
            }
            return Unmanaged.passUnretained(event)

        case .releasing(let releasing) where releasing == button:
            // The button is still physically down, but the app thinks otherwise.
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleMoved(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard case .locked(let button) = state else {
            return Unmanaged.passUnretained(event)
        }
        // Without this rewrite an app sees loose movement instead of a drag.
        event.type = button == .left ? .leftMouseDragged : .rightMouseDragged
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setDoubleValueField(.mouseEventPressure, value: 1.0)
        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard config.escapeReleases,
              case .locked = state,
              event.getIntegerValueField(.keyboardEventKeycode) == escapeKeyCode
        else {
            return Unmanaged.passUnretained(event)  // every other key: untouched
        }
        releaseLockIfNeeded()
        return nil
    }

    // MARK: - Releasing

    /// Sends a mouseUp if something is still locked, so a mouse button can never
    /// be left hanging.
    private func releaseLockIfNeeded() {
        guard case .locked(let button) = state else { return }
        state = .idle
        cancelAutoRelease()

        let location = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        if let up = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) {
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            up.post(tap: .cgSessionEventTap)
        }

        status.phase = .idle
        status.pressStarted = nil
        publish()
    }

    private func scheduleAutoRelease() {
        cancelAutoRelease()
        let current = config
        guard current.autoReleaseEnabled else { return }

        let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + current.autoReleaseAfter,
            0,
            0,
            0
        ) { [weak self] _ in
            self?.releaseLockIfNeeded()
        }
        autoReleaseTimer = timer
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
    }

    private func cancelAutoRelease() {
        if let autoReleaseTimer {
            CFRunLoopTimerInvalidate(autoReleaseTimer)
        }
        autoReleaseTimer = nil
    }

    private func publish() {
        let snapshot = status
        onStatus(snapshot)
    }
}

private func clickLockTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<ClickLockEngine>.fromOpaque(refcon).takeUnretainedValue()
    return engine.handle(type: type, event: event)
}
