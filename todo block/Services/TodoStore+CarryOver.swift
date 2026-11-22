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

    /// 结转未完成项。两边各自保留子项所需的父项，避免拆组后改变归属。
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

        let todayDate = Calendar.current.startOfDay(for: .now)
        var currentSortOrder = (items(for: todayDate).last?.sortOrder ?? 0) + 1000
        var transitions: [TodoItemTransition] = []

        for block in TodoHierarchyBlockEngine.topLevelBlocks(in: previousItems) {
            let items = Array(previousItems[block.range])
            let levels = TodoHierarchyBlockEngine.normalizedIndentLevels(in: items)
            var ancestors: [Int] = []
            let parents = levels.enumerated().map { index, level -> Int? in
                ancestors.removeLast(ancestors.count - level)
                let parent = ancestors.last
                ancestors.append(index)
                return parent
            }
            var stays = items.map(\.isCompleted)
            var carried = stays.map { !$0 }
            for index in items.indices.reversed() {
                guard let parent = parents[index] else { continue }
                stays[parent] = stays[parent] || stays[index]
                carried[parent] = carried[parent] || carried[index]
            }

            for index in items.indices where carried[index] {
                let item = items[index]
                let before = TodoItemSnapshot(from: item)
                let after: TodoItemSnapshot
                if stays[index] {
                    after = TodoItemSnapshot(
                        title: item.title,
                        isCompleted: item.isCompleted,
                        indentLevel: levels[index],
                        sortOrder: currentSortOrder,
                        containerKindRaw: TodoContainerKind.scheduled.rawValue,
                        dayDate: todayDate
                    )
                } else {
                    after = before.replacing(
                        indentLevel: levels[index],
                        sortOrder: currentSortOrder,
                        containerKindRaw: TodoContainerKind.scheduled.rawValue,
                        dayDate: todayDate
                    )
                }
                transitions.append(TodoItemTransition(before: stays[index] ? nil : before, after: after))
                currentSortOrder += 1000
            }
        }

        guard !transitions.isEmpty else { return nil }
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
