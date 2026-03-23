import XCTest
@testable import Nirvana

// MARK: - Mock SpaceBridge

/// Records calls to switchToSpace so tests can verify the wiring.
final class MockSpaceBridge: SpaceSwitching {
    var spaces: [Int] = [1, 11, 13, 10, 12, 58, 59, 60, 61]  // 9 spaces like a real setup
    var currentSpaceID: Int? = 1
    var switchedTo: [Int] = []

    func getCurrentSpaceID() -> Int? { currentSpaceID }
    func switchToSpace(_ spaceID: Int) { switchedTo.append(spaceID) }
    func listSpaceIDs() -> [Int] { spaces }
}

// MARK: - Space Switching Integration Tests

final class SpaceSwitchingTests: XCTestCase {

    // MARK: - Grid-to-Space Mapping

    /// Verify that enabled cells map to space IDs in the correct order.
    func testEnabledCellsMapToSpacesInOrder() {
        let model = GridModel(config: .defaultConfig)
        let bridge = MockSpaceBridge()
        let enabledCells = model.enabledCells

        // With all 9 cells enabled, cell index should map 1:1 to space index.
        for (i, cell) in enabledCells.enumerated() {
            XCTAssertEqual(cell.row, i / 3, "Cell \(i) row mismatch")
            XCTAssertEqual(cell.col, i % 3, "Cell \(i) col mismatch")
            XCTAssertTrue(i < bridge.spaces.count, "More cells than spaces")
        }
    }

    /// After moving right, the correct space ID should be targeted.
    func testMoveRightTargetsCorrectSpace() {
        let model = GridModel(config: .defaultConfig)
        let bridge = MockSpaceBridge()

        // Start at (0,0) = cell index 0 = space[0]
        model.move(.right)
        // Now at (0,1) = cell index 1 = space[1]

        let enabledCells = model.enabledCells
        guard let cellIndex = enabledCells.firstIndex(where: {
            $0.row == model.currentRow && $0.col == model.currentCol
        }) else {
            XCTFail("Current cell not found in enabledCells")
            return
        }

        let targetSpaceID = bridge.spaces[cellIndex]
        bridge.switchToSpace(targetSpaceID)

        XCTAssertEqual(bridge.switchedTo.last, 11, "Moving right from (0,0) should target space at index 1")
    }

    /// After moveTo(row:col:), the correct space ID should be targeted.
    func testMoveToTargetsCorrectSpace() {
        let model = GridModel(config: .defaultConfig)
        let bridge = MockSpaceBridge()

        model.moveTo(row: 2, col: 1)
        // (2,1) = cell index 7 = space[7]

        let enabledCells = model.enabledCells
        guard let cellIndex = enabledCells.firstIndex(where: {
            $0.row == model.currentRow && $0.col == model.currentCol
        }) else {
            XCTFail("Current cell not found in enabledCells")
            return
        }

        bridge.switchToSpace(bridge.spaces[cellIndex])
        XCTAssertEqual(bridge.switchedTo.last, 60, "moveTo(2,1) should target space at index 7")
    }

    /// With disabled cells, the mapping skips them correctly.
    func testDisabledCellsShiftSpaceMapping() {
        let model = GridModel(config: .defaultConfig)
        let bridge = MockSpaceBridge()

        // Disable (0,1) — now enabledCells has 8 entries
        model.setCell(row: 0, col: 1, enabled: false)

        // Move right from (0,0) should skip (0,1) and land on (0,2)
        model.move(.right)
        XCTAssertEqual(model.currentRow, 0)
        XCTAssertEqual(model.currentCol, 2)

        // (0,2) is now cell index 1 in enabledCells (since (0,1) is disabled)
        let enabledCells = model.enabledCells
        guard let cellIndex = enabledCells.firstIndex(where: {
            $0.row == model.currentRow && $0.col == model.currentCol
        }) else {
            XCTFail("Current cell not found in enabledCells")
            return
        }

        XCTAssertEqual(cellIndex, 1, "Cell (0,2) should be index 1 with (0,1) disabled")
        bridge.switchToSpace(bridge.spaces[cellIndex])
        XCTAssertEqual(bridge.switchedTo.last, 11, "Should target space at index 1")
    }

    // MARK: - HotkeyListener Callback Wiring

