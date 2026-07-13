//
//  TodoUndoManager.swift
//  todo block
//
//  Created by Claude on 2026/2/9.
//

import Foundation

enum TodoOperationValueTarget {
    case before
    case after
}

struct TodoCompletionChange {
    let itemId: UUID
    let before: Bool
    let after: Bool

    func value(for target: TodoOperationValueTarget) -> Bool {
        switch target {
        case .before:
            before
        case .after:
            after
        }
    }
}

struct TodoItemExistenceChange {
    let snapshot: TodoItemSnapshot
    let beforeExists: Bool
    let afterExists: Bool

    func exists(for target: TodoOperationValueTarget) -> Bool {
        switch target {
        case .before:
            beforeExists
        case .after:
            afterExists
        }
    }
}

struct TodoSelectionState: Equatable {
    let focusedItemId: UUID?
    let selectedItemIds: Set<UUID>
    let lastSelectedId: UUID?
    let cursorPosition: Int

    init(selectionManager: SelectionManager) {
        focusedItemId = selectionManager.focusedItemId
        selectedItemIds = selectionManager.selectedItemIds
        lastSelectedId = selectionManager.lastSelectedId
        cursorPosition = selectionManager.cursorPosition
    }

    init(focusing itemId: UUID?, cursorPosition: Int = 0) {
        focusedItemId = itemId
        selectedItemIds = itemId.map { [$0] } ?? []
        lastSelectedId = itemId
        self.cursorPosition = cursorPosition
    }

    func apply(to selectionManager: SelectionManager) {
        selectionManager.focusedItemId = focusedItemId
        selectionManager.selectedItemIds = selectedItemIds
        selectionManager.lastSelectedId = lastSelectedId
        selectionManager.cursorPosition = cursorPosition
        selectionManager.preferredHorizontalOffset = nil
        selectionManager.verticalMoveDirection = nil
    }
}

struct TodoSelectionChange {
    let historyContext: TodoSelectionHistoryContext
    let before: TodoSelectionState
    let after: TodoSelectionState

    init(
        selectionManager: SelectionManager,
        before: TodoSelectionState,
        after: TodoSelectionState
    ) {
        selectionManager.activateHistoryContext()
        historyContext = selectionManager.historyContext
        self.before = before
        self.after = after
    }

    func state(for target: TodoOperationValueTarget) -> TodoSelectionState {
        switch target {
        case .before:
            before
        case .after:
            after
        }
    }

    func apply(for target: TodoOperationValueTarget) {
        guard let selectionManager = SelectionManager.activeManager(for: historyContext) else {
            return
        }
        state(for: target).apply(to: selectionManager)
    }
}

struct TodoOperation {
    let actionName: String
    var completionChanges: [TodoCompletionChange] = []
    var itemExistenceChanges: [TodoItemExistenceChange] = []
    var selectionChanges: [TodoSelectionChange] = []

    var isEmpty: Bool {
        completionChanges.isEmpty
            && itemExistenceChanges.isEmpty
    }
}

// MARK: - TodoItem 快照（用于恢复已删除或移动的项目）

struct TodoItemSnapshot {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let indentLevel: Int
    let sortOrder: Double
    let containerKindRaw: String
    let dayDate: Date
    let createdAt: Date
    let updatedAt: Date

