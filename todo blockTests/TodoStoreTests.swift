//
//  TodoStoreTests.swift
//  todo blockTests
//
//  Created by Claude on 2026/1/17.
//

import XCTest
import SwiftData
@testable import todo_block

/// 注意：本套件和 UndoManagerTests / TodoParentChildGroupMoveModuleTests 都依赖
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

        let todaySection = try XCTUnwrap(store.carryOverIncompleteItems())
        let carriedItems = store.items(for: todaySection.date)

        XCTAssertEqual(carriedItems.map(\.title), ["parent", "child", "grandchild"])
        XCTAssertEqual(carriedItems.map(\.indentLevel), [0, 1, 2])

        XCTAssertTrue(store.undo())
        XCTAssertEqual(
            store.items(for: previousDate).map(\.indentLevel),
            [2, 4, 2]
        )
        XCTAssertEqual(grandchild.dayDate, Calendar.current.startOfDay(for: previousDate))
        XCTAssertFalse(store.canUndo)

        XCTAssertTrue(store.redo())
        XCTAssertEqual(
            store.items(for: todaySection.date).map(\.id),
            [parent.id, child.id, grandchild.id]
        )
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

        XCTAssertNil(todaySection)
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

        let todaySection = try XCTUnwrap(store.carryOverIncompleteItems())
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

    func testCarryOverWithNoEligibleContentKeepsRedoAndDoesNotCreateToday() throws {
        let store = TodoStore.shared
        let previousDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )
        _ = store.createItem(
            title: "completed",
            isCompleted: true,
            dayDate: previousDate
        )
        let futureDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 2, to: .now)
        )
        let temporary = store.createItem(title: "temporary", dayDate: futureDate)
        store.undoManager.clear()
        store.deleteItem(temporary)
        XCTAssertTrue(store.undo())
        XCTAssertTrue(store.canRedo)

        XCTAssertNil(store.carryOverIncompleteItems())

        XCTAssertTrue(store.canRedo)
        XCTAssertNotNil(store.todoItemsCache[temporary.id])
        XCTAssertTrue(store.todayItems().isEmpty)
        XCTAssertTrue(store.redo())
        XCTAssertNil(store.todoItemsCache[temporary.id])
    }

    func testAutomaticCarryOverWaitsForRedoButUserInitiatedCarryOverStartsNewDirection() throws {
        let store = TodoStore.shared
        let previousDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )
        let pending = store.createItem(title: "pending", dayDate: previousDate)
        let temporary = store.createItem(title: "temporary", dayDate: .now)
        store.undoManager.clear()
        store.deleteItem(temporary)
        XCTAssertTrue(store.undo())
        XCTAssertTrue(store.canRedo)

        XCTAssertNil(store.carryOverIncompleteItems(trigger: .automatic))
        XCTAssertTrue(Calendar.current.isDate(pending.dayDate, inSameDayAs: previousDate))
        XCTAssertTrue(store.canRedo)

        let todaySection = try XCTUnwrap(
            store.carryOverIncompleteItems(trigger: .userInitiated)
        )
        XCTAssertEqual(store.items(for: todaySection.date).map(\.id), [temporary.id, pending.id])
        XCTAssertFalse(store.canRedo)
        XCTAssertTrue(store.canUndo)
    }

    func testCarryOverRedoUsesRecordedItemsWithoutReevaluatingNewContent() throws {
        let store = TodoStore.shared
        let previousDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )
        let original = store.createItem(title: "original", dayDate: previousDate)
        let later = store.createItem(
            title: "later",
            isCompleted: true,
            dayDate: previousDate,
            afterItem: original
        )
        store.undoManager.clear()

        let todaySection = try XCTUnwrap(store.carryOverIncompleteItems())
        XCTAssertTrue(store.undo())
        later.isCompleted = false

        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.items(for: todaySection.date).map(\.id), [original.id])
        XCTAssertEqual(store.items(for: previousDate).map(\.id), [later.id])
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

    func testRestartKeepsSavedResultAndStartsWithEmptyHistory() throws {
        let store = TodoStore.shared
        let targetDate = date(year: 2026, month: 2, day: 20)
        let item = store.createItem(title: "restart", dayDate: targetDate)
        store.toggleComplete(item)
        XCTAssertTrue(store.flushPendingChangesSync())
        XCTAssertTrue(store.canUndo)

        store.reset()
        store.initialize(with: descriptor.mainContext)

        let restored = try XCTUnwrap(store.todoItemsCache[item.id])
        XCTAssertEqual(restored.title, "restart")
        XCTAssertTrue(restored.isCompleted)
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(store.canRedo)
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
        let updatedSection = store.sections(year: 2026, month: 2).first {
            Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }
        XCTAssertNotNil(updatedSection)
        XCTAssertEqual(updatedSection?.title, formatter.string(from: targetDate))
        XCTAssertTrue(Calendar.current.isDate(moved.dayDate, inSameDayAs: targetDate))

        XCTAssertTrue(store.undo())
        XCTAssertTrue(Calendar.current.isDate(moved.dayDate, inSameDayAs: sourceDate))
        XCTAssertTrue(store.redo())
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
