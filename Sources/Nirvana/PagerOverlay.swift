import SwiftUI
import AppKit

// MARK: - Design Constants

private enum PagerColors {
    static let indigo = Color(hex: 0x1a1a2e)
    static let gold = Color(hex: 0xc9a84c)
    static let goldGlow = Color(hex: 0xe8b84b).opacity(0.33)
    static let softWhite = Color(hex: 0xe8e8e8)
    static let cellBackground = Color.white.opacity(0.06)
    static let disabledBorder = Color.white.opacity(0.15)
    static let enabledBorder = Color.white.opacity(0.3)
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - PagerOverlayView

/// Full-screen 3x3 pager overlay showing workspace thumbnails.
struct PagerOverlayView: View {
    @ObservedObject var gridModel: GridModel
    @ObservedObject var animator: FocusCollapseAnimator
    @ObservedObject var viewModel: PagerOverlayViewModel

    /// Callback when a cell is selected (click or keyboard confirm).
    var onCellSelected: ((Int, Int) -> Void)?

    /// Callback to dismiss without selecting.
    var onDismiss: (() -> Void)?

    var body: some View {
        ZStack {
            // Background: deep indigo with frosted glass
            PagerColors.indigo
                .opacity(0.85)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            // Grid
            VStack(spacing: 12) {
                // Rows are displayed top-to-bottom: row 2 at top, row 0 at bottom
                // so spatial orientation matches a map (up = higher row index).
                ForEach((0..<3).reversed(), id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { col in
                            let cellAnim = animator.cellStates[row][col]
                            let isEnabled = gridModel.config.isEnabled(row: row, col: col)
                            let isSelected = row == gridModel.currentRow && col == gridModel.currentCol
                            let isHighlighted = row == viewModel.highlightedRow && col == viewModel.highlightedCol

                            PagerCellView(
                                row: row,
                                col: col,
                                isEnabled: isEnabled,
                                isSelected: isSelected,
                                isHighlighted: isHighlighted,
                                thumbnail: viewModel.thumbnail(for: row, col: col),
                                animState: cellAnim
                            )
                            .onTapGesture {
                                guard isEnabled else { return }
                                onCellSelected?(row, col)
                            }
                            .onHover { hovering in
                                if hovering && isEnabled {
                                    viewModel.highlightedRow = row
                                    viewModel.highlightedCol = col
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            viewModel.highlightedRow = gridModel.currentRow
            viewModel.highlightedCol = gridModel.currentCol
        }
        .onAppear {
            // Keyboard events are handled by HotkeyListener's CGEventTap
            // when the pager is visible — no need for SwiftUI key handlers
        }
    }

    // MARK: - Keyboard Navigation

    private func moveHighlight(_ direction: Direction) {
        let (dRow, dCol) = delta(for: direction)
        var newRow = viewModel.highlightedRow + dRow
        var newCol = viewModel.highlightedCol + dCol

        // Walk in direction, skipping disabled cells.
        while newRow >= 0 && newRow < 3 && newCol >= 0 && newCol < 3 {
            if gridModel.config.isEnabled(row: newRow, col: newCol) {
                withAnimation(.easeOut(duration: 0.12)) {
                    viewModel.highlightedRow = newRow
                    viewModel.highlightedCol = newCol
                }
                return
            }
            newRow += dRow
            newCol += dCol
        }
    }

    private func confirmHighlighted() {
        let row = viewModel.highlightedRow
        let col = viewModel.highlightedCol
        guard gridModel.config.isEnabled(row: row, col: col) else { return }
        onCellSelected?(row, col)
    }

    private func delta(for direction: Direction) -> (Int, Int) {
        switch direction {
        case .up:    return ( 1,  0)
        case .down:  return (-1,  0)
        case .left:  return ( 0, -1)
        case .right: return ( 0,  1)
        }
    }
}

// MARK: - PagerOverlayViewModel

/// Manages state for the pager overlay that isn't part of GridModel.
final class PagerOverlayViewModel: ObservableObject {
    @Published var highlightedRow: Int = 0
    @Published var highlightedCol: Int = 0

    /// Thumbnail provider.
    var thumbnailCapture: ThumbnailCapturing?

    /// Get thumbnail for a grid cell, or nil for fallback.
    func thumbnail(for row: Int, col: Int) -> NSImage? {
        let spaceID = row * 3 + col + 1
        return thumbnailCapture?.captureThumbnail(for: spaceID)
    }
}

// MARK: - PagerCellView

/// A single cell in the pager grid.
struct PagerCellView: View {
    let row: Int
    let col: Int
    let isEnabled: Bool
    let isSelected: Bool
    let isHighlighted: Bool
    let thumbnail: NSImage?
    let animState: CellAnimationState

    @State private var isHovering: Bool = false

    /// Cell number (1-9), displayed bottom-right.
    private var cellNumber: Int {
        row * 3 + col + 1
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Background
            if isEnabled {
                RoundedRectangle(cornerRadius: 8)
                    .fill(PagerColors.cellBackground)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        PagerColors.disabledBorder,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            }

            // Thumbnail or app-icon fallback
            if isEnabled {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(2)
                } else {
                    // Fallback: show grid icon placeholder
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(PagerColors.softWhite.opacity(0.3))
                }
            }

            // Cell number label
            if isEnabled {
                Text("\(cellNumber)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(PagerColors.softWhite.opacity(0.6))
                    .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        // Borders
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        // Gold glow for selected/highlighted
        .shadow(
            color: PagerColors.gold.opacity(animState.glowOpacity),
            radius: animState.glowRadius
        )
        // Highlight ring for keyboard navigation
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    PagerColors.gold.opacity(isHighlighted && !isSelected ? 0.6 : 0),
                    lineWidth: 2
                )
        )
        // Animation transforms
        .scaleEffect(animState.scale * (isHovering && isEnabled ? 1.02 : 1.0))
        .opacity(animState.opacity * (isHovering && isEnabled ? 1.1 : 1.0))
        .offset(x: animState.offsetX, y: animState.offsetY)
        // Hover
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }

    // MARK: - Styling

    private var borderColor: Color {
        if isSelected {
            return PagerColors.gold
        } else if isEnabled {
            return PagerColors.enabledBorder
        } else {
            return .clear // disabled cells use dashed stroke above
        }
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }
}
