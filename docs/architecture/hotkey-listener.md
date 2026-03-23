# Hotkey Listener

## Overview

HotkeyListener handles all global input: trigger key (Caps Lock), arrow/number keys for navigation, and 3/4-finger trackpad swipes. It drives the pager overlay lifecycle (show/dismiss) and grid navigation.

## Key Files

- `Sources/Nirvana/HotkeyListener.swift` — all input handling

## Trigger Key Configuration

The trigger key is centralized at the top of `HotkeyListener`:

```swift
private static let triggerKeyCode: Int64 = 57  // Caps Lock
private static func isTriggerDown(flags: CGEventFlags) -> Bool { ... }
private static func isTriggerDown(event: NSEvent) -> Bool { ... }
```

To rebind the trigger, change `triggerKeyCode` and the two `isTriggerDown` methods. Everything else uses `isTriggerHeld` — no scattered key checks.

## Dual Input Paths

Two parallel input mechanisms feed into shared handlers:

1. **CGEventTap** (primary) — installed as `.defaultTap` so it can swallow events (return nil). Catches Caps Lock and key-down events globally.
2. **NSEvent global monitors** (fallback) — `addGlobalMonitorForEvents` for `.flagsChanged` and `.keyDown`. Can't swallow events but works if the event tap fails.

Both paths call the same unified handlers:
- `handleTriggerKeyChanged(isDown:)` — trigger key press/release
- `handleActionKey(keyCode:)` — arrow keys and number keys while pager is open

## Event Swallowing

The event tap uses `.defaultTap` (not `.listenOnly`) so it can:
- **Swallow Caps Lock** — returns `nil` to prevent the actual caps toggle from happening
- **Swallow arrow/number keys** — while the pager is open, prevents these from reaching other apps

## Pager Lifecycle

```
Caps Lock pressed → start 200ms hold timer
    Timer fires → isPagerVisible = true, onPagerToggle?(true)
    Arrow/number keys → handleActionKey → grid navigation + onNavigate
Caps Lock released → cancel timer, isPagerVisible = false, onPagerToggle?(false)
```

## Swipe Gestures

3 or 4-finger trackpad swipes navigate the grid without showing the full pager. Instead, a brief 500ms "flash" of the pager appears via `flashPager()`.

Two swipe detection paths:
- **Raw gesture events** (`.gesture`) — accumulate `deltaX`/`deltaY` across touch frames, evaluate when fingers lift. Threshold: 50 points.
- **Discrete swipe events** (`.swipe`) — fire on some macOS configs when the system doesn't claim the gesture. `deltaX`/`deltaY` are ±1.

## Self-Generated Event Filtering

SpaceBridge posts synthetic `ctrl+N` CGEvents for space switching. HotkeyListener ignores these by checking `event.eventSourceUserData == selfGeneratedMarker`. The ctrl modifier flag (`maskControl`) is also checked as a secondary filter in the CGEvent keyDown path.
