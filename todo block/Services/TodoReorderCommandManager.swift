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
        var selectedIds = selectionManager.selectedItemIds
        if selectedIds.isEmpty, let focusedItemId = selectionManager.focusedItemId {
            selectedIds = [focusedItemId]
        }
        let selectedItems = selectedIds.compactMap { store.todoItemsCache[$0] }
        guard selectedItems.isEmpty == false else { return false }

        let originalFocusedItemId = selectionManager.focusedItemId
        var didMoveAnyBlock = false
        let selectedByDestination = Dictionary(grouping: selectedItems) {
            store.destination(for: $0).normalized
        }

        for (destination, destinationSelection) in selectedByDestination {
            let currentItems = store.items(in: destination)
            let rootIds = TodoHierarchyBlockEngine.blockRootIds(
                selectedFrom: Set(destinationSelection.map(\.id)),
                in: currentItems
            )
            let moveOrder = direction == .up ? rootIds : Array(rootIds.reversed())
            for rootId in moveOrder {
                let didMove = TodoKeyboardReorderEngine.move(
                    itemId: rootId,
                    direction: direction,
                    items: store.items(in: destination),
                    destination: destination,
                    store: store
                )
                didMoveAnyBlock = didMoveAnyBlock || didMove
            }
        }

        if didMoveAnyBlock {
            selectionManager.selectedItemIds = selectedIds
            selectionManager.focusedItemId = originalFocusedItemId
            selectionManager.lastSelectedId = originalFocusedItemId
            store.requestFocus(originalFocusedItemId)
        }

        return didMoveAnyBlock
    }
}
