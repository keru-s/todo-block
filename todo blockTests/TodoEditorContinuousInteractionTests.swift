import CoreGraphics
import XCTest
@testable import todo_block

@MainActor
final class TodoEditorContinuousInteractionTests: XCTestCase {
    func testOnlyOneContinuousInteractionCanBeActive() {
        let interaction = TodoEditorContinuousInteraction()
        let itemId = UUID()
        let sectionId = UUID()

        let selectionToken = interaction.beginCrossItemSelection(
            itemId: itemId,
            sectionId: sectionId,
            location: CGPoint(x: 10, y: 20)
        )

        XCTAssertNotNil(selectionToken)
        XCTAssertNil(interaction.beginItemDrag(itemId: UUID()))
        XCTAssertEqual(interaction.activeKind, .crossItemSelection)
        XCTAssertEqual(interaction.activeState?.itemId, itemId)
        XCTAssertEqual(interaction.activeState?.sectionId, sectionId)
    }

    func testInvalidTargetDoesNotReplaceLastValidMouseLocation() throws {
        let interaction = TodoEditorContinuousInteraction()
        let itemId = UUID()
        let token = try XCTUnwrap(
            interaction.beginCrossItemSelection(
                itemId: itemId,
                sectionId: UUID(),
                location: CGPoint(x: 1, y: 2)
            )
        )

        XCTAssertTrue(
            interaction.update(
                token: token,
                itemId: itemId,
                location: CGPoint(x: 3, y: 4),
                targetItemId: UUID()
            )
        )
        let lastValidLocation = interaction.lastValidLocation
        let targetItemId = interaction.targetItemId

        XCTAssertTrue(
            interaction.update(
                token: token,
                itemId: itemId,
                location: CGPoint(x: 100, y: 200),
                targetItemId: nil
            )
        )
        XCTAssertEqual(interaction.lastValidLocation, lastValidLocation)
        XCTAssertEqual(interaction.targetItemId, targetItemId)
    }

    func testEndingOrCancellingMakesLateEventsNoOps() throws {
        let interaction = TodoEditorContinuousInteraction()
        let itemId = UUID()
        let token = try XCTUnwrap(
            interaction.beginCrossItemSelection(
                itemId: itemId,
                sectionId: UUID()
            )
        )

        XCTAssertTrue(interaction.end(token: token))
        XCTAssertFalse(interaction.isActive)
        XCTAssertFalse(interaction.update(token: token, itemId: itemId, targetItemId: UUID()))
        XCTAssertFalse(interaction.end(token: token))
        XCTAssertFalse(interaction.cancel(token: token))
    }

    func testCancelInvalidatesTokenAndPreservesTheProcessBoundary() throws {
        let interaction = TodoEditorContinuousInteraction()
        let selectionToken = try XCTUnwrap(
            interaction.beginCrossItemSelection(
                itemId: UUID(),
                sectionId: UUID()
            )
        )

        XCTAssertTrue(interaction.cancel(token: selectionToken))
        let itemDragToken = try XCTUnwrap(interaction.beginItemDrag(itemId: UUID()))
        XCTAssertNotEqual(selectionToken, itemDragToken)
        XCTAssertEqual(interaction.activeKind, .itemDrag)
    }

    func testItemDragKeepsLastValidDropWhenPointerLeavesTheEditor() throws {
        let interaction = TodoEditorContinuousInteraction()
        let itemId = UUID()
        let firstLocation = CGPoint(x: 20, y: 30)
        let token = try XCTUnwrap(
            interaction.beginItemDrag(itemId: itemId, location: firstLocation)
        )
        let destination = TodoDropDestination.longTerm(isUrgent: false)
        let drop = TodoEditorContinuousDropLocation(
            destination: destination,
            index: 2,
            indentLevel: 1
        )

        XCTAssertTrue(
            interaction.update(
                token: token,
                itemId: itemId,
                location: CGPoint(x: 40, y: 50),
                targetItemId: UUID(),
                validDrop: drop
            )
        )
        XCTAssertEqual(interaction.lastValidDrop, drop)

        let outsideLocation = CGPoint(x: 900, y: 1_200)
        XCTAssertTrue(
            interaction.updateLocation(
                token: token,
                itemId: itemId,
                location: outsideLocation
            )
        )
        XCTAssertEqual(interaction.lastLocation, outsideLocation)
        XCTAssertEqual(interaction.lastValidDrop, drop)
        XCTAssertEqual(interaction.lastValidLocation, CGPoint(x: 40, y: 50))
    }

    func testInvalidatingAnItemDragTargetClearsTargetAndLateEventsAreIgnored() throws {
        let interaction = TodoEditorContinuousInteraction()
        let itemId = UUID()
        let token = try XCTUnwrap(interaction.beginItemDrag(itemId: itemId))

        XCTAssertTrue(interaction.invalidateTarget(token: token, itemId: itemId))
        XCTAssertNil(interaction.targetItemId)
        XCTAssertNil(interaction.lastValidDrop)
        XCTAssertTrue(interaction.cancel(token: token))
        XCTAssertFalse(
            interaction.updateLocation(
                token: token,
                itemId: itemId,
                location: .zero
            )
        )
    }

    func testItemDragTracksSidebarTargetUntilItIsCleared() throws {
        let interaction = TodoEditorContinuousInteraction()
        let itemId = UUID()
        let token = try XCTUnwrap(interaction.beginItemDrag(itemId: itemId))
        let destination = SidebarDestination.month(year: 2026, month: 8)

        XCTAssertTrue(
            interaction.update(
                token: token,
                itemId: itemId,
                location: .zero,
                sidebarDestination: destination
            )
        )
        XCTAssertEqual(interaction.targetSidebarDestination, destination)
        XCTAssertNil(interaction.targetItemId)

        XCTAssertTrue(interaction.clearSidebarTarget(token: token, itemId: itemId))
        XCTAssertNil(interaction.targetSidebarDestination)
        XCTAssertTrue(interaction.cancel(token: token))
    }
}
