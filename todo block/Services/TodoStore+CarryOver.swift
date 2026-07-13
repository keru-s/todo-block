//
//  TodoStore+CarryOver.swift
//  todo block
//

import Foundation

extension TodoStore {
    /// 查找最近一个日期在今天之前的 DaySection（不一定是严格的"昨天"）。
    func findPreviousDaySection() -> DaySection? {
        let today = Calendar.current.startOfDay(for: .now)
        return validDaySections
            .filter { $0.date < today }
            .max(by: { $0.date < $1.date })
    }

    /// 将前一天未完成的 item 继承到今天。
    /// - 子项全部未完成（或无子项）：整块直接移动到今天
    /// - 子项中有已完成的：复制一级 item，移动未完成子项，已完成子项留原位
    @discardableResult
    func carryOverIncompleteItems() -> DaySection {
        guard let previousSection = findPreviousDaySection() else {
            return getOrCreateTodaySection()
        }

        let todaySection = getOrCreateTodaySection()
        let todayDate = todaySection.date

        let previousItems = items(for: previousSection.date)
        guard !previousItems.isEmpty else { return todaySection }

        let blocks = TodoHierarchyBlockEngine.topLevelBlocks(in: previousItems)
        let incompleteBlocks = blocks.filter { block in
            previousItems[block.range.lowerBound].isCompleted == false
        }
        guard !incompleteBlocks.isEmpty else { return todaySection }

        let existingTodayItems = items(for: todayDate)
        var currentSortOrder = (existingTodayItems.last?.sortOrder ?? 0) + 1000

        var moveOldSnapshots: [TodoItemSnapshot] = []
        var moveNewSnapshots: [TodoItemSnapshot] = []

        for block in incompleteBlocks {
            let blockItems = Array(previousItems[block.range])
            guard let parent = blockItems.first else { continue }
            let descendants = Array(blockItems.dropFirst())
            let hasCompletedDescendants = descendants.contains { $0.isCompleted }
            let itemsToMove: [TodoItem]
            let normalizedIndentLevels: [Int]

            if !hasCompletedDescendants {
                itemsToMove = blockItems
                normalizedIndentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(
                    in: itemsToMove)
            } else {
                let copiedParent = createItem(
                    title: parent.title,
                    dayDate: todayDate,
                    indentLevel: 0,
                    containerKind: .scheduled
                )
                copiedParent.sortOrder = currentSortOrder
                currentSortOrder += 1000

                itemsToMove = descendants.filter { !$0.isCompleted }
                normalizedIndentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(
                    itemsToMove.map(\.indentLevel),
                    baseIndentLevel: 1
                )
            }

            for (item, indentLevel) in zip(itemsToMove, normalizedIndentLevels) {
                let oldSnapshot = TodoItemSnapshot(from: item)
                moveOldSnapshots.append(oldSnapshot)

                item.dayDate = todayDate
                item.indentLevel = indentLevel
                item.sortOrder = currentSortOrder
                item.updatedAt = .now
                currentSortOrder += 1000

                let newSnapshot = TodoItemSnapshot(from: item)
                moveNewSnapshots.append(newSnapshot)
            }
        }

        if !moveOldSnapshots.isEmpty {
            undoManager.registerMoveItems(
                from: moveOldSnapshots, to: moveNewSnapshots, store: self)
        }

        cleanupSectionIfEmpty(scheduledDate: previousSection.date)
        refreshTrigger += 1
        scheduleSave()

        undoManager.nsUndoManager.setActionName("继承昨日待办")

        return todaySection
    }
}
