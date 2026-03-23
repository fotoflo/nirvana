import SwiftUI

// MARK: - FocusCollapseState

/// The phases of the Focus Collapse animation.
enum FocusCollapseState: Equatable {
    case idle
    case focus       // Phase 1: Grid visible, active cell gold glow (150ms)
    case separation  // Phase 2: Non-selected drift outward, selected scales up (250ms)
    case resolve     // Phase 3: Selected expands to full screen, others fade out (300ms)
    case completed
}

// MARK: - CellAnimationState

/// Per-cell animation properties driven by FocusCollapseAnimator.
struct CellAnimationState: Equatable {
    var scale: CGFloat = 1.0
    var opacity: Double = 1.0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var glowRadius: CGFloat = 0
    var glowOpacity: Double = 0

    /// Default state for an enabled cell.
    static let enabled = CellAnimationState()

    /// Default state for a disabled cell.
    static let disabled = CellAnimationState(opacity: 0.3)
}

// MARK: - FocusCollapseAnimator

/// Orchestrates the 3-phase Focus Collapse animation across the 3x3 grid.
///
/// Usage:
/// ```swift
/// animator.beginCollapse(selectedRow: 1, selectedCol: 1)
/// ```
/// The animator publishes state changes that drive SwiftUI animations.
final class FocusCollapseAnimator: ObservableObject {

    // MARK: - Published State

    @Published var state: FocusCollapseState = .idle
    @Published var cellStates: [[CellAnimationState]]

    // MARK: - Configuration

    /// Duration of each phase in seconds.
    struct Timing {
        static let focus: Double = 0.15       // 150ms
        static let separation: Double = 0.25  // 250ms
        static let resolve: Double = 0.30     // 300ms
    }

    /// How far non-selected cells drift outward in the separation phase.
    private let driftDistance: CGFloat = 10

    /// The selected cell's scale during separation.
    private let selectedScale: CGFloat = 1.06

    /// The scale of non-selected cells during separation.
    private let nonSelectedScale: CGFloat = 0.95

    /// Gold glow radius during focus phase.
    private let focusGlowRadius: CGFloat = 15

    /// Gold glow radius during separation (intensified).
    private let separationGlowRadius: CGFloat = 25

    /// Callback fired when the animation completes.
    var onComplete: (() -> Void)?

    // MARK: - Private

    private var selectedRow: Int = 0
    private var selectedCol: Int = 0
    private var collapseGeneration: Int = 0

    // MARK: - Init

    init() {
        // Initialize a 3x3 grid of default cell states.
        cellStates = Array(
            repeating: Array(repeating: CellAnimationState.enabled, count: 3),
            count: 3
        )
    }

    // MARK: - Public API

    /// Reset all cells to their default (idle) animation state.
    func resetToIdle(config: [[Bool]]? = nil) {
        collapseGeneration += 1
        state = .idle
        for row in 0..<3 {
            for col in 0..<3 {
                let isEnabled = config?[row][col] ?? true
                cellStates[row][col] = isEnabled
                    ? .enabled
                    : .disabled
            }
        }
    }

    /// Begin the 3-phase Focus Collapse animation toward the selected cell.
    func beginCollapse(selectedRow: Int, selectedCol: Int) {
        self.selectedRow = selectedRow
        self.selectedCol = selectedCol
        collapseGeneration += 1
        let gen = collapseGeneration

        // Phase 1: Focus
        enterFocusPhase()

        // Phase 2: Separation (after focus completes)
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.focus) { [weak self] in
            guard let self, self.collapseGeneration == gen else { return }
            self.enterSeparationPhase()
        }

        // Phase 3: Resolve (after separation completes)
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.focus + Timing.separation) { [weak self] in
            guard let self, self.collapseGeneration == gen else { return }
            self.enterResolvePhase()
        }

        // Completed
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.focus + Timing.separation + Timing.resolve) { [weak self] in
            guard let self, self.collapseGeneration == gen else { return }
            self.state = .completed
            self.onComplete?()
        }
    }

    /// Cancel any in-progress collapse animation.
    func cancelCollapse() {
        collapseGeneration += 1
    }

    // MARK: - Phase Implementations

    /// Phase 1 — Focus: Grid is visible, selected cell gets gold glow.
    private func enterFocusPhase() {
        withAnimation(.easeInOut(duration: Timing.focus)) {
            state = .focus

            for row in 0..<3 {
                for col in 0..<3 {
                    if row == selectedRow && col == selectedCol {
                        cellStates[row][col].glowRadius = focusGlowRadius
                        cellStates[row][col].glowOpacity = 1.0
                        cellStates[row][col].scale = 1.0
                        cellStates[row][col].opacity = 1.0
                    } else {
                        cellStates[row][col].glowRadius = 0
                        cellStates[row][col].glowOpacity = 0
                        cellStates[row][col].scale = 1.0
                        cellStates[row][col].opacity = 1.0
                    }
                }
            }
        }
    }

    /// Phase 2 — Separation: Non-selected shrink/fade/drift; selected scales up, glow intensifies.
    private func enterSeparationPhase() {
        withAnimation(.easeInOut(duration: Timing.separation)) {
            state = .separation

            for row in 0..<3 {
                for col in 0..<3 {
                    if row == selectedRow && col == selectedCol {
                        cellStates[row][col].scale = selectedScale
                        cellStates[row][col].opacity = 1.0
                        cellStates[row][col].glowRadius = separationGlowRadius
                        cellStates[row][col].glowOpacity = 1.0
                        cellStates[row][col].offsetX = 0
                        cellStates[row][col].offsetY = 0
                    } else {
                        let drift = driftVector(fromRow: row, fromCol: col)
                        cellStates[row][col].scale = nonSelectedScale
                        cellStates[row][col].opacity = 0.5
                        cellStates[row][col].offsetX = drift.x
                        cellStates[row][col].offsetY = drift.y
                        cellStates[row][col].glowRadius = 0
                        cellStates[row][col].glowOpacity = 0
                    }
                }
            }
        }
    }

    /// Phase 3 — Resolve: Selected expands to fill; others fade out and continue drifting.
    private func enterResolvePhase() {
        withAnimation(.easeInOut(duration: Timing.resolve)) {
            state = .resolve

            for row in 0..<3 {
                for col in 0..<3 {
                    if row == selectedRow && col == selectedCol {
                        // Expand to fill the screen
                        cellStates[row][col].scale = 3.0
                        cellStates[row][col].opacity = 1.0
                        cellStates[row][col].glowRadius = 0
                        cellStates[row][col].glowOpacity = 0
                    } else {
                        let drift = driftVector(fromRow: row, fromCol: col)
                        cellStates[row][col].scale = 0.8
                        cellStates[row][col].opacity = 0
                        cellStates[row][col].offsetX = drift.x * 3
                        cellStates[row][col].offsetY = drift.y * 3
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Calculate the outward drift direction from a cell relative to the selected cell.
    private func driftVector(fromRow row: Int, fromCol col: Int) -> CGPoint {
        let dx = CGFloat(col - selectedCol)
        let dy = CGFloat(row - selectedRow)

        // If the cell is in the same row/col as selected, drift purely along that axis.
        // Otherwise drift diagonally.
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else {
            // Same cell as selected (shouldn't happen here, but safe fallback)
            return .zero
        }

        return CGPoint(
            x: (dx / length) * driftDistance,
            y: (dy / length) * driftDistance
        )
    }

    /// Total animation duration for all three phases.
    static var totalDuration: Double {
        Timing.focus + Timing.separation + Timing.resolve
    }
}
