//
//  TodoOperationUnitTests.swift
//  todo blockTests
//

import SwiftData
import XCTest

@testable import todo_block

@MainActor
final class TodoOperationUnitTests: XCTestCase {
    private var container: ModelContainer!
    private var store: TodoStore!

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: configuration
        )
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
        store = TodoStore.shared
    }

    func testOperationUnitAppliesAllStateAndSelectionThenReversesExactly() {
        let date = fixedDate(day: 1)
        let selectionManager = SelectionManager()
        let first = store.createItem(title: "第一项", dayDate: date)
        store.undoManager.clear()
        selectionManager.restoreFocus(to: first.id)
        selectionManager.activateHistoryContext()

        let beforeFirst = TodoItemSnapshot(from: first)
        let afterFirst = beforeFirst.replacing(title: "第一项（已改）")
        let created = TodoItemSnapshot(
            title: "第二项",
            indentLevel: 0,
            sortOrder: first.sortOrder + 1000,
            containerKindRaw: TodoContainerKind.scheduled.rawValue,
            dayDate: date
        )
        let unit = TodoOperationUnit(
            actionName: "组合修改",
            itemTransitions: [
                TodoItemTransition(before: beforeFirst, after: afterFirst),
                TodoItemTransition(before: nil, after: created)
            ],
            selectionTransitions: [
                TodoSelectionTransition(
                    historyContext: selectionManager.historyContext,
                    before: TodoSelectionState(focusing: first.id),
                    after: TodoSelectionState(focusing: created.id)
                )
            ]
        )

        XCTAssertTrue(store.undoManager.perform(unit, store: store))
        XCTAssertEqual(first.title, "第一项（已改）")
        XCTAssertNotNil(store.todoItemsCache[created.id])
        XCTAssertEqual(selectionManager.focusedItemId, created.id)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(first.title, "第一项")
        XCTAssertNil(store.todoItemsCache[created.id])
        XCTAssertEqual(selectionManager.focusedItemId, first.id)

        XCTAssertTrue(store.redo())
        XCTAssertEqual(first.title, "第一项（已改）")
        XCTAssertNotNil(store.todoItemsCache[created.id])
        XCTAssertEqual(selectionManager.focusedItemId, created.id)
    }

    func testRejectedUnitLeavesEveryItemAndHistoryUntouched() {
        let date = fixedDate(day: 2)
        let first = store.createItem(title: "第一项", dayDate: date)
        let second = store.createItem(title: "第二项", dayDate: date)
        store.undoManager.clear()

        let beforeFirst = TodoItemSnapshot(from: first)
        let beforeSecond = TodoItemSnapshot(from: second)
        second.title = "已经被其他动作修改"

        let unit = TodoOperationUnit(
            actionName: "不应部分生效",
            itemTransitions: [
                TodoItemTransition(before: beforeFirst, after: beforeFirst.replacing(title: "错误修改")),
                TodoItemTransition(before: beforeSecond, after: beforeSecond.replacing(title: "也不应修改"))
            ]
        )

        XCTAssertFalse(store.undoManager.perform(unit, store: store))
        XCTAssertEqual(first.title, "第一项")
        XCTAssertEqual(second.title, "已经被其他动作修改")
        XCTAssertFalse(store.canUndo)
    }

    func testNoChangeAndRejectedUnitKeepRedoButNewEffectiveUnitClearsIt() {
        let date = fixedDate(day: 3)
        let item = store.createItem(title: "原文", dayDate: date)
        store.undoManager.clear()
        store.toggleComplete(item)
        XCTAssertTrue(store.undo())
        XCTAssertTrue(store.canRedo)

        XCTAssertFalse(store.undoManager.perform(TodoOperationUnit(actionName: "无变化"), store: store))
        XCTAssertTrue(store.canRedo)

        let impossible = TodoOperationUnit(
            actionName: "过期",
            itemTransitions: [
                TodoItemTransition(
                    before: TodoItemSnapshot(from: item).replacing(title: "并不存在的前态"),
                    after: TodoItemSnapshot(from: item).replacing(title: "不应写入")
                )
            ]
        )
        XCTAssertFalse(store.undoManager.perform(impossible, store: store))
        XCTAssertTrue(store.canRedo)

        let before = TodoItemSnapshot(from: item)
        let effective = TodoOperationUnit(
            actionName: "新操作",
            itemTransitions: [
                TodoItemTransition(before: before, after: before.replacing(title: "新内容"))
            ]
        )
        XCTAssertTrue(store.undoManager.perform(effective, store: store))
        XCTAssertEqual(item.title, "新内容")
        XCTAssertFalse(store.canRedo)
    }

    func testReferenceModelMatchesMixedOperationAndHistorySequence() {
        let date = fixedDate(day: 4)
        let item = store.createItem(title: "0", dayDate: date)
        store.undoManager.clear()
        var reference = TitleHistoryReference(initialTitle: "0")

        for step in 1...12 {
            let before = TodoItemSnapshot(from: item)
            let afterTitle = "\(step)"
            let unit = TodoOperationUnit(
                actionName: "改标题",
                itemTransitions: [
                    TodoItemTransition(before: before, after: before.replacing(title: afterTitle))
                ]
            )
            XCTAssertTrue(store.undoManager.perform(unit, store: store))
            reference.apply(afterTitle)
            XCTAssertEqual(item.title, reference.currentTitle)
        }

        for _ in 0..<5 {
            XCTAssertTrue(store.undo())
            reference.undo()
            XCTAssertEqual(item.title, reference.currentTitle)
        }
        for _ in 0..<3 {
            XCTAssertTrue(store.redo())
            reference.redo()
            XCTAssertEqual(item.title, reference.currentTitle)
        }

        let before = TodoItemSnapshot(from: item)
        let replacement = "新的分支"
        XCTAssertTrue(
            store.undoManager.perform(
                TodoOperationUnit(
                    actionName: "替代操作",
                    itemTransitions: [
                        TodoItemTransition(before: before, after: before.replacing(title: replacement))
                    ]
                ),
                store: store
            )
        )
        reference.apply(replacement)
        XCTAssertEqual(item.title, reference.currentTitle)
        XCTAssertFalse(store.canRedo)
    }

    func testLegacyOperationUsesTheSameStructuredHistory() {
        let date = fixedDate(day: 5)
        let item = store.createItem(title: "旧入口", dayDate: date)
        store.undoManager.clear()
        let before = TodoItemSnapshot(from: item)

        XCTAssertTrue(
            store.undoManager.perform(
                TodoOperation(
                    actionName: "旧入口修改",
                    itemStateChanges: [
                        TodoItemStateChange(before: before, after: before.replacing(title: "新状态"))
                    ]
                ),
                store: store
            )
        )
        XCTAssertEqual(item.title, "新状态")
        XCTAssertEqual(store.undoManager.undoActionName, "旧入口修改")
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "旧入口")
    }

    private func fixedDate(day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: day)) ?? .now
    }
}

private struct TitleHistoryReference {
    private(set) var currentTitle: String
    private var undoTitles: [String] = []
    private var redoTitles: [String] = []

    init(initialTitle: String) {
        currentTitle = initialTitle
    }

    mutating func apply(_ title: String) {
        undoTitles.append(currentTitle)
        currentTitle = title
        redoTitles.removeAll()
    }

    mutating func undo() {
        guard let previous = undoTitles.popLast() else { return }
        redoTitles.append(currentTitle)
        currentTitle = previous
    }

    mutating func redo() {
        guard let next = redoTitles.popLast() else { return }
        undoTitles.append(currentTitle)
        currentTitle = next
    }
}