    init(from item: TodoItem) {
        self.id = item.id
        self.title = item.title
        self.isCompleted = item.isCompleted
        self.indentLevel = item.indentLevel
        self.sortOrder = item.sortOrder
        self.containerKindRaw = item.containerKindRaw
        self.dayDate = item.dayDate
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        indentLevel: Int,
        sortOrder: Double,
        containerKindRaw: String,
        dayDate: Date,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.indentLevel = indentLevel
        self.sortOrder = sortOrder
        self.containerKindRaw = containerKindRaw
        self.dayDate = Calendar.current.startOfDay(for: dayDate)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func matchesUserState(of item: TodoItem) -> Bool {
        item.id == id
            && item.title == title
            && item.isCompleted == isCompleted
            && item.indentLevel == indentLevel
            && item.sortOrder == sortOrder
            && item.containerKindRaw == containerKindRaw
            && item.dayDate == dayDate
            && item.createdAt == createdAt
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

    private enum InvocationResult {
        case legacyApplied
        case applied
        case invalid
    }

    private var invocationResult = InvocationResult.legacyApplied

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

    @discardableResult
    func perform(_ operation: TodoOperation, store: TodoStore) -> Bool {
        guard operation.isEmpty == false else { return false }
        guard canApply(operation, target: .after, store: store) else { return false }

        guard apply(operation, target: .after, store: store) else { return false }
        register(operation, target: .before, store: store)
        store.scheduleSave()
        return true
    }

    private func register(
        _ operation: TodoOperation,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            guard let self else { return }
            guard self.canApply(operation, target: target, store: store) else {
                self.invocationResult = .invalid
                return
            }

            guard self.apply(operation, target: target, store: store) else {
                self.invocationResult = .invalid
                return
            }
            self.invocationResult = .applied
            let oppositeTarget: TodoOperationValueTarget =
                target == .before ? .after : .before
            self.register(operation, target: oppositeTarget, store: store)
            store.scheduleSave()
        }
        nsUndoManager.setActionName(operation.actionName)
    }

    private func canApply(
        _ operation: TodoOperation,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) -> Bool {
        let sourceTarget: TodoOperationValueTarget = target == .before ? .after : .before
        let completionChangesAreValid = operation.completionChanges.allSatisfy { change in
            guard let item = store.todoItemsCache[change.itemId] else { return false }
            return item.isCompleted == change.value(for: sourceTarget)
        }
        guard completionChangesAreValid else { return false }

        return operation.itemExistenceChanges.allSatisfy { change in
            let sourceExists = change.exists(for: sourceTarget)
            guard sourceExists else {
                return store.todoItemsCache[change.snapshot.id] == nil
            }
            guard let item = store.todoItemsCache[change.snapshot.id] else { return false }
            return change.snapshot.matchesUserState(of: item)
        }
    }

    private func apply(
        _ operation: TodoOperation,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) -> Bool {
        let snapshotsToRestore: [TodoItemSnapshot] =
            operation.itemExistenceChanges.compactMap { change -> TodoItemSnapshot? in
            guard
                change.exists(for: target),
                store.todoItemsCache[change.snapshot.id] == nil
            else { return nil }
            return change.snapshot
        }
        guard store.restoreItems(from: snapshotsToRestore) else {
            return false
        }

        for change in operation.completionChanges {
            guard let item = store.todoItemsCache[change.itemId] else { continue }
            item.isCompleted = change.value(for: target)
            item.updatedAt = .now
        }

        for change in operation.itemExistenceChanges
        where change.exists(for: target) == false {
            guard let item = store.todoItemsCache[change.snapshot.id] else { continue }
            store.deleteItemWithoutUndo(item)
        }

        operation.selectionChanges.forEach { $0.apply(for: target) }
        return true
    }

    // MARK: - 失效记录跳过

    /// 旧式闭包无法执行时只上报失效，由外层 undo / redo 循环继续寻找有效记录。
    /// 不在闭包内重入 UndoManager，确保撤销与恢复使用各自正确的方向。
    private func markCurrentInvocationInvalid() {
        invocationResult = .invalid
    }

    private func markCurrentInvocationApplied() {
        invocationResult = .applied
    }

    // MARK: - 注册撤销操作

    /// 注册创建 Item 的撤销（撤销时删除该 Item，redo 时恢复）
    /// - Parameters:
    ///   - itemId: 新创建的 item ID
    ///   - previousItemId: 创建前焦点所在的 item ID（撤销后恢复焦点）
    ///   - store: TodoStore 实例
    func registerCreateItem(itemId: UUID, previousItemId: UUID?, store: TodoStore) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            guard let item = store.todoItemsCache[itemId] else {
                self?.markCurrentInvocationInvalid()
                return
            }
            self?.markCurrentInvocationApplied()
            // 保存快照用于 redo
            let snapshot = TodoItemSnapshot(from: item)
            store.deleteItemWithoutUndo(item)
            store.requestFocus(previousItemId)
            // 注册 redo 操作（恢复 item）
            self?.nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
                self?.markCurrentInvocationApplied()
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
            self?.markCurrentInvocationApplied()
            store.restoreItem(from: snapshot)
            store.requestFocus(snapshot.id)
            // 注册 redo 操作（再次删除 item）
            self?.nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
                guard let item = store.todoItemsCache[snapshot.id] else {
                    self?.markCurrentInvocationInvalid()
                    return
                }
                self?.markCurrentInvocationApplied()
                store.deleteItemWithoutUndo(item)
                // 再次注册 undo 操作
                self?.registerDeleteItem(snapshot: snapshot, store: store)
            }
            self?.nsUndoManager.setActionName("删除")
        }
        nsUndoManager.setActionName("删除")
    }

    /// 注册批量删除的撤销（支持对称 redo）
    func registerDeleteItems(snapshots: [TodoItemSnapshot], store: TodoStore) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            self?.markCurrentInvocationApplied()
            // undo: 恢复所有 snapshot
            for snapshot in snapshots.reversed() {
                store.restoreItem(from: snapshot)
            }
            // 注册 redo: 再次批量删除
            self?.nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
                let items = snapshots.compactMap { store.todoItemsCache[$0.id] }
                guard items.count == snapshots.count else {
                    self?.markCurrentInvocationInvalid()
                    return
                }
                self?.markCurrentInvocationApplied()
                for item in items {
                    store.deleteItemWithoutUndo(item)
                }
                // 再注册 undo
                self?.registerDeleteItems(snapshots: snapshots, store: store)
            }
            self?.nsUndoManager.setActionName("批量删除")
        }
        nsUndoManager.setActionName("批量删除")
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
            guard let item = store.todoItemsCache[itemId] else {
                self?.markCurrentInvocationInvalid()
                return
            }
            let childItems = childOldStates.compactMap { store.todoItemsCache[$0.0] }
            guard childItems.count == childOldStates.count else {
                self?.markCurrentInvocationInvalid()
                return
            }
            self?.markCurrentInvocationApplied()
            item.isCompleted = oldState
            item.updatedAt = Date()
            for (child, (_, childState)) in zip(childItems, childOldStates) {
                child.isCompleted = childState
                child.updatedAt = Date()
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
        registerItemFieldChange(
            itemId: itemId, oldValue: oldIndent, newValue: newIndent,
            actionName: "缩进", store: store,
            apply: { $0.indentLevel = $1 }
        )
    }

    /// 注册标题变化的撤销
    func registerTitleChange(itemId: UUID, oldTitle: String, newTitle: String, store: TodoStore) {
        registerItemFieldChange(
            itemId: itemId, oldValue: oldTitle, newValue: newTitle,
            actionName: "编辑", store: store,
            apply: { $0.title = $1 }
        )
    }

    /// 单字段改写的对称撤销模板：失效跳过 → 应用 oldValue → 反向自重注册 → 调度保存。
    private func registerItemFieldChange<Value>(
        itemId: UUID,
        oldValue: Value,
        newValue: Value,
        actionName: String,
        store: TodoStore,
        apply: @escaping (TodoItem, Value) -> Void
    ) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            guard let item = store.todoItemsCache[itemId] else {
                self?.markCurrentInvocationInvalid()
                return
            }
            self?.markCurrentInvocationApplied()
            apply(item, oldValue)
            item.updatedAt = Date()
            self?.registerItemFieldChange(
                itemId: itemId, oldValue: newValue, newValue: oldValue,
                actionName: actionName, store: store, apply: apply
            )
            store.scheduleSave()
        }
        nsUndoManager.setActionName(actionName)
    }

    /// 注册移动 Items 的撤销
    func registerMoveItems(from oldSnapshots: [TodoItemSnapshot], to newSnapshots: [TodoItemSnapshot], store: TodoStore) {
        nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
            let items = oldSnapshots.compactMap { store.todoItemsCache[$0.id] }
            guard items.count == oldSnapshots.count else {
                self?.markCurrentInvocationInvalid()
                return
            }
            // 先把可能被孤儿清理删掉的源 DaySection 重建回来，否则下面写 dayDate
            // 时该日没有 section，UI 端就会出现"item 有日期但月份列表里看不到"的悬空状态。
            for snapshot in oldSnapshots
            where snapshot.containerKindRaw == TodoContainerKind.scheduled.rawValue {
                _ = store.getOrCreateSection(for: snapshot.dayDate)
            }
            for (item, snapshot) in zip(items, oldSnapshots) {
                item.containerKindRaw = snapshot.containerKindRaw
                item.dayDate = snapshot.dayDate
                item.sortOrder = snapshot.sortOrder
                item.indentLevel = snapshot.indentLevel
                item.updatedAt = Date()
            }
            self?.markCurrentInvocationApplied()
            self?.registerMoveItems(from: newSnapshots, to: oldSnapshots, store: store)
            store.scheduleSave()
        }
        nsUndoManager.setActionName("移动")
    }

    /// 执行撤销
    @discardableResult
    func undo() -> Bool {
        while nsUndoManager.canUndo {
            invocationResult = .legacyApplied
            nsUndoManager.undo()
            switch invocationResult {
            case .invalid:
                continue
            case .applied, .legacyApplied:
                return true
            }
        }
        return false
    }

    /// 执行重做
    @discardableResult
    func redo() -> Bool {
        while nsUndoManager.canRedo {
            invocationResult = .legacyApplied
            nsUndoManager.redo()
            switch invocationResult {
            case .invalid:
                continue
            case .applied, .legacyApplied:
                return true
            }
        }
        return false
    }

    /// 清空撤销栈
    func clear() {
        nsUndoManager.removeAllActions()
    }
}
