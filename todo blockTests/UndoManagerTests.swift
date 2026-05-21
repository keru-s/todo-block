//
//  UndoManagerTests.swift
//  todo blockTests
//
//  Created by Claude on 2026/2/9.
//

import SwiftData
import XCTest

@testable import todo_block

@MainActor
final class UndoManagerTests: XCTestCase {

    var descriptor: ModelContainer!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        descriptor = try ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: descriptor.mainContext)
    }

    // MARK: - 测试撤销新增

    func testUndoCreateItem() {
        let store = TodoStore.shared
        let date = Date()

        // 创建一个 item
        let item = store.createItem(title: "Test Item", dayDate: date)
        XCTAssertEqual(store.items(for: date).count, 1)
        XCTAssertTrue(store.canUndo)

        // 撤销
        let undone = store.undo()
        XCTAssertTrue(undone)
        XCTAssertEqual(store.items(for: date).count, 0)
        XCTAssertFalse(store.canUndo)
    }

    func testUndoCreateItemRequestsPreviousFocus() {
        let store = TodoStore.shared
        let date = Date()

        let first = store.createItem(title: "First", dayDate: date)
        store.undoManager.clear()

        _ = store.createItem(title: "Second", dayDate: date, afterItem: first)
        XCTAssertEqual(store.items(for: date).count, 2)

        let undone = store.undo()
        XCTAssertTrue(undone)
        XCTAssertEqual(store.items(for: date).count, 1)
        XCTAssertEqual(store.focusRequestId, first.id)
    }

    // MARK: - 测试撤销删除

    func testUndoDeleteItem() {
        let store = TodoStore.shared
        let date = Date()

        // 创建一个 item
        let item = store.createItem(title: "To Delete", dayDate: date)
        let itemId = item.id

        // 清空创建产生的撤销
        store.undoManager.clear()

        // 删除
        store.deleteItem(item)
        XCTAssertEqual(store.items(for: date).count, 0)
        XCTAssertTrue(store.canUndo)

        // 撤销
        let undone = store.undo()
        XCTAssertTrue(undone)
        XCTAssertEqual(store.items(for: date).count, 1)

        // 确认恢复的是同一个 ID
        let restored = store.items(for: date).first
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.id, itemId)
        XCTAssertEqual(restored?.title, "To Delete")
    }

    // MARK: - 测试撤销完成状态切换

    func testUndoToggleComplete() {
        let store = TodoStore.shared
        let date = Date()

        let item = store.createItem(title: "Toggle Test", dayDate: date)
        store.undoManager.clear()

        XCTAssertFalse(item.isCompleted)

        // 切换完成状态
        store.toggleComplete(item)
        XCTAssertTrue(item.isCompleted)
        XCTAssertTrue(store.canUndo)

        // 撤销
        store.undo()
        XCTAssertFalse(item.isCompleted)
    }

    // MARK: - 测试撤销完成状态（含子任务）

    func testUndoToggleCompleteWithChildren() {
        let store = TodoStore.shared
        let date = Date()

        let parent = store.createItem(title: "Parent", dayDate: date, indentLevel: 0)
        let child1 = store.createItem(title: "Child1", dayDate: date, indentLevel: 1)
        let child2 = store.createItem(title: "Child2", dayDate: date, indentLevel: 1)

        store.undoManager.clear()

        // 切换父任务完成状态（子任务应一同完成）
        store.toggleComplete(parent)
        XCTAssertTrue(parent.isCompleted)
        XCTAssertTrue(child1.isCompleted)
        XCTAssertTrue(child2.isCompleted)

        // 撤销（子任务应恢复）
        store.undo()
        XCTAssertFalse(parent.isCompleted)
        XCTAssertFalse(child1.isCompleted)
        XCTAssertFalse(child2.isCompleted)
    }

    // MARK: - 测试撤销缩进变化

    func testUndoIndentChange() {
        let store = TodoStore.shared
        let date = Date()

        let item = store.createItem(title: "Indent Test", dayDate: date)
        store.undoManager.clear()

        XCTAssertEqual(item.indentLevel, 0)

        // 增加缩进
        let oldIndent = item.indentLevel
        item.indentLevel = 1  // 手动设置缩进
        store.registerIndentChange(itemId: item.id, oldIndent: oldIndent, newIndent: item.indentLevel)

        XCTAssertEqual(item.indentLevel, 1)

        // 撤销
        store.undo()
        XCTAssertEqual(item.indentLevel, 0)

        // 重做
        store.redo()
        XCTAssertEqual(item.indentLevel, 1)
    }

    // MARK: - 测试撤销栈限制

    func testUndoStackLimit() {
        let store = TodoStore.shared
        let date = Date()

        store.undoManager.clear()

        // 创建 60 个 items（超过 50 限制）
        for i in 0..<60 {
            _ = store.createItem(title: "Item \(i)", dayDate: date)
        }

        // NSUndoManager 应该限制在 50 步
        // 由于使用 NSUndoManager，我们检查 canUndo 是否正常工作
        XCTAssertTrue(store.canUndo)

        // 撤销所有可撤销的操作
        var undoCount = 0
        while store.canUndo && undoCount < 100 {
            store.undo()
            undoCount += 1
        }

        // 应该最多能撤销 50 次（levelsOfUndo = 50）
        XCTAssertLessThanOrEqual(undoCount, 50)
    }

    // MARK: - 测试多步撤销

    func testMultipleUndo() {
        let store = TodoStore.shared
        let date = Date()
        let originalGroupsByEvent = store.nsUndoManager.groupsByEvent

        store.nsUndoManager.groupsByEvent = false
        defer {
            store.nsUndoManager.groupsByEvent = originalGroupsByEvent
        }

        store.undoManager.clear()

        // 创建 3 个 items
        store.nsUndoManager.beginUndoGrouping()
        _ = store.createItem(title: "Item 1", dayDate: date)
        store.nsUndoManager.endUndoGrouping()

        store.nsUndoManager.beginUndoGrouping()
        _ = store.createItem(title: "Item 2", dayDate: date)
        store.nsUndoManager.endUndoGrouping()

        store.nsUndoManager.beginUndoGrouping()
        _ = store.createItem(title: "Item 3", dayDate: date)
        store.nsUndoManager.endUndoGrouping()

        XCTAssertEqual(store.items(for: date).count, 3)

        // 连续撤销 3 次
        store.undo()
        XCTAssertEqual(store.items(for: date).count, 2)

        store.undo()
        XCTAssertEqual(store.items(for: date).count, 1)

        store.undo()
        XCTAssertEqual(store.items(for: date).count, 0)
    }

    func testRedoToggleComplete() {
        let store = TodoStore.shared
        let date = Date()

        let item = store.createItem(title: "Toggle Redo", dayDate: date)
        store.undoManager.clear()

        store.toggleComplete(item)
        XCTAssertTrue(item.isCompleted)

        store.undo()
        XCTAssertFalse(item.isCompleted)

        store.redo()
        XCTAssertTrue(item.isCompleted)
    }

    func testUndoRedoCrossContainerMove() {
        let store = TodoStore.shared
        let sourceDate = fixedDate(year: 2026, month: 1, day: 5)

        let item = store.createItem(title: "cross container", dayDate: sourceDate)
        store.undoManager.clear()

        store.moveItemWithChildren(
            item,
            to: .longTerm(isUrgent: false),
            afterItem: nil,
            newIndentLevel: 0
        )
        XCTAssertEqual(item.containerKind, .longTermImportant)

        store.undo()
        XCTAssertEqual(item.containerKind, .scheduled)
        XCTAssertTrue(Calendar.current.isDate(item.dayDate, inSameDayAs: sourceDate))

        store.redo()
        XCTAssertEqual(item.containerKind, .longTermImportant)
    }

    func testUndoRedoCrossMonthMove() {
        let store = TodoStore.shared
        let sourceDate = fixedDate(year: 2026, month: 1, day: 10)
        let targetDate = fixedDate(year: 2026, month: 2, day: 22)

        let item = store.createItem(title: "cross month", dayDate: sourceDate)
        _ = store.createItem(title: "anchor", dayDate: targetDate)
        store.undoManager.clear()

        let target = store.tailItemForScheduledMonth(year: 2026, month: 2)
        store.moveItemWithChildren(
            item,
            to: .scheduled(date: target.date),
            afterItem: target.tailItem,
            newIndentLevel: 0
        )
        XCTAssertTrue(Calendar.current.isDate(item.dayDate, inSameDayAs: targetDate))

        store.undo()
        XCTAssertTrue(Calendar.current.isDate(item.dayDate, inSameDayAs: sourceDate))
        XCTAssertEqual(item.containerKind, .scheduled)

        store.redo()
        XCTAssertTrue(Calendar.current.isDate(item.dayDate, inSameDayAs: targetDate))
    }

    // MARK: - 回归测试：撤销链路 × SwiftData 持久化边界

    /// #1: 在 deleteItem 的 debounce 窗口内立即撤销，restoreItem 应先 flush pending delete，
    /// 不应触发 @Attribute(.unique) UUID 冲突。
    func testRestoreInDebounceWindowDoesNotConflict() throws {
        let store = TodoStore.shared
        let date = Date()
        let item = store.createItem(title: "race", dayDate: date)
        let originalId = item.id
        store.undoManager.clear()

        // 让 store 持有一些尚未落盘的 changes
        item.title = "edited"
        store.scheduleSave()

        // 删除并立即撤销（在 300ms debounce 内）
        store.deleteItem(item)
        XCTAssertEqual(store.items(for: date).count, 0)
        store.undo()
        XCTAssertEqual(store.items(for: date).count, 1)

        // 把所有挂起的变更落盘，验证数据库内仅有一条同 id
        let context = descriptor.mainContext
        try context.save()
        let fetched = try context.fetch(
            FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == originalId })
        )
        XCTAssertEqual(fetched.count, 1, "唯一约束：数据库内不应同时存在两条同 id 的 item")
        XCTAssertNil(store.lastSaveError, "保存不应出错")
    }

    /// #3: 失效 undo（目标 item 已被外部路径删除）应自动跳过到下一个仍有效的 undo 步骤。
    func testStaleUndoSkipsToNextStep() async throws {
        let store = TodoStore.shared
        let date = Date()

        store.undoManager.clear()
        let a = store.createItem(title: "A", dayDate: date)
        _ = store.createItem(title: "B", dayDate: date)

        // 绕过 deleteItem 注册的 undo，模拟"其他路径删除了 a"
        store.deleteItemWithoutUndo(a)
        XCTAssertEqual(store.items(for: date).count, 1)

        // 栈顶 undo（创建 B）仍有效
        store.undo()
        XCTAssertEqual(store.items(for: date).count, 0)

        // 再撤销：命中"创建 A"的 undo，但 A 已不在 cache → skipStaleUndo 触发
        // skipStaleUndo 用 Task 异步再 undo 一次，等一个 main tick
        store.undo()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(store.canUndo, "失效 undo 步骤应被跳过，整个栈应清空")
    }

    /// #7: 批量删除的撤销必须能 redo，与单条 registerDeleteItem 行为对称。
    func testBatchDeleteSupportsRedo() {
        let store = TodoStore.shared
        let date = Date()

        let items = (0..<3).map { store.createItem(title: "item \($0)", dayDate: date) }
        let snapshots = items.map { TodoItemSnapshot(from: $0) }
        store.undoManager.clear()

        for item in items { store.deleteItemWithoutUndo(item) }
        store.undoManager.registerDeleteItems(snapshots: snapshots, store: store)
        XCTAssertEqual(store.items(for: date).count, 0)

        store.undo()
        XCTAssertEqual(store.items(for: date).count, 3)
        XCTAssertTrue(store.canRedo, "批量删除撤销后必须能 redo")

        store.redo()
        XCTAssertEqual(store.items(for: date).count, 0, "redo 应再次批量删除")
        XCTAssertTrue(store.canUndo, "redo 后应能再 undo")
    }

    private func fixedDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar.current
        return calendar.startOfDay(for: calendar.date(from: components) ?? Date())
    }
}
