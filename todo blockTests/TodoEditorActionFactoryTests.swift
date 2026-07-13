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
        selectionManager.selectedItemIds = [moving.id, next.id]
        selectionManager.focusedItemId = next.id
        selectionManager.lastSelectedId = next.id
        selectionManager.cursorPosition = 3
        store.undoManager.clear()

        actions.moveItemByKeyboard(moving.id, .down)

        XCTAssertEqual(store.items(for: day).map(\.id), [next.id, moving.id, child.id])
        XCTAssertEqual(selectionManager.focusedItemId, moving.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [moving.id])
        XCTAssertEqual(selectionManager.cursorPosition, 3)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(selectionManager.focusedItemId, next.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [moving.id, next.id])
        XCTAssertEqual(selectionManager.cursorPosition, 3)

        XCTAssertTrue(store.redo())
        XCTAssertEqual(selectionManager.focusedItemId, moving.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [moving.id])
        XCTAssertEqual(selectionManager.cursorPosition, 3)
    }

    func testInvalidKeyboardMoveDoesNotChangeSelectionOrHistory() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let first = store.createItem(title: "first", dayDate: day)
        let second = store.createItem(title: "second", dayDate: day, afterItem: first)
        let actions = TodoEditorActionFactory.make(store: store, selectionManager: selectionManager)
        selectionManager.selectedItemIds = [first.id, second.id]
        selectionManager.focusedItemId = second.id
        selectionManager.lastSelectedId = second.id
        selectionManager.cursorPosition = 2
        store.undoManager.clear()

        actions.moveItemByKeyboard(first.id, .up)

        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, second.id])
        XCTAssertEqual(selectionManager.focusedItemId, second.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [first.id, second.id])
        XCTAssertEqual(selectionManager.cursorPosition, 2)
        XCTAssertFalse(store.canUndo)
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

    func testEnterSplitIntoChildUpdatesCurrentItemAndFocusesChild() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let item = store.createItem(title: "abcde", dayDate: day, indentLevel: 1)
        let actions = TodoEditorActionFactory.make(store: store, selectionManager: selectionManager)

        actions.enterPressed(
            item.id,
            .splitIntoChild(newCurrentTitle: "ab", childTitle: "cde")
        )

        let items = store.items(for: day)
        XCTAssertEqual(items.map(\.title), ["ab", "cde"])
        XCTAssertEqual(items.map(\.indentLevel), [1, 2])
        XCTAssertEqual(selectionManager.focusedItemId, items.last?.id)
        XCTAssertEqual(selectionManager.cursorPosition, 0)
    }

    func testMoveDraggedItemToLongTermSidebarKeepsParentChildBlock() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let parent = store.createItem(title: "parent", dayDate: day, indentLevel: 1)
        let child = store.createItem(title: "child", dayDate: day, afterItem: parent, indentLevel: 2)
        let actions = TodoEditorActionFactory.make(store: store, selectionManager: selectionManager)
        selectionManager.selectedItemIds = [parent.id, child.id]
        selectionManager.focusedItemId = child.id
        selectionManager.lastSelectedId = child.id
        selectionManager.cursorPosition = 2
        store.undoManager.clear()

        actions.moveDraggedItemToSidebar(parent.id, .longTerm)

        let longTermTitles = store.longTermItems(isUrgent: false).map(\.title)
        XCTAssertEqual(longTermTitles, ["parent", "child"])
        XCTAssertEqual(parent.containerKind, .longTermImportant)
        XCTAssertEqual(child.containerKind, .longTermImportant)
        XCTAssertEqual(parent.indentLevel, 0)
        XCTAssertEqual(child.indentLevel, 1)
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.cursorPosition, 2)
        XCTAssertTrue(store.items(for: day).isEmpty)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(selectionManager.focusedItemId, child.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id, child.id])
        XCTAssertEqual(selectionManager.cursorPosition, 2)

        XCTAssertTrue(store.redo())
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.cursorPosition, 2)
    }

    func testMoveDraggedItemAcrossLongTermBucketsKeepsParentChildBlock() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let parent = store.createItem(
            title: "parent",
            dayDate: day,
            indentLevel: 1,
            containerKind: .longTermUrgent
        )
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 2,
            containerKind: .longTermUrgent
        )
        let target = store.createItem(
            title: "target",
            dayDate: day,
            containerKind: .longTermImportant
        )
        let actions = TodoEditorActionFactory.make(store: store, selectionManager: selectionManager)
        selectionManager.selectedItemIds = [parent.id, target.id]
        selectionManager.focusedItemId = target.id
        selectionManager.lastSelectedId = target.id
        selectionManager.cursorPosition = 4
        store.undoManager.clear()

        actions.moveDraggedItem(parent.id, .longTerm(isUrgent: false), 1, 1)

        XCTAssertEqual(store.longTermItems(isUrgent: true).map(\.id), [])
        XCTAssertEqual(store.longTermItems(isUrgent: false).map(\.id), [target.id, parent.id, child.id])
        XCTAssertEqual(parent.containerKind, .longTermImportant)
        XCTAssertEqual(child.containerKind, .longTermImportant)
        XCTAssertEqual(parent.indentLevel, 1)
        XCTAssertEqual(child.indentLevel, 2)
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.cursorPosition, 4)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(selectionManager.focusedItemId, target.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id, target.id])
        XCTAssertEqual(selectionManager.cursorPosition, 4)

        XCTAssertTrue(store.redo())
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.cursorPosition, 4)
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
