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

        TodoStore.shared.initialize(with: descriptor.mainContext)
        TodoStore.shared.reset()
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

        store.undoManager.clear()

        // 创建 3 个 items
        let item1 = store.createItem(title: "Item 1", dayDate: date)
        let item2 = store.createItem(title: "Item 2", dayDate: date)
        let item3 = store.createItem(title: "Item 3", dayDate: date)

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
}
