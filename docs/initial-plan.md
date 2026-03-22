# Nirvana — Initial Plan

A macOS spatial pager that maps Spaces into a 2D grid with live preview thumbnails.
Inspired by FVWM/Enlightenment's virtual desktop pagers from the 90s.

**Repo:** fotoflo/nirvana
**License:** MIT
**Language:** Swift (SwiftUI + AppKit)
**Min macOS:** 12.3 (ScreenCaptureKit)
**Distribution:** Homebrew cask, GitHub releases (App Store later)

---

## Core Concept

Nirvana is NOT a tiling window manager. It is a **spatial pager** — a 2D grid overlay for macOS Spaces with live thumbnails. Users bring their own WM (AeroSpace, yabai, Amethyst) or none at all.

**One-sentence description:** Nirvana = spatial calm under pressure.

### Product Rules (from the core feeling)

1. **No chaos states** — never show overlapping windows in the overlay. Everything resolves into clean tiles or fades out.
2. **Movement is continuous** — no jumps, ever. Every transition = glide, fade, or morph.
3. **You never get lost** — orientation always visible (menu bar icon shows position, pager flashes on teleport).

---

## Signature Interaction: Focus Collapse

The brand-defining interaction. When the user selects a space:

### Phase 1: Focus
- Grid fully visible
- Active cell highlighted (gold glow)
- Everything stable

### Phase 2: Separation
- Non-selected cells: scale → 0.94–0.96, opacity → 0.4–0.6, slight outward drift (8–12px)
- Selected cell: scale → 1.05–1.08, glow intensifies
- Grid still readable

### Phase 3: Resolve
- Selected expands → full screen
- Others: fade to 0, continue outward drift (no blur needed)
- Grid disappears at the very end

See: `design/space-focus.png` for the 4-frame storyboard.

---

## Architecture

### What macOS provides (we don't reinvent)
- Spaces (virtual desktops) — user creates up to 9
- 4-finger swipe left/right — native Space switching (we map rows to consecutive Spaces)
- Mission Control (4-finger up) — untouched
- App Exposé (4-finger down) — untouched
- cmd-tab — native app switching, untouched

### What Nirvana adds
- 2D grid mapping of 1D Spaces (3x3 max, Tetris-style toggle)
- 3-finger swipe ←→↑↓ — grid navigation (free by default, macOS defaults to 4-finger)
- Alt hold → pager overlay with live thumbnails + arrow key navigation
- Focus Collapse animation on space selection
- cmd-tab teleport detection → brief pager flash showing old→new position
- Procedural cloud background (GPU shader)
- Menu bar icon showing current position in grid

### Data Model

```swift
struct GridCell {
    let row: Int      // 0-2
    let col: Int      // 0-2
    let spaceID: Int  // macOS Space ID
    let enabled: Bool // Tetris-style toggle
}

struct GridConfig {
    let cells: [GridCell]  // up to 9
    let rows: Int          // max 3
    let cols: Int          // max 3
}
```

### Space Mapping

Rows map to consecutive macOS Spaces so native left/right swipe works within a row:

```
Row 3 (top):    Space 7  Space 8  Space 9
Row 2 (middle): Space 4  Space 5  Space 6
Row 1 (bottom): Space 1  Space 2  Space 3

macOS sees: 1,2,3,4,5,6,7,8,9 in a line
User sees:  3x3 grid
Swipe ←→:   macOS moves within row (automatic)
Swipe ↑↓:   Nirvana jumps ±3 Spaces (row change)
```

---

## Navigation

### Input Methods

| Input | Action | Handler |
|-------|--------|---------|
| 3-finger swipe ←→ | Move left/right in grid | Nirvana (NSEvent gesture monitor) |
| 3-finger swipe ↑↓ | Move up/down in grid | Nirvana (NSEvent gesture monitor) |
| 4-finger swipe ←→ | Native Space switch (within row) | macOS (untouched) |
| 4-finger swipe ↑ | Mission Control | macOS (untouched) |
| 4-finger swipe ↓ | App Exposé | macOS (untouched) |
| Alt hold | Show pager overlay | Nirvana (CGEventTap) |
| Alt hold + ↑↓←→ | Navigate grid while pager open | Nirvana |
| Alt release | Focus Collapse into selected space | Nirvana |
| Alt hold + 1-9 | Jump directly to cell | Nirvana |
| cmd-tab | Native app switch → flash pager if Space changes | macOS + Nirvana detection |

