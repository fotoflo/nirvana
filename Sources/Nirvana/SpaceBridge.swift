import AppKit
import Cocoa
import Foundation
import os.log

// MARK: - Private CGSConnection API (loaded at runtime via dlsym)
// These are undocumented private APIs from SkyLight.framework.
// They may break across macOS versions. Use with caution.

private let skylight: UnsafeMutableRawPointer? = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private typealias CGSDefaultConnectionFunc = @convention(c) () -> Int
private typealias CGSGetActiveSpaceFunc = @convention(c) (Int) -> Int
private typealias CGSManagedDisplayGetCurrentSpaceFunc = @convention(c) (Int, CFString) -> Int
private typealias CGSCopyManagedDisplaySpacesFunc = @convention(c) (Int) -> CFArray

private func CGSDefaultConnection() -> Int {
    guard let handle = skylight,
          let sym = dlsym(handle, "CGSDefaultConnection") else { return 0 }
    return unsafeBitCast(sym, to: CGSDefaultConnectionFunc.self)()
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
            if let uuidString = CFUUIDCreateString(nil, uuid?.takeUnretainedValue()) {
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
    /// Modern macOS restricts direct space switching via private API, so this method
    /// attempts the CGS route first and falls back to keyboard simulation (ctrl+number).
    func switchToSpace(_ spaceID: Int) {
        // Determine the 1-based index of the target space
        let spaces = listSpaceIDs()
        guard let index = spaces.firstIndex(of: spaceID) else {
            logger.error("Space ID \(spaceID) not found in known spaces")
            return
        }
        let oneBasedIndex = index + 1

        // TODO: Direct CGS space switching (CGSSetWorkspace / SLSActivateSpace) is
        // unreliable on macOS 12+. We go straight to the keyboard-simulation fallback.
        switchViaKeyboardSimulation(spaceNumber: oneBasedIndex)
    }

    /// Returns an ordered list of all user-created (non-fullscreen) space IDs on the
    /// main display. The order matches the left-to-right arrangement in Mission Control.
    func listSpaceIDs() -> [Int] {
        let conn = CGSDefaultConnection()
        guard conn != 0 else {
            logger.warning("CGSDefaultConnection returned 0 — cannot list spaces")
            return []
        }

        let displaysInfo = CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] ?? []
        var ids: [Int] = []

        for display in displaysInfo {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                // Type 0 = user space, Type 4 = fullscreen space
                // We only care about user spaces for the grid.
                if let id64 = space["id64"] as? Int, let type = space["type"] as? Int, type == 0 {
                    ids.append(id64)
                } else if let managedSpaceID = space["ManagedSpaceID"] as? Int, let type = space["type"] as? Int, type == 0 {
                    ids.append(managedSpaceID)
                }
            }
        }

        spaceIDMap = ids
        return ids
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

    /// Simulates ctrl+<number> keypress to switch to a Space by its Mission Control index.
    /// Requires Accessibility permissions (System Settings > Privacy > Accessibility).
    private func switchViaKeyboardSimulation(spaceNumber: Int) {
        // TODO: This requires the user to have ctrl+number shortcuts enabled in
        // System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
        // Also requires Accessibility permission for CGEvent posting.

        guard (1...9).contains(spaceNumber) else {
            logger.warning("Cannot simulate keyboard switch to space \(spaceNumber) — only 1-9 supported")
            return
        }

        // Key codes for numbers 1-9 on US keyboard layout
        let keyCodes: [Int: UInt16] = [
            1: 0x12, // 1
            2: 0x13, // 2
            3: 0x14, // 3
            4: 0x15, // 4
            5: 0x17, // 5
            6: 0x16, // 6
            7: 0x1A, // 7
            8: 0x1C, // 8
            9: 0x19, // 9
        ]

        guard let keyCode = keyCodes[spaceNumber] else { return }

        let source = CGEventSource(stateID: .hidSystemState)

        // ctrl + number key
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            logger.error("Failed to create CGEvent for space switch keyboard simulation")
            return
        }

        keyDown.flags = .maskControl
        keyUp.flags = .maskControl

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        logger.info("Simulated ctrl+\(spaceNumber) to switch space")
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when an external space change is detected (cmd-tab, Mission Control, swipe).
    static let externalSpaceChanged = Notification.Name("com.nirvana.externalSpaceChanged")
}
