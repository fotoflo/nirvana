# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Nirvana is a macOS menu bar app that maps native Spaces into a 2D spatial grid (3x3 max) with live preview thumbnails. It is a **spatial pager only** — NOT a tiling window manager. Users bring their own WM or none.

Full spec: `docs/initial-plan.md` — read this first for every design decision.
Design mockups: `design/` — reference images for icon, pager, settings, onboarding, focus collapse.

## Build & Test Commands

```bash
# Build
swift build

# Run
swift run Nirvana

# Run all tests
swift test

# Run a single test
swift test --filter NirvanaTests.GridModelTests/testMoveRight
```

This is a Swift Package Manager project (no Xcode project file). Platform target is macOS 13+.

## Architecture

**App lifecycle:** Pure AppKit (`NSApplication` + `AppDelegate`), not SwiftUI App. This keeps the menu bar app alive when all windows close. Entry point is `App.swift:NirvanaEntry`.

**Data flow:** `GridModel` is the central shared state (singleton via `GridModel.shared`). It's an `ObservableObject` that publishes position and config changes via `@Published` properties AND `NotificationCenter` (`.gridPositionChanged`, `.gridConfigChanged`). Other components observe it:

- `SpaceBridge` — syncs grid position ↔ macOS Spaces. Uses private `CGSConnection` APIs loaded at runtime via `dlsym` from `SkyLight.framework`. Space switching uses `NSAppleScript` to send `ctrl+N` keystrokes.
- `HotkeyListener` — global input via `CGEventTap` (with `NSEvent.addGlobalMonitorForEvents` fallback). Handles: alt-hold (200ms) → show pager, arrow keys → navigate, alt-release → Focus Collapse. Also handles 3/4-finger swipe gestures.
- `PagerOverlayController` — manages the borderless fullscreen `NSWindow` hosting the SwiftUI pager overlay. Coordinates with `FocusCollapseAnimator` and calls back to `AppDelegate` for actual space switching.
- `TeleportFlashController` — shows mini-pager flash on external space changes (cmd-tab).

**Pager overlay:** SwiftUI views (`PagerOverlayView`, `PagerCellView`) hosted in an NSWindow at `.screenSaver` level. The cloud background is a SpriteKit scene (`CloudScene`) with an inline GLSL fragment shader.

**Focus Collapse animation:** 3-phase sequence (Focus 150ms → Separation 250ms → Resolve 300ms) driven by `FocusCollapseAnimator`. Uses a generation counter to cancel stale animations. After resolve, the overlay holds for 600ms to mask the macOS space-switch swoosh.

**Config persistence:** Grid config saved as JSON to `~/.config/nirvana/config.json`. First-launch state tracked via `UserDefaults` key `nirvana.onboardingCompleted`.

**Protocols for testability:** `SpaceSwitching` (for SpaceBridge), `ThumbnailCapturing` (for ThumbnailCapture) — mock implementations exist for tests.

## Key Decisions (locked)

- Grid is 3x3 max with Tetris-style cell toggle (enable/disable individual cells)
- Row 0 = bottom of grid. Grid displays reversed (row 2 at top) so spatial orientation matches a map
- Navigation skips disabled cells, no wrapping at edges
- Space switching maps enabled cells to macOS Spaces in row-major order
- `up` direction = +1 row, `down` = -1 row (see `GridModel.delta(for:)`)
- Thumbnails use `CGWindowListCreateImage`, degrade to app icons without Screen Recording permission
- Debug logging goes to `/tmp/nirvana-events.log` (HotkeyListener)
- The gold glow (`#c9a84c`) is the brand signature — every visual should feature it

## Visual Identity

- Primary: Deep indigo `#1a1a2e`
- Accent/glow: Soft gold `#c9a84c` / Warm amber `#e8b84b33`
- Surface: Frosted glass (`.ultraThinMaterial`)
- Text: Soft white `#e8e8e8`
- Color extensions: `Color.nirvanaIndigo`, `Color.nirvanaGold`, `Color.nirvanaGlow`, `Color.nirvanaText`

## macOS Private APIs

SpaceBridge uses undocumented APIs from `SkyLight.framework` loaded via `dlsym`:
- `CGSMainConnectionID` / `_CGSDefaultConnection` — get connection handle
- `CGSGetActiveSpace` — current space ID
- `CGSManagedDisplayGetCurrentSpace` — per-display current space
- `CGSCopyManagedDisplaySpaces` — enumerate all spaces

These may break across macOS versions. The app requires Accessibility permission (for CGEventTap) and Screen Recording permission (for thumbnails).

## Notifications

- `.gridPositionChanged` — userInfo: `oldRow`, `oldCol`, `newRow`, `newCol`
- `.gridConfigChanged` — config was modified
- `.externalSpaceChanged` — macOS space changed externally (cmd-tab, Mission Control)
