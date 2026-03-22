import Cocoa
import CoreGraphics

// MARK: - HotkeyListener

/// Listens for global hotkeys (Alt hold + arrows/numbers) and 3-finger swipe
/// gestures to drive the spatial pager.
///
/// - Alt hold ≥ 200 ms → show pager overlay
/// - Arrow keys while Alt held → navigate grid
/// - Number keys 1-9 while Alt held → jump to cell
/// - Alt release → dismiss pager (triggers Focus Collapse)
/// - 3-finger swipe → navigate grid + flash pager for 500 ms
final class HotkeyListener {

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

    /// Whether the pager overlay is currently visible.
    private(set) var isPagerVisible = false

    /// Whether the Option/Alt key is currently held down.
    private var isAltHeld = false

    /// Timer that fires after the alt-hold threshold (200 ms).
    private var altHoldTimer: DispatchSourceTimer?

    /// Timer used for the brief "flash" pager on swipe navigation.
    private var swipeFlashTimer: DispatchSourceTimer?

    /// Threshold before the pager is shown on alt hold.
    private let altHoldDelay: TimeInterval = 0.2 // 200 ms

    /// Duration of the pager flash after a 3-finger swipe.
    private let swipeFlashDuration: TimeInterval = 0.5 // 500 ms

    // MARK: - Init

    init(gridModel: GridModel) {
        self.gridModel = gridModel
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Begin listening for hotkeys and gestures.
    func start() {
        installEventTap()
        installGestureMonitor()
    }

    /// Stop all listeners and clean up resources.
    func stop() {
        removeEventTap()
        removeGestureMonitor()
        cancelAltHoldTimer()
        cancelSwipeFlashTimer()
        isPagerVisible = false
        isAltHeld = false
    }

    // MARK: - CGEventTap

    private func installEventTap() {
        // We need to listen to flagsChanged (modifier keys) and keyDown (arrows/numbers).
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        // Pass `self` as userInfo so the C callback can reach back into Swift.
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // can block/modify events
            eventsOfInterest: eventMask,
            callback: hotkeyEventCallback,
            userInfo: unmanagedSelf
        ) else {
            // TODO: Prompt the user to grant Accessibility permission in
            //       System Settings → Privacy & Security → Accessibility.
            print("[HotkeyListener] ⚠️ Failed to create CGEventTap. "
                + "Accessibility permission is likely not granted.")
            return
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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

    // MARK: - Event handling (called from C callback)

    /// Process a CGEvent; return `nil` to swallow the event, or the event to pass it through.
    fileprivate func handleEvent(_ proxy: CGEventTapProxy,
                                  type: CGEventType,
                                  event: CGEvent) -> CGEvent? {
        // If the tap is disabled by the system (timeout), re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return event
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return event
        }
    }

    // MARK: Flags Changed (Alt press/release)

    private func handleFlagsChanged(_ event: CGEvent) -> CGEvent? {
        let flags = event.flags
        let altDown = flags.contains(.maskAlternate)

        if altDown && !isAltHeld {
            // Alt just pressed
            isAltHeld = true
            startAltHoldTimer()
        } else if !altDown && isAltHeld {
            // Alt just released
            isAltHeld = false
            cancelAltHoldTimer()

            if isPagerVisible {
                isPagerVisible = false
                DispatchQueue.main.async { [weak self] in
                    self?.onPagerToggle?(false)
                }
            }
        }

        // Always pass flagsChanged through — don't eat modifier events.
        return event
    }

    // MARK: Key Down (arrows, number keys while Alt held)

    private func handleKeyDown(_ event: CGEvent) -> CGEvent? {
        // Only intercept keys while Alt is held and pager is visible.
        guard isAltHeld, isPagerVisible else {
            return event
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Arrow keys
        if let direction = directionForKeyCode(keyCode) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                _ = self.gridModel.move(direction)
                self.onNavigate?(direction)
            }
            return nil // swallow the event
        }

        // Number keys 1-9 (top row: keycodes 18-21, 23, 22, 26, 28, 25)
        if let cellIndex = cellIndexForKeyCode(keyCode) {
            DispatchQueue.main.async { [weak self] in
                // cellIndex is 1-9, map to row/col: row = (index-1)/3, col = (index-1)%3
                let row = (cellIndex - 1) / 3
                let col = (cellIndex - 1) % 3
                _ = self?.gridModel.moveTo(row: row, col: col)
            }
            return nil // swallow the event
        }

        // Anything else passes through.
        return event
    }

