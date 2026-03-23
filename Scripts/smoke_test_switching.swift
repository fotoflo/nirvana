#!/usr/bin/env swift
//
// Smoke test: verifies that space switching actually works on this machine.
// Requires Accessibility permission. Run with: swift Scripts/smoke_test_switching.swift
//

import Cocoa
import CoreGraphics

// MARK: - Private API Wrappers

let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private typealias ConnFunc = @convention(c) () -> Int
private typealias GetActiveSpaceFunc = @convention(c) (Int) -> Int
private typealias CopySpacesFunc = @convention(c) (Int) -> CFArray
private typealias SetSpaceFunc = @convention(c) (Int, CFString, Int) -> Void

func getConnection() -> Int {
    for name in ["CGSMainConnectionID", "_CGSDefaultConnection"] {
        if let sym = dlsym(skylight, name) {
            let r = unsafeBitCast(sym, to: ConnFunc.self)()
            if r != 0 { return r }
        }
    }
    return 0
}

func getActiveSpace(_ conn: Int) -> Int {
    guard let sym = dlsym(skylight, "CGSGetActiveSpace") else { return 0 }
    return unsafeBitCast(sym, to: GetActiveSpaceFunc.self)(conn)
}

func listSpaces(_ conn: Int) -> [Int] {
    guard let sym = dlsym(skylight, "CGSCopyManagedDisplaySpaces") else { return [] }
    let raw = unsafeBitCast(sym, to: CopySpacesFunc.self)(conn)
    guard let displays = raw as? [[String: Any]] else { return [] }
    var ids: [Int] = []
    for d in displays {
        guard let spaces = d["Spaces"] as? [[String: Any]] else { continue }
        for s in spaces {
            if let id = s["id64"] as? Int, id > 0 { ids.append(id) }
        }
    }
    return ids
}

func getDisplayUUID() -> CFString? {
    guard let screen = NSScreen.main,
          let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
          let uuid = CGDisplayCreateUUIDFromDisplayID(did)?.takeRetainedValue(),
          let str = CFUUIDCreateString(nil, uuid) else { return nil }
    return str
}

// MARK: - Switching Methods

/// Switch via CGEvent ctrl+N (the method Nirvana uses).
func switchViaCGEvent(spaceIndex: Int) -> Bool {
    let keyCodes: [Int: CGKeyCode] = [1:18, 2:19, 3:20, 4:21, 5:23, 6:22, 7:26, 8:28, 9:25]
    guard spaceIndex >= 1, spaceIndex <= 9, let kc = keyCodes[spaceIndex] else { return false }

    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: kc, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: kc, keyDown: false) else { return false }

    down.flags = .maskControl
    up.flags = .maskControl
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
}

// MARK: - Test Runner

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✅ \(message)")
        passed += 1
    } else {
        print("  ❌ FAIL: \(message)")
        failed += 1
    }
}

// MARK: - Tests

print("=== Nirvana Space Switching Smoke Test ===\n")

let conn = getConnection()
assert(conn != 0, "CGSConnection is valid (got \(conn))")

let spaces = listSpaces(conn)
assert(spaces.count >= 2, "At least 2 spaces available (got \(spaces.count))")

guard spaces.count >= 2 else {
    print("\n⚠️  Need at least 2 spaces to test switching. Add more in Mission Control.")
    exit(1)
}

let originalSpace = getActiveSpace(conn)
assert(originalSpace > 0, "Can read current space ID (got \(originalSpace))")

let originalIndex = spaces.firstIndex(of: originalSpace) ?? 0
let targetIndex = (originalIndex + 1) % spaces.count
let targetSpace = spaces[targetIndex]

print("\n--- Test: CGEvent ctrl+N switching ---")
print("  Current: space \(originalSpace) (index \(originalIndex))")
print("  Target:  space \(targetSpace) (index \(targetIndex))")

let sent = switchViaCGEvent(spaceIndex: targetIndex + 1)
assert(sent, "CGEvent posted successfully")

// Wait for macOS to process the switch
Thread.sleep(forTimeInterval: 1.0)

let afterSpace = getActiveSpace(conn)
assert(afterSpace == targetSpace, "Space changed to \(targetSpace) (got \(afterSpace))")

// Switch back
print("\n--- Switching back to original space ---")
let sentBack = switchViaCGEvent(spaceIndex: originalIndex + 1)
assert(sentBack, "CGEvent posted for return trip")

Thread.sleep(forTimeInterval: 1.0)

let finalSpace = getActiveSpace(conn)
assert(finalSpace == originalSpace, "Returned to original space \(originalSpace) (got \(finalSpace))")

// Summary
print("\n=== Results: \(passed) passed, \(failed) failed ===")
exit(failed > 0 ? 1 : 0)
