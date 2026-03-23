import Cocoa
import CoreGraphics

// MARK: - HotkeyListener

/// Listens for global hotkeys (Caps Lock hold + arrows/numbers) and 3-finger swipe
/// gestures to drive the spatial pager.
///
/// - Caps Lock hold ≥ 200 ms → show pager overlay
/// - Arrow keys while Caps Lock held → navigate grid
/// - Number keys 1-9 while Caps Lock held → jump to cell
/// - Caps Lock release → dismiss pager (triggers Focus Collapse)
/// - 3-finger swipe → navigate grid + flash pager for 500 ms
final class HotkeyListener {

    // MARK: - Trigger Key Configuration

    /// The keycode that activates the pager (57 = Caps Lock).
    /// Change this single value to rebind the trigger key.
    private static let triggerKeyCode: Int64 = 57

    /// Returns true if the trigger key is currently pressed, based on CGEvent flags.
    private static func isTriggerDown(flags: CGEventFlags) -> Bool {
        flags.contains(.maskAlphaShift)
    }

    /// Returns true if an NSEvent is the trigger key being pressed.
    private static func isTriggerDown(event: NSEvent) -> Bool {
        event.keyCode == UInt16(triggerKeyCode) && event.modifierFlags.contains(.capsLock)
    }

    /// Returns true if an NSEvent is the trigger key being released.
    private static func isTriggerUp(event: NSEvent) -> Bool {
        event.keyCode == UInt16(triggerKeyCode) && !event.modifierFlags.contains(.capsLock)
    }

    // MARK: - Public properties

    /// Called with `true` to show the pager overlay, `false` to dismiss.
    var onPagerToggle: ((Bool) -> Void)?

    /// Called when the user navigates via arrow key or swipe.
    var onNavigate: ((Direction) -> Void)?

    // MARK: - Private state

    private let gridModel: GridModel
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureMonitor: Any?
    private var swipeMonitor: Any?

    /// Whether the pager overlay is currently visible.
    private(set) var isPagerVisible = false

    /// Whether the trigger key is currently held down.
    private var isTriggerHeld = false

    /// Timer that fires after the hold threshold (200 ms).
    private var holdTimer: DispatchSourceTimer?

    /// Timer used for the brief "flash" pager on swipe navigation.
    private var swipeFlashTimer: DispatchSourceTimer?

    /// Threshold before the pager is shown on trigger hold.
    private let holdDelay: TimeInterval = 0.2 // 200 ms

    /// Duration of the pager flash after a 3-finger swipe.
    private let swipeFlashDuration: TimeInterval = 0.5 // 500 ms

    /// Custom userData value we stamp on our own simulated events so the tap
    /// can recognise and ignore them (prevents feedback loops).
    static let selfGeneratedMarker: Int64 = 0x4E5256_4E41 // "NRVNA"

    // MARK: - Init

    /// Debug log file for event monitoring (NSLog doesn't reliably show in unified log).
    private static let debugLog: FileHandle? = {
        let path = "/tmp/nirvana-events.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    private func debugLog(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        HotkeyListener.debugLog?.seekToEndOfFile()
        HotkeyListener.debugLog?.write(line.data(using: .utf8)!)
    }

    init(gridModel: GridModel) {
        self.gridModel = gridModel
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Global monitors for flagsChanged and keyDown as fallback.
    private var flagsMonitor: Any?
    private var keyMonitor: Any?

    /// Begin listening for hotkeys and gestures.
    func start() {
        installEventTap()
        installGlobalMonitors()
        installGestureMonitor()
    }

    /// Stop all listeners and clean up resources.
    func stop() {
        removeEventTap()
        removeGlobalMonitors()
        removeGestureMonitor()
        cancelHoldTimer()
        cancelSwipeFlashTimer()
        isPagerVisible = false
        isTriggerHeld = false
    }

    // MARK: - CGEventTap

    private func installEventTap() {
        NSLog("[HotkeyListener] Installing event tap... AXIsProcessTrusted=%d", AXIsProcessTrusted() ? 1 : 0)

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()

        // Use .defaultTap so we can swallow Caps Lock events (prevent actual caps toggle).
        var tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventCallback,
            userInfo: unmanagedSelf
        )

        if tap == nil {
            NSLog("[HotkeyListener] HID tap failed, trying session tap...")
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: hotkeyEventCallback,
                userInfo: unmanagedSelf
            )
        }