### Edge Behavior
No wrap. At the edge, swipe does nothing. The spatial model stays solid.

### cmd-tab Teleport Flash
When cmd-tab causes a Space change that Nirvana didn't initiate:
- Mini pager flashes in corner (not fullscreen — cmd-tab should be fast)
- Shows trail/line from old position → new position
- Gold glow on new position
- Fades out after 300ms

See: `design/flash-to-space.png`

---

## UI Components

### Pager Overlay (fullscreen)
- Triggered by: alt hold, 3-finger swipe (briefly)
- Frosted glass background (`.ultraThinMaterial`) OR procedural cloud shader
- 3x3 grid of thumbnail cells
- Active cell: gold glow border (#c9a84c), slight scale up
- Inactive cells: thin white border, subtle shadow
- Empty/disabled cells: faint dashed outline with breathing animation
- Workspace numbers in bottom-right of each cell
- Hover: gentle scale up (1.02x) + brighten

See: `design/pager.png`, `design/space-focus.png`

### Procedural Cloud Background
- Fractal Brownian Motion (fBm) noise shader
- 4-5 octaves of Simplex noise
- Animated with time uniform (slow drift)
- Colored with indigo/purple/amber gradient
- On Focus Collapse: clouds part/disperse from selected cell
- Implementation: SpriteKit + `SKShader` (or Metal `MTKView`)
- Performance: <1% GPU utilization

### Menu Bar Icon
- Tiny 3x3 grid with dot showing current position
- Dot slides smoothly (200ms ease-out) when position changes — never jumps
- Click → dropdown: Preferences, About, Quit

### Settings UI
- Sidebar navigation: Grid, Gestures, Navigation, Menubar, Sound
- Frosted glass panel matching Nirvana's visual identity
- Gold accent line, indigo/dark theme

See: `design/settings.png`

### Grid Editor (in Settings → Grid tab)
- 3x3 grid of toggleable cells
- Click to enable/disable (Tetris-style layout)
- Drag to reorder which Space maps to which cell
- Shows live Space previews in cells during setup

### Onboarding (3 steps)
1. **Create Spaces** — instructs user to open Mission Control and create Spaces. Shows progress bar (N of 9).
2. **Arrange Your Grid** — drag-and-drop Space thumbnails into grid cells. See: `design/onboarding.png`
3. **Permissions** — grant Accessibility (keyboard shortcuts) and Screen Recording (live previews). Without Screen Recording, falls back to app icons.

---

## Visual Identity

### Color Palette — "Digital Zen"

| Role | Color | Hex |
|------|-------|-----|
| Primary | Deep indigo | #1a1a2e |
| Accent | Soft gold | #c9a84c |
| Glow | Warm amber | #e8b84b33 |
| Surface | Frosted glass | blur + 15% opacity |
| Active | Lotus pink (alt) | #d4727a |
| Text | Soft white | #e8e8e8 |

### App Icon
3x3 grid with rounded corners, one cell glowing gold/amber. Gradient: indigo → deep purple.

See: `design/icon.png`, `design/brand-mark.png`, `design/logo.png`

### Brand Principles
- **The gold glow** is the signature visual. Every screenshot features it.
- **Crossfade transitions** — spaces don't snap, they glide.
- **Calm power** — aesthetic differentiates from "hacker tool" vibes of yabai/AeroSpace.

---

## Graceful Degradation

| Permissions | Behavior |
|-------------|----------|
| Full (Accessibility + Screen Recording) | Pager with live thumbnails |
| No Screen Recording | Pager with app icons + window count |
| No Accessibility | Click-only (no hotkeys), menu bar only |
| No Spaces created | Onboarding prompts to create them |

---

## Technical Details

### macOS APIs

| API | Purpose |
|-----|---------|
| `CGSConnection` (private) | Switch Spaces programmatically, enumerate Space IDs |
| `ScreenCaptureKit` | Live window thumbnails (public, macOS 12.3+) |
| `CGEventTap` | Global hotkey interception (alt hold, arrow keys) |
| `NSEvent.addGlobalMonitorForEvents` | 3-finger swipe gesture detection |
| `CGWindowListCopyWindowInfo` | Window positions, sizes, app names |
| `NSWorkspace.didActivateApplicationNotification` | Detect cmd-tab Space changes |
| `.ultraThinMaterial` (SwiftUI) | Frosted glass overlay background |

### Thumbnail Strategy
- Current workspace: live composite screenshot on pager open (~10ms via `CGWindowListCreateImage`)
- Other workspaces: cached thumbnails from last visit
- Cache updates each time user switches workspaces
- With ScreenCaptureKit: can stream at 10fps for live video in thumbnails

### Performance Targets
- Pager open: <50ms
- Space switch: <100ms
- Cloud shader: <1% GPU
- Memory footprint: <50MB
- Binary size: ~5MB

---

## Project Structure

```
Nirvana/
├── Package.swift
├── Sources/
│   └── Nirvana/
│       ├── App.swift              # Menu bar app entry point
│       ├── GridModel.swift        # Grid data model + navigation logic
│       ├── SpaceBridge.swift      # CGSConnection private API bridge
│       ├── ThumbnailCapture.swift # ScreenCaptureKit wrapper
│       ├── PagerOverlay.swift     # SwiftUI fullscreen overlay
│       ├── FocusCollapse.swift    # Signature animation
│       ├── CloudShader.swift      # Procedural cloud background
│       ├── HotkeyListener.swift   # CGEventTap + gesture detection
│       ├── ConfigView.swift       # Settings UI
│       └── OnboardingView.swift   # First-launch flow
├── Tests/
│   └── NirvanaTests/
│       ├── GridModelTests.swift
│       └── SpaceBridgeTests.swift
├── design/                        # Reference mockups
│   ├── brand-mark.png
│   ├── flash-to-space.png
│   ├── icon.png
│   ├── logo.png
│   ├── onboarding.png
│   ├── pager.png
│   ├── settings.png
│   └── space-focus.png
├── docs/
│   └── initial-plan.md            # This file
├── LICENSE
└── README.md
```

---

## Build Phases

### Phase 1: Scaffold
- Create GitHub repo (fotoflo/nirvana)
- Swift Package Manager project
- Menu bar app shell with icon
- MIT license, README

### Phase 2: Core Model
- GridModel — 3x3 max, Tetris-style cell toggle
- Space mapping — map macOS Spaces to grid cells
- Navigation logic — directional movement, no wrap
- Config persistence — JSON file

### Phase 3: Space Switching
- CGSConnection bridge — enumerate and switch Spaces
- Detect external Space changes (cmd-tab) via NSWorkspace notifications
- Flash mini pager on teleport

### Phase 4: Gestures + Hotkeys
- 3-finger swipe ←→↑↓ for grid navigation (NSEvent global monitor)
- Alt hold → show pager, arrow keys to navigate
- CGEventTap for global key interception

### Phase 5: Pager Overlay
- Full-screen SwiftUI overlay
- Thumbnail capture via ScreenCaptureKit (cache on switch)
- Gold glow on active cell, dashed empty cells
- Focus Collapse animation
- Procedural cloud shader background
- Graceful degradation (app icons if no Screen Recording)

### Phase 6: Settings + Onboarding
- Grid editor (click to toggle cells, drag to assign Spaces)
- Gesture config
- Launch at login
- Permissions status + grant buttons
- 3-step onboarding flow

### Phase 7: Distribution
- Code signing + notarization (Apple Developer account)
- Homebrew cask formula
- README with GIF demo
- GitHub releases

---

## Design References

All mockups in `design/`:

| File | Description |
|------|-------------|
| `brand-mark.png` | Brand mark / wordmark |
| `flash-to-space.png` | cmd-tab teleport flash animation |
| `icon.png` | App icon (3x3 grid with gold center) |
| `logo.png` | Logo with text |
| `onboarding.png` | Step 2 onboarding — arrange your grid |
| `pager.png` | Full pager overlay with 9 spaces |
| `settings.png` | Settings UI — Gestures tab |
| `space-focus.png` | Focus Collapse 4-frame storyboard |

---

## Multi-Monitor
Primary display only for MVP. Single grid, single pager.

## Numbering
Reading order (1,2,3 on top row). Matches macOS Space numbering.

## Sound
Optional, off by default. Subtle tone on space switch. Different pitch per row (lower = bottom, higher = top). Future consideration.
