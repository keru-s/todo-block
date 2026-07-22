//
//  TodoStore+CarryOver.swift
//  todo block
//

import Foundation

enum TodoCarryOverTrigger: Equatable {
    case automatic
    case userInitiated
}

extension TodoStore {
    /// 查找最近一个日期在今天之前的 DaySection（不一定是严格的“昨天”）。
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
    func carryOverIncompleteItems(
        trigger: TodoCarryOverTrigger = .userInitiated
    ) -> DaySection? {
        if trigger == .automatic, canRedo {
            return nil
        }
        guard let previousSection = findPreviousDaySection() else { return nil }

        let previousItems = items(for: previousSection.date)
        guard previousItems.isEmpty == false else { return nil }

        let blocks = TodoHierarchyBlockEngine.topLevelBlocks(in: previousItems)
        let incompleteBlocks = blocks.filter { block in
            previousItems[block.range.lowerBound].isCompleted == false
        }
        guard incompleteBlocks.isEmpty == false else { return nil }

        let todayDate = Calendar.current.startOfDay(for: .now)
        var currentSortOrder = (items(for: todayDate).last?.sortOrder ?? 0) + 1000
        var transitions: [TodoItemTransition] = []

        for block in incompleteBlocks {
            let blockItems = Array(previousItems[block.range])
            guard let parent = blockItems.first else { continue }
            let descendants = Array(blockItems.dropFirst())
            let hasCompletedDescendants = descendants.contains { $0.isCompleted }
            let itemsToMove: [TodoItem]
            let normalizedIndentLevels: [Int]

            if hasCompletedDescendants == false {
                itemsToMove = blockItems
                normalizedIndentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(
                    in: itemsToMove
                )
            } else {
                let copiedParent = TodoItemSnapshot(
                    title: parent.title,
                    indentLevel: 0,
                    sortOrder: currentSortOrder,
                    containerKindRaw: TodoContainerKind.scheduled.rawValue,
                    dayDate: todayDate
                )
                transitions.append(TodoItemTransition(before: nil, after: copiedParent))
                currentSortOrder += 1000

                itemsToMove = descendants.filter { $0.isCompleted == false }
                normalizedIndentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(
                    itemsToMove.map(\.indentLevel),
                    baseIndentLevel: 1
                )
            }

            for (item, indentLevel) in zip(itemsToMove, normalizedIndentLevels) {
                let before = TodoItemSnapshot(from: item)
                let after = before.replacing(
                    indentLevel: indentLevel,
                    sortOrder: currentSortOrder,
                    containerKindRaw: TodoContainerKind.scheduled.rawValue,
                    dayDate: todayDate
                )
                transitions.append(TodoItemTransition(before: before, after: after))
                currentSortOrder += 1000
            }
        }

        let operation = TodoOperationUnit(
            actionName: "继承昨日待办",
            itemTransitions: transitions,
            attention: .destination(.scheduled(date: todayDate))
        )
        guard undoManager.perform(operation, store: self) else { return nil }

        return daySectionsCache.values.first {
            Calendar.current.isDate($0.date, inSameDayAs: todayDate)
        }
    }
}
