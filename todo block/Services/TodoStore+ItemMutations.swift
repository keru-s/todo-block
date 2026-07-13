//
//  TodoStore+ItemMutations.swift
//  todo block
//
//  TodoItem CRUD：创建 / 删除 / 批量删 / 恢复 / 更新 / 勾选 / 移动。
//  从 TodoStore.swift 抽出，主文件仅保留状态、初始化、查询、撤销 facade。
//

import Foundation
import SwiftData

extension TodoStore {
    /// 创建新的待办事项
    func createItem(
        title: String = "",
        dayDate: Date,
        afterItem: TodoItem? = nil,
        indentLevel: Int = 0,
        containerKind: TodoContainerKind = .scheduled,
        insertAtBeginning: Bool = false,
        selectionManager: SelectionManager? = nil
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

        let snapshot = TodoItemSnapshot(
            title: title,
            indentLevel: indentLevel,
            sortOrder: newSortOrder,
            containerKindRaw: containerKind.rawValue,
            dayDate: normalizedDate
        )
        let selectionChanges: [TodoSelectionChange]
        if let selectionManager {
            selectionChanges = [
                TodoSelectionChange(
                    selectionManager: selectionManager,
                    before: TodoSelectionState(selectionManager: selectionManager),
                    after: TodoSelectionState(focusing: snapshot.id)
                )
            ]
        } else {
            selectionChanges = []
        }
        let operation = TodoOperation(
            actionName: "新建",
            itemExistenceChanges: [
                TodoItemExistenceChange(
                    snapshot: snapshot,
                    beforeExists: false,
                    afterExists: true
                )
            ],
            selectionChanges: selectionChanges,
            focusChange: TodoFocusChange(
                before: selectionManager?.focusedItemId ?? afterItem?.id,
                after: snapshot.id
            )
        )
        guard
            undoManager.perform(operation, store: self),
            let newItem = todoItemsCache[snapshot.id]
        else {
            preconditionFailure("创建待办的统一操作未能应用")
        }
        return newItem
    }

    /// 在 `item` 前插入一条同级新 item。
    /// 找同 container + 同 dayDate 里 sortOrder 紧挨着 item 的前驱，
    /// 然后复用 `createItem(afterItem:)` 的 sortOrder 平均逻辑落点。
    /// 若 item 已经是首项，走 `insertAtBeginning` 分支。
    @discardableResult
    func createItemBefore(
        _ item: TodoItem,
        selectionManager: SelectionManager? = nil
    ) -> TodoItem {
        let predecessor = todoItemsCache.values
            .filter {
                $0.containerKindRaw == item.containerKindRaw
                    && $0.dayDate == item.dayDate
                    && $0.sortOrder < item.sortOrder
            }
            .max(by: { $0.sortOrder < $1.sortOrder })

        return createItem(
            dayDate: item.dayDate,
            afterItem: predecessor,
            indentLevel: item.indentLevel,
            containerKind: item.containerKind,
            insertAtBeginning: predecessor == nil,
            selectionManager: selectionManager
        )
    }

    /// 把 `item` 的 title 在光标处切开。原 item 留下 `newCurrentTitle`，
    /// 紧邻其下方插入一条 indent + 1 的子项（已达 max 时降级为同级 sibling），
    /// title = `childTitle`。两个操作合并为 1 步撤销。
    @discardableResult
    func splitItem(_ item: TodoItem, newCurrentTitle: String, childTitle: String) -> TodoItem {
        let oldTitle = item.title
        let newIndent = min(item.indentLevel + 1, TodoItem.maxIndentLevel)

        nsUndoManager.beginUndoGrouping()
        defer {
            nsUndoManager.endUndoGrouping()
            nsUndoManager.setActionName("拆分")
        }

        item.title = newCurrentTitle
        item.updatedAt = Date()
        undoManager.registerTitleChange(
            itemId: item.id,
            oldTitle: oldTitle,
            newTitle: newCurrentTitle,
            store: self
        )

        let child = createItem(
            title: childTitle,
            dayDate: item.dayDate,
            afterItem: item,
            indentLevel: newIndent,
            containerKind: item.containerKind
        )

        scheduleSave()
        return child
    }