    // MARK: - Alt Hold Timer

    private func startAltHoldTimer() {
        cancelAltHoldTimer()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + altHoldDelay)
        timer.setEventHandler { [weak self] in
            guard let self, self.isAltHeld else { return }
            self.isPagerVisible = true
            self.onPagerToggle?(true)
        }
        timer.resume()
        altHoldTimer = timer
    }

    private func cancelAltHoldTimer() {
        altHoldTimer?.cancel()
        altHoldTimer = nil
    }

    // MARK: - 3-Finger Swipe Gesture

    private func installGestureMonitor() {
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: .gesture) { [weak self] event in
            self?.handleGestureEvent(event)
        }
    }

    private func removeGestureMonitor() {
        if let monitor = gestureMonitor {
            NSEvent.removeMonitor(monitor)
            gestureMonitor = nil
        }
    }

    /// Accumulated swipe delta for the current gesture.
    private var swipeDeltaX: CGFloat = 0
    private var swipeDeltaY: CGFloat = 0
    private var isTrackingSwipe = false

    /// Minimum distance (points) before a swipe is recognized.
    private let swipeThreshold: CGFloat = 50

    private func handleGestureEvent(_ event: NSEvent) {
        // Check for exactly 3 active touches.
        let touches = event.touches(matching: .touching, in: nil)
        let touchCount = touches.count

        if touchCount == 3 {
            if !isTrackingSwipe {
                // Start tracking a new swipe gesture.
                isTrackingSwipe = true
                swipeDeltaX = 0
                swipeDeltaY = 0
            }

            // Accumulate deltas from the scroll-like values on the gesture event.
            swipeDeltaX += event.deltaX
            swipeDeltaY += event.deltaY
        } else if isTrackingSwipe {
            // Fingers lifted — evaluate the swipe.
            isTrackingSwipe = false
            evaluateSwipe()
        }
    }

    private func evaluateSwipe() {
        let absX = abs(swipeDeltaX)
        let absY = abs(swipeDeltaY)

        // Need to exceed threshold in at least one axis.
        guard max(absX, absY) >= swipeThreshold else { return }

        let direction: Direction
        if absX > absY {
            // Horizontal swipe — invert so swiping left moves grid left.
            direction = swipeDeltaX > 0 ? .left : .right
        } else {
            // Vertical swipe — invert so swiping up moves grid up.
            direction = swipeDeltaY > 0 ? .up : .down
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            _ = self.gridModel.move(direction)
            self.onNavigate?(direction)
            self.flashPager()
        }
    }

    /// Briefly show the pager overlay for swipe feedback.
    private func flashPager() {
        // If pager is already up from alt-hold, don't interfere.
        guard !isAltHeld else { return }

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

    /// Map arrow key codes to Direction.
    private func directionForKeyCode(_ keyCode: Int64) -> Direction? {
        switch keyCode {
        case 123: return .left   // ←
        case 124: return .right  // →
        case 125: return .down   // ↓
        case 126: return .up     // ↑
        default:  return nil
        }
    }

    /// Map number key codes (top row 1-9) to a 0-based cell index.
    /// macOS key codes for the number row:
    ///   1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25
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

/// Global C-compatible callback for the CGEventTap.
/// Bridges into the `HotkeyListener` instance via the `userInfo` pointer.
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

    // Returning nil swallows the event.
    return nil
}
