//
//  TodoEditorActionFactoryTests.swift
//  todo blockTests
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoEditorActionFactoryTests: XCTestCase {
    private var container: ModelContainer!
    private var selectionManager: SelectionManager!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: config
        )

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
        selectionManager = SelectionManager()
    }

    func testToggleCompletedActionTogglesParentAndChildren() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let parent = store.createItem(title: "parent", dayDate: day, indentLevel: 0)
        let child = store.createItem(title: "child", dayDate: day, afterItem: parent, indentLevel: 1)
        let actions = TodoEditorActionFactory.make(store: store, selectionManager: selectionManager)

        actions.toggleCompleted(parent.id)

        XCTAssertTrue(parent.isCompleted)
        XCTAssertTrue(child.isCompleted)
    }

    func testKeyboardMoveActionMovesBlockAndRestoresFocus() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let moving = store.createItem(title: "moving", dayDate: day, indentLevel: 0)
        let child = store.createItem(title: "child", dayDate: day, afterItem: moving, indentLevel: 1)
        let next = store.createItem(title: "next", dayDate: day, afterItem: child, indentLevel: 0)
        let actions = TodoEditorActionFactory.make(store: store, selectionManager: selectionManager)

        actions.moveItemByKeyboard(moving.id, .down)

        XCTAssertEqual(store.items(for: day).map(\.id), [next.id, moving.id, child.id])
        XCTAssertEqual(selectionManager.focusedItemId, moving.id)
    }

    func testDragSelectionActionsSelectContinuousRange() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let first = store.createItem(title: "first", dayDate: day)
        let second = store.createItem(title: "second", dayDate: day)
        let third = store.createItem(title: "third", dayDate: day)
        let actions = TodoEditorActionFactory.make(store: store, selectionManager: selectionManager)

        actions.beginDragSelection(first.id, nil)
        actions.updateDragSelection(third.id)
        actions.endDragSelection()

        XCTAssertEqual(selectionManager.selectedItemIds, [first.id, second.id, third.id])
        XCTAssertEqual(selectionManager.focusedItemId, third.id)
    }

    func testMoveDraggedItemToLongTermSidebarKeepsParentChildBlock() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let parent = store.createItem(title: "parent", dayDate: day, indentLevel: 1)
        let child = store.createItem(title: "child", dayDate: day, afterItem: parent, indentLevel: 2)
        let actions = TodoEditorActionFactory.make(store: store, selectionManager: selectionManager)

        actions.moveDraggedItemToSidebar(parent.id, .longTerm)

        let longTermTitles = store.longTermItems(isUrgent: false).map(\.title)
        XCTAssertEqual(longTermTitles, ["parent", "child"])
        XCTAssertEqual(parent.containerKind, .longTermImportant)
        XCTAssertEqual(child.containerKind, .longTermImportant)
        XCTAssertEqual(parent.indentLevel, 0)
        XCTAssertEqual(child.indentLevel, 1)
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertTrue(store.items(for: day).isEmpty)
    }

    func testMoveDraggedItemToMonthSidebarUsesLatestDateAndKeepsParentChildBlock() {
        let store = TodoStore.shared
        let sourceDay = date(year: 2026, month: 4, day: 1)
        let targetOldDay = date(year: 2026, month: 6, day: 3)
        let targetLatestDay = date(year: 2026, month: 6, day: 20)
        _ = store.createItem(title: "old", dayDate: targetOldDay)
        _ = store.createItem(title: "latest", dayDate: targetLatestDay)
        let parent = store.createItem(
            title: "parent",
            dayDate: sourceDay,
            indentLevel: 1,
            containerKind: .longTermImportant
        )
        let child = store.createItem(
            title: "child",
            dayDate: sourceDay,
            afterItem: parent,
            indentLevel: 2,
            containerKind: .longTermImportant
        )
        let actions = TodoEditorActionFactory.make(store: store, selectionManager: selectionManager)

        actions.moveDraggedItemToSidebar(parent.id, .month(year: 2026, month: 6))

        XCTAssertTrue(parent.containerKind == TodoContainerKind.scheduled)
        XCTAssertTrue(child.containerKind == TodoContainerKind.scheduled)
        XCTAssertTrue(Calendar.current.isDate(parent.dayDate, inSameDayAs: targetLatestDay))
        XCTAssertTrue(Calendar.current.isDate(child.dayDate, inSameDayAs: targetLatestDay))
        XCTAssertEqual(store.items(for: targetLatestDay).map(\.title), ["parent", "child", "latest"])
        XCTAssertEqual(parent.indentLevel, 0)
        XCTAssertEqual(child.indentLevel, 1)
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }
}
