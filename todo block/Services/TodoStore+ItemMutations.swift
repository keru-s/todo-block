//
//  TodoStore+ItemMutations.swift
//  todo block
//
//  TodoItem CRUD：创建 / 删除 / 批量删 / 恢复 / 更新 / 勾选 / 移动。
//  从 TodoStore.swift 抽出，主文件仅保留状态、初始化、查询、撤销 facade。
//

import Foundation
import OSLog
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
        let selectionTransitions: [TodoSelectionTransition]
        if let selectionManager {
            selectionTransitions = [
                TodoSelectionTransition(
                    selectionManager: selectionManager,
                    before: TodoSelectionState(selectionManager: selectionManager),
                    after: TodoSelectionState(focusing: snapshot.id)
                )
            ]
        } else {
            selectionTransitions = []
        }
        let operation = TodoOperationUnit(
            actionName: "新建",
            itemTransitions: [TodoItemTransition(before: nil, after: snapshot)],
            selectionTransitions: selectionTransitions
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
        let selectionTransitions: [TodoSelectionTransition] = selectionManager.map { manager in
            [
                TodoSelectionTransition(
                    selectionManager: manager,
                    before: TodoSelectionState(selectionManager: manager),
                    after: TodoSelectionState(focusing: childSnapshot.id)
                )
            ]
        } ?? []
        let operation = TodoOperationUnit(
            actionName: "拆分",
            itemTransitions: [
                TodoItemTransition(before: nil, after: childSnapshot),
                TodoItemTransition(before: before, after: before.replacing(title: newCurrentTitle))
            ],
            selectionTransitions: selectionTransitions
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
        selectionTransition: TodoSelectionTransition? = nil
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
        let operation = TodoOperationUnit(
            actionName: snapshots.count == 1 ? "删除" : "批量删除",
            itemTransitions: snapshots.map { TodoItemTransition(before: $0, after: nil) },
            selectionTransitions: selectionTransition.map { [$0] } ?? []
        )
        return undoManager.perform(operation, store: self)
    }

    /// 一次恢复整组待办。写盘失败不会阻止已经完成的撤销；后续重试只保存最终状态。
    @discardableResult
    func restoreItems(from snapshots: [TodoItemSnapshot]) -> Bool {
        guard snapshots.isEmpty == false else { return true }
        // 正常情况下先落盘 pending delete，避免与下方 insert 撞 @Attribute(.unique) UUID。
        // 若写盘已失败，先记住用户眼前的完整结果，再回到上次确认状态并重建该结果，
        // 避免同一上下文中同时保留待删除对象和同身份的新对象。
        let pendingSnapshots = todoItemsCache.values.map(TodoItemSnapshot.init(from:))
        if flushPendingChangesSync() == false {
            let restoredIds = Set(snapshots.map(\.id))
            let deletedItemIds = Set(
                modelContext?.deletedModelsArray.compactMap { ($0 as? TodoItem)?.id } ?? []
            )
            if restoredIds.isDisjoint(with: deletedItemIds) == false {
                return restoreItemsAfterFailedSave(
                    existingSnapshots: pendingSnapshots,
                    restoredSnapshots: snapshots
                )
            }
        }
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
                updatedAt: .now
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

    private func restoreItemsAfterFailedSave(
        existingSnapshots: [TodoItemSnapshot],
        restoredSnapshots: [TodoItemSnapshot]
    ) -> Bool {
        guard let modelContext else { return false }

        var desiredSnapshots: [UUID: TodoItemSnapshot] = [:]
        for snapshot in existingSnapshots + restoredSnapshots {
            desiredSnapshots[snapshot.id] = snapshot
        }

        let insertedItemIds = Set(
            modelContext.insertedModelsArray.compactMap { ($0 as? TodoItem)?.id }
        )
        let insertedSectionIds = Set(
            modelContext.insertedModelsArray.compactMap { ($0 as? DaySection)?.id }
        )

        var persistedItems: [UUID: TodoItem]
        var persistedSections: [DaySection]
        do {
            persistedItems = Dictionary(
                uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<TodoItem>()).map {
                    ($0.id, $0)
                }
            )
            persistedSections = try modelContext.fetch(FetchDescriptor<DaySection>())
        } catch {
            Self.logger.error(
                "restoreItemsAfterFailedSave preparation failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        // 尚未落盘的对象会被 rollback 移除，不能在之后复用；它们会根据上方快照重新插入。
        for itemId in insertedItemIds {
            persistedItems.removeValue(forKey: itemId)
        }
        persistedSections.removeAll { insertedSectionIds.contains($0.id) }

        // Fetch 会忽略待删除对象；把它们也带入重建清单，rollback 后复用原对象，
        // 从而既不会重复插入同一 UUID，也不会为同一天重复创建 DaySection。
        for item in modelContext.deletedModelsArray.compactMap({ $0 as? TodoItem })
        where insertedItemIds.contains(item.id) == false {
            persistedItems[item.id] = item
        }
        persistedSections.append(
            contentsOf: modelContext.deletedModelsArray.compactMap { section in
                guard let section = section as? DaySection,
                      insertedSectionIds.contains(section.id) == false
                else {
                    return nil
                }
                return section
            }
        )

        // 先确认可以拿到重建所需的已确认对象，再回到已确认状态。这样读取失败时，
        // 用户眼前的内存修改完全不受影响；rollback 后也不再有任何可能失败的读取步骤。
        modelContext.rollback()

        var rebuiltItems: [UUID: TodoItem] = [:]
        for snapshot in desiredSnapshots.values {
            let item: TodoItem
            if let persistedItem = persistedItems[snapshot.id] {
                persistedItem.title = snapshot.title
                persistedItem.isCompleted = snapshot.isCompleted
                persistedItem.indentLevel = snapshot.indentLevel
                persistedItem.sortOrder = snapshot.sortOrder
                persistedItem.containerKindRaw = snapshot.containerKindRaw
                persistedItem.dayDate = snapshot.dayDate
                persistedItem.updatedAt = .now
                item = persistedItem
            } else {
                item = TodoItem(
                    id: snapshot.id,
                    title: snapshot.title,
                    isCompleted: snapshot.isCompleted,
                    indentLevel: snapshot.indentLevel,
                    sortOrder: snapshot.sortOrder,
                    containerKindRaw: snapshot.containerKindRaw,
                    dayDate: snapshot.dayDate,
                    createdAt: snapshot.createdAt,
                    updatedAt: .now
                )
                modelContext.insert(item)
            }
            rebuiltItems[item.id] = item
        }

        for item in persistedItems.values where desiredSnapshots[item.id] == nil {
            modelContext.delete(item)
        }

        let scheduledDates = Set(rebuiltItems.values.compactMap { item -> Date? in
            guard item.containerKind == .scheduled else { return nil }
            return Calendar.current.startOfDay(for: item.dayDate)
        })
        var rebuiltSections: [UUID: DaySection] = [:]
        var sectionDates = Set<Date>()
        for section in persistedSections {
            let date = Calendar.current.startOfDay(for: section.date)
            if scheduledDates.contains(date) {
                rebuiltSections[section.id] = section
                sectionDates.insert(date)
            } else {
                modelContext.delete(section)
            }
        }
        for date in scheduledDates where sectionDates.contains(date) == false {
            let section = DaySection(date: date, sortOrder: Double(Date().timeIntervalSince1970))
            rebuiltSections[section.id] = section
            modelContext.insert(section)
        }

        todoItemsCache = rebuiltItems
        daySectionsCache = rebuiltSections
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

        let transitions = block.range.compactMap { index -> TodoItemTransition? in
            let blockItem = allItems[index]
            guard blockItem.isCompleted != newState else { return nil }
            let before = TodoItemSnapshot(from: blockItem)
            return TodoItemTransition(before: before, after: before.replacing(isCompleted: newState))
        }
        undoManager.perform(
            TodoOperationUnit(actionName: "勾选", itemTransitions: transitions),
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
        let transitions = allItems.compactMap { candidate -> TodoItemTransition? in
            guard coveredIds.contains(candidate.id), candidate.isCompleted != isCompleted else {
                return nil
            }
            let before = TodoItemSnapshot(from: candidate)
            return TodoItemTransition(before: before, after: before.replacing(isCompleted: isCompleted))
        }
        guard transitions.isEmpty == false else { return }
        undoManager.perform(
            TodoOperationUnit(actionName: "勾选", itemTransitions: transitions),
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
        let selectionTransitions: [TodoSelectionTransition] = selectionManager.map { manager in
            let state = TodoSelectionState(selectionManager: manager)
            return [TodoSelectionTransition(selectionManager: manager, before: state, after: state)]
        } ?? []
        undoManager.perform(
            TodoOperationUnit(
                actionName: appliedDelta > 0 ? "缩进" : "反缩进",
                itemTransitions: zip(oldSnapshots, newSnapshots).map {
                    TodoItemTransition(before: $0.0, after: $0.1)
                },
                selectionTransitions: selectionTransitions
            ),
            store: self
        )
    }

}
