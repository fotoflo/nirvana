import AppKit
import Foundation

/// Renders a tiny grid icon for the menu bar status item.
///
/// The icon is an 18x18 pt image showing the 3x3 grid. Each cell is drawn as:
/// - **Enabled cell:** subtle gray rounded rect
/// - **Current position:** gold-filled rounded rect (#c9a84c)
/// - **Disabled cell:** faint outline only
struct MenuBarIconRenderer {

    // MARK: - Constants

    private static let iconSize = CGSize(width: 18, height: 18)
    private static let gridSize = 3
    private static let cellSpacing: CGFloat = 1.5
    private static let cellCornerRadius: CGFloat = 1.0

    // Colors
    private static let goldColor = NSColor(red: 0xC9 / 255.0, green: 0xA8 / 255.0, blue: 0x4C / 255.0, alpha: 1.0) // #c9a84c
    private static let enabledFill = NSColor(white: 0.55, alpha: 0.6)
    private static let disabledStroke = NSColor(white: 0.5, alpha: 0.25)

    // MARK: - Properties

    private let gridModel: GridModel

    // MARK: - Init

    init(gridModel: GridModel) {
        self.gridModel = gridModel
    }

    // MARK: - Render

    /// Renders the menu bar icon as an `NSImage`.
    /// The image is template-compatible for dark/light menu bar, except the gold
    /// highlight which uses an explicit color.
    func render() -> NSImage {
        let size = Self.iconSize
        let image = NSImage(size: size, flipped: false) { rect in
            self.drawGrid(in: rect)
            return true
        }

        // Do NOT set as template — we use explicit colors (gold highlight).
        image.isTemplate = false
        return image
    }

    // MARK: - Drawing

    private func drawGrid(in rect: CGRect) {
        let totalSpacing = Self.cellSpacing * CGFloat(Self.gridSize + 1)
        let cellWidth = (rect.width - totalSpacing) / CGFloat(Self.gridSize)
        let cellHeight = (rect.height - totalSpacing) / CGFloat(Self.gridSize)

        let currentRow = gridModel.currentRow
        let currentCol = gridModel.currentCol

        for row in 0..<Self.gridSize {
            for col in 0..<Self.gridSize {
                let x = Self.cellSpacing + CGFloat(col) * (cellWidth + Self.cellSpacing)
                // Flip Y so row 0 is top (NSImage drawing coords have origin at bottom-left)
                let flippedRow = (Self.gridSize - 1) - row
                let y = Self.cellSpacing + CGFloat(flippedRow) * (cellHeight + Self.cellSpacing)

                let cellRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
                let path = NSBezierPath(roundedRect: cellRect, xRadius: Self.cellCornerRadius, yRadius: Self.cellCornerRadius)

                let isEnabled = gridModel.config.isEnabled(row: row, col: col)
                let isCurrent = (row == currentRow && col == currentCol)

                if isCurrent && isEnabled {
                    // Gold highlight for current position
                    Self.goldColor.setFill()
                    path.fill()
                } else if isEnabled {
                    // Subtle gray fill for enabled cells
                    Self.enabledFill.setFill()
                    path.fill()
                } else {
                    // Faint outline for disabled cells
                    Self.disabledStroke.setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                }
            }
        }
    }
}
