import Foundation

enum TodoReorderMoveEngine {
    static func performMove(
        draggedId: UUID,
        toIndex: Int,
        indentLevel: Int,
        items: [TodoItem],
        destination: TodoDropDestination,
        store: TodoStore
    ) {
        guard let draggedItem = store.todoItemsCache[draggedId] else { return }

        let normalizedToIndex = min(max(toIndex, 0), items.count)
        var remainingItems = items
        var movingItemIds = Set<UUID>()
        let normalizedDestination = destination.normalized

        if store.destination(for: draggedItem) == normalizedDestination,
            let draggedIndex = items.firstIndex(where: { $0.id == draggedId }),
            let movingBlock = TodoHierarchyBlockEngine.block(
                startingAt: draggedIndex,
                in: items
            )
        {
            if normalizedToIndex >= movingBlock.range.lowerBound,
               normalizedToIndex <= movingBlock.range.upperBound {
                return
            }
            movingItemIds = Set(movingBlock.itemIds)
            remainingItems.removeAll { movingItemIds.contains($0.id) }
        }

        let removedBeforeInsert = items.prefix(normalizedToIndex).reduce(into: 0) { count, item in
            if movingItemIds.contains(item.id) {
                count += 1
            }
        }

        let adjustedInsertIndex = min(
            max(0, normalizedToIndex - removedBeforeInsert),
            remainingItems.count
        )
        let afterItem = adjustedInsertIndex > 0 ? remainingItems[adjustedInsertIndex - 1] : nil

        var clampedIndentLevel = min(max(indentLevel, 0), TodoItem.maxIndentLevel)
        if let afterItem {
            clampedIndentLevel = min(clampedIndentLevel, afterItem.indentLevel + 1)
        } else {
            clampedIndentLevel = 0
        }

        store.moveItemWithChildren(
            draggedItem,
            to: normalizedDestination,
            afterItem: afterItem,
            newIndentLevel: clampedIndentLevel
        )
    }
}
