//
//  TodoKeyboardReorderEngine.swift
//  todo block
//
//  Created by Codex on 2026/3/11.
//

import Foundation

enum TodoKeyboardReorderDirection {
    case up
    case down
}

struct TodoKeyboardReorderPlan: Equatable {
    let afterItemId: UUID?
    let indentLevel: Int
}

enum TodoKeyboardReorderEngine {
    static func canMove(
        itemId: UUID,
        direction: TodoKeyboardReorderDirection,
        items: [TodoItem]
    ) -> Bool {
        movementPlan(itemId: itemId, direction: direction, items: items) != nil
    }

    @discardableResult
    static func move(
        itemId: UUID,
        direction: TodoKeyboardReorderDirection,
        items: [TodoItem],
        destination: TodoDropDestination,
        store: TodoStore
    ) -> Bool {
        guard
            let item = store.todoItemsCache[itemId],
            let plan = movementPlan(itemId: itemId, direction: direction, items: items)
        else {
            return false
        }

        let afterItem = plan.afterItemId.flatMap { store.todoItemsCache[$0] }
        store.moveItemWithChildren(
            item,
            to: destination,
            afterItem: afterItem,
            newIndentLevel: plan.indentLevel
        )
        store.requestFocus(itemId)
        return true
    }

    static func movementPlan(
        itemId: UUID,
        direction: TodoKeyboardReorderDirection,
        items: [TodoItem]
    ) -> TodoKeyboardReorderPlan? {
        guard let currentIndex = items.firstIndex(where: { $0.id == itemId }) else {
            return nil
        }

        guard let movingBlock = TodoHierarchyBlockEngine.block(
            startingAt: currentIndex,
            in: items
        ) else {
            return nil
        }
        let movingIds = Set(movingBlock.itemIds)
        let targetInsertIndex: Int

        switch direction {
        case .up:
            guard let precedingBlockStart = TodoHierarchyBlockEngine.precedingBlockStart(
                before: movingBlock,
                in: items
            ) else { return nil }
            targetInsertIndex = precedingBlockStart
        case .down:
            guard let followingInsertionIndex = TodoHierarchyBlockEngine.followingInsertionIndex(
                after: movingBlock,
                in: items
            ) else { return nil }
            targetInsertIndex = followingInsertionIndex
        }

        let remainingItems = items.filter { movingIds.contains($0.id) == false }
        let removedBeforeInsert = items.prefix(targetInsertIndex).reduce(into: 0) { count, item in
            if movingIds.contains(item.id) {
                count += 1
            }
        }
        let adjustedInsertIndex = min(
            max(0, targetInsertIndex - removedBeforeInsert),
            remainingItems.count
        )
        let afterItemId =
            adjustedInsertIndex > 0 ? remainingItems[adjustedInsertIndex - 1].id : nil

        return TodoKeyboardReorderPlan(
            afterItemId: afterItemId,
            indentLevel: movingBlock.rootIndentLevel
        )
    }
}
