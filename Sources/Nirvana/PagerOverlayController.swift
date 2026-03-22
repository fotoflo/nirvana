import AppKit
import SwiftUI

// MARK: - PagerOverlayController

/// Manages the borderless, transparent NSWindow that hosts the PagerOverlayView.
final class PagerOverlayController {

    // MARK: - Properties

    private let gridModel: GridModel
    private let animator = FocusCollapseAnimator()
    private let viewModel = PagerOverlayViewModel()
    private var thumbnailCapture: ThumbnailCapture?

    private var window: NSWindow?
    private var isVisible: Bool = false

    // MARK: - Init

    init(gridModel: GridModel, thumbnailCapture: ThumbnailCapture? = nil) {
        self.gridModel = gridModel
        self.thumbnailCapture = thumbnailCapture ?? ThumbnailCapture()
        viewModel.thumbnailCapture = self.thumbnailCapture

        animator.onComplete = { [weak self] in
            self?.finalizeCollapse()
        }
    }

    // MARK: - Show

    /// Show the pager overlay with a fade-in animation.
    func show() {
        guard !isVisible else { return }

        // Cache the current workspace thumbnail before showing the overlay.
        if let spaceID = gridModel.currentSpaceID {
            thumbnailCapture?.updateCache(for: spaceID)
        }

        // Reset animator to idle state.
        animator.resetToIdle(config: gridModel.config.cells)

        // Sync highlight to current position.
        viewModel.highlightedRow = gridModel.currentRow
        viewModel.highlightedCol = gridModel.currentCol

        let overlay = PagerOverlayView(
            gridModel: gridModel,
            animator: animator,
            viewModel: viewModel,
            onCellSelected: { [weak self] row, col in
                self?.selectCell(row: row, col: col)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: overlay)

        // Use the main screen's frame.
        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = hostingView

        // Make the window key so it receives keyboard events.
        window.makeKeyAndOrderFront(nil)

        // Fade in.
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }

        self.window = window
        isVisible = true
    }

    // MARK: - Dismiss with Focus Collapse

    /// Trigger the Focus Collapse animation on the currently highlighted cell, then dismiss.
    func dismissWithFocusCollapse() {
        guard isVisible else { return }

        let row = viewModel.highlightedRow
        let col = viewModel.highlightedCol

        // Move GridModel to the selected cell.
        gridModel.moveTo(row: row, col: col)

        // Start the 3-phase animation.
        animator.beginCollapse(selectedRow: row, selectedCol: col)
    }

    /// Simple fade-out dismiss without Focus Collapse.
    func dismiss() {
        guard isVisible, let window = window else { return }
        isVisible = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.tearDownWindow()
        })
    }

    // MARK: - Private

    /// Called when a cell is tapped or keyboard-confirmed.
    private func selectCell(row: Int, col: Int) {
        guard gridModel.config.isEnabled(row: row, col: col) else { return }

        // Update highlight.
        viewModel.highlightedRow = row
        viewModel.highlightedCol = col

        // Move grid model.
        gridModel.moveTo(row: row, col: col)

        // Begin Focus Collapse animation.
        animator.beginCollapse(selectedRow: row, selectedCol: col)
    }

    /// Cleanup after Focus Collapse completes.
    private func finalizeCollapse() {
        guard isVisible else { return }
        isVisible = false

        // Quick fade to black then close.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.tearDownWindow()
        })
    }

    /// Remove the window entirely.
    private func tearDownWindow() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }
}
