import Foundation

enum TodoCompletionRule {
    private struct CompletionBlock {
        let indices: [Int]
        let wasComplete: Bool
        let isComplete: Bool
    }

    /// 输入为同一列表按当前顺序排列的快照。输出包含勾选及其引发的全部换位。
    static func transitions(
        in items: [TodoItemSnapshot],
        for itemIds: Set<UUID>,
        isCompleted: Bool
    ) -> [TodoItemTransition] {
        let originalOrder = Array(items.indices)
        let indentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(
            items.map(\.indentLevel), baseIndentLevel: 0
        )
        var completion = items.map(\.isCompleted)
        var index = 0

        func siblingBlocks(at level: Int, parentIsSelected: Bool) -> [CompletionBlock] {
            var blocks: [CompletionBlock] = []
            while index < items.count, indentLevels[index] == level {
                let rootIndex = index
                let item = items[rootIndex]
                let isSelected = parentIsSelected || itemIds.contains(item.id)
                if isSelected {
                    completion[rootIndex] = isCompleted
                }

                index += 1
                let children = siblingBlocks(at: level + 1, parentIsSelected: isSelected)
                blocks.append(CompletionBlock(
                    indices: [rootIndex] + children.flatMap(\.indices),
                    wasComplete: item.isCompleted && children.allSatisfy(\.wasComplete),
                    isComplete: completion[rootIndex] && children.allSatisfy(\.isComplete)
                ))
            }

            if isCompleted, blocks.contains(where: { !$0.wasComplete && $0.isComplete }) {
                return blocks.filter { !$0.isComplete } + blocks.filter(\.isComplete)
            }
            return blocks
        }

        let order = siblingBlocks(at: 0, parentIsSelected: false).flatMap(\.indices)
        var sortOrders = items.map(\.sortOrder)
        var reorderedIndentLevels = order.map { items[$0].indentLevel }
        if order != originalOrder {
            // 并列的排序值无法可靠表达换位后的顺序。
            if zip(sortOrders, sortOrders.dropFirst()).contains(where: { $0 >= $1 }) {
                sortOrders = originalOrder.map { Double($0 + 1) * 1000 }
            }
            // 只修正换位后会改变父子关系的旧数据缩进。
            let expectedLevels = order.map { indentLevels[$0] }
            let actualLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(
                reorderedIndentLevels, baseIndentLevel: 0
            )
            for position in order.indices where expectedLevels[position] != actualLevels[position] {
                reorderedIndentLevels[position] = expectedLevels[position]
            }
        }

        return order.enumerated().compactMap { position, originalIndex in
            let before = items[originalIndex]
            let nextCompletion = completion[originalIndex]
            let nextSortOrder = sortOrders[position]
            let nextIndentLevel = reorderedIndentLevels[position]
            guard nextCompletion != before.isCompleted
                || nextSortOrder != before.sortOrder
                || nextIndentLevel != before.indentLevel
            else { return nil }

            return TodoItemTransition(before: before, after: before.replacing(
                isCompleted: nextCompletion, indentLevel: nextIndentLevel, sortOrder: nextSortOrder
            ))
        }
    }
}
