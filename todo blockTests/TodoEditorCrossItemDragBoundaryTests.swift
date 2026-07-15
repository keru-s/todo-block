import CoreGraphics
import XCTest
@testable import todo_block

final class TodoEditorCrossItemDragBoundaryTests: XCTestCase {
    private let rowFrame = CGRect(x: 20, y: 100, width: 320, height: 64)
    private let titleFrame = CGRect(x: 72, y: 104, width: 180, height: 56)
    private let horizontalProtection: CGFloat = 42

    func testRemainingInsideTheCurrentRowAndProtectionKeepsTextSelection() {
        XCTAssertFalse(
            TodoEditorCrossItemDragBoundary.hasExitedTextSelectionRegion(
                at: CGPoint(x: 280, y: 120),
                rowFrame: rowFrame,
                titleFrame: titleFrame,
                horizontalProtection: horizontalProtection
            )
        )
    }

    func testMovingAboveOrBelowTheCurrentRowStartsItemSelection() {
        XCTAssertTrue(
            TodoEditorCrossItemDragBoundary.hasExitedTextSelectionRegion(
                at: CGPoint(x: 120, y: 99),
                rowFrame: rowFrame,
                titleFrame: titleFrame,
                horizontalProtection: horizontalProtection
            )
        )
        XCTAssertTrue(
            TodoEditorCrossItemDragBoundary.hasExitedTextSelectionRegion(
                at: CGPoint(x: 120, y: 165),
                rowFrame: rowFrame,
                titleFrame: titleFrame,
                horizontalProtection: horizontalProtection
            )
        )
    }

    func testMovingPastTheThreeCharacterProtectionStartsItemSelection() {
        XCTAssertFalse(
            TodoEditorCrossItemDragBoundary.hasExitedTextSelectionRegion(
                at: CGPoint(x: 30, y: 130),
                rowFrame: rowFrame,
                titleFrame: titleFrame,
                horizontalProtection: horizontalProtection
            )
        )
        XCTAssertTrue(
            TodoEditorCrossItemDragBoundary.hasExitedTextSelectionRegion(
                at: CGPoint(x: 29, y: 130),
                rowFrame: rowFrame,
                titleFrame: titleFrame,
                horizontalProtection: horizontalProtection
            )
        )
        XCTAssertFalse(
            TodoEditorCrossItemDragBoundary.hasExitedTextSelectionRegion(
                at: CGPoint(x: 294, y: 130),
                rowFrame: rowFrame,
                titleFrame: titleFrame,
                horizontalProtection: horizontalProtection
            )
        )
        XCTAssertTrue(
            TodoEditorCrossItemDragBoundary.hasExitedTextSelectionRegion(
                at: CGPoint(x: 295, y: 130),
                rowFrame: rowFrame,
                titleFrame: titleFrame,
                horizontalProtection: horizontalProtection
            )
        )
    }
}
