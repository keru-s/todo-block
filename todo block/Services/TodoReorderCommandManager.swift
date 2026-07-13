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
        guard selectedItems.isEmpty == false, selectedItems.count == selectedIds.count else {
            return false
        }

        let originalFocusedItemId = selectionManager.focusedItemId
        let selectionBefore = TodoSelectionState(selectionManager: selectionManager)
        let selectedByDestination = Dictionary(grouping: selectedItems) {
            store.destination(for: $0).normalized
        }
        var rootsByDestination: [(TodoDropDestination, [UUID])] = []
        var beforeSnapshotsById: [UUID: TodoItemSnapshot] = [:]

        for (destination, destinationSelection) in selectedByDestination {
            let currentItems = store.items(in: destination)
            let rootIds = TodoHierarchyBlockEngine.blockRootIds(
                selectedFrom: Set(destinationSelection.map(\.id)),
                in: currentItems
            )
            guard rootIds.isEmpty == false else { return false }
            guard rootIds.allSatisfy({ rootId in
                TodoKeyboardReorderEngine.movementPlan(
                    itemId: rootId,
                    direction: direction,
                    items: currentItems
                ) != nil
            }) else {
                return false
            }
            rootsByDestination.append((destination, rootIds))
            for item in currentItems {
                beforeSnapshotsById[item.id] = TodoItemSnapshot(from: item)
            }
        }

        let didMoveAllBlocks = store.undoManager.performWithoutRecording {
            for (destination, rootIds) in rootsByDestination {
                let moveOrder = direction == .up ? rootIds : Array(rootIds.reversed())
                for rootId in moveOrder {
                    guard TodoKeyboardReorderEngine.move(
                        itemId: rootId,
                        direction: direction,
                        items: store.items(in: destination),
                        destination: destination,
                        store: store,
                        selectionManager: selectionManager
                    ) else {
                        return false
                    }
                }
            }
            return true
        }
        guard didMoveAllBlocks else {
            _ = store.applyExistingItemSnapshots(Array(beforeSnapshotsById.values))
            selectionBefore.apply(to: selectionManager)
            return false
        }

        selectionManager.selectedItemIds = selectedIds
        selectionManager.focusedItemId = originalFocusedItemId
        selectionManager.lastSelectedId = originalFocusedItemId

        let stateChanges = beforeSnapshotsById.values.compactMap { before -> TodoItemStateChange? in
            guard
                let item = store.todoItemsCache[before.id],
                before.matchesUserState(of: item) == false
            else { return nil }
            return TodoItemStateChange(before: before, after: TodoItemSnapshot(from: item))
        }
        let selectionAfter = TodoSelectionState(selectionManager: selectionManager)
        let operation = TodoOperation(
            actionName: "移动",
            itemStateChanges: stateChanges,
            selectionChanges: [
                TodoSelectionChange(
                    selectionManager: selectionManager,
                    before: selectionBefore,
                    after: selectionAfter
                )
            ]
        )
        guard store.undoManager.recordApplied(operation, store: store) else {
            _ = store.applyExistingItemSnapshots(Array(beforeSnapshotsById.values))
            selectionBefore.apply(to: selectionManager)
            return false
        }

        return true
    }
}
