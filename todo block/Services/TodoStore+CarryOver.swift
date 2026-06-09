//
//  TodoStore+CarryOver.swift
//  todo block
//

import Foundation

extension TodoStore {
    /// 查找最近一个日期在今天之前的 DaySection（不一定是严格的"昨天"）。
    func findPreviousDaySection() -> DaySection? {
        let today = Calendar.current.startOfDay(for: Date())
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

        let blocks = parseItemBlocks(previousItems)
        let incompleteBlocks = blocks.filter { !$0.parent.isCompleted }
        guard !incompleteBlocks.isEmpty else { return todaySection }

        let existingTodayItems = items(for: todayDate)
        var currentSortOrder = (existingTodayItems.last?.sortOrder ?? 0) + 1000

        var moveOldSnapshots: [TodoItemSnapshot] = []
        var moveNewSnapshots: [TodoItemSnapshot] = []

        for block in incompleteBlocks {
            let hasCompletedChildren = block.children.contains { $0.isCompleted }

            if !hasCompletedChildren {
                // 无已完成子项：整块直接移动
                let allItems = [block.parent] + block.children
                for item in allItems {
                    let oldSnapshot = TodoItemSnapshot(from: item)
                    moveOldSnapshots.append(oldSnapshot)

                    item.dayDate = todayDate
                    item.sortOrder = currentSortOrder
                    item.updatedAt = Date()
                    currentSortOrder += 1000

                    let newSnapshot = TodoItemSnapshot(from: item)
                    moveNewSnapshots.append(newSnapshot)
                }
            } else {
                // 有已完成子项：复制一级 item，仅移动未完成子项
                let copiedParent = createItem(
                    title: block.parent.title,
                    dayDate: todayDate,
                    indentLevel: 0,
                    containerKind: .scheduled
                )
                copiedParent.sortOrder = currentSortOrder
                currentSortOrder += 1000

                for child in block.children where !child.isCompleted {
                    let oldSnapshot = TodoItemSnapshot(from: child)
                    moveOldSnapshots.append(oldSnapshot)

                    child.dayDate = todayDate
                    child.sortOrder = currentSortOrder
                    child.updatedAt = Date()
                    currentSortOrder += 1000

                    let newSnapshot = TodoItemSnapshot(from: child)
                    moveNewSnapshots.append(newSnapshot)
                }
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

    /// 将 items 解析为 block 结构：每个 block = 一个 indent-0 item + 紧随其后的所有 indent > 0 item。
    private func parseItemBlocks(_ items: [TodoItem]) -> [(parent: TodoItem, children: [TodoItem])] {
        var blocks: [(parent: TodoItem, children: [TodoItem])] = []
        var currentParent: TodoItem?
        var currentChildren: [TodoItem] = []

        for item in items {
            if item.indentLevel == 0 {
                if let parent = currentParent {
                    blocks.append((parent, currentChildren))
                }
                currentParent = item
                currentChildren = []
            } else {
                currentChildren.append(item)
            }
        }
        if let parent = currentParent {
            blocks.append((parent, currentChildren))
        }

        return blocks
    }
}
