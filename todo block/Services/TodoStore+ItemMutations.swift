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
        isCompleted: Bool = false,
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
            isCompleted: isCompleted,
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
            selectionChanges: selectionChanges
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
    func splitItem(
        _ item: TodoItem,
        newCurrentTitle: String,
        childTitle: String,
        selectionManager: SelectionManager? = nil
    ) -> TodoItem? {
        guard todoItemsCache[item.id] === item else { return nil }
        let before = TodoItemSnapshot(from: item)
        let newIndent = min(item.indentLevel + 1, TodoItem.maxIndentLevel)
        let destinationItems = items(in: destination(for: item))
        guard let itemIndex = destinationItems.firstIndex(where: { $0.id == item.id }) else {
            return nil
        }
        let childSortOrder: Double
        if itemIndex + 1 < destinationItems.count {
            childSortOrder = (item.sortOrder + destinationItems[itemIndex + 1].sortOrder) / 2
        } else {
            childSortOrder = item.sortOrder + 1000
        }
        let childSnapshot = TodoItemSnapshot(
            title: childTitle,
            indentLevel: newIndent,
            sortOrder: childSortOrder,
            containerKindRaw: item.containerKindRaw,
            dayDate: item.dayDate
        )
        let selectionChanges: [TodoSelectionChange] = selectionManager.map { manager in
            [
                TodoSelectionChange(
                    selectionManager: manager,
                    before: TodoSelectionState(selectionManager: manager),
                    after: TodoSelectionState(focusing: childSnapshot.id)
                )
            ]
        } ?? []
        let operation = TodoOperation(
            actionName: "拆分",
            itemExistenceChanges: [
                TodoItemExistenceChange(
                    snapshot: childSnapshot,
                    beforeExists: false,
                    afterExists: true
                )
            ],
            itemStateChanges: [
                TodoItemStateChange(
                    before: before,
                    after: before.replacing(title: newCurrentTitle)
                )
            ],
            selectionChanges: selectionChanges
        )
        guard undoManager.perform(operation, store: self) else { return nil }
        return todoItemsCache[childSnapshot.id]
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
            selectionChanges: selectionChange.map { [$0] } ?? []
        )
        return undoManager.perform(operation, store: self)
    }

    /// 一次恢复整组待办；写入前只落盘一次待删除状态，避免批量恢复中途部分提交。
    @discardableResult
    func restoreItems(from snapshots: [TodoItemSnapshot]) -> Bool {
        guard snapshots.isEmpty == false else { return true }
        // 让 pending 的 delete 先落盘，避免与下方 insert 撞 @Attribute(.unique) UUID
        guard flushPendingChangesSync() else { return false }
        guard snapshots.allSatisfy({ todoItemsCache[$0.id] == nil }) else { return false }

        for snapshot in snapshots {
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
        }
        refreshTrigger += 1
        scheduleSave()
        return true
    }

    /// 把一组已有待办一次改到记录好的状态，并把日期维护并入同一步。
    @discardableResult
    func applyExistingItemSnapshots(_ snapshots: [TodoItemSnapshot]) -> Bool {
        guard snapshots.isEmpty == false else { return true }
        let items = snapshots.compactMap { todoItemsCache[$0.id] }
        guard items.count == snapshots.count else { return false }

        let sourceScheduledDates = Set(items.compactMap { item -> Date? in
            guard item.containerKind == .scheduled else { return nil }
            return Calendar.current.startOfDay(for: item.dayDate)
        })
        for snapshot in snapshots
        where snapshot.containerKindRaw == TodoContainerKind.scheduled.rawValue {
            _ = ensureSectionMaterialized(for: snapshot.dayDate)
        }

        for (item, snapshot) in zip(items, snapshots) {
            item.title = snapshot.title
            item.isCompleted = snapshot.isCompleted
            item.indentLevel = snapshot.indentLevel
            item.sortOrder = snapshot.sortOrder
            item.containerKindRaw = snapshot.containerKindRaw
            item.dayDate = snapshot.dayDate
            item.updatedAt = .now
        }

        for date in sourceScheduledDates {
            cleanupSectionIfEmpty(scheduledDate: date)
        }
        refreshTrigger += 1
        scheduleSave()
        return true
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

    func setCompletion(
        of itemIds: Set<UUID>,
        in destination: TodoDropDestination,
        isCompleted: Bool
    ) {
        let allItems = items(in: destination)
        let rootIds = TodoHierarchyBlockEngine.blockRootIds(
            selectedFrom: itemIds,
            in: allItems
        )
        let coveredIds = TodoHierarchyBlockEngine.itemIdsCoveredByBlocks(
            rootedAt: Set(rootIds),
            in: allItems
        )
        let changes = allItems.compactMap { candidate -> TodoCompletionChange? in
            guard coveredIds.contains(candidate.id), candidate.isCompleted != isCompleted else {
                return nil
            }
            return TodoCompletionChange(
                itemId: candidate.id,
                before: candidate.isCompleted,
                after: isCompleted
            )
        }
        guard changes.isEmpty == false else { return }
        undoManager.perform(
            TodoOperation(actionName: "勾选", completionChanges: changes),
            store: self
        )
    }

    func indentItem(_ item: TodoItem, selectionManager: SelectionManager? = nil) {
        changeIndent(of: item, requestedDelta: 1, selectionManager: selectionManager)
    }

    func outdentItem(_ item: TodoItem, selectionManager: SelectionManager? = nil) {
        changeIndent(of: item, requestedDelta: -1, selectionManager: selectionManager)
    }

    private func changeIndent(
        of item: TodoItem,
        requestedDelta: Int,
        selectionManager: SelectionManager?
    ) {
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
        let newSnapshots = oldSnapshots.enumerated().map { offset, snapshot in
            snapshot.replacing(indentLevel: blockIndentLevels[offset] + appliedDelta)
        }
        let selectionChanges: [TodoSelectionChange] = selectionManager.map { manager in
            let state = TodoSelectionState(selectionManager: manager)
            return [TodoSelectionChange(selectionManager: manager, before: state, after: state)]
        } ?? []
        undoManager.perform(
            TodoOperation(
                actionName: appliedDelta > 0 ? "缩进" : "反缩进",
                itemStateChanges: zip(oldSnapshots, newSnapshots).map {
                    TodoItemStateChange(before: $0.0, after: $0.1)
                },
                selectionChanges: selectionChanges
            ),
            store: self
        )
    }

}
