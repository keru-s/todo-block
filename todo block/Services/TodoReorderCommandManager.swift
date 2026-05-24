//
//  TodoReorderCommandManager.swift
//  todo block
//
//  Created by Codex on 2026/3/11.
//

import Foundation
import Observation

@MainActor
@Observable
final class TodoReorderCommandManager {
    static let shared = TodoReorderCommandManager()

    private var moveUpHandler: (() -> Bool)?
    private var moveDownHandler: (() -> Bool)?

    private init() {}

    func activateListContext(store: TodoStore, selectionManager: SelectionManager) {
        moveUpHandler = { [weak selectionManager] in
            guard let selectionManager else { return false }
            return Self.moveSelection(
                direction: .up,
                store: store,
                selectionManager: selectionManager
            )
        }
        moveDownHandler = { [weak selectionManager] in
            guard let selectionManager else { return false }
            return Self.moveSelection(
                direction: .down,
                store: store,
                selectionManager: selectionManager
            )
        }
    }

    func clearContext() {
        moveUpHandler = nil
        moveDownHandler = nil
    }

    @discardableResult
    func moveSelectionUp() -> Bool {
        moveUpHandler?() ?? false
    }

    @discardableResult
    func moveSelectionDown() -> Bool {
        moveDownHandler?() ?? false
    }

    private static func moveSelection(
        direction: TodoKeyboardReorderDirection,
        store: TodoStore,
        selectionManager: SelectionManager
    ) -> Bool {
        guard
            let itemId = activeItemId(in: selectionManager),
            let item = store.todoItemsCache[itemId]
        else {
            return false
        }

        let destination = store.destination(for: item)
        let items = store.items(in: destination)
        let didMove = TodoKeyboardReorderEngine.move(
            itemId: itemId,
            direction: direction,
            items: items,
            destination: destination,
            store: store
        )

        if didMove {
            selectionManager.restoreFocus(to: itemId)
        }

        return didMove
    }

    private static func activeItemId(in selectionManager: SelectionManager) -> UUID? {
        if let focusedItemId = selectionManager.focusedItemId {
            return focusedItemId
        }

        if selectionManager.selectedItemIds.count == 1 {
            return selectionManager.selectedItemIds.first
        }

        return nil
    }
}
