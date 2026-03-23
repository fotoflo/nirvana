import SwiftUI
import AppKit

// MARK: - TeleportFlashController

/// Shows a brief mini-pager in the bottom-right corner when an external
/// Space change is detected (e.g. cmd-tab teleport). Displays a trail
/// from old position → new position with gold glow, then fades out.
final class TeleportFlashController {

    private let gridModel: GridModel
    private var window: NSWindow?
    private var fadeTimer: DispatchSourceTimer?
    private var spaceObserver: NSObjectProtocol?
    private var positionObserver: NSObjectProtocol?

    /// Previous grid position, updated on each flash.
    private var previousRow: Int = 0
    private var previousCol: Int = 0

    init(gridModel: GridModel) {
        self.gridModel = gridModel
        self.previousRow = gridModel.currentRow
        self.previousCol = gridModel.currentCol
        startObserving()
    }

    deinit {
        if let observer = spaceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = positionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        fadeTimer?.cancel()
    }

    private func startObserving() {
        spaceObserver = NotificationCenter.default.addObserver(
            forName: .externalSpaceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleExternalChange()
        }

        positionObserver = NotificationCenter.default.addObserver(
            forName: .gridPositionChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let oldRow = notification.userInfo?["oldRow"] as? Int,
               let oldCol = notification.userInfo?["oldCol"] as? Int {
                self.previousRow = oldRow
                self.previousCol = oldCol
            }
        }
    }

    private func handleExternalChange() {
        let newRow = gridModel.currentRow
        let newCol = gridModel.currentCol

        // Don't flash if position didn't actually change.
        guard newRow != previousRow || newCol != previousCol else { return }

        flash(fromRow: previousRow, fromCol: previousCol, toRow: newRow, toCol: newCol)
        previousRow = newRow
        previousCol = newCol
    }

    private func flash(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int) {
        // Tear down any existing flash.
        tearDown()

        let flashView = TeleportFlashView(
            gridModel: gridModel,
            fromRow: fromRow,
            fromCol: fromCol,
            toRow: toRow,
            toCol: toCol
        )

        guard let screen = NSScreen.main else { return }

        let size = CGSize(width: 120, height: 120)
        let origin = CGPoint(
            x: screen.frame.maxX - size.width - 20,
            y: screen.visibleFrame.minY + 20
        )

        let window = NSWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: flashView)

        // Fade in.
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            window.animator().alphaValue = 1.0
        }

        self.window = window

        // Fade out after 300ms.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.3)
        timer.setEventHandler { [weak self] in
            self?.fadeOut()
        }
        timer.resume()
        fadeTimer = timer
    }

    private func fadeOut() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.tearDown()
        })
    }

    private func tearDown() {
        fadeTimer?.cancel()
        fadeTimer = nil
        window?.orderOut(nil)
        window = nil
    }
}

// MARK: - TeleportFlashView

/// Mini 3x3 grid showing a trail from old → new position.
struct TeleportFlashView: View {
    let gridModel: GridModel
    let fromRow: Int
    let fromCol: Int
    let toRow: Int
    let toCol: Int

    var body: some View {
        VStack(spacing: 3) {
            ForEach((0..<3).reversed(), id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { col in
                        let isEnabled = gridModel.config.isEnabled(row: row, col: col)
                        let isFrom = row == fromRow && col == fromCol
                        let isTo = row == toRow && col == toCol

                        RoundedRectangle(cornerRadius: 3)
                            .fill(cellColor(isEnabled: isEnabled, isFrom: isFrom, isTo: isTo))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(
                                        isTo ? Color.nirvanaGold : Color.white.opacity(0.2),
                                        lineWidth: isTo ? 2 : 0.5
                                    )
                            )
                            .shadow(
                                color: isTo ? Color.nirvanaGold.opacity(0.8) : .clear,
                                radius: isTo ? 4 : 0
                            )
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.nirvanaIndigo.opacity(0.9))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        )
    }

    private func cellColor(isEnabled: Bool, isFrom: Bool, isTo: Bool) -> Color {
        if isTo {
            return Color.nirvanaGold.opacity(0.5)
        } else if isFrom {
            return Color.nirvanaGold.opacity(0.15)
        } else if isEnabled {
            return Color.white.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}
