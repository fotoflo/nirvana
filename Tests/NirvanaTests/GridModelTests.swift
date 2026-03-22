import XCTest
@testable import Nirvana

final class GridModelTests: XCTestCase {

    // Fresh model for each test — all cells enabled, position at (0,0).
    private func makeModel() -> GridModel {
        GridModel(config: .defaultConfig)
    }

    // MARK: - Initial State

    func testDefaultInitialState() {
        let model = makeModel()
        XCTAssertEqual(model.currentRow, 0)
        XCTAssertEqual(model.currentCol, 0)
        XCTAssertEqual(model.config.rows, 3)
        XCTAssertEqual(model.config.cols, 3)
    }

    func testAllCellsEnabledByDefault() {
        let model = makeModel()
        for row in 0..<3 {
            for col in 0..<3 {
                XCTAssertTrue(model.config.isEnabled(row: row, col: col),
                              "Cell (\(row),\(col)) should be enabled by default")
            }
        }
    }

    func testEnabledCellsDefault() {
        let model = makeModel()
        XCTAssertEqual(model.enabledCells.count, 9)
    }

    // MARK: - Navigation Basics

    func testMoveRight() {
        let model = makeModel()
        XCTAssertTrue(model.move(.right))
        XCTAssertEqual(model.currentRow, 0)
        XCTAssertEqual(model.currentCol, 1)
    }

    func testMoveUp() {
        let model = makeModel()
        XCTAssertTrue(model.move(.up))
        XCTAssertEqual(model.currentRow, 1)
        XCTAssertEqual(model.currentCol, 0)
    }

    func testMoveDown() {
        let model = makeModel()
        // Start at row 1 so we can move down.
        model.moveTo(row: 1, col: 0)
        XCTAssertTrue(model.move(.down))
        XCTAssertEqual(model.currentRow, 0)
        XCTAssertEqual(model.currentCol, 0)
    }

    func testMoveLeft() {
        let model = makeModel()
        model.moveTo(row: 0, col: 1)
        XCTAssertTrue(model.move(.left))
        XCTAssertEqual(model.currentRow, 0)
        XCTAssertEqual(model.currentCol, 0)
    }

    func testSequentialMoves() {
        let model = makeModel()
        XCTAssertTrue(model.move(.right))   // (0,1)
        XCTAssertTrue(model.move(.right))   // (0,2)
        XCTAssertTrue(model.move(.up))      // (1,2)
        XCTAssertTrue(model.move(.left))    // (1,1)
        XCTAssertEqual(model.currentRow, 1)
        XCTAssertEqual(model.currentCol, 1)
    }

    // MARK: - Edge Behavior (No Wrap)

    func testNoWrapLeft() {
        let model = makeModel()
        XCTAssertFalse(model.move(.left))
        XCTAssertEqual(model.currentCol, 0)
    }

    func testNoWrapDown() {
        let model = makeModel()
        XCTAssertFalse(model.move(.down))
        XCTAssertEqual(model.currentRow, 0)
    }

    func testNoWrapRight() {
        let model = makeModel()
        model.moveTo(row: 0, col: 2)
        XCTAssertFalse(model.move(.right))
        XCTAssertEqual(model.currentCol, 2)
    }

    func testNoWrapUp() {
        let model = makeModel()
        model.moveTo(row: 2, col: 0)
        XCTAssertFalse(model.move(.up))
        XCTAssertEqual(model.currentRow, 2)
    }

    // MARK: - Disabled Cell Skipping

    func testSkipDisabledCellRight() {
        let model = makeModel()
        // Disable (0,1) — moving right from (0,0) should skip to (0,2).
        model.setCell(row: 0, col: 1, enabled: false)
        XCTAssertTrue(model.move(.right))
        XCTAssertEqual(model.currentRow, 0)
        XCTAssertEqual(model.currentCol, 2)
    }

    func testSkipDisabledCellUp() {
        let model = makeModel()
        // Disable (1,0) — moving up from (0,0) should skip to (2,0).
        model.setCell(row: 1, col: 0, enabled: false)
        XCTAssertTrue(model.move(.up))
        XCTAssertEqual(model.currentRow, 2)
        XCTAssertEqual(model.currentCol, 0)
    }

    func testCannotMoveIfAllTargetsDisabled() {
        let model = makeModel()
        // Disable (0,1) and (0,2) — can't move right from (0,0).
        model.setCell(row: 0, col: 1, enabled: false)
        model.setCell(row: 0, col: 2, enabled: false)
        XCTAssertFalse(model.move(.right))
        XCTAssertEqual(model.currentCol, 0)
    }

