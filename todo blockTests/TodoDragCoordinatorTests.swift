//
//  TodoDragCoordinatorTests.swift
//  todo blockTests
//
//  Created by 327776 on 2026/3/24.
//

import XCTest
@testable import todo_block

@MainActor
final class TodoDragCoordinatorTests: XCTestCase {
    private var coordinator: TodoDragCoordinator!

    override func setUp() async throws {
        coordinator = TodoDragCoordinator.shared
        coordinator.cancelDrag()
        coordinator.removeAllSidebarTargets()
    }

    override func tearDown() async throws {
        coordinator.cancelDrag()
        coordinator.removeAllSidebarTargets()
    }

    // MARK: - Lifecycle

    func testBeginDragSetsActiveState() {
        let id = UUID()
        coordinator.beginDrag(itemId: id)

        XCTAssertTrue(coordinator.isDragging)
        XCTAssertEqual(coordinator.draggedItemId, id)
    }

    func testUpdateDragRecordsGlobalLocation() {
        let id = UUID()
        coordinator.beginDrag(itemId: id)
        coordinator.updateDrag(globalLocation: CGPoint(x: 100, y: 200))

        XCTAssertEqual(coordinator.globalDragLocation, CGPoint(x: 100, y: 200))
    }

    func testEndDragReturnsFinalStateAndClears() {
        let id = UUID()
        coordinator.beginDrag(itemId: id)
        coordinator.updateDrag(globalLocation: CGPoint(x: 50, y: 60))

        let result = coordinator.endDrag()

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.itemId, id)
        XCTAssertEqual(result?.globalLocation, CGPoint(x: 50, y: 60))
        XCTAssertFalse(coordinator.isDragging)
        XCTAssertNil(coordinator.draggedItemId)
        XCTAssertNil(coordinator.globalDragLocation)
    }

    func testEndDragReturnsNilWhenNoDragActive() {
        let result = coordinator.endDrag()
        XCTAssertNil(result)
    }

    func testCancelDragClearsState() {
        coordinator.beginDrag(itemId: UUID())
        coordinator.updateDrag(globalLocation: CGPoint(x: 10, y: 20))
        coordinator.cancelDrag()

        XCTAssertFalse(coordinator.isDragging)
        XCTAssertNil(coordinator.draggedItemId)
        XCTAssertNil(coordinator.globalDragLocation)
    }

    // MARK: - Sidebar targets

    func testRegisterAndQuerySidebarTarget() {
        let dest = SidebarDestination.month(year: 2026, month: 3)
        coordinator.registerSidebarTarget(dest, frame: CGRect(x: 0, y: 100, width: 150, height: 30))

        XCTAssertEqual(
            coordinator.sidebarTarget(at: CGPoint(x: 75, y: 115)),
            dest
        )
    }

    func testSidebarTargetReturnsNilForPointOutsideFrame() {
        let dest = SidebarDestination.longTerm
        coordinator.registerSidebarTarget(dest, frame: CGRect(x: 0, y: 0, width: 150, height: 30))

        XCTAssertNil(coordinator.sidebarTarget(at: CGPoint(x: 75, y: 100)))
    }

    func testHoveredSidebarDestinationDuringDrag() {
        let dest = SidebarDestination.longTerm
        coordinator.registerSidebarTarget(dest, frame: CGRect(x: 0, y: 0, width: 150, height: 30))

        coordinator.beginDrag(itemId: UUID())
        coordinator.updateDrag(globalLocation: CGPoint(x: 75, y: 15))

        XCTAssertEqual(coordinator.hoveredSidebarDestination, dest)
    }

    func testHoveredSidebarDestinationIsNilWhenNotDragging() {
        let dest = SidebarDestination.longTerm
        coordinator.registerSidebarTarget(dest, frame: CGRect(x: 0, y: 0, width: 150, height: 30))

        XCTAssertNil(coordinator.hoveredSidebarDestination)
    }

    func testUpdatingSidebarTargetFrameOverwritesPrevious() {
        let dest = SidebarDestination.month(year: 2026, month: 1)
        coordinator.registerSidebarTarget(dest, frame: CGRect(x: 0, y: 0, width: 150, height: 30))
        coordinator.registerSidebarTarget(dest, frame: CGRect(x: 0, y: 200, width: 150, height: 30))

        XCTAssertNil(coordinator.sidebarTarget(at: CGPoint(x: 75, y: 15)))
        XCTAssertEqual(
            coordinator.sidebarTarget(at: CGPoint(x: 75, y: 215)),
            dest
        )
    }
}
