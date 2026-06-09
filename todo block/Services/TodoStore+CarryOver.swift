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
    /// - 未完成的一级 item：复制到今天（原件留在昨天）
    /// - 未完成的子级 item：移动到今天新复制的一级 item 下
    /// - 已完成的子级 item：留在昨天原位不动
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
