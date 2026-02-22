//
//  TodoReorderMoveEngine.swift
//  todo block
//
//  Created by Codex on 2026/2/22.
//

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
            let draggedIndex = items.firstIndex(where: { $0.id == draggedId })
        {
            let baseIndent = items[draggedIndex].indentLevel
            movingItemIds.insert(draggedId)

            var nextIndex = draggedIndex + 1
            while nextIndex < items.count {
                let candidate = items[nextIndex]
                if candidate.indentLevel > baseIndent {
                    movingItemIds.insert(candidate.id)
                    nextIndex += 1
                } else {
                    break
                }
            }

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