    /// 删除待办事项
    func deleteItem(_ item: TodoItem) {
        let destinationItems = items(in: destination(for: item))
        guard
            let itemIndex = destinationItems.firstIndex(where: { $0.id == item.id }),
            let block = TodoHierarchyBlockEngine.block(startingAt: itemIndex, in: destinationItems)
        else { return }

        deleteItemsAsBatch(block.range.map { destinationItems[$0] })
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
    @discardableResult
    func deleteItemsAsBatch(
        _ items: [TodoItem],
        selectionChange: TodoSelectionChange? = nil
    ) -> Bool {
        guard items.isEmpty == false else { return false }
        guard items.allSatisfy({ todoItemsCache[$0.id] != nil }) else { return false }

        var expandedItems: [TodoItem] = []
        var expandedIds = Set<UUID>()
        let itemsByDestination = Dictionary(grouping: items) { destination(for: $0).normalized }
        for (destination, roots) in itemsByDestination {
            let destinationItems = self.items(in: destination)
            let coveredIds = TodoHierarchyBlockEngine.itemIdsCoveredByBlocks(
                rootedAt: Set(roots.map(\.id)),
                in: destinationItems
            )
            for itemId in coveredIds {
                guard
                    expandedIds.insert(itemId).inserted,
                    let item = todoItemsCache[itemId]
                else { continue }
                expandedItems.append(item)
            }
        }
        guard expandedItems.isEmpty == false else { return false }

        let snapshots = expandedItems.map { TodoItemSnapshot(from: $0) }
        let operation = TodoOperation(
            actionName: snapshots.count == 1 ? "删除" : "批量删除",
            itemExistenceChanges: snapshots.map {
                TodoItemExistenceChange(
                    snapshot: $0,
                    beforeExists: true,
                    afterExists: false
                )
            },
            selectionChanges: selectionChange.map { [$0] } ?? [],
            focusChange: selectionChange.map {
                TodoFocusChange(
                    before: $0.before.focusedItemId,
                    after: $0.after.focusedItemId
                )
            }
        )
        return undoManager.perform(operation, store: self)
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
        let newState = item.isCompleted == false

        guard
            let itemIndex = allItems.firstIndex(where: { $0.id == item.id }),
            let block = TodoHierarchyBlockEngine.block(startingAt: itemIndex, in: allItems)
        else { return }

        let changes = block.range.compactMap { index -> TodoCompletionChange? in
            let blockItem = allItems[index]
            guard blockItem.isCompleted != newState else { return nil }
            return TodoCompletionChange(
                itemId: blockItem.id,
                before: blockItem.isCompleted,
                after: newState
            )
        }
        undoManager.perform(
            TodoOperation(actionName: "勾选", completionChanges: changes),
            store: self
        )
    }

    func indentItem(_ item: TodoItem) {
        changeIndent(of: item, requestedDelta: 1)
    }

    func outdentItem(_ item: TodoItem) {
        changeIndent(of: item, requestedDelta: -1)
    }

    private func changeIndent(of item: TodoItem, requestedDelta: Int) {
        let destinationItems = items(in: destination(for: item))
        guard
            let itemIndex = destinationItems.firstIndex(where: { $0.id == item.id }),
            let block = TodoHierarchyBlockEngine.block(startingAt: itemIndex, in: destinationItems)
        else { return }

        let blockIndentLevels = block.range.map { destinationItems[$0].indentLevel }
        let appliedDelta: Int
        if requestedDelta > 0 {
            appliedDelta = min(
                requestedDelta,
                TodoItem.maxIndentLevel - (blockIndentLevels.max() ?? 0)
            )
        } else {
            appliedDelta = max(requestedDelta, -(blockIndentLevels.min() ?? 0))
        }
        guard appliedDelta != 0 else { return }

        let blockItems = block.range.map { destinationItems[$0] }
        let oldSnapshots = blockItems.map { TodoItemSnapshot(from: $0) }
        for (offset, blockItem) in blockItems.enumerated() {
            blockItem.indentLevel = blockIndentLevels[offset] + appliedDelta
            blockItem.updatedAt = .now
        }
        let newSnapshots = blockItems.map { TodoItemSnapshot(from: $0) }
        undoManager.registerMoveItems(from: oldSnapshots, to: newSnapshots, store: self)
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

        guard
            let itemIndex = sourceItems.firstIndex(where: { $0.id == item.id }),
            let movingBlock = TodoHierarchyBlockEngine.block(
                startingAt: itemIndex,
                in: sourceItems
            )
        else {
            return
        }

        let movingIds = Set(movingBlock.itemIds)
        if sourceDestination.normalized == normalizedDestination,
           let afterItem,
           movingIds.contains(afterItem.id) {
            return
        }
        if sourceDestination.normalized == normalizedDestination,
           afterItem == nil,
           movingBlock.range.lowerBound == 0 {
            return
        }

        let normalizedIndentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(in: sourceItems)
        for index in movingBlock.range
        where sourceItems[index].indentLevel != normalizedIndentLevels[index] {
            sourceItems[index].indentLevel = normalizedIndentLevels[index]
            sourceItems[index].updatedAt = .now
        }

        let itemsToMove = movingBlock.range.map { sourceItems[$0] }
        let baseIndent = movingBlock.rootIndentLevel
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
