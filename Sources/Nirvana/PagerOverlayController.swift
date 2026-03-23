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
    private var positionObserver: NSObjectProtocol?

    /// Called after Focus Collapse completes so the app can switch the macOS Space.
    var onSpaceSelected: ((Int, Int) -> Void)?

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

        // Clean up any stale window from a previous session (e.g., rapid toggle).
        if window != nil {
            tearDownWindow()
        }

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

        // Keep highlight in sync when arrow keys move the grid position.
        positionObserver = NotificationCenter.default.addObserver(
            forName: .gridPositionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.viewModel.highlightedRow = self.gridModel.currentRow
            self.viewModel.highlightedCol = self.gridModel.currentCol
        }
    }

    // MARK: - Dismiss with Focus Collapse

    /// Trigger the Focus Collapse animation on the currently highlighted cell, then dismiss.
    func dismissWithFocusCollapse() {
        guard isVisible, window != nil else {
            // If window is already gone, just reset state.
            isVisible = false
            return
        }

        let row = viewModel.highlightedRow
        let col = viewModel.highlightedCol

        // Move grid to highlighted cell and start collapse animation.
        // When collapse completes, finalizeCollapse() fires onSpaceSelected
        // and holds the overlay to mask the macOS swoosh.
        selectCell(row: row, col: col)
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

        // Notify the app to switch the actual macOS Space.
        let row = viewModel.highlightedRow
        let col = viewModel.highlightedCol
        onSpaceSelected?(row, col)

        // Hold overlay to mask the swoosh, then fade out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self?.window?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.tearDownWindow()
            })
        }
    }

    /// Remove the window entirely.
    private func tearDownWindow() {
        if let observer = positionObserver {
            NotificationCenter.default.removeObserver(observer)
            positionObserver = nil
        }
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }
}
