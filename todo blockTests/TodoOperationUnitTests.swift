//
//  TodoOperationUnitTests.swift
//  todo blockTests
//

import SwiftData
import XCTest

@testable import todo_block

@MainActor
final class TodoOperationUnitTests: XCTestCase {
    private var container: ModelContainer?
    private var store: TodoStore { .shared }

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: configuration
        )
        self.container = container
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
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

    func testUnitWithUnavailableSelectionOwnerStillAppliesItsItemChange() {
        let date = fixedDate(day: 6)
        let item = store.createItem(title: "原内容", dayDate: date)
        store.undoManager.clear()
        let before = TodoItemSnapshot(from: item)
        let unavailableContext = TodoSelectionHistoryContext.ephemeral(UUID())

        let unit = TodoOperationUnit(
            actionName: "已关闭列表的编辑",
            itemTransitions: [
                TodoItemTransition(before: before, after: before.replacing(title: "已写入"))
            ],
            selectionTransitions: [
                TodoSelectionTransition(
                    historyContext: unavailableContext,
                    before: TodoSelectionState(focusing: item.id),
                    after: TodoSelectionState(focusing: item.id, cursorPosition: 3)
                )
            ]
        )

        XCTAssertTrue(store.undoManager.perform(unit, store: store))
        XCTAssertEqual(item.title, "已写入")
        XCTAssertTrue(store.canUndo)
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

    func testStructuredHistoryKeepsOnlyTheMostRecentFiftyUnits() {
        let date = fixedDate(day: 7)
        let item = store.createItem(title: "0", dayDate: date)
        store.undoManager.clear()

        for step in 1...52 {
            let before = TodoItemSnapshot(from: item)
            XCTAssertTrue(
                store.undoManager.perform(
                    TodoOperationUnit(
                        actionName: "改标题",
                        itemTransitions: [
                            TodoItemTransition(before: before, after: before.replacing(title: "\(step)"))
                        ]
                    ),
                    store: store
                )
            )
        }

        var undoCount = 0
        while store.undo() {
            undoCount += 1
        }
        XCTAssertEqual(undoCount, 50)
        XCTAssertEqual(item.title, "2")
    }

    func testStaleUnitIsDiscardedBeforeEarlierValidUnitUndoes() {
        let date = fixedDate(day: 8)
        let first = store.createItem(title: "第一项", dayDate: date)
        let second = store.createItem(title: "第二项", dayDate: date)
        store.undoManager.clear()

        let firstBefore = TodoItemSnapshot(from: first)
        XCTAssertTrue(
            store.undoManager.perform(
                TodoOperationUnit(
                    actionName: "第一项修改",
                    itemTransitions: [
                        TodoItemTransition(before: firstBefore, after: firstBefore.replacing(title: "第一项已改"))
                    ]
                ),
                store: store
            )
        )
        let secondBefore = TodoItemSnapshot(from: second)
        XCTAssertTrue(
            store.undoManager.perform(
                TodoOperationUnit(
                    actionName: "第二项修改",
                    itemTransitions: [
                        TodoItemTransition(before: secondBefore, after: secondBefore.replacing(title: "第二项已改"))
                    ]
                ),
                store: store
            )
        )
        second.title = "外部变化"

        XCTAssertTrue(store.undo())
        XCTAssertEqual(first.title, "第一项")
        XCTAssertEqual(second.title, "外部变化")
        XCTAssertFalse(store.canUndo)
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

    func testLegacyAndOperationUnitEntriesHaveEquivalentUndoRedoBehavior() {
        let date = fixedDate(day: 9)
        let unitItem = store.createItem(title: "原内容", dayDate: date)
        let legacyItem = store.createItem(title: "原内容", dayDate: date)
        store.undoManager.clear()

        let unitBefore = TodoItemSnapshot(from: unitItem)
        XCTAssertTrue(
            store.undoManager.perform(
                TodoOperationUnit(
                    actionName: "新入口修改",
                    itemTransitions: [
                        TodoItemTransition(before: unitBefore, after: unitBefore.replacing(title: "修改后"))
                    ]
                ),
                store: store
            )
        )
        XCTAssertTrue(store.undo())
        let unitAfterUndo = unitItem.title
        XCTAssertTrue(store.redo())
        let unitAfterRedo = unitItem.title

        store.undoManager.clear()
        let legacyBefore = TodoItemSnapshot(from: legacyItem)
        XCTAssertTrue(
            store.undoManager.perform(
                TodoOperation(
                    actionName: "旧入口修改",
                    itemStateChanges: [
                        TodoItemStateChange(before: legacyBefore, after: legacyBefore.replacing(title: "修改后"))
                    ]
                ),
                store: store
            )
        )
        XCTAssertTrue(store.undo())
        let legacyAfterUndo = legacyItem.title
        XCTAssertTrue(store.redo())
        let legacyAfterRedo = legacyItem.title

        XCTAssertEqual([unitAfterUndo, unitAfterRedo], [legacyAfterUndo, legacyAfterRedo])
    }

    func testReferenceModelTracksIdentityOrderHierarchyAndEditingSelection() {
        let date = fixedDate(day: 10)
        let selectionManager = SelectionManager()
        let first = store.createItem(title: "根", dayDate: date)
        store.undoManager.clear()
        selectionManager.restoreFocus(to: first.id)
        selectionManager.activateHistoryContext()

        let created = TodoItemSnapshot(
            title: "子项",
            indentLevel: 1,
            sortOrder: first.sortOrder + 1000,
            containerKindRaw: TodoContainerKind.scheduled.rawValue,
            dayDate: date
        )
        let firstBefore = TodoItemSnapshot(from: first)
        let firstAfter = firstBefore.replacing(title: "根（已完成）", isCompleted: true)
        let initialState = TodoUserStateReference.State(
            items: [
                .init(id: first.id, title: "根", isCompleted: false, indentLevel: 0, sortOrder: first.sortOrder)
            ],
            selection: .init(
                focusedItemId: first.id,
                selectedItemIds: [first.id],
                cursorPosition: 0,
                textSelectionLength: 0
            )
        )
        let createdState = TodoUserStateReference.State(
            items: [
                .init(
                    id: first.id,
                    title: "根（已完成）",
                    isCompleted: true,
                    indentLevel: 0,
                    sortOrder: first.sortOrder
                ),
                .init(id: created.id, title: "子项", isCompleted: false, indentLevel: 1, sortOrder: created.sortOrder)
            ],
            selection: .init(
                focusedItemId: created.id,
                selectedItemIds: [created.id],
                cursorPosition: 2,
                textSelectionLength: 1
            )
        )
        var reference = TodoUserStateReference(initialState: initialState)
        let firstSelection = TodoSelectionState(selectionManager: selectionManager)
        let createdSelection = TodoSelectionState(
            focusedItemId: created.id,
            selectedItemIds: [created.id],
            lastSelectedId: created.id,
            cursorPosition: 2,
            textSelectionLength: 1
        )

        XCTAssertTrue(
            store.undoManager.perform(
                TodoOperationUnit(
                    actionName: "创建子项并完成父项",
                    itemTransitions: [
                        TodoItemTransition(before: firstBefore, after: firstAfter),
                        TodoItemTransition(before: nil, after: created)
                    ],
                    selectionTransitions: [
                        TodoSelectionTransition(
                            historyContext: selectionManager.historyContext,
                            before: firstSelection,
                            after: createdSelection
                        )
                    ]
                ),
                store: store
            )
        )
        reference.apply(createdState)
        assertActualState(matches: reference.currentState, date: date, selectionManager: selectionManager)

        XCTAssertTrue(store.undo())
        reference.undo()
        assertActualState(matches: reference.currentState, date: date, selectionManager: selectionManager)

        XCTAssertTrue(store.redo())
        reference.redo()
        assertActualState(matches: reference.currentState, date: date, selectionManager: selectionManager)

        let deletedState = TodoUserStateReference.State(
            items: [createdState.items[0]],
            selection: initialState.selection
        )
        XCTAssertTrue(
            store.undoManager.perform(
                TodoOperationUnit(
                    actionName: "删除子项",
                    itemTransitions: [TodoItemTransition(before: created, after: nil)],
                    selectionTransitions: [
                        TodoSelectionTransition(
                            historyContext: selectionManager.historyContext,
                            before: createdSelection,
                            after: firstSelection
                        )
                    ]
                ),
                store: store
            )
        )
        reference.apply(deletedState)
        assertActualState(matches: reference.currentState, date: date, selectionManager: selectionManager)

        XCTAssertTrue(store.undo())
        reference.undo()
        assertActualState(matches: reference.currentState, date: date, selectionManager: selectionManager)
    }

    private func assertActualState(
        matches reference: TodoUserStateReference.State,
        date: Date,
        selectionManager: SelectionManager
    ) {
        let actualItems = store.items(for: date).map {
            TodoUserStateReference.Item(
                id: $0.id,
                title: $0.title,
                isCompleted: $0.isCompleted,
                indentLevel: $0.indentLevel,
                sortOrder: $0.sortOrder
            )
        }
        XCTAssertEqual(actualItems, reference.items)
        XCTAssertEqual(selectionManager.focusedItemId, reference.selection.focusedItemId)
        XCTAssertEqual(selectionManager.selectedItemIds, reference.selection.selectedItemIds)
        XCTAssertEqual(selectionManager.cursorPosition, reference.selection.cursorPosition)
        XCTAssertEqual(selectionManager.textSelectionLength, reference.selection.textSelectionLength)
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

private struct TodoUserStateReference {
    struct Item: Equatable {
        let id: UUID
        let title: String
        let isCompleted: Bool
        let indentLevel: Int
        let sortOrder: Double
    }

    struct Selection: Equatable {
        let focusedItemId: UUID?
        let selectedItemIds: Set<UUID>
        let cursorPosition: Int
        let textSelectionLength: Int
    }

    struct State: Equatable {
        let items: [Item]
        let selection: Selection
    }

    private(set) var currentState: State
    private var undoStates: [State] = []
    private var redoStates: [State] = []

    init(initialState: State) {
        currentState = initialState
    }

    mutating func apply(_ state: State) {
        undoStates.append(currentState)
        currentState = state
        redoStates.removeAll()
    }

    mutating func undo() {
        guard let state = undoStates.popLast() else { return }
        redoStates.append(currentState)
        currentState = state
    }

    mutating func redo() {
        guard let state = redoStates.popLast() else { return }
        undoStates.append(currentState)
        currentState = state
    }
}