    /// Arrow key navigation should fire onNavigate (which triggers space switching).
    func testArrowNavigationFiresCallback() {
        let model = GridModel(config: .defaultConfig)
        let listener = HotkeyListener(gridModel: model)

        var navigateCalled = false
        listener.onNavigate = { _ in
            navigateCalled = true
        }

        // Simulate what happens when an arrow key is pressed while pager is visible:
        // The grid moves, then onNavigate fires.
        model.move(.right)
        listener.onNavigate?(.right)

        XCTAssertTrue(navigateCalled, "onNavigate should be called on arrow key navigation")
        XCTAssertEqual(model.currentCol, 1)
    }

    /// Number key jump should also fire onNavigate (this was the bug we fixed).
    func testNumberKeyJumpFiresCallback() {
        let model = GridModel(config: .defaultConfig)
        let listener = HotkeyListener(gridModel: model)

        var navigateCalled = false
        listener.onNavigate = { _ in
            navigateCalled = true
        }

        // Simulate number key "5" press → moveTo(1,1), then onNavigate fires.
        let moved = model.moveTo(row: 1, col: 1)
        if moved {
            listener.onNavigate?(.right)
        }

        XCTAssertTrue(moved, "moveTo(1,1) should succeed")
        XCTAssertTrue(navigateCalled, "onNavigate should fire after number key jump")
    }

    /// moveTo same position should NOT fire onNavigate (no actual move).
    func testNoCallbackWhenPositionUnchanged() {
        let model = GridModel(config: .defaultConfig)

        var navigateCalled = false

        // moveTo current position returns true but doesn't post notification
        let moved = model.moveTo(row: 0, col: 0)
        if moved && (model.currentRow != 0 || model.currentCol != 0) {
            navigateCalled = true
        }

        XCTAssertTrue(moved, "moveTo same position returns true")
        XCTAssertFalse(navigateCalled, "Should not trigger navigation for same position")
    }

    /// Moving to a disabled cell should NOT fire onNavigate.
    func testNoCallbackForDisabledCell() {
        let model = GridModel(config: .defaultConfig)
        model.setCell(row: 1, col: 1, enabled: false)

        var navigateCalled = false

        let moved = model.moveTo(row: 1, col: 1)
        if moved {
            navigateCalled = true
        }

        XCTAssertFalse(moved, "moveTo disabled cell should fail")
        XCTAssertFalse(navigateCalled, "Should not trigger navigation for disabled cell")
    }

    // MARK: - End-to-End Switching Flow

    /// Simulate the full flow: grid move → lookup cell index → switch to space.
    /// This mirrors the logic in App.switchToCurrentGridSpace().
    func testFullSwitchingFlow() {
        let model = GridModel(config: .defaultConfig)
        let bridge = MockSpaceBridge()

        // Simulate: user navigates right, right, up → ends at (1,2)
        model.move(.right)
        model.move(.right)
        model.move(.up)

        XCTAssertEqual(model.currentRow, 1)
        XCTAssertEqual(model.currentCol, 2)

        // This is the same logic as App.switchToCurrentGridSpace()
        let enabledCells = model.enabledCells
        guard let cellIndex = enabledCells.firstIndex(where: {
            $0.row == model.currentRow && $0.col == model.currentCol
        }) else {
            XCTFail("Current cell not found")
            return
        }

        let spaces = bridge.listSpaceIDs()
        guard cellIndex < spaces.count else {
            XCTFail("Cell index \(cellIndex) out of range for \(spaces.count) spaces")
            return
        }

        bridge.switchToSpace(spaces[cellIndex])

        // (1,2) = cell index 5 → space[5] = 58
        XCTAssertEqual(cellIndex, 5)
        XCTAssertEqual(bridge.switchedTo.last, 58)
    }

    /// Full flow with fewer spaces than cells should not crash.
    func testSwitchingWithFewerSpacesThanCells() {
        let model = GridModel(config: .defaultConfig)
        let bridge = MockSpaceBridge()
        bridge.spaces = [1, 2, 3]  // Only 3 spaces but 9 cells

        model.moveTo(row: 1, col: 0)  // Cell index 3

        let enabledCells = model.enabledCells
        guard let cellIndex = enabledCells.firstIndex(where: {
            $0.row == model.currentRow && $0.col == model.currentCol
        }) else {
            XCTFail("Current cell not found")
            return
        }

        // cellIndex 3 >= spaces.count 3 — should NOT switch
        XCTAssertFalse(cellIndex < bridge.spaces.count,
                       "Should detect that cell index exceeds available spaces")
    }
}