        guard let tap else {
            NSLog("[HotkeyListener] ⚠️ Failed to create CGEventTap at both HID and session level")
            return
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[HotkeyListener] ✅ Event tap installed successfully")
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: - NSEvent Global Monitors (fallback)

    private func installGlobalMonitors() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            guard event.keyCode == UInt16(Self.triggerKeyCode) else { return }
            let down = Self.isTriggerDown(event: event)
            self.debugLog("flagsChanged: triggerDown=\(down) code=\(event.keyCode) mods=0x\(String(event.modifierFlags.rawValue, radix: 16))")
            self.handleTriggerKeyChanged(isDown: down)
        }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            self.debugLog("keyDown: code=\(event.keyCode) held=\(self.isTriggerHeld) pager=\(self.isPagerVisible)")
            guard self.isTriggerHeld, self.isPagerVisible else { return }
            self.handleActionKey(keyCode: Int64(event.keyCode))
        }

        NSLog("[HotkeyListener] Global NSEvent monitors installed: flags=%@, key=%@",
              flagsMonitor != nil ? "ok" : "nil",
              keyMonitor != nil ? "ok" : "nil")
    }

    private func removeGlobalMonitors() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: - Event handling (called from C callback)

    /// Process a CGEvent. Returns nil to swallow the event, or the event to pass through.
    fileprivate func handleEvent(_ proxy: CGEventTapProxy,
                                  type: CGEventType,
                                  event: CGEvent) -> CGEvent? {
        // If the tap is disabled by the system (timeout), re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NSLog("[HotkeyListener] Event tap was disabled (type=%d), re-enabling", type.rawValue)
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return event
        }

        // Ignore our own simulated events (from SpaceBridge space switching).
        if event.getIntegerValueField(.eventSourceUserData) == HotkeyListener.selfGeneratedMarker {
            return event
        }

        switch type {
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Self.triggerKeyCode {
                let isDown = Self.isTriggerDown(flags: event.flags)
                NSLog("[HotkeyListener] trigger: down=%d flags=0x%llx", isDown ? 1 : 0, event.flags.rawValue)
                handleTriggerKeyChanged(isDown: isDown)
                return nil  // Swallow trigger key — prevent native behavior
            }
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            NSLog("[HotkeyListener] keyDown: code=%d held=%d pager=%d", keyCode, isTriggerHeld ? 1 : 0, isPagerVisible ? 1 : 0)
            if isTriggerHeld && isPagerVisible {
                handleActionKey(keyCode: keyCode)
                return nil  // Swallow keys while pager is open
            }
        default:
            break
        }

        return event
    }

    // MARK: - Unified Trigger Key Handler

    /// Called from both CGEvent and NSEvent paths when the trigger key state changes.
    private func handleTriggerKeyChanged(isDown: Bool) {
        if isDown && !isTriggerHeld {
            isTriggerHeld = true
            startHoldTimer()
        } else if !isDown && isTriggerHeld {
            isTriggerHeld = false
            cancelHoldTimer()
            if isPagerVisible {
                isPagerVisible = false
                DispatchQueue.main.async { [weak self] in
                    self?.onPagerToggle?(false)
                }
            }
        }
    }

    // MARK: - Unified Action Key Handler

    /// Called from both CGEvent and NSEvent paths for key presses while pager is open.
    private func handleActionKey(keyCode: Int64) {
        // Ignore ctrl+key events — SpaceBridge.switchToSpace() sends ctrl+N
        // via CGEvent to trigger macOS space switching. We must not react
        // to those synthetic key events or we'd get a feedback loop.
        // (CGEvent path only; NSEvent monitor doesn't see our synthetic events.)

        // Arrow keys → navigate grid
        if let direction = directionForKeyCode(keyCode) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                _ = self.gridModel.move(direction)
                self.onNavigate?(direction)
            }
            return
        }

        // Number keys 1-9 → jump to cell
        if let cellIndex = cellIndexForKeyCode(keyCode) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let row = cellIndex / 3
                let col = cellIndex % 3
                if self.gridModel.moveTo(row: row, col: col) {
                    self.onNavigate?(.right)
                }
            }
            return
        }
    }

    // MARK: - CGEvent Key Down (legacy path for ctrl filter)

    private func handleKeyDown(_ event: CGEvent) {
        guard isTriggerHeld, isPagerVisible else { return }

        // Ignore ctrl+key events — SpaceBridge sends ctrl+N for space switching.
        if event.flags.contains(.maskControl) { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        handleActionKey(keyCode: keyCode)
    }

    // MARK: - Hold Timer

    private func startHoldTimer() {
        cancelHoldTimer()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + holdDelay)
        timer.setEventHandler { [weak self] in
            guard let self, self.isTriggerHeld else { return }
            self.isPagerVisible = true
            self.onPagerToggle?(true)
        }
        timer.resume()
        holdTimer = timer
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    // MARK: - 3-Finger Swipe Gesture

    private func installGestureMonitor() {
        // Monitor raw gesture events for multi-finger swipes.
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: .gesture) { [weak self] event in
            self?.handleGestureEvent(event)
        }

        // Also monitor discrete swipe events (swipeWithEvent:) which fire
        // when macOS doesn't claim the gesture. On some configs 3-finger
        // vertical swipes come through here instead.
        swipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] event in
            self?.handleDiscreteSwipe(event)
        }

        NSLog("[HotkeyListener] Gesture monitor installed: %@, swipe monitor: %@",
              gestureMonitor != nil ? "success" : "nil",
              swipeMonitor != nil ? "success" : "nil")
    }

    private func removeGestureMonitor() {
        if let monitor = gestureMonitor {
            NSEvent.removeMonitor(monitor)
            gestureMonitor = nil
        }
        if let monitor = swipeMonitor {
            NSEvent.removeMonitor(monitor)
            swipeMonitor = nil
        }
    }

    /// Accumulated swipe delta for the current gesture.
    private var swipeDeltaX: CGFloat = 0
    private var swipeDeltaY: CGFloat = 0
    private var isTrackingSwipe = false

    /// Minimum distance (points) before a swipe is recognized.
    private let swipeThreshold: CGFloat = 50

    private func handleGestureEvent(_ event: NSEvent) {
        // Accept 3 or 4 active touches (3-finger swipes may not arrive
        // for vertical on default macOS settings, so also support 4-finger).
        let touches = event.touches(matching: .touching, in: nil)
        let touchCount = touches.count

        if touchCount == 3 || touchCount == 4 {
            if !isTrackingSwipe {
                isTrackingSwipe = true
                swipeDeltaX = 0
                swipeDeltaY = 0
            }

            swipeDeltaX += event.deltaX
            swipeDeltaY += event.deltaY
        } else if isTrackingSwipe {
            isTrackingSwipe = false
            evaluateSwipe()
        }
    }

    /// Handle discrete swipe events (swipeWithEvent:). These fire when
    /// the system doesn't claim the gesture. deltaX/deltaY are ±1.
    private func handleDiscreteSwipe(_ event: NSEvent) {
        let direction: Direction
        if abs(event.deltaX) > abs(event.deltaY) {
            direction = event.deltaX > 0 ? .left : .right
        } else {
            direction = event.deltaY > 0 ? .up : .down
        }

        NSLog("[HotkeyListener] Discrete swipe: direction=\(direction)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let moved = self.gridModel.move(direction)
            if moved {
                self.onNavigate?(direction)
                self.flashPager()
            }
        }
    }

    private func evaluateSwipe() {
        let absX = abs(swipeDeltaX)
        let absY = abs(swipeDeltaY)

        NSLog("[HotkeyListener] Swipe ended: deltaX=%.1f deltaY=%.1f threshold=%.1f", swipeDeltaX, swipeDeltaY, swipeThreshold)

        guard max(absX, absY) >= swipeThreshold else {
            NSLog("[HotkeyListener] Swipe below threshold, ignoring")
            return
        }

        let direction: Direction
        if absX > absY {
            direction = swipeDeltaX > 0 ? .left : .right
        } else {
            direction = swipeDeltaY > 0 ? .up : .down
        }

        NSLog("[HotkeyListener] Swipe direction: \(direction), current pos: (\(gridModel.currentRow), \(gridModel.currentCol))")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let moved = self.gridModel.move(direction)
            NSLog("[HotkeyListener] Move result: \(moved), new pos: (\(self.gridModel.currentRow), \(self.gridModel.currentCol))")
            self.onNavigate?(direction)
            self.flashPager()
        }
    }

    /// Briefly show the pager overlay for swipe feedback.
    private func flashPager() {
        guard !isTriggerHeld else { return }

        isPagerVisible = true
        onPagerToggle?(true)

        cancelSwipeFlashTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + swipeFlashDuration)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.isPagerVisible = false
            self.onPagerToggle?(false)
        }
        timer.resume()
        swipeFlashTimer = timer
    }

    private func cancelSwipeFlashTimer() {
        swipeFlashTimer?.cancel()
        swipeFlashTimer = nil
    }

    // MARK: - Key Code Mapping

    private func directionForKeyCode(_ keyCode: Int64) -> Direction? {
        switch keyCode {
        case 123: return .left   // ←
        case 124: return .right  // →
        case 125: return .down   // ↓
        case 126: return .up     // ↑
        default:  return nil
        }
    }

    private func cellIndexForKeyCode(_ keyCode: Int64) -> Int? {
        switch keyCode {
        case 18: return 0  // 1
        case 19: return 1  // 2
        case 20: return 2  // 3
        case 21: return 3  // 4
        case 23: return 4  // 5
        case 22: return 5  // 6
        case 26: return 6  // 7
        case 28: return 7  // 8
        case 25: return 8  // 9
        default: return nil
        }
    }
}

// MARK: - CGEventTap C Callback

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }

    let listener = Unmanaged<HotkeyListener>.fromOpaque(userInfo).takeUnretainedValue()

    if let resultEvent = listener.handleEvent(proxy, type: type, event: event) {
        return Unmanaged.passUnretained(resultEvent)
    }

    // Event was swallowed (returned nil from handleEvent).
    return nil
}
