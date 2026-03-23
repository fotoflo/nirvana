import AppKit
import Cocoa
import Foundation
import os.log

// MARK: - Private CGSConnection API (loaded at runtime via dlsym)
// These are undocumented private APIs from SkyLight.framework.
// They may break across macOS versions. Use with caution.

private let skylight: UnsafeMutableRawPointer? = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
private let coreGraphicsLib: UnsafeMutableRawPointer? = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

private typealias CGSDefaultConnectionFunc = @convention(c) () -> Int
private typealias CGSGetActiveSpaceFunc = @convention(c) (Int) -> Int
private typealias CGSManagedDisplayGetCurrentSpaceFunc = @convention(c) (Int, CFString) -> Int
private typealias CGSCopyManagedDisplaySpacesFunc = @convention(c) (Int) -> CFArray

private func CGSDefaultConnection() -> Int {
    // Try multiple function names across SkyLight and CoreGraphics
    let names = ["CGSMainConnectionID", "_CGSDefaultConnection", "CGSDefaultConnection"]
    let handles = [skylight, coreGraphicsLib].compactMap { $0 }

    for handle in handles {
        for name in names {
            if let sym = dlsym(handle, name) {
                let result = unsafeBitCast(sym, to: CGSDefaultConnectionFunc.self)()
                if result != 0 {
                    NSLog("[SpaceBridge] CGSDefaultConnection resolved via \(name) = \(result)")
                    return result
                }
            }
        }
    }

    // Also try RTLD_DEFAULT (search all loaded libraries)
    for name in names {
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { // RTLD_DEFAULT
            let result = unsafeBitCast(sym, to: CGSDefaultConnectionFunc.self)()
            if result != 0 {
                NSLog("[SpaceBridge] CGSDefaultConnection resolved via RTLD_DEFAULT/\(name) = \(result)")
                return result
            }
        }
    }

    NSLog("[SpaceBridge] All CGSDefaultConnection variants returned 0")
    return 0
}

private func CGSGetActiveSpace(_ conn: Int) -> Int {
    guard let handle = skylight,
          let sym = dlsym(handle, "CGSGetActiveSpace") else { return 0 }
    return unsafeBitCast(sym, to: CGSGetActiveSpaceFunc.self)(conn)
}

private func CGSManagedDisplayGetCurrentSpace(_ conn: Int, _ displayID: CFString) -> Int {
    guard let handle = skylight,
          let sym = dlsym(handle, "CGSManagedDisplayGetCurrentSpace") else { return 0 }
    return unsafeBitCast(sym, to: CGSManagedDisplayGetCurrentSpaceFunc.self)(conn, displayID)
}

private func CGSCopyManagedDisplaySpaces(_ conn: Int) -> CFArray {
    guard let handle = skylight,
          let sym = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return [] as CFArray }
    return unsafeBitCast(sym, to: CGSCopyManagedDisplaySpacesFunc.self)(conn)
}

// MARK: - Protocol

/// Protocol for Space switching, enabling mock injection in tests.
protocol SpaceSwitching {
    func getCurrentSpaceID() -> Int?
    func switchToSpace(_ spaceID: Int)
    func listSpaceIDs() -> [Int]
}

// MARK: - SpaceBridge

/// Bridges Nirvana's grid model to macOS Spaces via private CGSConnection APIs.
/// Monitors for external space changes (e.g. cmd-tab, Mission Control) and keeps
/// the grid model in sync.
final class SpaceBridge: SpaceSwitching {

    // MARK: - Properties

    private let gridModel: GridModel
    private let logger = Logger(subsystem: "com.nirvana.app", category: "SpaceBridge")
    private var spaceObserver: NSObjectProtocol?

    /// Cached mapping of grid cell index -> macOS space ID.
    /// Rebuilt on each call to `listSpaceIDs()`.
    private(set) var spaceIDMap: [Int] = []

    // MARK: - Init

    init(gridModel: GridModel) {
        self.gridModel = gridModel
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring

    /// Begin listening for external space changes (cmd-tab, Mission Control swipe, etc.).
    func startMonitoring() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleExternalSpaceChange()
        }

