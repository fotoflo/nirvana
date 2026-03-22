import Foundation
import Combine

// MARK: - Direction

enum Direction {
    case up, down, left, right
}

// MARK: - Notifications

extension Notification.Name {
    static let gridPositionChanged = Notification.Name("nirvana.gridPositionChanged")
    static let gridConfigChanged = Notification.Name("nirvana.gridConfigChanged")
}

// MARK: - GridCell

struct GridCell: Codable, Equatable {
    let row: Int      // 0-2
    let col: Int      // 0-2
    var enabled: Bool
}

// MARK: - GridConfig

struct GridConfig: Codable, Equatable {
    var cells: [[Bool]]  // 3x3 grid of enabled/disabled

    var rows: Int { cells.count }
    var cols: Int { cells.first?.count ?? 0 }

    /// Default config: 3x3 with all cells enabled.
    static let defaultConfig = GridConfig(
        cells: Array(repeating: Array(repeating: true, count: 3), count: 3)
    )

    /// Returns true if the given position is within bounds and enabled.
    func isEnabled(row: Int, col: Int) -> Bool {
        guard row >= 0, row < rows, col >= 0, col < cols else { return false }
        return cells[row][col]
    }
}

// MARK: - GridModel

final class GridModel: ObservableObject {

    // MARK: Singleton

    static let shared = GridModel()

    // MARK: Published State

    @Published private(set) var currentRow: Int = 0
    @Published private(set) var currentCol: Int = 0
    @Published var config: GridConfig {
        didSet {
            if config != oldValue {
                saveConfig()
                NotificationCenter.default.post(name: .gridConfigChanged, object: self)
            }
        }
    }

    // MARK: Constants

    static let maxRows = 3
    static let maxCols = 3

    // MARK: Config Persistence

    private static let configDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/nirvana", isDirectory: true)
    }()

    private static var configFileURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    // MARK: Init

    init(config: GridConfig = GridConfig.defaultConfig) {
        self.config = config
    }

    /// Creates a GridModel by loading persisted config, falling back to defaults.
    convenience init(loadFromDisk: Bool) {
        if loadFromDisk, let loaded = GridModel.loadConfigFromDisk() {
            self.init(config: loaded)
        } else {
            self.init()
        }
    }

    // MARK: - Navigation

    /// Attempt to move in the given direction. Returns true if the move succeeded.
    /// Navigation skips disabled cells. No wrapping at edges.
    @discardableResult
    func move(_ direction: Direction) -> Bool {
        let (dRow, dCol) = delta(for: direction)
        var newRow = currentRow + dRow
        var newCol = currentCol + dCol

        // Walk in the direction, skipping disabled cells, until we find an
        // enabled cell or go out of bounds.
        while isInBounds(row: newRow, col: newCol) {
            if config.isEnabled(row: newRow, col: newCol) {
                let oldRow = currentRow
                let oldCol = currentCol
                currentRow = newRow
                currentCol = newCol
                NotificationCenter.default.post(
                    name: .gridPositionChanged,
                    object: self,
                    userInfo: [
                        "oldRow": oldRow,
                        "oldCol": oldCol,
                        "newRow": newRow,
                        "newCol": newCol
                    ]
                )
                return true
            }
            newRow += dRow
            newCol += dCol
        }
        return false
    }

    /// Move directly to a specific cell. Returns true if the cell is valid and enabled.
    @discardableResult
    func moveTo(row: Int, col: Int) -> Bool {
        guard isInBounds(row: row, col: col), config.isEnabled(row: row, col: col) else {
            return false
        }
        let oldRow = currentRow
        let oldCol = currentCol
        guard row != oldRow || col != oldCol else { return true }
        currentRow = row
        currentCol = col
        NotificationCenter.default.post(
            name: .gridPositionChanged,
            object: self,
            userInfo: [
                "oldRow": oldRow,
                "oldCol": oldCol,
                "newRow": row,
                "newCol": col
            ]
        )
        return true
    }

    // MARK: - Cell Toggle

    /// Enable or disable a cell. Cannot disable the current position.
    @discardableResult
    func toggleCell(row: Int, col: Int) -> Bool {
        guard isInBounds(row: row, col: col) else { return false }
        let newValue = !config.cells[row][col]
        // Prevent disabling the cell we're currently on.
        if !newValue && row == currentRow && col == currentCol {
            return false
        }
        config.cells[row][col] = newValue
        return true
    }

    /// Explicitly set a cell's enabled state.
    @discardableResult
    func setCell(row: Int, col: Int, enabled: Bool) -> Bool {
        guard isInBounds(row: row, col: col) else { return false }
        if !enabled && row == currentRow && col == currentCol {
            return false
        }
        config.cells[row][col] = enabled
        return true
    }

    // MARK: - Space Mapping

    /// Maps a grid cell to a macOS Space ID (1-indexed).
    /// Row 0 (bottom) = Spaces 1-3, Row 1 = Spaces 4-6, Row 2 = Spaces 7-9.
    func spaceIDForCell(row: Int, col: Int) -> Int? {
        guard isInBounds(row: row, col: col), config.isEnabled(row: row, col: col) else {
            return nil
        }
        return row * config.cols + col + 1
    }

    /// Reverse lookup: macOS Space ID -> GridCell.
    func cellForSpaceID(_ spaceID: Int) -> GridCell? {
        guard spaceID >= 1 else { return nil }
        let index = spaceID - 1
        let row = index / config.cols
        let col = index % config.cols
        guard isInBounds(row: row, col: col) else { return nil }
        return GridCell(row: row, col: col, enabled: config.cells[row][col])
    }

    /// The Space ID for the current position.
    var currentSpaceID: Int? {
        spaceIDForCell(row: currentRow, col: currentCol)
    }

    // MARK: - Enabled Cells

    /// All currently enabled cells.
    var enabledCells: [GridCell] {
        var result: [GridCell] = []
        for row in 0..<config.rows {
            for col in 0..<config.cols {
                if config.cells[row][col] {
                    result.append(GridCell(row: row, col: col, enabled: true))
                }
            }
        }
        return result
    }

    /// All cells (enabled and disabled).
    var allCells: [GridCell] {
        var result: [GridCell] = []
        for row in 0..<config.rows {
            for col in 0..<config.cols {
                result.append(GridCell(row: row, col: col, enabled: config.cells[row][col]))
            }
        }
        return result
    }

    // MARK: - Persistence

    func saveConfig() {
        do {
            try FileManager.default.createDirectory(
                at: GridModel.configDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: GridModel.configFileURL, options: .atomic)
        } catch {
            print("[Nirvana] Failed to save config: \(error)")
        }
    }

    static func loadConfigFromDisk() -> GridConfig? {
        guard let data = try? Data(contentsOf: configFileURL) else { return nil }
        return try? JSONDecoder().decode(GridConfig.self, from: data)
    }

    /// Resets config to defaults and removes persisted file.
    func resetToDefaults() {
        config = .defaultConfig
        currentRow = 0
        currentCol = 0
        try? FileManager.default.removeItem(at: GridModel.configFileURL)
    }

    // MARK: - Private Helpers

    private func isInBounds(row: Int, col: Int) -> Bool {
        row >= 0 && row < config.rows && col >= 0 && col < config.cols
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
