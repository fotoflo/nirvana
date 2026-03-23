# Space Switching

## Overview

Nirvana switches macOS Spaces by posting synthetic `ctrl+N` keystrokes via `CGEvent`. This goes through the Dock's normal space-switch pathway, which correctly leaves windows on their original spaces.

## Key Files

- `Sources/Nirvana/SpaceBridge.swift` — `switchToSpace(_:)` posts CGEvent keystrokes, `listSpaceIDs()` enumerates spaces via private CGS APIs, `detectCurrentSpace()` syncs grid position from macOS
- `Sources/Nirvana/App.swift` — `switchToCurrentGridSpace()` maps current grid position → space ID → calls `SpaceBridge.switchToSpace()`
- `Sources/Nirvana/HotkeyListener.swift` — fires `onNavigate` callback after grid moves, which triggers `switchToCurrentGridSpace()`

## Data Flow

```
User input (arrow/number/swipe)
    → HotkeyListener moves GridModel
    → HotkeyListener.onNavigate fires
    → App.switchToCurrentGridSpace()
    → looks up cell index in GridModel.enabledCells
    → maps cell index to space ID via SpaceBridge.listSpaceIDs()
    → SpaceBridge.switchToSpace(spaceID)
    → CGEvent ctrl+N posted to .cghidEventTap
    → macOS Dock processes the switch
```

For pager cell clicks, the flow goes through `PagerOverlayController.selectCell()` → Focus Collapse animation → `onSpaceSelected` callback → same `switchToCurrentGridSpace()`.

## Important Patterns

**Synthetic event marking:** SpaceBridge stamps outgoing CGEvents with `HotkeyListener.selfGeneratedMarker` (0x4E52564E41 = "NRVNA") in the `eventSourceUserData` field. HotkeyListener checks this field and ignores marked events to prevent feedback loops.

**Space enumeration:** `listSpaceIDs()` uses `CGSCopyManagedDisplaySpaces` (private API via dlsym) to get all spaces. Space IDs are non-sequential (e.g., 1, 11, 13, 10, 12, 58, 59, 60, 61) — the array order matches Mission Control's left-to-right arrangement.

**Cell-to-space mapping:** Enabled grid cells are enumerated in row-major order (row 0 col 0, row 0 col 1, ...). Cell index N maps to `listSpaceIDs()[N]`. Disabled cells are skipped, so disabling a cell shifts the mapping for all cells after it.

## Why Not CGSManagedDisplaySetCurrentSpace

This private API switches instantly with no animation, but it drags the currently focused window to the new space. This is because it bypasses the Dock's window management — only yabai (which injects into Dock.app with SIP disabled) can use it correctly. **Never use this API.**

## Requirements

- **Accessibility permission** — needed for CGEventTap and CGEvent posting
- **ctrl+number shortcuts enabled** — System Settings > Keyboard > Keyboard Shortcuts > Mission Control > "Switch to Desktop N" must be enabled for ctrl+1 through ctrl+9