        // Seed the initial state
        detectCurrentSpace()
        logger.info("SpaceBridge monitoring started")
    }

    /// Stop listening for space change notifications.
    func stopMonitoring() {
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
        logger.info("SpaceBridge monitoring stopped")
    }

    // MARK: - SpaceSwitching

    /// Returns the macOS space ID of the currently active space on the main display,
    /// or nil if the private API call fails.
    func getCurrentSpaceID() -> Int? {
        let conn = CGSDefaultConnection()
        guard conn != 0 else {
            logger.warning("CGSDefaultConnection returned 0 — private API unavailable")
            return nil
        }

        // Try the managed-display variant first (more reliable on multi-monitor setups).
        if let mainScreen = NSScreen.main,
           let displayID = mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)
            // takeRetainedValue() because CGDisplayCreateUUIDFromDisplayID follows the Create Rule (+1).
            if let cfuuid = uuid?.takeRetainedValue(),
               let uuidString = CFUUIDCreateString(nil, cfuuid) {
                let spaceID = CGSManagedDisplayGetCurrentSpace(conn, uuidString)
                if spaceID > 0 {
                    return spaceID
                }
            }
        }

        // Fallback: CGSGetActiveSpace (works for single display)
        let spaceID = CGSGetActiveSpace(conn)
        if spaceID > 0 {
            return spaceID
        }

        logger.warning("Could not determine current space ID from private API")
        return nil
    }

    /// Switch to a macOS Space by its space ID.
    ///
    /// Uses CGEvent to post ctrl+N keystrokes, which triggers the standard
    /// macOS space switch through the Dock. This correctly leaves windows
    /// on their original spaces. Requires ctrl+number shortcuts enabled in
    /// System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
    func switchToSpace(_ spaceID: Int) {
        let spaces = listSpaceIDs()
        guard let targetIndex = spaces.firstIndex(of: spaceID) else {
            logger.error("switchToSpace: space \(spaceID) not found in \(spaces)")
            return
        }

        let spaceNumber = targetIndex + 1  // 1-based
        let keyCodes: [Int: CGKeyCode] = [1:18, 2:19, 3:20, 4:21, 5:23, 6:22, 7:26, 8:28, 9:25]
        guard spaceNumber <= 9, let keyCode = keyCodes[spaceNumber] else {
            logger.error("switchToSpace: space number \(spaceNumber) out of range")
            return
        }

        logger.info("switchToSpace: → space \(spaceID) (ctrl+\(spaceNumber))")

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            logger.error("switchToSpace: failed to create CGEvent")
            return
        }

        // Mark events so our own event tap ignores them.
        keyDown.setIntegerValueField(.eventSourceUserData, value: HotkeyListener.selfGeneratedMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: HotkeyListener.selfGeneratedMarker)

        keyDown.flags = .maskControl
        keyUp.flags = .maskControl
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Returns an ordered list of all user-created (non-fullscreen) space IDs on the
    /// main display. The order matches the left-to-right arrangement in Mission Control.
    func listSpaceIDs() -> [Int] {
        let conn = CGSDefaultConnection()
        guard conn != 0 else {
            logger.warning("CGSDefaultConnection returned 0 — cannot list spaces")
            return []
        }

        NSLog("[SpaceBridge] Connection: \(conn)")

        let raw = CGSCopyManagedDisplaySpaces(conn)
        NSLog("[SpaceBridge] Raw result type: \(type(of: raw)), count: \(CFArrayGetCount(raw))")

        guard let displaysInfo = raw as? [[String: Any]] else {
            // Try alternative cast
            if let altCast = raw as? [Any] {
                NSLog("[SpaceBridge] Alternative cast succeeded with \(altCast.count) items")
                for (i, item) in altCast.enumerated() {
                    NSLog("[SpaceBridge] Item \(i) type: \(type(of: item))")
                    if let dict = item as? [String: Any] {
                        NSLog("[SpaceBridge] Item \(i) keys: \(dict.keys.sorted())")
                    }
                }
            }
            NSLog("[SpaceBridge] CGSCopyManagedDisplaySpaces returned unexpected format")
            return []
        }

        var ids: [Int] = []

        for display in displaysInfo {
            guard let spaces = display["Spaces"] as? [[String: Any]] else {
                logger.info("Display entry has no 'Spaces' key. Keys: \(display.keys.sorted())")
                continue
            }

            logger.info("Found \(spaces.count) space entries on display")

            for space in spaces {
                let type = space["type"] as? Int
                let id64 = space["id64"] as? Int
                let managedSpaceID = space["ManagedSpaceID"] as? Int
                let spaceID = id64 ?? managedSpaceID ?? 0

                NSLog("[SpaceBridge] Space entry: id64=\(id64 ?? -1) ManagedSpaceID=\(managedSpaceID ?? -1) type=\(type ?? -1) keys=\(space.keys.sorted())")

                // Include all spaces: user (type 0), fullscreen (type 4), and unknown types
                if spaceID > 0 {
                    ids.append(spaceID)
                }
            }
        }

        logger.info("listSpaceIDs found \(ids.count) spaces: \(ids)")
        spaceIDMap = ids
        return ids
    }

    /// Returns the total count of all space entries (including fullscreen).
    /// Used by onboarding to show how many spaces the user has.
    func listAllSpaceEntries() -> Int {
        return listSpaceIDs().count
    }

    // MARK: - Detection

    /// Reads the current macOS space and updates the grid model's position to match.
    func detectCurrentSpace() {
        guard let currentID = getCurrentSpaceID() else {
            logger.info("detectCurrentSpace: could not read current space ID")
            return
        }

        let spaces = listSpaceIDs()
        guard let index = spaces.firstIndex(of: currentID) else {
            logger.info("detectCurrentSpace: current space ID \(currentID) not found in list of \(spaces.count) spaces")
            return
        }

        updateGridPosition(fromSpaceIndex: index)
    }

    // MARK: - Private Helpers

    /// Called when macOS notifies us the active space changed externally.
    private func handleExternalSpaceChange() {
        logger.debug("External space change detected")
        detectCurrentSpace()

        // Post notification so the menu bar icon and pager can react
        NotificationCenter.default.post(name: .externalSpaceChanged, object: nil)
    }

    /// Maps a linear space index to a grid (row, col) and updates the model.
    private func updateGridPosition(fromSpaceIndex index: Int) {
        let enabledCells = gridModel.enabledCells
        guard index < enabledCells.count else {
            logger.info("Space index \(index) exceeds enabled grid cells (\(enabledCells.count))")
            return
        }

        let cell = enabledCells[index]
        gridModel.moveTo(row: cell.row, col: cell.col)
    }

    // Space switching uses CGEvent ctrl+N keystrokes — see switchToSpace(_:).
    // CGSManagedDisplaySetCurrentSpace was tried but drags focused windows along.
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when an external space change is detected (cmd-tab, Mission Control, swipe).
    static let externalSpaceChanged = Notification.Name("com.nirvana.externalSpaceChanged")
}
