//
//  UndoManager.swift
//  todo block
//
//  Created by Claude on 2026/2/9.
//

import Foundation

// MARK: - 焦点恢复通知

extension Notification.Name {
    static let focusRequest = Notification.Name("focusRequest")
}
// MARK: - TodoItem 快照（用于恢复已删除或移动的项目）

struct TodoItemSnapshot {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let indentLevel: Int
    let sortOrder: Double
    let dayDate: Date
    let createdAt: Date
    let updatedAt: Date

    init(from item: TodoItem) {
        self.id = item.id
        self.title = item.title
        self.isCompleted = item.isCompleted
        self.indentLevel = item.indentLevel
        self.sortOrder = item.sortOrder
        self.dayDate = item.dayDate
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }
}

// MARK: - 统一撤销管理器（基于 NSUndoManager）

/// 使用 NSUndoManager 统一管理所有撤销操作
/// 这样可以与 TextField 的原生撤销共享同一个撤销栈
@MainActor
@Observable
final class TodoUndoManager {
    /// 共享的 NSUndoManager 实例
    let nsUndoManager = UndoManager()

    /// 最大撤销步数
    private let maxUndoSteps = 50

    /// 是否有可撤销的操作
    var canUndo: Bool {
        nsUndoManager.canUndo
    }

    /// 是否有可重做的操作
    var canRedo: Bool {
        nsUndoManager.canRedo
    }

    init() {
        nsUndoManager.levelsOfUndo = maxUndoSteps
    }

    // MARK: - 注册撤销操作

    /// 注册创建 Item 的撤销（撤销时删除该 Item，redo 时恢复）
    /// - Parameters:
    ///   - itemId: 新创建的 item ID
    ///   - previousItemId: 创建前焦点所在的 item ID（撤销后恢复焦点）
    ///   - store: TodoStore 实例
    func registerCreateItem(itemId: UUID, previousItemId: UUID?, store: TodoStore) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            guard let item = store.todoItemsCache[itemId] else { return }
            // 保存快照用于 redo
            let snapshot = TodoItemSnapshot(from: item)
            store.deleteItemWithoutUndo(item)
            store.requestFocus(previousItemId)
            // 注册 redo 操作（恢复 item）
            self?.nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
                store.restoreItem(from: snapshot)
                store.requestFocus(itemId)
                // 再次注册 undo 操作
                self?.registerCreateItem(
                    itemId: itemId, previousItemId: previousItemId, store: store)
            }
            self?.nsUndoManager.setActionName("新建")
        }
        nsUndoManager.setActionName("新建")
    }

    /// 注册删除 Item 的撤销（撤销时恢复该 Item，redo 时删除）
    func registerDeleteItem(snapshot: TodoItemSnapshot, store: TodoStore) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            store.restoreItem(from: snapshot)
            store.requestFocus(snapshot.id)
            // 注册 redo 操作（再次删除 item）
            self?.nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
                if let item = store.todoItemsCache[snapshot.id] {
                    store.deleteItemWithoutUndo(item)
                    // 再次注册 undo 操作
                    self?.registerDeleteItem(snapshot: snapshot, store: store)
                }
            }
            self?.nsUndoManager.setActionName("删除")
        }
        nsUndoManager.setActionName("删除")
    }

    /// 注册批量删除的撤销
    func registerDeleteItems(snapshots: [TodoItemSnapshot], store: TodoStore) {
        nsUndoManager.registerUndo(withTarget: store) { store in
            for snapshot in snapshots.reversed() {
                store.restoreItem(from: snapshot)
            }
        }
        nsUndoManager.setActionName("删除")
    }

    /// 注册完成状态切换的撤销
    func registerToggleComplete(
        itemId: UUID,
        oldState: Bool,
        newState: Bool,
        childOldStates: [(UUID, Bool)],
        childNewStates: [(UUID, Bool)],
        store: TodoStore
    ) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            if let item = store.todoItemsCache[itemId] {
                item.isCompleted = oldState
                item.updatedAt = Date()
            }
            for (childId, childState) in childOldStates {
                if let child = store.todoItemsCache[childId] {
                    child.isCompleted = childState
                    child.updatedAt = Date()
                }
            }
            self?.registerToggleComplete(
                itemId: itemId,
                oldState: newState,
                newState: oldState,
                childOldStates: childNewStates,
                childNewStates: childOldStates,
                store: store
            )
            store.scheduleSave()
        }
        nsUndoManager.setActionName("勾选")
    }

    /// 注册缩进变化的撤销
    func registerIndentChange(itemId: UUID, oldIndent: Int, newIndent: Int, store: TodoStore) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            if let item = store.todoItemsCache[itemId] {
                item.indentLevel = oldIndent
                item.updatedAt = Date()
                self?.registerIndentChange(
                    itemId: itemId, oldIndent: newIndent, newIndent: oldIndent, store: store)
                store.scheduleSave()
            }
        }
        nsUndoManager.setActionName("缩进")
    }

    /// 注册标题变化的撤销
    func registerTitleChange(itemId: UUID, oldTitle: String, newTitle: String, store: TodoStore) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            if let item = store.todoItemsCache[itemId] {
                item.title = oldTitle
                item.updatedAt = Date()
                self?.registerTitleChange(
                    itemId: itemId, oldTitle: newTitle, newTitle: oldTitle, store: store)
                store.scheduleSave()
            }
        }
        nsUndoManager.setActionName("编辑")
    }

    /// 注册移动 Items 的撤销
    func registerMoveItems(from oldSnapshots: [TodoItemSnapshot], to newSnapshots: [TodoItemSnapshot], store: TodoStore) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            for snapshot in oldSnapshots {
                if let item = store.todoItemsCache[snapshot.id] {
                    item.dayDate = snapshot.dayDate
                    item.sortOrder = snapshot.sortOrder
                    item.indentLevel = snapshot.indentLevel
                    item.updatedAt = Date()
                }
            }
            self?.registerMoveItems(from: newSnapshots, to: oldSnapshots, store: store)
            store.scheduleSave()
        }
        nsUndoManager.setActionName("移动")
    }

    /// 执行撤销
    func undo() {
        if nsUndoManager.canUndo {
            nsUndoManager.undo()
        }
    }

    /// 执行重做
    func redo() {
        if nsUndoManager.canRedo {
            nsUndoManager.redo()
        }
    }

    /// 清空撤销栈
    func clear() {
        nsUndoManager.removeAllActions()
    }
}