    func testCannotNavigateToDisabledCell() {
        let model = makeModel()
        model.setCell(row: 0, col: 1, enabled: false)
        XCTAssertFalse(model.moveTo(row: 0, col: 1))
        XCTAssertEqual(model.currentCol, 0)
    }

    // MARK: - Cell Toggle

    func testToggleCell() {
        let model = makeModel()
        XCTAssertTrue(model.toggleCell(row: 1, col: 1))
        XCTAssertFalse(model.config.isEnabled(row: 1, col: 1))
        XCTAssertTrue(model.toggleCell(row: 1, col: 1))
        XCTAssertTrue(model.config.isEnabled(row: 1, col: 1))
    }

    func testCannotDisableCurrentCell() {
        let model = makeModel()
        XCTAssertFalse(model.toggleCell(row: 0, col: 0))
        XCTAssertTrue(model.config.isEnabled(row: 0, col: 0))
    }

    func testEnabledCellsAfterDisabling() {
        let model = makeModel()
        model.setCell(row: 2, col: 2, enabled: false)
        model.setCell(row: 1, col: 1, enabled: false)
        XCTAssertEqual(model.enabledCells.count, 7)
        // Verify the disabled ones are not in the list.
        XCTAssertFalse(model.enabledCells.contains(GridCell(row: 2, col: 2, enabled: true)))
        XCTAssertFalse(model.enabledCells.contains(GridCell(row: 1, col: 1, enabled: true)))
    }

    // MARK: - Space ID Mapping

    func testSpaceIDForRow0() {
        let model = makeModel()
        // Row 0 = Spaces 1, 2, 3
        XCTAssertEqual(model.spaceIDForCell(row: 0, col: 0), 1)
        XCTAssertEqual(model.spaceIDForCell(row: 0, col: 1), 2)
        XCTAssertEqual(model.spaceIDForCell(row: 0, col: 2), 3)
    }

    func testSpaceIDForRow1() {
        let model = makeModel()
        // Row 1 = Spaces 4, 5, 6
        XCTAssertEqual(model.spaceIDForCell(row: 1, col: 0), 4)
        XCTAssertEqual(model.spaceIDForCell(row: 1, col: 1), 5)
        XCTAssertEqual(model.spaceIDForCell(row: 1, col: 2), 6)
    }

    func testSpaceIDForRow2() {
        let model = makeModel()
        // Row 2 = Spaces 7, 8, 9
        XCTAssertEqual(model.spaceIDForCell(row: 2, col: 0), 7)
        XCTAssertEqual(model.spaceIDForCell(row: 2, col: 1), 8)
        XCTAssertEqual(model.spaceIDForCell(row: 2, col: 2), 9)
    }

    func testSpaceIDForDisabledCell() {
        let model = makeModel()
        model.setCell(row: 1, col: 1, enabled: false)
        XCTAssertNil(model.spaceIDForCell(row: 1, col: 1))
    }

    func testCurrentSpaceID() {
        let model = makeModel()
        XCTAssertEqual(model.currentSpaceID, 1)
        model.moveTo(row: 1, col: 2)
        XCTAssertEqual(model.currentSpaceID, 6)
    }

    // MARK: - Reverse Lookup (Space ID -> Cell)

    func testCellForSpaceID() {
        let model = makeModel()
        let cell1 = model.cellForSpaceID(1)
        XCTAssertEqual(cell1, GridCell(row: 0, col: 0, enabled: true))

        let cell5 = model.cellForSpaceID(5)
        XCTAssertEqual(cell5, GridCell(row: 1, col: 1, enabled: true))

        let cell9 = model.cellForSpaceID(9)
        XCTAssertEqual(cell9, GridCell(row: 2, col: 2, enabled: true))
    }

    func testCellForInvalidSpaceID() {
        let model = makeModel()
        XCTAssertNil(model.cellForSpaceID(0))
        XCTAssertNil(model.cellForSpaceID(-1))
        XCTAssertNil(model.cellForSpaceID(10))
    }

    func testCellForSpaceIDReflectsDisabled() {
        let model = makeModel()
        model.setCell(row: 0, col: 2, enabled: false)
        let cell = model.cellForSpaceID(3)
        XCTAssertNotNil(cell)
        XCTAssertEqual(cell?.enabled, false)
    }

    // MARK: - MoveTo

    func testMoveToValidCell() {
        let model = makeModel()
        XCTAssertTrue(model.moveTo(row: 2, col: 2))
        XCTAssertEqual(model.currentRow, 2)
        XCTAssertEqual(model.currentCol, 2)
    }

