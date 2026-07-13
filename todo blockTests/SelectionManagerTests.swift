//
//  SelectionManagerTests.swift
//  todo blockTests
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class SelectionManagerTests: XCTestCase {
    
    var selectionManager: SelectionManager!
    var items: [TodoItem]!
    
    override func setUp() {
        super.setUp()
        selectionManager = SelectionManager()
        
        // Create 5 items
        items = (0..<5).map { i in
            TodoItem(title: "Item \(i)", sortOrder: Double(i))
        }
    }
    
    // MARK: - Selection Tests
    
    @MainActor
    func testSingleSelect() {
        let item = items[0]
        selectionManager.handleSelect(item: item, allItems: items, shiftPressed: false)
        
        XCTAssertEqual(selectionManager.selectedItemIds.count, 1)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(item.id))
        XCTAssertEqual(selectionManager.focusedItemId, item.id)
        XCTAssertEqual(selectionManager.lastSelectedId, item.id)
    }
    
    @MainActor
    func testMultiSelectWithShift() {
        // Select first
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: false)
        
        // Shift select third (should select 0, 1, 2)
        selectionManager.handleSelect(item: items[2], allItems: items, shiftPressed: true)
        
        XCTAssertEqual(selectionManager.selectedItemIds.count, 3)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[0].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[1].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[2].id))
        XCTAssertEqual(selectionManager.focusedItemId, items[2].id)
    }
    
    @MainActor
    func testReverseMultiSelect() {
        // Select third
        selectionManager.handleSelect(item: items[2], allItems: items, shiftPressed: false)
        
        // Shift select first (should select 0, 1, 2)
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: true)
        
        XCTAssertEqual(selectionManager.selectedItemIds.count, 3)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[0].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[1].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[2].id))
    }

    @MainActor
    func testLongPressDragSelectionForward() {
        selectionManager.beginDragSelection(item: items[1], allItems: items)
        selectionManager.updateDragSelection(to: items[4], allItems: items)

        XCTAssertEqual(selectionManager.selectedItemIds.count, 4)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[1].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[2].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[3].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[4].id))
        XCTAssertEqual(selectionManager.focusedItemId, items[4].id)
    }

    @MainActor
    func testLongPressDragSelectionBackward() {
        selectionManager.beginDragSelection(item: items[4], allItems: items)
        selectionManager.updateDragSelection(to: items[2], allItems: items)

        XCTAssertEqual(selectionManager.selectedItemIds.count, 3)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[2].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[3].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[4].id))
        XCTAssertEqual(selectionManager.focusedItemId, items[2].id)
    }

    @MainActor
    func testEndLongPressDragSelection() {
        selectionManager.beginDragSelection(item: items[0], allItems: items)
        selectionManager.endDragSelection()
        selectionManager.updateDragSelection(to: items[3], allItems: items)

        XCTAssertEqual(selectionManager.selectedItemIds, Set([items[0].id]))
    }
    
    @MainActor
    func testClearSelection() {
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: false)
        selectionManager.clearSelection()
        
        // clearSelection only works if > 1 selected ?
        // checking implementation: if selectedItemIds.count > 1 { removeAll }
        // Let's test single selection clear
        XCTAssertEqual(selectionManager.selectedItemIds.count, 1) // Should still be 1 if implementaiton is count > 1
        
        // Test multi select clear
        selectionManager.selectedItemIds = [items[0].id, items[1].id]
        selectionManager.clearSelection()
        XCTAssertTrue(selectionManager.selectedItemIds.isEmpty)
    }
    
    // MARK: - Focus Movement Tests
    
    @MainActor
    func testMoveFocusDown() {
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: false)
        selectionManager.moveFocusDown(from: items[0], allItems: items)
        
        XCTAssertEqual(selectionManager.focusedItemId, items[1].id)
        XCTAssertEqual(selectionManager.selectedItemIds.first, items[1].id)
    }
    
    @MainActor
    func testMoveFocusUp() {
        selectionManager.handleSelect(item: items[1], allItems: items, shiftPressed: false)
        selectionManager.moveFocusUp(from: items[1], allItems: items)
        
        XCTAssertEqual(selectionManager.focusedItemId, items[0].id)
    }
    
    @MainActor
    func testMoveFocusBoundaries() {
        // Up at top
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: false)
        selectionManager.moveFocusUp(from: items[0], allItems: items)
        XCTAssertEqual(selectionManager.focusedItemId, items[0].id)

        // Down at bottom
        let last = items.last!
        selectionManager.handleSelect(item: last, allItems: items, shiftPressed: false)
        selectionManager.moveFocusDown(from: last, allItems: items)
        XCTAssertEqual(selectionManager.focusedItemId, last.id)
    }
}

