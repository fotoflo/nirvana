# Nirvana — Claude Context

A macOS spatial pager that maps Spaces into a 2D grid with live preview thumbnails.
Inspired by FVWM/Enlightenment's virtual desktop pagers from the 90s.

## Quick Reference

- **Full spec:** `docs/initial-plan.md` — read this first, it has every decision
- **Design mockups:** `design/` — 8 reference images (icon, pager, settings, onboarding, focus collapse, etc.)
- **Repo:** fotoflo/nirvana (GitHub, not yet created)
- **License:** MIT

## Key Decisions (locked)

- **Name:** Nirvana
- **What it is:** Spatial pager only. NOT a tiling WM. Users bring their own WM or none.
- **Grid:** 3x3 max, Tetris-style toggle (users enable/disable cells)
- **macOS Spaces:** We map native Spaces to grid cells. Rows = consecutive Spaces. macOS owns horizontal swipe, we add vertical.
- **Gestures:** 3-finger swipe ←→↑↓ = grid nav (free by default, macOS defaults to 4-finger). No system settings changes needed.
- **Hotkey:** Alt hold = show pager overlay, arrow keys navigate, release = Focus Collapse into selected space
- **Focus Collapse:** The signature interaction. Selected space expands to fullscreen, others shrink/fade/drift outward. 3 phases: Focus → Separation → Resolve.
- **cmd-tab:** Let macOS handle it. If Space changes, flash mini pager in corner (300ms) showing old→new position.
- **Edge behavior:** No wrap. Spatial model stays solid.
- **Thumbnails:** ScreenCaptureKit for live previews. Cache on workspace switch. Degrade to app icons without Screen Recording permission.
- **Cloud background:** Procedural GPU shader (fBm noise). Clouds part on Focus Collapse.
- **Menu bar:** Always visible. Tiny 3x3 grid with dot showing position. Dot slides smoothly (200ms ease-out).
- **Multi-monitor:** Primary display only (MVP).
- **Labels:** Numbers only, no custom names (MVP).
- **Distribution:** Homebrew cask first, App Store later.
- **Min macOS:** 12.3 (ScreenCaptureKit)

## Build Phases

1. **Scaffold** — GitHub repo, Swift Package Manager project, menu bar app shell, MIT license
2. **Core Model** — GridModel, Space mapping, navigation logic, config persistence
3. **Space Switching** — CGSConnection bridge, detect cmd-tab teleports
4. **Gestures + Hotkeys** — 3-finger swipe, alt hold, CGEventTap
5. **Pager Overlay** — SwiftUI overlay, thumbnails, gold glow, Focus Collapse, cloud shader
6. **Settings + Onboarding** — Grid editor, gesture config, permissions, 3-step onboarding
7. **Distribution** — Code signing, notarization, Homebrew cask, README with GIF

## Architecture

```
Nirvana/
├── Package.swift
├── Sources/Nirvana/
│   ├── App.swift              # Menu bar app entry
│   ├── GridModel.swift        # Grid data model + navigation
│   ├── SpaceBridge.swift      # CGSConnection private API
│   ├── ThumbnailCapture.swift # ScreenCaptureKit
│   ├── PagerOverlay.swift     # SwiftUI overlay
│   ├── FocusCollapse.swift    # Signature animation
│   ├── CloudShader.swift      # Procedural clouds
│   ├── HotkeyListener.swift   # CGEventTap + gestures
│   ├── ConfigView.swift       # Settings UI
│   └── OnboardingView.swift   # First-launch
├── Tests/NirvanaTests/
├── design/                    # Reference mockups
└── docs/                      # Specs
```

## Visual Identity

- **Primary:** Deep indigo #1a1a2e
- **Accent/glow:** Soft gold #c9a84c / Warm amber #e8b84b33
- **Surface:** Frosted glass (`.ultraThinMaterial`)
- **Text:** Soft white #e8e8e8
- **Brand rule:** The gold glow is the signature. Every screenshot features it.

## macOS APIs

- `CGSConnection` (private) — Space switching + enumeration
- `ScreenCaptureKit` — Live thumbnails
- `CGEventTap` — Global hotkeys
- `NSEvent.addGlobalMonitorForEvents` — 3-finger gesture detection
- `CGWindowListCopyWindowInfo` — Window positions/sizes
- `NSWorkspace` notifications — Detect cmd-tab Space changes

## Testing

- GridModel + navigation: pure unit tests
- SpaceBridge + ThumbnailCapture: protocol-based, mock in tests
- PagerOverlay: snapshot tests (swift-snapshot-testing)
- Push macOS APIs to edges behind protocols

## User Info

- GitHub: fotoflo
- Has Apple Developer account (for signing/notarization)
- gh CLI authenticated
- Prefers wide open permissions for new projects
- Wants autonomous building (will go to sleep and let Claude work)