    func testMoveToSamePosition() {
        let model = makeModel()
        // Should succeed (no-op) but not crash.
        XCTAssertTrue(model.moveTo(row: 0, col: 0))
        XCTAssertEqual(model.currentRow, 0)
        XCTAssertEqual(model.currentCol, 0)
    }

    func testMoveToOutOfBounds() {
        let model = makeModel()
        XCTAssertFalse(model.moveTo(row: 3, col: 0))
        XCTAssertFalse(model.moveTo(row: -1, col: 0))
        XCTAssertFalse(model.moveTo(row: 0, col: 3))
        XCTAssertEqual(model.currentRow, 0)
        XCTAssertEqual(model.currentCol, 0)
    }

    // MARK: - Config Persistence

    func testSaveAndLoadConfig() {
        let model = makeModel()
        model.setCell(row: 1, col: 1, enabled: false)
        model.setCell(row: 2, col: 0, enabled: false)
        model.saveConfig()

        let loaded = GridModel.loadConfigFromDisk()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded, model.config)
        XCTAssertFalse(loaded!.isEnabled(row: 1, col: 1))
        XCTAssertFalse(loaded!.isEnabled(row: 2, col: 0))
        XCTAssertTrue(loaded!.isEnabled(row: 0, col: 0))

        // Clean up.
        model.resetToDefaults()
    }

    func testResetToDefaults() {
        let model = makeModel()
        model.moveTo(row: 2, col: 2)
        model.setCell(row: 1, col: 1, enabled: false)
        model.resetToDefaults()

        XCTAssertEqual(model.currentRow, 0)
        XCTAssertEqual(model.currentCol, 0)
        XCTAssertTrue(model.config.isEnabled(row: 1, col: 1))
        XCTAssertEqual(model.enabledCells.count, 9)
    }

    // MARK: - Notifications

    func testPositionChangedNotification() {
        let model = makeModel()
        let expectation = XCTestExpectation(description: "gridPositionChanged fires")

        let observer = NotificationCenter.default.addObserver(
            forName: .gridPositionChanged,
            object: model,
            queue: nil
        ) { notification in
            XCTAssertEqual(notification.userInfo?["oldRow"] as? Int, 0)
            XCTAssertEqual(notification.userInfo?["oldCol"] as? Int, 0)
            XCTAssertEqual(notification.userInfo?["newRow"] as? Int, 0)
            XCTAssertEqual(notification.userInfo?["newCol"] as? Int, 1)
            expectation.fulfill()
        }

        model.move(.right)
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    func testConfigChangedNotification() {
        let model = makeModel()
        let expectation = XCTestExpectation(description: "gridConfigChanged fires")

        let observer = NotificationCenter.default.addObserver(
            forName: .gridConfigChanged,
            object: model,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }

        model.setCell(row: 2, col: 2, enabled: false)
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - GridConfig

    func testGridConfigEquality() {
        let a = GridConfig.defaultConfig
        let b = GridConfig.defaultConfig
        XCTAssertEqual(a, b)
    }

    func testGridConfigOutOfBounds() {
        let config = GridConfig.defaultConfig
        XCTAssertFalse(config.isEnabled(row: -1, col: 0))
        XCTAssertFalse(config.isEnabled(row: 0, col: 3))
        XCTAssertFalse(config.isEnabled(row: 3, col: 0))
    }

    // MARK: - GridCell

    func testGridCellEquality() {
        let a = GridCell(row: 1, col: 2, enabled: true)
        let b = GridCell(row: 1, col: 2, enabled: true)
        XCTAssertEqual(a, b)

        let c = GridCell(row: 1, col: 2, enabled: false)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Edge Cases

    func testAllCellsProperty() {
        let model = makeModel()
        XCTAssertEqual(model.allCells.count, 9)
    }

    func testToggleOutOfBounds() {
        let model = makeModel()
        XCTAssertFalse(model.toggleCell(row: 3, col: 0))
        XCTAssertFalse(model.toggleCell(row: 0, col: -1))
    }

    func testSetCellOutOfBounds() {
        let model = makeModel()
        XCTAssertFalse(model.setCell(row: -1, col: 0, enabled: true))
    }

    func testSkipMultipleDisabledCells() {
        let model = makeModel()
        // Disable (1,0) and (2,0) — can't move up at all from (0,0).
        model.setCell(row: 1, col: 0, enabled: false)
        model.setCell(row: 2, col: 0, enabled: false)
        XCTAssertFalse(model.move(.up))
        XCTAssertEqual(model.currentRow, 0)
    }
}