// MARK: - SelectionManager 删除/批量撤销集成测试 (Phase 1.C)
// 这些 case 需要真实 TodoStore + SwiftData 上下文，与上面的纯逻辑测试分开两个 class，
// 避免单测之间共享 store.shared 状态而互相干扰。

@MainActor
final class SelectionManagerDeleteTests: XCTestCase {
    var descriptor: ModelContainer!
    var selectionManager: SelectionManager!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        descriptor = try ModelContainer(
            for: TodoItem.self, DaySection.self, configurations: config
        )
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: descriptor.mainContext)
        selectionManager = SelectionManager()
    }

    /// 6. 接通批量撤销后：多选删除应注册单步 undo，actionName 为 "批量删除"
    func testDeleteSelectedItemsRegistersSingleBatchUndo() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 11, day: 1)
        let items = (0..<3).map { store.createItem(title: "i\($0)", dayDate: day) }
        store.undoManager.clear()

        selectionManager.selectedItemIds = Set(items.map(\.id))
        selectionManager.focusedItemId = items[0].id
        selectionManager.lastSelectedId = items[0].id
        selectionManager.deleteSelectedItems(store: store) { d in store.items(for: d) }

        XCTAssertTrue(store.canUndo, "批量删除后应可撤销")
        XCTAssertEqual(
            store.nsUndoManager.undoActionName,
            "批量删除",
            "actionName 应为单步'批量删除',而非逐条'删除'"
        )

        // 关键断言：一次 undo 即恢复全部 3 条 → 证明只注册了一步 undo
        store.undo()
        XCTAssertEqual(store.items(for: day).count, 3, "一次 undo 应恢复全部")
    }

    /// 7. 单次 Cmd+Z 应恢复全部被删 item，且顺序与删除前一致
    func testUndoBatchDeleteRestoresAllItemsInOriginalOrder() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 11, day: 2)
        let items = (0..<3).map { store.createItem(title: "i\($0)", dayDate: day) }
        let originalIds = items.map(\.id)
        store.undoManager.clear()

        selectionManager.selectedItemIds = Set(items.map(\.id))
        selectionManager.focusedItemId = items[0].id
        selectionManager.lastSelectedId = items[0].id
        selectionManager.deleteSelectedItems(store: store) { d in store.items(for: d) }

        XCTAssertEqual(store.items(for: day).count, 0, "前置:全部删除")

        store.undo()

        let restored = store.items(for: day).map(\.id)
        XCTAssertEqual(restored, originalIds, "undo 后顺序应与删除前一致")
    }

    /// 8. 单次 Cmd+Shift+Z 应再次批量删除（与 undo 对称）
    func testRedoBatchDeleteRemovesAllItems() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 11, day: 3)
        let items = (0..<3).map { store.createItem(title: "i\($0)", dayDate: day) }
        store.undoManager.clear()

        selectionManager.selectedItemIds = Set(items.map(\.id))
        selectionManager.focusedItemId = items[0].id
        selectionManager.lastSelectedId = items[0].id
        selectionManager.deleteSelectedItems(store: store) { d in store.items(for: d) }

        store.undo()
        XCTAssertEqual(store.items(for: day).count, 3, "前置:undo 已恢复")

        store.redo()
        XCTAssertEqual(store.items(for: day).count, 0, "redo 应再次批量删除")
        XCTAssertTrue(store.canUndo, "redo 后应能再 undo")
    }

    /// 9. 焦点回退：上方有未删项时焦点向上，否则向下
    func testDeleteSelectedItemsRestoresFocusUpwardThenDownward() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 10, day: 5)
        let i0 = store.createItem(title: "0", dayDate: day)
        let i1 = store.createItem(title: "1", dayDate: day)
        let i2 = store.createItem(title: "2", dayDate: day)
        let i3 = store.createItem(title: "3", dayDate: day)

        // Step A: 选 {i1,i2}（焦点 i1），删除后焦点应向上回退到 i0
        selectionManager.selectedItemIds = [i1.id, i2.id]
        selectionManager.focusedItemId = i1.id
        selectionManager.lastSelectedId = i1.id
        selectionManager.deleteSelectedItems(store: store) { d in store.items(for: d) }
        XCTAssertEqual(selectionManager.focusedItemId, i0.id, "上方有未删项，焦点向上")
        XCTAssertEqual(selectionManager.selectedItemIds, [i0.id])

        // Step B: 现在剩 {i0, i3}。选 i0 删除后，上方为空 → 焦点应向下回退到 i3
        selectionManager.selectedItemIds = [i0.id]
        selectionManager.focusedItemId = i0.id
        selectionManager.lastSelectedId = i0.id
        selectionManager.deleteSelectedItems(store: store) { d in store.items(for: d) }
        XCTAssertEqual(selectionManager.focusedItemId, i3.id, "上方无项，焦点向下")
    }

    func testDeleteSelectedParentSkipsDeletedDescendantsWhenRestoringFocus() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 10, day: 6)
        let parent = store.createItem(title: "parent", dayDate: day, indentLevel: 0)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let tail = store.createItem(
            title: "tail",
            dayDate: day,
            afterItem: child,
            indentLevel: 0
        )

        selectionManager.selectedItemIds = [parent.id]
        selectionManager.focusedItemId = parent.id
        selectionManager.lastSelectedId = parent.id
        selectionManager.deleteSelectedItems(store: store) { date in store.items(for: date) }

        XCTAssertEqual(store.items(for: day).map(\.id), [tail.id])
        XCTAssertEqual(selectionManager.focusedItemId, tail.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [tail.id])
    }

    func testUndoRedoParentDeleteRestoresWholeBlockAndSelection() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 10, day: 7)
        let parent = store.createItem(title: "parent", dayDate: day, indentLevel: 0)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let tail = store.createItem(title: "tail", dayDate: day, afterItem: child)
        store.undoManager.clear()

        selectionManager.selectedItemIds = [parent.id]
        selectionManager.focusedItemId = parent.id
        selectionManager.lastSelectedId = parent.id
        selectionManager.deleteSelectedItems(store: store) { date in store.items(for: date) }

        XCTAssertEqual(store.items(for: day).map(\.id), [tail.id])
        XCTAssertEqual(selectionManager.selectedItemIds, [tail.id])

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: day).map(\.id), [parent.id, child.id, tail.id])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])

        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.items(for: day).map(\.id), [tail.id])
        XCTAssertEqual(selectionManager.focusedItemId, tail.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [tail.id])
    }

    func testDeleteDoesNothingWhenAnySelectedItemIsMissing() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 10, day: 8)
        let first = store.createItem(title: "first", dayDate: day)
        let second = store.createItem(title: "second", dayDate: day, afterItem: first)
        store.undoManager.clear()

        let missingId = UUID()
        selectionManager.selectedItemIds = [first.id, missingId]
        selectionManager.focusedItemId = first.id
        selectionManager.lastSelectedId = first.id
        selectionManager.deleteSelectedItems(store: store) { date in store.items(for: date) }

        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, second.id])
        XCTAssertEqual(selectionManager.selectedItemIds, [first.id, missingId])
        XCTAssertFalse(store.canUndo)
    }

    func testUndoRestoresSelectionIntoReplacementViewContext() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 10, day: 9)
        let first = store.createItem(title: "first", dayDate: day)
        let second = store.createItem(title: "second", dayDate: day, afterItem: first)
        store.undoManager.clear()

        selectionManager = SelectionManager(historyContext: .mainWindow)
        selectionManager.selectedItemIds = [first.id, second.id]
        selectionManager.focusedItemId = first.id
        selectionManager.lastSelectedId = first.id
        selectionManager.deleteSelectedItems(store: store) { date in store.items(for: date) }

        let replacement = SelectionManager(historyContext: .mainWindow)
        selectionManager = replacement

        XCTAssertTrue(store.undo())
        XCTAssertEqual(replacement.focusedItemId, first.id)
        XCTAssertEqual(replacement.selectedItemIds, [first.id, second.id])
        XCTAssertNil(store.focusRequestId, "恢复选择不应广播到无关入口")
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
