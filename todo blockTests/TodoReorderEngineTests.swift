//
//  TodoReorderEngineTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/2/22.
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoReorderEngineTests: XCTestCase {
    private var descriptor: ModelContainer!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        descriptor = try ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: descriptor.mainContext)
    }

    func testPerformMoveMovesParentAndChildrenAsABlock() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 2, day: 22)

        let parent = store.createItem(title: "parent", dayDate: dayDate, indentLevel: 0)
        let child = store.createItem(
            title: "child",
            dayDate: dayDate,
            afterItem: parent,
            indentLevel: 1
        )
        let sibling = store.createItem(
            title: "sibling",
            dayDate: dayDate,
            afterItem: child,
            indentLevel: 0
        )
        let initialItems = store.items(for: dayDate)

        TodoReorderMoveEngine.performMove(
            draggedId: parent.id,
            toIndex: 3,
            indentLevel: 0,
            items: initialItems,
            destination: .scheduled(date: dayDate),
            store: store
        )

        let reordered = store.items(for: dayDate)
        XCTAssertEqual(reordered.map(\.id), [sibling.id, parent.id, child.id])
        XCTAssertEqual(parent.indentLevel, 0)
        XCTAssertEqual(child.indentLevel, 1)
    }

    func testDraggingSelectedSiblingChildrenMovesThemTogether() {
        let store = TodoStore.shared
        let selectionManager = SelectionManager()
        let dayDate = date(year: 2026, month: 2, day: 22)

        let parent = store.createItem(title: "parent", dayDate: dayDate, indentLevel: 0)
        let firstChild = store.createItem(
            title: "first child",
            dayDate: dayDate,
            afterItem: parent,
            indentLevel: 1
        )
        let secondChild = store.createItem(
            title: "second child",
            dayDate: dayDate,
            afterItem: firstChild,
            indentLevel: 1
        )
        let tail = store.createItem(
            title: "tail",
            dayDate: dayDate,
            afterItem: secondChild,
            indentLevel: 0
        )
        selectionManager.selectedItemIds = [firstChild.id, secondChild.id]
        selectionManager.focusedItemId = firstChild.id
        selectionManager.lastSelectedId = secondChild.id

        let moved = TodoSelectionDragMoveEngine.performMove(
            TodoSelectionDragMoveRequest(
                draggedId: firstChild.id,
                destination: .scheduled(date: dayDate),
                insertionIndex: 4,
                indentLevel: 0
            ),
            store: store,
            selectionManager: selectionManager
        )

        XCTAssertTrue(moved)
        XCTAssertEqual(
            store.items(for: dayDate).map(\.id),
            [parent.id, tail.id, firstChild.id, secondChild.id]
        )
        XCTAssertEqual(firstChild.indentLevel, 0)
        XCTAssertEqual(secondChild.indentLevel, 0)
        XCTAssertEqual(selectionManager.selectedItemIds, [firstChild.id, secondChild.id])
    }

    func testSelectionDragMoveDefersSingleSelectedParentToRegularMove() {
        let store = TodoStore.shared
        let selectionManager = SelectionManager()
        let dayDate = date(year: 2026, month: 2, day: 22)

        let parent = store.createItem(title: "parent", dayDate: dayDate, indentLevel: 0)
        let child = store.createItem(
            title: "child",
            dayDate: dayDate,
            afterItem: parent,
            indentLevel: 1
        )
        let tail = store.createItem(
            title: "tail",
            dayDate: dayDate,
            afterItem: child,
            indentLevel: 0
        )
        selectionManager.selectedItemIds = [parent.id]

        let moved = TodoSelectionDragMoveEngine.performMove(
            TodoSelectionDragMoveRequest(
                draggedId: parent.id,
                destination: .scheduled(date: dayDate),
                insertionIndex: 3,
                indentLevel: 0
            ),
            store: store,
            selectionManager: selectionManager
        )

        XCTAssertFalse(moved)
        XCTAssertEqual(store.items(for: dayDate).map(\.id), [parent.id, child.id, tail.id])
    }

    func testPerformMoveClampsIndentAgainstPreviousItem() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 2, day: 22)

        let first = store.createItem(title: "first", dayDate: dayDate, indentLevel: 0)
        let dragged = store.createItem(
            title: "dragged",
            dayDate: dayDate,
            afterItem: first,
            indentLevel: 0
        )
        let tail = store.createItem(
            title: "tail",
            dayDate: dayDate,
            afterItem: dragged,
            indentLevel: 0
        )

        TodoReorderMoveEngine.performMove(
            draggedId: dragged.id,
            toIndex: 3,
            indentLevel: TodoItem.maxIndentLevel,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertEqual(dragged.indentLevel, 1)
        XCTAssertEqual(store.items(for: dayDate).map(\.id), [first.id, tail.id, dragged.id])
    }

    func testPerformMoveKeepsNormalizedDescendantWhoseRawIndentIsShallower() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 2, day: 22)

        let moving = store.createItem(title: "moving", dayDate: dayDate, indentLevel: 3)
        let descendant = store.createItem(
            title: "descendant",
            dayDate: dayDate,
            afterItem: moving,
            indentLevel: 2
        )
        _ = store.createItem(
            title: "sibling",
            dayDate: dayDate,
            afterItem: descendant,
            indentLevel: 0
        )

        TodoReorderMoveEngine.performMove(
            draggedId: moving.id,
            toIndex: 3,
            indentLevel: 0,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertEqual(
            store.items(for: dayDate).map(\.title),
            ["sibling", "moving", "descendant"]
        )
        XCTAssertEqual(moving.indentLevel, 0)
        XCTAssertEqual(descendant.indentLevel, 1)
    }

    func testPerformMoveIntoOwnDescendantsDoesNothing() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 2, day: 22)

        let parent = store.createItem(title: "parent", dayDate: dayDate, indentLevel: 0)
        let child = store.createItem(
            title: "child",
            dayDate: dayDate,
            afterItem: parent,
            indentLevel: 1
        )
        let grandchild = store.createItem(
            title: "grandchild",
            dayDate: dayDate,
            afterItem: child,
            indentLevel: 2
        )
        _ = store.createItem(
            title: "tail",
            dayDate: dayDate,
            afterItem: grandchild,
            indentLevel: 0
        )

        TodoReorderMoveEngine.performMove(
            draggedId: parent.id,
            toIndex: 2,
            indentLevel: 1,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertEqual(
            store.items(for: dayDate).map(\.title),
            ["parent", "child", "grandchild", "tail"]
        )
        XCTAssertEqual(parent.indentLevel, 0)
    }

    func testPerformMoveOntoOwnPositionDoesNothing() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 2, day: 22)

        let first = store.createItem(title: "first", dayDate: dayDate, indentLevel: 0)
        let moving = store.createItem(
            title: "moving",
            dayDate: dayDate,
            afterItem: first,
            indentLevel: 0
        )
        let originalSortOrder = moving.sortOrder
        let originalUpdatedAt = moving.updatedAt

        TodoReorderMoveEngine.performMove(
            draggedId: moving.id,
            toIndex: 1,
            indentLevel: 1,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertEqual(store.items(for: dayDate).map(\.id), [first.id, moving.id])
        XCTAssertEqual(moving.indentLevel, 0)
        XCTAssertEqual(moving.sortOrder, originalSortOrder)
        XCTAssertEqual(moving.updatedAt, originalUpdatedAt)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar.current
        return calendar.startOfDay(for: calendar.date(from: components) ?? Date())
    }
}
