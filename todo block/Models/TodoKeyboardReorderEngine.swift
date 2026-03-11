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

        let movingIds = movingBlockIds(startingAt: currentIndex, items: items)
        let targetInsertIndex: Int

        switch direction {
        case .up:
            guard currentIndex > 0 else { return nil }
            targetInsertIndex = currentIndex - 1
        case .down:
            let currentBlockEnd = blockEnd(startingAt: currentIndex, items: items)
            let nextBlockStart = currentBlockEnd + 1
            guard nextBlockStart < items.count else { return nil }
            targetInsertIndex = downwardInsertIndex(
                currentIndex: currentIndex,
                nextBlockStart: nextBlockStart,
                items: items
            )
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
            indentLevel: items[currentIndex].indentLevel
        )
    }

    private static func movingBlockIds(startingAt startIndex: Int, items: [TodoItem]) -> Set<UUID> {
        let endIndex = blockEnd(startingAt: startIndex, items: items)
        return Set(items[startIndex...endIndex].map(\.id))
    }

    private static func downwardInsertIndex(
        currentIndex: Int,
        nextBlockStart: Int,
        items: [TodoItem]
    ) -> Int {
        let currentIndentLevel = items[currentIndex].indentLevel
        let nextItemIndentLevel = items[nextBlockStart].indentLevel

        if currentIndentLevel > nextItemIndentLevel {
            return nextBlockStart + 1
        }

        return blockEnd(startingAt: nextBlockStart, items: items) + 1
    }

    private static func blockEnd(startingAt startIndex: Int, items: [TodoItem]) -> Int {
        let baseIndent = items[startIndex].indentLevel
        var endIndex = startIndex

        for index in (startIndex + 1)..<items.count {
            if items[index].indentLevel > baseIndent {
                endIndex = index
            } else {
                break
            }
        }

        return endIndex
    }
}
