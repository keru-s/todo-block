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
        TodoDropLocationEngine.dropState(
            for: location,
            items: items,
            itemFrames: itemFrames,
            itemHeight: itemHeight,
            indentWidth: indentWidth,
            baseX: 0,
            constrainsToVerticalRange: true,
            verticalSlack: itemHeight
        )
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

}
