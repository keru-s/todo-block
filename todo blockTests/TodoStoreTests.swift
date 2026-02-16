//
//  TodoStoreTests.swift
//  todo blockTests
//
//  Created by Claude on 2026/1/17.
//

import XCTest
import SwiftData
@testable import todo_block

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

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar.current
        return calendar.startOfDay(for: calendar.date(from: components) ?? Date())
    }
}
