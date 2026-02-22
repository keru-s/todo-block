//
//  MenuBarManualReorderEngine.swift
//  todo block
//
//  Created by Codex on 2026/2/22.
//

import CoreGraphics
import Foundation

enum MenuBarManualReorderEngine {
    static func dropState(
        for location: CGPoint,
        items: [TodoItem],
        itemFrames: [UUID: CGRect],
        itemHeight: CGFloat,
        indentWidth: CGFloat
    ) -> TodoListDropState {
        if items.isEmpty {
            return .insertAt(index: 0, indentLevel: 0)
        }

        let y = location.y
        let x = location.x
        let availableFrames = items.compactMap { itemFrames[$0.id] }
        if let minY = availableFrames.map({ $0.minY }).min(),
            let maxY = availableFrames.map({ $0.maxY }).max(),
            (y < minY - itemHeight || y > maxY + itemHeight)
        {
            return .none
        }

        var insertIndex = items.count
        let hasCompleteFrames = items.allSatisfy { itemFrames[$0.id] != nil }

        if hasCompleteFrames {
            for (index, item) in items.enumerated() {
                guard let frame = itemFrames[item.id] else { continue }
                if y < frame.midY {
                    insertIndex = index
                    break
                }
            }
        } else {
            var accumulatedHeight: CGFloat = 0
            for (index, item) in items.enumerated() {
                let estimatedHeight = estimatedItemHeight(for: item, defaultHeight: itemHeight)
                if y < accumulatedHeight + estimatedHeight / 2 {
                    insertIndex = index
                    break
                }
                accumulatedHeight += estimatedHeight
            }
        }

        let relativeX = max(0, x)
        var indentLevel = Int(relativeX / indentWidth)

        if insertIndex > 0 {
            indentLevel = min(indentLevel, items[insertIndex - 1].indentLevel + 1)
        } else {
            indentLevel = 0
        }

        indentLevel = min(indentLevel, TodoItem.maxIndentLevel)
        return .insertAt(index: insertIndex, indentLevel: indentLevel)
    }

    static func performMove(
        draggedId: UUID,
        dropState: TodoListDropState,
        items: [TodoItem],
        destination: TodoDropDestination,
        store: TodoStore
    ) {
        guard case .insertAt(let toIndex, let indentLevel) = dropState else { return }
        TodoReorderMoveEngine.performMove(
            draggedId: draggedId,
            toIndex: toIndex,
            indentLevel: indentLevel,
            items: items,
            destination: destination,
            store: store
        )
    }

    private static func estimatedItemHeight(for item: TodoItem, defaultHeight: CGFloat) -> CGFloat {
        let explicitLineCount = max(1, item.title.components(separatedBy: "\n").count)
        let multiLineHeight = CGFloat(explicitLineCount) * 20 + 8
        return max(defaultHeight, multiLineHeight)
    }
}
