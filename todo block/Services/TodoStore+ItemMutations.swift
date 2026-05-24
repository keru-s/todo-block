//
//  TodoStore+ItemMutations.swift
//  todo block
//
//  TodoItem CRUD：创建 / 删除 / 批量删 / 恢复 / 更新 / 勾选 / 移动。
//  从 TodoStore.swift 抽出，主文件仅保留状态、初始化、查询、撤销 facade。
//

import Foundation
import SwiftData

@MainActor
extension TodoStore {
    /// 创建新的待办事项
    func createItem(
        title: String = "",
        dayDate: Date,
        afterItem: TodoItem? = nil,
        indentLevel: Int = 0,
        containerKind: TodoContainerKind = .scheduled,
        insertAtBeginning: Bool = false
    ) -> TodoItem {
        let normalizedDate = Calendar.current.startOfDay(for: dayDate)
        let destination: TodoDropDestination = {
            switch containerKind {
            case .scheduled:
                return .scheduled(date: normalizedDate)
            case .longTermUrgent:
                return .longTerm(isUrgent: true)
            case .longTermImportant:
                return .longTerm(isUrgent: false)
            }
        }()

        let currentItems = items(in: destination)
        var newSortOrder: Double

        if let afterItem,
            let afterIndex = currentItems.firstIndex(where: { $0.id == afterItem.id })
        {
            if afterIndex + 1 < currentItems.count {
                let nextItem = currentItems[afterIndex + 1]
                newSortOrder = (afterItem.sortOrder + nextItem.sortOrder) / 2
            } else {
                newSortOrder = afterItem.sortOrder + 1000
            }
        } else if insertAtBeginning, let firstItem = currentItems.first {
            newSortOrder = firstItem.sortOrder - 1000
        } else if let lastItem = currentItems.last {
            newSortOrder = lastItem.sortOrder + 1000
        } else {
            newSortOrder = 1000
        }

        if containerKind == .scheduled {
            _ = ensureSectionMaterialized(for: normalizedDate)
        }

        let newItem = TodoItem(
            title: title,
            indentLevel: indentLevel,
            sortOrder: newSortOrder,
            containerKindRaw: containerKind.rawValue,
            dayDate: normalizedDate
        )

        todoItemsCache[newItem.id] = newItem

        modelContext?.insert(newItem)
        refreshTrigger += 1
        scheduleSave()

        undoManager.registerCreateItem(
            itemId: newItem.id, previousItemId: afterItem?.id, store: self)

        return newItem
    }

    /// 删除待办事项
    func deleteItem(_ item: TodoItem) {
        let snapshot = TodoItemSnapshot(from: item)
        undoManager.registerDeleteItem(snapshot: snapshot, store: self)

        let scheduledDate: Date? = item.containerKind == .scheduled ? item.dayDate : nil
        todoItemsCache.removeValue(forKey: item.id)
        modelContext?.delete(item)
        if let scheduledDate {
            cleanupSectionIfEmpty(scheduledDate: scheduledDate)
        }
        refreshTrigger += 1
        scheduleSave()
    }

    /// 删除待办事项（不注册撤销，用于撤销操作内部调用）
    func deleteItemWithoutUndo(_ item: TodoItem) {
        let scheduledDate: Date? = item.containerKind == .scheduled ? item.dayDate : nil
        todoItemsCache.removeValue(forKey: item.id)
        modelContext?.delete(item)
        if let scheduledDate {
            cleanupSectionIfEmpty(scheduledDate: scheduledDate)
        }
        refreshTrigger += 1
        scheduleSave()
    }

    /// 批量删除若干 item，注册单步撤销（"批量删除"）。
    /// 与逐条 `deleteItem` 相比，撤销原子性更高：一次 Cmd+Z 即可恢复全部。
    /// SelectionManager.deleteSelectedItems 是主要调用方。
    func deleteItemsAsBatch(_ items: [TodoItem]) {
        guard items.isEmpty == false else { return }

        let snapshots = items.map { TodoItemSnapshot(from: $0) }

        // 收集需要事后清理的 scheduled section 日期，去重
        var scheduledDatesToCheck: Set<Date> = []
        for item in items where item.containerKind == .scheduled {
            scheduledDatesToCheck.insert(Calendar.current.startOfDay(for: item.dayDate))
        }

        // 全量删除（不在循环内注册逐条 undo）
        for item in items {
            todoItemsCache.removeValue(forKey: item.id)
            modelContext?.delete(item)
        }

        // 删完后再回收空 section（顺序敏感：所有 item 已离开 cache，cleanup 才能识别空）
        for date in scheduledDatesToCheck {
            cleanupSectionIfEmpty(scheduledDate: date)
        }

        // 单步注册批量撤销
        undoManager.registerDeleteItems(snapshots: snapshots, store: self)

        refreshTrigger += 1
        scheduleSave()
    }

