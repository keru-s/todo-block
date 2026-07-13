//
//  TodoStoreTests.swift
//  todo blockTests
//
//  Created by Claude on 2026/1/17.
//

import XCTest
import SwiftData
@testable import todo_block

/// 注意：本套件和 UndoManagerTests / TodoKeyboardReorderEngineTests 都依赖
/// `TodoStore.shared` 这一全局单例，靠 setUp 里 reset+initialize 隔离用例。
/// 此前提是 xcodebuild test 在 macOS 平台默认**串行**执行 test class — 不要在
/// scheme 里启用 parallel-testable（`-parallel-testing-enabled YES`），否则
/// 跨 class 并行会互相 reset 单例状态、产生 flake。
@MainActor
final class TodoStoreTests: XCTestCase {

    var descriptor: ModelContainer!

    override func setUp() async throws {
        // Use in-memory container for testing
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        descriptor = try ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: descriptor.mainContext)

        // Clear shared store cache between tests (important because it's a singleton)
        // Since we re-initialize with a fresh context, it should reload from empty
    }
    
    func testCreateItem() {
        let store = TodoStore.shared
        let date = Date()
        
        let item = store.createItem(title: "Test Item", dayDate: date)
        
        XCTAssertEqual(item.title, "Test Item")
        XCTAssertEqual(store.items(for: date).count, 1)
        XCTAssertEqual(store.items(for: date).first?.id, item.id)
        XCTAssertTrue(store.todoItemsCache.keys.contains(item.id))
    }
    
    func testDeleteItem() {
        let store = TodoStore.shared
        let date = Date()
        let item = store.createItem(title: "To Delete", dayDate: date)
        
        XCTAssertEqual(store.items(for: date).count, 1)
        
        store.deleteItem(item)
        
        XCTAssertEqual(store.items(for: date).count, 0)
        XCTAssertFalse(store.todoItemsCache.keys.contains(item.id))
    }
    
    func testItemSorting() {
        let store = TodoStore.shared
        let date = Date()
        
        let item1 = store.createItem(title: "First", dayDate: date)
        // createItem automatically adds with sortOrder increment
        let item2 = store.createItem(title: "Second", dayDate: date)
        
        let items = store.items(for: date)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, item1.id)
        XCTAssertEqual(items[1].id, item2.id)
        XCTAssertLessThan(items[0].sortOrder, items[1].sortOrder)
    }
    
    func testIndent() {
        let store = TodoStore.shared
        let item = store.createItem(dayDate: Date())
        
        XCTAssertEqual(item.indentLevel, 0)
        
        item.indent()
        XCTAssertEqual(item.indentLevel, 1)
        
        item.indent()
        item.indent()
        item.indent()
        item.indent() // max 4
        XCTAssertEqual(item.indentLevel, TodoItem.maxIndentLevel)
        
        item.outdent()
        XCTAssertEqual(item.indentLevel, TodoItem.maxIndentLevel - 1)
    }

    func testCreateItemIndentLevelIsClampedToMaxLevel() {
        let store = TodoStore.shared
        let item = store.createItem(dayDate: Date(), indentLevel: 100)
        XCTAssertEqual(item.indentLevel, TodoItem.maxIndentLevel)
    }
    
    func testCompleteToggle() {
        let store = TodoStore.shared
        let item = store.createItem(dayDate: Date())
        
        XCTAssertFalse(item.isCompleted)
        
        store.toggleComplete(item)
        XCTAssertTrue(item.isCompleted)
        
        store.toggleComplete(item)
        XCTAssertFalse(item.isCompleted)
    }
    
    func testChildCompletionPropagation() {
        let store = TodoStore.shared
        let date = Date()
        
        /*
         Parent
           Child 1 (indent 1)
           Child 2 (indent 1)
         Sibling (indent 0)
         */
        
        let parent = store.createItem(title: "Parent", dayDate: date, indentLevel: 0)
        let child1 = store.createItem(title: "Child 1", dayDate: date, indentLevel: 1)
        let child2 = store.createItem(title: "Child 2", dayDate: date, indentLevel: 1)
        let sibling = store.createItem(title: "Sibling", dayDate: date, indentLevel: 0)
        
        // Completing parent should complete children
        store.toggleComplete(parent)
        
        XCTAssertTrue(parent.isCompleted)
        XCTAssertTrue(child1.isCompleted)
        XCTAssertTrue(child2.isCompleted)
        XCTAssertFalse(sibling.isCompleted) // Sibling unaffected
        
        // Uncompleting parent
        store.toggleComplete(parent)
        XCTAssertFalse(parent.isCompleted)
        XCTAssertFalse(child1.isCompleted)
        XCTAssertFalse(child2.isCompleted)
    }

    func testCarryOverMovesIncompleteTopLevelBlockWithNestedStructure() throws {
        let store = TodoStore.shared
        let previousDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -1, to: .now))
        let parent = store.createItem(title: "parent", dayDate: previousDate, indentLevel: 2)
        let child = store.createItem(
            title: "child", dayDate: previousDate, afterItem: parent, indentLevel: 4)
        let grandchild = store.createItem(
            title: "grandchild", dayDate: previousDate, afterItem: child, indentLevel: 2)
        store.undoManager.clear()

        let todaySection = store.carryOverIncompleteItems()
        let carriedItems = store.items(for: todaySection.date)

        XCTAssertEqual(carriedItems.map(\.title), ["parent", "child", "grandchild"])
        XCTAssertEqual(carriedItems.map(\.indentLevel), [0, 1, 2])

        XCTAssertTrue(store.undo())
        XCTAssertEqual(
            store.items(for: previousDate).map(\.indentLevel),
            [2, 4, 2]
        )
        XCTAssertEqual(grandchild.dayDate, Calendar.current.startOfDay(for: previousDate))
    }

    func testCarryOverSkipsReopenedChildOfCompletedTopLevelParent() throws {
        let store = TodoStore.shared
        let previousDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -1, to: .now))
        let parent = store.createItem(title: "parent", dayDate: previousDate, indentLevel: 0)
        let child = store.createItem(
            title: "child", dayDate: previousDate, afterItem: parent, indentLevel: 1)
        parent.isCompleted = true
        child.isCompleted = false

        let todaySection = store.carryOverIncompleteItems()

        XCTAssertTrue(store.items(for: todaySection.date).isEmpty)
        XCTAssertEqual(store.items(for: previousDate).map(\.title), ["parent", "child"])
    }

    func testCarryOverCopiesParentAndKeepsIncompleteDescendantStructure() throws {
        let store = TodoStore.shared
        let previousDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -1, to: .now))
        let parent = store.createItem(title: "parent", dayDate: previousDate, indentLevel: 0)
        let completedChild = store.createItem(
            title: "completed", dayDate: previousDate, afterItem: parent, indentLevel: 1)
        let incompleteGrandchild = store.createItem(
            title: "incomplete", dayDate: previousDate, afterItem: completedChild, indentLevel: 2)
        completedChild.isCompleted = true
        store.undoManager.clear()

        let todaySection = store.carryOverIncompleteItems()
        let carriedItems = store.items(for: todaySection.date)

        XCTAssertEqual(carriedItems.map(\.title), ["parent", "incomplete"])
        XCTAssertEqual(carriedItems.map(\.indentLevel), [0, 1])
        XCTAssertEqual(store.items(for: previousDate).map(\.title), ["parent", "completed"])
        XCTAssertEqual(incompleteGrandchild.indentLevel, 1)

        XCTAssertTrue(store.undo())
        XCTAssertTrue(store.items(for: todaySection.date).isEmpty)
        XCTAssertEqual(
            store.items(for: previousDate).map(\.title),
            ["parent", "completed", "incomplete"]
        )

        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.items(for: todaySection.date).map(\.title), ["parent", "incomplete"])
    }

    func testMoveItemToAnotherMonthUsesLatestDateTail() {
        let store = TodoStore.shared
        let januaryDate = date(year: 2026, month: 1, day: 10)
        let februaryOld = date(year: 2026, month: 2, day: 12)
        let februaryLatest = date(year: 2026, month: 2, day: 20)

        let draggedItem = store.createItem(title: "Dragged", dayDate: januaryDate)
        _ = store.createItem(title: "Feb old", dayDate: februaryOld)
        let febTail = store.createItem(title: "Feb latest", dayDate: februaryLatest)

        let target = store.tailItemForScheduledMonth(year: 2026, month: 2)
        store.moveItemWithChildren(
            draggedItem,
            to: .scheduled(date: target.date),
            afterItem: target.tailItem,
            newIndentLevel: 0
        )

        XCTAssertEqual(target.tailItem?.id, febTail.id)
        XCTAssertTrue(Calendar.current.isDate(draggedItem.dayDate, inSameDayAs: februaryLatest))
        XCTAssertEqual(store.items(for: februaryLatest).last?.id, draggedItem.id)
    }

    func testMoveItemToEmptyMonthUsesClampedTodayDay() {
        let store = TodoStore.shared
        let today = date(year: 2026, month: 1, day: 31)

        let fallback = store.fallbackDateForEmptyMonth(
            year: 2026,
            month: 2,
            today: today
        )

        XCTAssertEqual(Calendar.current.component(.year, from: fallback), 2026)
        XCTAssertEqual(Calendar.current.component(.month, from: fallback), 2)
        XCTAssertEqual(Calendar.current.component(.day, from: fallback), 28)
    }

    func testMoveItemToLongTermNonUrgent() {
        let store = TodoStore.shared
        let item = store.createItem(title: "scheduled", dayDate: date(year: 2026, month: 1, day: 8))

        store.moveItemWithChildren(
            item,
            to: .longTerm(isUrgent: false),
            afterItem: nil,
            newIndentLevel: 0
        )

        XCTAssertEqual(item.containerKind, .longTermImportant)
        XCTAssertEqual(store.longTermItems(isUrgent: false).map(\.id), [item.id])
    }

    func testMoveItemToLongTermNonUrgentWithNilAfterItemInsertsAtHead() {
        let store = TodoStore.shared
        let firstLongTerm = store.createItem(
            title: "existing",
            dayDate: date(year: 2026, month: 1, day: 8),
            containerKind: .longTermImportant
        )
        let moved = store.createItem(title: "scheduled", dayDate: date(year: 2026, month: 1, day: 9))

        store.moveItemWithChildren(
            moved,
            to: .longTerm(isUrgent: false),
            afterItem: nil,
            newIndentLevel: 0
        )

        XCTAssertEqual(store.longTermItems(isUrgent: false).map(\.title), ["scheduled", "existing"])
        XCTAssertEqual(firstLongTerm.containerKind, .longTermImportant)
    }

    func testMoveItemBetweenLongTermUrgentAndNonUrgent() {
        let store = TodoStore.shared
        let item = store.createItem(
            title: "urgent",
            dayDate: date(year: 2026, month: 1, day: 8),
            containerKind: .longTermUrgent
        )

        store.moveItemWithChildren(
            item,
            to: .longTerm(isUrgent: false),
            afterItem: nil,
            newIndentLevel: 0
        )

        XCTAssertEqual(item.containerKind, .longTermImportant)
        XCTAssertTrue(store.longTermItems(isUrgent: true).isEmpty)
        XCTAssertEqual(store.longTermItems(isUrgent: false).map(\.id), [item.id])
    }

    func testMoveItemFromLongTermBackToScheduledMonth() {
        let store = TodoStore.shared
        let item = store.createItem(
            title: "long term",
            dayDate: date(year: 2026, month: 1, day: 9),
            containerKind: .longTermImportant
        )
        _ = store.createItem(title: "anchor", dayDate: date(year: 2026, month: 3, day: 15))

        let target = store.tailItemForScheduledMonth(year: 2026, month: 3)
        store.moveItemWithChildren(
            item,
            to: .scheduled(date: target.date),
            afterItem: target.tailItem,
            newIndentLevel: 0
        )

        XCTAssertEqual(item.containerKind, .scheduled)
        XCTAssertTrue(Calendar.current.isDate(item.dayDate, inSameDayAs: target.date))
        XCTAssertEqual(store.items(for: target.date).last?.id, item.id)
    }

    func testMoveItemToMonthPrefersLatestSectionEvenWhenEmpty() {
        let store = TodoStore.shared
        let longTermItem = store.createItem(
            title: "long term",
            dayDate: date(year: 2026, month: 2, day: 1),
            containerKind: .longTermImportant
        )

        let monthOldDate = date(year: 2026, month: 2, day: 9)
        let monthLatestEmptyDate = date(year: 2026, month: 2, day: 15)
        _ = store.createItem(title: "old item", dayDate: monthOldDate)
        _ = store.getOrCreateSection(for: monthLatestEmptyDate)

        let target = store.tailItemForScheduledMonth(year: 2026, month: 2)
        store.moveItemWithChildren(
            longTermItem,
            to: .scheduled(date: target.date),
            afterItem: target.tailItem,
            newIndentLevel: 0
        )

        XCTAssertNil(target.tailItem)
        XCTAssertTrue(Calendar.current.isDate(target.date, inSameDayAs: monthLatestEmptyDate))
        XCTAssertTrue(Calendar.current.isDate(longTermItem.dayDate, inSameDayAs: monthLatestEmptyDate))
        XCTAssertEqual(store.items(for: monthLatestEmptyDate).map(\.id), [longTermItem.id])
    }

    func testInitializeReloadReplacesStaleCachesAfterExternalDeletion() throws {
        let store = TodoStore.shared
        let date = self.date(year: 2026, month: 2, day: 16)
        let created = store.createItem(title: "to-delete-externally", dayDate: date)
        XCTAssertEqual(store.items(for: date).map(\.id), [created.id])

        descriptor.mainContext.delete(created)
        try descriptor.mainContext.save()

        store.initialize(with: descriptor.mainContext)

        XCTAssertTrue(store.items(for: date).isEmpty)
        XCTAssertNil(store.todoItemsCache[created.id])
    }

    func testItemsQuerySurvivesExternalDeletionWithoutReinitialize() throws {
        let store = TodoStore.shared
        let date = self.date(year: 2026, month: 2, day: 17)
        let created = store.createItem(title: "externally-deleted", dayDate: date)
        XCTAssertEqual(store.items(for: date).map(\.id), [created.id])

        descriptor.mainContext.delete(created)
        try descriptor.mainContext.save()

        XCTAssertTrue(store.items(for: date).isEmpty)
    }

    func testMoveItemToExistingMonthWithNilAfterItemInsertsAtHead() {
        let store = TodoStore.shared
        let source = store.createItem(
            title: "from long term",
            dayDate: date(year: 2026, month: 1, day: 1),
            containerKind: .longTermImportant
        )
        let targetDate = date(year: 2026, month: 2, day: 16)
        let firstExisting = store.createItem(title: "existing-1", dayDate: targetDate)
        _ = store.createItem(title: "existing-2", dayDate: targetDate, afterItem: firstExisting)

        store.moveItemWithChildren(
            source,
            to: .scheduled(date: targetDate),
            afterItem: nil,
            newIndentLevel: 0
        )

        XCTAssertEqual(store.items(for: targetDate).map(\.title), ["from long term", "existing-1", "existing-2"])
    }

    func testCreateItemInsertAtBeginningPlacesNewItemAtHead() {
        let store = TodoStore.shared
        let targetDate = date(year: 2026, month: 2, day: 16)
        let first = store.createItem(title: "first", dayDate: targetDate)
        _ = store.createItem(title: "second", dayDate: targetDate, afterItem: first)

        _ = store.createItem(
            title: "head",
            dayDate: targetDate,
            insertAtBeginning: true
        )

        XCTAssertEqual(store.items(for: targetDate).map(\.title), ["head", "first", "second"])
    }

    func testCanCopyAndExportInScheduledMonthScope() {
        let store = TodoStore.shared
        let targetDate = date(year: 2026, month: 2, day: 16)
        let inScope = store.createItem(title: "in-scope", dayDate: targetDate)
        _ = store.createItem(title: "out-scope", dayDate: date(year: 2026, month: 1, day: 1))

        let scope = TodoClipboardScope.scheduledMonth(year: 2026, month: 2)
        let snapshot = TodoClipboardSelectionSnapshot(
            focusedItemId: nil,
            selectedItemIds: [inScope.id]
        )

        XCTAssertTrue(store.canCopy(scope: scope, selection: snapshot))
        let markdown = store.exportMarkdown(scope: scope, selection: snapshot)
        XCTAssertEqual(markdown, "- [ ] in-scope")
    }

    func testExportParentAndSelectedChildIncludesHierarchyOnce() {
        let store = TodoStore.shared
        let targetDate = date(year: 2026, month: 2, day: 16)
        let parent = store.createItem(title: "parent", dayDate: targetDate, indentLevel: 0)
        let child = store.createItem(
            title: "child",
            dayDate: targetDate,
            afterItem: parent,
            indentLevel: 1
        )
        _ = store.createItem(
            title: "grandchild",
            dayDate: targetDate,
            afterItem: child,
            indentLevel: 2
        )

        let markdown = store.exportMarkdown(
            scope: .scheduledMonth(year: 2026, month: 2),
            selection: TodoClipboardSelectionSnapshot(
                focusedItemId: parent.id,
                selectedItemIds: [parent.id, child.id]
            )
        )

        XCTAssertEqual(
            markdown,
            """
            - [ ] parent
              - [ ] child
                - [ ] grandchild
            """
        )
    }

    func testImportMarkdownTightensJumpedIndentWithoutChangingOrder() {
        let store = TodoStore.shared
        let targetDate = date(year: 2026, month: 2, day: 16)
        let anchor = store.createItem(title: "anchor", dayDate: targetDate)

        let result = store.importMarkdown(
            """
                - [ ] parent
                        - [ ] child
                          - [ ] grandchild
            """,
            scope: .scheduledMonth(year: 2026, month: 2),
            selection: TodoClipboardSelectionSnapshot(
                focusedItemId: anchor.id,
                selectedItemIds: [anchor.id]
            )
        )

        let created = result?.createdItemIds.compactMap { store.todoItemsCache[$0] } ?? []
        XCTAssertEqual(created.map(\.title), ["parent", "child", "grandchild"])
        XCTAssertEqual(created.map(\.indentLevel), [0, 1, 2])
    }

    func testImportCompletedItemUndoRedoPreservesRecordedResult() {
        let store = TodoStore.shared
        store.undoManager.clear()

        let result = store.importMarkdown(
            "- [x] completed",
            scope: .scheduledMonth(year: 2026, month: 2),
            selection: TodoClipboardSelectionSnapshot(
                focusedItemId: nil,
                selectedItemIds: []
            )
        )
        guard let createdId = result?.createdItemIds.first else {
            return XCTFail("应创建已完成待办")
        }
        XCTAssertEqual(store.todoItemsCache[createdId]?.isCompleted, true)

        XCTAssertTrue(store.undo())
        XCTAssertNil(store.todoItemsCache[createdId])

        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.todoItemsCache[createdId]?.isCompleted, true)
    }

    func testImportMarkdownBatchAndSelectionUndoRedoAsOneStep() {
        let store = TodoStore.shared
        let targetDate = date(year: 2026, month: 2, day: 16)
        let anchor = store.createItem(title: "anchor", dayDate: targetDate)
        _ = store.createItem(title: "next", dayDate: targetDate, afterItem: anchor)
        let selectionManager = SelectionManager()
        selectionManager.selectedItemIds = [anchor.id]
        selectionManager.focusedItemId = anchor.id
        selectionManager.lastSelectedId = anchor.id
        selectionManager.cursorPosition = 3
        store.undoManager.clear()

        let result = store.importMarkdown(
            """
            - [ ] parent
                - [x] child
            """,
            scope: .scheduledMonth(year: 2026, month: 2),
            selection: TodoClipboardSelectionSnapshot(
                focusedItemId: anchor.id,
                selectedItemIds: [anchor.id]
            ),
            selectionManager: selectionManager
        )

        guard let result else { return XCTFail("应整批粘贴") }
        XCTAssertEqual(
            store.items(for: targetDate).map(\.title),
            ["anchor", "parent", "child", "next"]
        )
        XCTAssertEqual(selectionManager.selectedItemIds, Set(result.createdItemIds))
        XCTAssertEqual(selectionManager.focusedItemId, result.focusedItemId)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: targetDate).map(\.title), ["anchor", "next"])
        XCTAssertEqual(selectionManager.selectedItemIds, [anchor.id])
        XCTAssertEqual(selectionManager.focusedItemId, anchor.id)
        XCTAssertEqual(selectionManager.cursorPosition, 3)

        XCTAssertTrue(store.redo())
        XCTAssertEqual(
            store.items(for: targetDate).map(\.title),
            ["anchor", "parent", "child", "next"]
        )
        XCTAssertEqual(selectionManager.selectedItemIds, Set(result.createdItemIds))
        XCTAssertEqual(selectionManager.focusedItemId, result.focusedItemId)
    }

    func testInvalidImportLeavesNoSectionAndKeepsRedoPath() {
        let store = TodoStore.shared
        let original = store.createItem(title: "original", dayDate: date(year: 2026, month: 1, day: 1))
        store.undoManager.clear()
        store.deleteItem(original)
        XCTAssertTrue(store.undo())
        let sectionCountBefore = store.daySectionsCache.count
        XCTAssertTrue(store.canRedo)

        let result = store.importMarkdown(
            "not a todo",
            scope: .scheduledMonth(year: 2026, month: 9),
            selection: TodoClipboardSelectionSnapshot(focusedItemId: nil, selectedItemIds: [])
        )

        XCTAssertNil(result)
        XCTAssertEqual(store.daySectionsCache.count, sectionCountBefore)
        XCTAssertTrue(store.canRedo)
        XCTAssertTrue(store.redo())
        XCTAssertNil(store.todoItemsCache[original.id])
    }

    func testEmptyMonthPasteCreatesAndUndoRemovesDateSection() {
        let store = TodoStore.shared
        store.undoManager.clear()

        let result = store.importMarkdown(
            "- [ ] september",
            scope: .scheduledMonth(year: 2026, month: 9),
            selection: TodoClipboardSelectionSnapshot(focusedItemId: nil, selectedItemIds: [])
        )

        guard let createdId = result?.createdItemIds.first,
              let created = store.todoItemsCache[createdId]
        else { return XCTFail("应创建待办和日期") }
        let pastedDate = created.dayDate
        XCTAssertTrue(
            store.daySectionsCache.values.contains {
                Calendar.current.isDate($0.date, inSameDayAs: pastedDate)
            }
        )

        XCTAssertTrue(store.undo())
        XCTAssertNil(store.todoItemsCache[createdId])
        XCTAssertFalse(
            store.daySectionsCache.values.contains {
                Calendar.current.isDate($0.date, inSameDayAs: pastedDate)
            }
        )

        XCTAssertTrue(store.redo())
        XCTAssertNotNil(store.todoItemsCache[createdId])
        XCTAssertTrue(
            store.daySectionsCache.values.contains {
                Calendar.current.isDate($0.date, inSameDayAs: pastedDate)
            }
        )
    }

    func testFailedSplitLeavesItemUntouchedAndKeepsRedoPath() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 2, day: 16)
        let staleItem = store.createItem(title: "abcde", dayDate: day)
        store.undoManager.clear()
        store.deleteItem(staleItem)
        XCTAssertTrue(store.undo())
        XCTAssertTrue(store.canRedo)

        XCTAssertNil(
            store.splitItem(
                staleItem,
                newCurrentTitle: "ab",
                childTitle: "cde"
            )
        )

        XCTAssertEqual(store.items(for: day).map(\.title), ["abcde"])
        XCTAssertTrue(store.canRedo)
        XCTAssertTrue(store.redo())
        XCTAssertTrue(store.items(for: day).isEmpty)
    }

    func testCopyExportDoesNotClearRedoPath() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 2, day: 16)
        let item = store.createItem(title: "copy me", dayDate: day)
        store.undoManager.clear()
        store.deleteItem(item)
        XCTAssertTrue(store.undo())
        XCTAssertTrue(store.canRedo)

        XCTAssertNotNil(
            store.exportMarkdown(
                scope: .scheduledMonth(year: 2026, month: 2),
                selection: TodoClipboardSelectionSnapshot(
                    focusedItemId: item.id,
                    selectedItemIds: [item.id]
                )
            )
        )

        XCTAssertTrue(store.canRedo)
        XCTAssertTrue(store.redo())
        XCTAssertNil(store.todoItemsCache[item.id])
    }

    func testImportMarkdownScheduledMonthPrefersFocusedItem() {
        let store = TodoStore.shared
        let targetDate = date(year: 2026, month: 2, day: 16)
        let focused = store.createItem(title: "focus", dayDate: targetDate)
        _ = store.createItem(title: "tail", dayDate: targetDate, afterItem: focused)

        let result = store.importMarkdown(
            "- [ ] pasted",
            scope: .scheduledMonth(year: 2026, month: 2),
            selection: TodoClipboardSelectionSnapshot(
                focusedItemId: focused.id,
                selectedItemIds: []
            )
        )

        guard
            let result,
            let created = store.todoItemsCache[result.focusedItemId]
        else {
            XCTFail("Expected pasted item")
            return
        }

        XCTAssertEqual(result.createdItemIds, [created.id])
        XCTAssertTrue(Calendar.current.isDate(created.dayDate, inSameDayAs: targetDate))
        let orderedItems = store.items(for: targetDate)
        guard
            let focusedIndex = orderedItems.firstIndex(where: { $0.id == focused.id }),
            focusedIndex + 1 < orderedItems.count
        else {
            XCTFail("Expected focused item followed by pasted item")
            return
        }
        XCTAssertEqual(orderedItems[focusedIndex + 1].id, created.id)
    }

    func testImportMarkdownLongTermFallbacksToImportantContainer() {
        let store = TodoStore.shared
        let existing = store.createItem(
            title: "existing",
            dayDate: Date(),
            containerKind: .longTermImportant
        )

        let result = store.importMarkdown(
            "- [ ] pasted",
            scope: .longTerm,
            selection: TodoClipboardSelectionSnapshot(
                focusedItemId: nil,
                selectedItemIds: []
            )
        )

        guard
            let result,
            let created = store.todoItemsCache[result.focusedItemId]
        else {
            XCTFail("Expected pasted item")
            return
        }

        XCTAssertEqual(created.containerKind, .longTermImportant)
        XCTAssertEqual(store.longTermItems(isUrgent: false).map(\.id), [existing.id, created.id])
    }

    func testImportMarkdownTodayFallbacksToTodayTail() {
        let store = TodoStore.shared
        let todayExisting = store.createItem(title: "today-existing", dayDate: Date())

        let result = store.importMarkdown(
            "- [ ] pasted",
            scope: .today,
            selection: TodoClipboardSelectionSnapshot(
                focusedItemId: nil,
                selectedItemIds: []
            )
        )

        guard
            let result,
            let created = store.todoItemsCache[result.focusedItemId]
        else {
            XCTFail("Expected pasted item")
            return
        }

        XCTAssertEqual(store.todayItems().map(\.id), [todayExisting.id, created.id])
        XCTAssertTrue(Calendar.current.isDateInToday(created.dayDate))
    }

    func testUpdateSectionDateMergesIntoExistingSection() {
        let store = TodoStore.shared
        let sourceDate = date(year: 2026, month: 2, day: 15)
        let targetDate = date(year: 2026, month: 2, day: 18)

        let sourceSection = store.getOrCreateSection(for: sourceDate)
        _ = store.getOrCreateSection(for: targetDate)
        let moved = store.createItem(title: "to-move", dayDate: sourceDate)

        store.updateSectionDate(sourceSection, to: targetDate)

        XCTAssertTrue(Calendar.current.isDate(moved.dayDate, inSameDayAs: targetDate))
        XCTAssertNil(store.daySectionsCache[sourceSection.id])
        XCTAssertEqual(
            store.sections(year: 2026, month: 2)
                .filter { Calendar.current.isDate($0.date, inSameDayAs: targetDate) }
                .count,
            1
        )
    }

    func testUpdateSectionDateUpdatesSectionWhenTargetMissing() {
        let store = TodoStore.shared
        let sourceDate = date(year: 2026, month: 2, day: 15)
        let targetDate = date(year: 2026, month: 2, day: 19)

        let section = store.getOrCreateSection(for: sourceDate)
        let moved = store.createItem(title: "to-update", dayDate: sourceDate)

        store.updateSectionDate(section, to: targetDate)

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        XCTAssertTrue(Calendar.current.isDate(section.date, inSameDayAs: targetDate))
        XCTAssertEqual(section.title, formatter.string(from: targetDate))
        XCTAssertTrue(Calendar.current.isDate(moved.dayDate, inSameDayAs: targetDate))
    }

    func testIndentAndOutdentItemRegisterUndoAndClampAtBounds() {
        let store = TodoStore.shared
        let item = store.createItem(title: "indent", dayDate: Date())
        store.undoManager.clear()

        store.indentItem(item)
        XCTAssertEqual(item.indentLevel, 1)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.indentLevel, 0)

        store.indentItem(item)
        XCTAssertEqual(item.indentLevel, 1)
        store.outdentItem(item)
        XCTAssertEqual(item.indentLevel, 0)

        item.indentLevel = TodoItem.maxIndentLevel
        store.indentItem(item)
        XCTAssertEqual(item.indentLevel, TodoItem.maxIndentLevel)

        item.indentLevel = 0
        store.outdentItem(item)
        XCTAssertEqual(item.indentLevel, 0)
    }

    // MARK: - Persistence (Phase 1.A，保护 P0-2 拆分)

    /// 1. scheduleSave 在 0.3s debounce 后会自动落盘
    func testScheduleSaveEventuallyPersistsViaDebounce() async throws {
        let store = TodoStore.shared
        _ = store.createItem(title: "debounced", dayDate: Date())

        XCTAssertTrue(descriptor.mainContext.hasChanges, "前置：创建后应有 pending 变更")

        // 等待 > 0.3s debounce + 一点 buffer
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertFalse(
            descriptor.mainContext.hasChanges,
            "debounce 后 scheduleSave 应已自动落盘"
        )
        XCTAssertNil(store.lastSaveError)
    }

    /// 2. flushPendingChangesSync 同步落盘 pending 变更并返回 true
    func testFlushPendingChangesSyncSavesAndReturnsTrue() {
        let store = TodoStore.shared
        _ = store.createItem(title: "to-flush", dayDate: Date())
        XCTAssertTrue(descriptor.mainContext.hasChanges)

        let didSave = store.flushPendingChangesSync()

        XCTAssertTrue(didSave)
        XCTAssertFalse(descriptor.mainContext.hasChanges, "flush 后不应再有 pending 变更")
        XCTAssertNil(store.lastSaveError)
    }

    // MARK: - Section maintenance (Phase 1.B，保护 P0-2 拆分)

    /// 3. getOrCreateSection 对同一日期幂等：只创建一次
    func testGetOrCreateSectionIsIdempotentForSameDate() {
        let store = TodoStore.shared
        let target = date(year: 2026, month: 5, day: 24)

        let s1 = store.getOrCreateSection(for: target)
        let s2 = store.getOrCreateSection(for: target)

        XCTAssertEqual(s1.id, s2.id, "同一日期应返回同一 section")
        let matching = store.sections(year: 2026, month: 5)
            .filter { Calendar.current.isDate($0.date, inSameDayAs: target) }
        XCTAssertEqual(matching.count, 1, "缓存内仅应留一份 section")
    }

    /// 4. initialize 时孤儿 section（无对应 scheduled item）应被清理
    func testInitializeCleansUpOrphanSections() throws {
        let context = descriptor.mainContext
        let orphanDate = date(year: 2026, month: 6, day: 1)

        // 直接通过 context 插入孤儿 section，绕过 store 的关联管理
        let orphan = DaySection(date: orphanDate, sortOrder: 1)
        context.insert(orphan)
        try context.save()

        // 重新 init store，触发 cleanupAllOrphanSections
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: context)

        let store = TodoStore.shared
        XCTAssertFalse(
            store.sections(year: 2026, month: 6)
                .contains { Calendar.current.isDate($0.date, inSameDayAs: orphanDate) },
            "孤儿 section 应在 initialize 时被清理"
        )
    }

    /// 5. cleanupSectionIfEmpty 反向：仍有 sibling item 时 section 必须保留
    func testDeleteItemKeepsSectionWhenSiblingsRemain() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 7, day: 10)

        let first = store.createItem(title: "first", dayDate: day)
        _ = store.createItem(title: "second", dayDate: day)

        store.deleteItem(first)

        XCTAssertEqual(store.items(for: day).count, 1, "应剩 1 条")
        XCTAssertTrue(
            store.sections(year: 2026, month: 7)
                .contains { Calendar.current.isDate($0.date, inSameDayAs: day) },
            "仍有 item，section 不应被清理"
        )
    }

    // MARK: - No-migration contract (Phase 1.E，保护 P0-6 删除迁移)

    /// 12. 现行 schema 数据 round-trip：raw="scheduled" 的 item 加载后能正常显示
    func testInitializeAcceptsCurrentSchemaItemsWithoutMigration() throws {
        let context = descriptor.mainContext
        let day = date(year: 2026, month: 8, day: 15)

        let item = TodoItem(
            title: "current schema",
            indentLevel: 0,
            sortOrder: 1,
            containerKindRaw: TodoContainerKind.scheduled.rawValue,
            dayDate: day
        )
        context.insert(item)
        try context.save()

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: context)

        let visible = TodoStore.shared.items(for: day)
        XCTAssertEqual(visible.map(\.id), [item.id])
        XCTAssertEqual(item.containerKind, .scheduled)
    }

    /// 13. 空 containerKindRaw 通过 getter `?? .scheduled` 兜底仍可见为 scheduled。
    /// 删除迁移后 raw 值不再被强制写回 "scheduled"，但 UI 行为不应变。
    func testInitializeFiltersLegacyEmptyContainerKindGracefully() throws {
        let context = descriptor.mainContext
        let day = date(year: 2026, month: 9, day: 1)

        let item = TodoItem(
            title: "legacy",
            indentLevel: 0,
            sortOrder: 1,
            containerKindRaw: "",  // 模拟 v1 数据
            dayDate: day
        )
        context.insert(item)
        try context.save()

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: context)

        // 通过 getter 兜底应被识别为 scheduled，能正常出现在 items(for:)
        XCTAssertEqual(item.containerKind, .scheduled)
        XCTAssertEqual(TodoStore.shared.items(for: day).map(\.id), [item.id])
    }

    // MARK: - moveItemWithChildren（带子项的 reorder）回归测试

    /// 回归用例：目标列表中 afterItem 与下一项 sortOrder 距离很小（< 0.001 * childCount）
    /// 时，子项的固定步进会把它们推到 nextItem 之后，导致父子分离。
    /// 真实数据示例：[..., a:5500.0, b:5500.001, c:5500.002, ...]
    /// 把另一组 [parent, child1, child2] 移到 a 之后：
    /// midpoint = (5500.0+5500.001)/2 = 5500.0005，子项 = 5500.0015/5500.0025，
    /// 大于 b 的 5500.001 — 排序后变成 [a, parent, b, child1, c, child2]。
    func testMoveParentIntoTightlyPackedSiblingsKeepsChildrenAdjacent() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 24)

        // 目标列表：sortOrder 密集排布的三个相邻项
        let a = store.createItem(title: "a", dayDate: day)
        let b = store.createItem(title: "b", dayDate: day, afterItem: a)
        _ = store.createItem(title: "c", dayDate: day, afterItem: b)
        // 把 a/b 的 sortOrder 调整成 1.000/1.001（模拟历史密集插入产物）
        a.sortOrder = 1.000
        b.sortOrder = 1.001
        store.items(for: day).first { $0.title == "c" }?.sortOrder = 1.002

        // 源列表：parent + 2 child（在同一天的末尾，sortOrder >> 1.x）
        let parent = store.createItem(title: "parent", dayDate: day, indentLevel: 0)
        let child1 = store.createItem(title: "child1", dayDate: day, afterItem: parent, indentLevel: 1)
        _ = store.createItem(title: "child2", dayDate: day, afterItem: child1, indentLevel: 1)

        // 把 parent 移到 a 之后
        store.moveItemWithChildren(
            parent,
            to: .scheduled(date: day),
            afterItem: a,
            newIndentLevel: 0
        )

        // 期望 child 紧跟 parent，不被 b/c 隔开
        let actual = store.items(for: day).map(\.title)
        let actualWithOrder = store.items(for: day).map { "\($0.title)@\($0.sortOrder)" }
        XCTAssertEqual(
            actual,
            ["a", "parent", "child1", "child2", "b", "c"],
            "Actual order: \(actualWithOrder)"
        )
    }


    /// 同日内将带 child 的 parent 向下移到 anchor 之后，child 必须跟随。
    func testMoveParentWithChildrenWithinSameDayCarriesChildren() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 24)

        let parent = store.createItem(title: "parent", dayDate: day)
        let child1 = store.createItem(title: "child1", dayDate: day, afterItem: parent, indentLevel: 1)
        let child2 = store.createItem(title: "child2", dayDate: day, afterItem: child1, indentLevel: 1)
        let anchor = store.createItem(title: "anchor", dayDate: day, afterItem: child2)

        store.moveItemWithChildren(
            parent,
            to: .scheduled(date: day),
            afterItem: anchor,
            newIndentLevel: 0
        )

        XCTAssertEqual(
            store.items(for: day).map(\.title),
            ["anchor", "parent", "child1", "child2"]
        )
        XCTAssertEqual(child1.indentLevel, 1)
        XCTAssertEqual(child2.indentLevel, 1)
    }

    /// 走 TodoReorderMoveEngine（UI 拖放实际路径），二级 parent 带三级 child 向下移动。
    func testReorderEngineMovesLevel2ParentWithLevel3Child() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 24)

        let top = store.createItem(title: "top", dayDate: day)  // indent 0
        let parent = store.createItem(title: "parent", dayDate: day, afterItem: top, indentLevel: 1)
        let child = store.createItem(title: "child", dayDate: day, afterItem: parent, indentLevel: 2)
        let after = store.createItem(title: "after", dayDate: day, afterItem: child, indentLevel: 1)

        // 模拟 UI：将 parent (indent 1) 拖到 after (indent 1) 下方
        let items = store.items(for: day)
        let afterIndex = items.firstIndex(where: { $0.id == after.id })!
        TodoReorderMoveEngine.performMove(
            draggedId: parent.id,
            toIndex: afterIndex + 1,  // 插入 after 之后
            indentLevel: 1,
            items: items,
            destination: .scheduled(date: day),
            store: store
        )

        XCTAssertEqual(
            store.items(for: day).map(\.title),
            ["top", "after", "parent", "child"]
        )
    }

    /// 走 TodoKeyboardReorderEngine（快捷键 Cmd+↑↓ 实际路径），二级 parent 向下，三级 child 必须跟随。
    func testKeyboardReorderMovesLevel2ParentWithLevel3ChildDown() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 24)

        let top = store.createItem(title: "top", dayDate: day)
        let parent = store.createItem(title: "parent", dayDate: day, afterItem: top, indentLevel: 1)
        let child = store.createItem(title: "child", dayDate: day, afterItem: parent, indentLevel: 2)
        _ = store.createItem(title: "after", dayDate: day, afterItem: child, indentLevel: 1)

        let moved = TodoKeyboardReorderEngine.move(
            itemId: parent.id,
            direction: .down,
            items: store.items(for: day),
            destination: .scheduled(date: day),
            store: store
        )

        XCTAssertTrue(moved)
        XCTAssertEqual(
            store.items(for: day).map(\.title),
            ["top", "after", "parent", "child"]
        )
    }

    /// 跨日移动带 child 的 parent，child.dayDate 必须跟随。
    func testMoveParentWithChildrenAcrossDaysCarriesChildren() {
        let store = TodoStore.shared
        let from = date(year: 2026, month: 5, day: 24)
        let to = date(year: 2026, month: 5, day: 25)

        let parent = store.createItem(title: "parent", dayDate: from)
        let child = store.createItem(title: "child", dayDate: from, afterItem: parent, indentLevel: 1)
        let anchor = store.createItem(title: "anchor", dayDate: to)

        store.moveItemWithChildren(
            parent,
            to: .scheduled(date: to),
            afterItem: anchor,
            newIndentLevel: 0
        )

        XCTAssertEqual(store.items(for: from).map(\.title), [])
        XCTAssertEqual(store.items(for: to).map(\.title), ["anchor", "parent", "child"])
        XCTAssertTrue(Calendar.current.isDate(child.dayDate, inSameDayAs: to))
    }

    func testDeleteParentDeletesDescendantsAndUndoRestoresWholeBlock() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 24)
        let parent = store.createItem(title: "parent", dayDate: day, indentLevel: 0)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let grandchild = store.createItem(
            title: "grandchild",
            dayDate: day,
            afterItem: child,
            indentLevel: 2
        )
        _ = store.createItem(title: "tail", dayDate: day, afterItem: grandchild, indentLevel: 0)
        store.undoManager.clear()

        store.deleteItem(parent)

        XCTAssertEqual(store.items(for: day).map(\.title), ["tail"])
        XCTAssertTrue(store.undo())
        XCTAssertEqual(
            store.items(for: day).map(\.title),
            ["parent", "child", "grandchild", "tail"]
        )
        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.items(for: day).map(\.title), ["tail"])
    }

    func testIndentAndOutdentParentMoveAllDescendantsBySameAmount() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 24)
        let parent = store.createItem(title: "parent", dayDate: day, indentLevel: 0)
        let child = store.createItem(title: "child", dayDate: day, afterItem: parent, indentLevel: 1)
        let grandchild = store.createItem(
            title: "grandchild",
            dayDate: day,
            afterItem: child,
            indentLevel: 2
        )
        store.undoManager.clear()

        store.indentItem(parent)
        XCTAssertEqual([parent.indentLevel, child.indentLevel, grandchild.indentLevel], [1, 2, 3])

        XCTAssertTrue(store.undo())
        XCTAssertEqual([parent.indentLevel, child.indentLevel, grandchild.indentLevel], [0, 1, 2])
        XCTAssertTrue(store.redo())
        XCTAssertEqual([parent.indentLevel, child.indentLevel, grandchild.indentLevel], [1, 2, 3])

        store.outdentItem(parent)
        XCTAssertEqual([parent.indentLevel, child.indentLevel, grandchild.indentLevel], [0, 1, 2])
    }

    func testToggleCompleteUsesNormalizedBlockForMalformedIndentation() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 24)
        let parent = store.createItem(title: "parent", dayDate: day, indentLevel: 3)
        let child = store.createItem(title: "child", dayDate: day, afterItem: parent, indentLevel: 2)
        _ = store.createItem(title: "tail", dayDate: day, indentLevel: 0)
        child.isCompleted = true
        store.undoManager.clear()

        store.toggleComplete(parent)

        XCTAssertTrue(parent.isCompleted)
        XCTAssertTrue(child.isCompleted)
        XCTAssertEqual(parent.indentLevel, 3)
        XCTAssertEqual(child.indentLevel, 2)
        XCTAssertTrue(store.undo())
        XCTAssertFalse(parent.isCompleted)
        XCTAssertTrue(child.isCompleted)
        XCTAssertEqual(parent.indentLevel, 3)
        XCTAssertEqual(child.indentLevel, 2)
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