    /// 恢复已删除的待办事项
    func restoreItem(from snapshot: TodoItemSnapshot) {
        // 让 pending 的 delete 先落盘，避免与下方 insert 撞 @Attribute(.unique) UUID
        flushPendingChangesSync()
        let restoredItem = TodoItem(
            id: snapshot.id,
            title: snapshot.title,
            isCompleted: snapshot.isCompleted,
            indentLevel: snapshot.indentLevel,
            sortOrder: snapshot.sortOrder,
            containerKindRaw: snapshot.containerKindRaw,
            dayDate: snapshot.dayDate,
            createdAt: snapshot.createdAt,
            updatedAt: Date()
        )

        if restoredItem.containerKind == .scheduled {
            _ = ensureSectionMaterialized(for: restoredItem.dayDate)
        }

        todoItemsCache[restoredItem.id] = restoredItem
        modelContext?.insert(restoredItem)
        refreshTrigger += 1
        scheduleSave()
    }

    /// 更新待办事项
    func updateItem(_ item: TodoItem) {
        item.updatedAt = Date()
        scheduleSave()
    }

    /// 标记完成（包括子任务）
    func toggleComplete(_ item: TodoItem) {
        let allItems = items(in: destination(for: item))
        let oldState = item.isCompleted
        let newState = oldState == false

        var childStates: [(UUID, Bool)] = []

        item.isCompleted = newState
        item.updatedAt = Date()

        if let itemIndex = allItems.firstIndex(where: { $0.id == item.id }) {
            let itemIndent = item.indentLevel

            for index in (itemIndex + 1)..<allItems.count {
                let child = allItems[index]
                if child.indentLevel > itemIndent {
                    childStates.append((child.id, child.isCompleted))
                    child.isCompleted = newState
                    child.updatedAt = Date()
                } else {
                    break
                }
            }
        }

        let childNewStates = childStates.map { ($0.0, newState) }
        undoManager.registerToggleComplete(
            itemId: item.id,
            oldState: oldState,
            newState: newState,
            childOldStates: childStates,
            childNewStates: childNewStates,
            store: self
        )

        scheduleSave()
    }

    /// 移动待办事项及其子项到新位置
    func moveItemWithChildren(
        _ item: TodoItem,
        to destination: TodoDropDestination,
        afterItem: TodoItem?,
        newIndentLevel: Int
    ) {
        let normalizedDestination = destination.normalized
        let sourceDestination = self.destination(for: item)
        let sourceItems = items(in: sourceDestination)

        guard let itemIndex = sourceItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        var itemsToMove = [item]
        var movingIds: Set<UUID> = [item.id]
        let baseIndent = item.indentLevel

        for index in (itemIndex + 1)..<sourceItems.count {
            let child = sourceItems[index]
            if child.indentLevel > baseIndent {
                itemsToMove.append(child)
                movingIds.insert(child.id)
            } else {
                break
            }
        }

        let snapshots = itemsToMove.map { TodoItemSnapshot(from: $0) }
        let indentDelta = newIndentLevel - baseIndent

        let targetItems = items(in: normalizedDestination).filter { movingIds.contains($0.id) == false }

        // 计算 baseSortOrder + stepSize：必须保证 itemsToMove 落点全在
        // (afterItem, nextItem) 这个 gap 内，否则带 child 移动时 child 会越过
        // nextItem 排到后面，看起来像"父项移走了 child 没跟上"。
        // 固定 0.001 步进在历史密集插入产生的小 gap（如 0.001）下会触发。
        let baseSortOrder: Double
        let stepSize: Double
        if let afterItem,
            let afterIndex = targetItems.firstIndex(where: { $0.id == afterItem.id })
        {
            if afterIndex + 1 < targetItems.count {
                let nextItem = targetItems[afterIndex + 1]
                let gap = nextItem.sortOrder - afterItem.sortOrder
                // 把 gap 平均分给 (itemsToMove.count + 1) 个间隔，
                // baseSortOrder 占第 1 格，余下 N 个 child 各占 1 格，
                // 最后一个 child 离 nextItem 还有 1 格缓冲。
                let slots = Double(itemsToMove.count + 1)
                stepSize = gap / slots
                baseSortOrder = afterItem.sortOrder + stepSize
            } else {
                baseSortOrder = afterItem.sortOrder + 1000
                stepSize = 0.001
            }
        } else if let firstItem = targetItems.first {
            baseSortOrder = firstItem.sortOrder - 1000
            stepSize = 0.001
        } else {
            baseSortOrder = 1000
            stepSize = 0.001
        }

        if case .scheduled(let date) = normalizedDestination {
            _ = ensureSectionMaterialized(for: date)
        }

        for (offset, movingItem) in itemsToMove.enumerated() {
            movingItem.containerKind = normalizedDestination.containerKind
            if case .scheduled(let date) = normalizedDestination {
                movingItem.dayDate = date
            }
            movingItem.sortOrder = baseSortOrder + Double(offset) * stepSize
            movingItem.indentLevel = max(
                0,
                min(TodoItem.maxIndentLevel, movingItem.indentLevel + indentDelta)
            )
            movingItem.updatedAt = Date()
        }

        let movedSnapshots = itemsToMove.map { TodoItemSnapshot(from: $0) }
        undoManager.registerMoveItems(from: snapshots, to: movedSnapshots, store: self)

        // 若源是 scheduled 且目标 ≠ 源，源日期可能变成空 section，清理掉。
        if case .scheduled(let sourceDate) = sourceDestination.normalized,
           sourceDestination.normalized != normalizedDestination {
            cleanupSectionIfEmpty(scheduledDate: sourceDate)
        }

        refreshTrigger += 1
        scheduleSave()
    }
}
