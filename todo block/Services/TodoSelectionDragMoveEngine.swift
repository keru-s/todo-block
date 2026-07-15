//
//  TodoSelectionDragMoveEngine.swift
//  todo block
//

import Foundation

struct TodoSelectionDragMoveRequest {
    let draggedId: UUID
    let destination: TodoDropDestination
    let insertionIndex: Int
    let indentLevel: Int
}

@MainActor
enum TodoSelectionDragMoveEngine {
    @discardableResult
    static func performMove(
        _ request: TodoSelectionDragMoveRequest,
        store: TodoStore,
        selectionManager: SelectionManager
    ) -> Bool {
        guard let draggedItem = store.todoItemsCache[request.draggedId] else { return false }

        let sourceDestination = store.destination(for: draggedItem).normalized
        let sourceItems = store.items(in: sourceDestination)
        let sourceIds = Set(sourceItems.map(\.id))
        let selectedItemIds = selectionManager.selectedItemIds
        guard selectedItemIds.count > 1 else { return false }
        guard selectedItemIds.isSubset(of: sourceIds) else { return false }
        let selectedSourceIds = selectedItemIds.intersection(sourceIds)
        guard selectedSourceIds.contains(request.draggedId) else { return false }

        let rootIds = TodoHierarchyBlockEngine.blockRootIds(
            selectedFrom: selectedSourceIds,
            in: sourceItems
        )
        let movingIds = Set(
            TodoHierarchyBlockEngine.itemIdsCoveredByBlocks(
                rootedAt: Set(rootIds),
                in: sourceItems
            )
        )
        let movingItems = sourceItems.filter { movingIds.contains($0.id) }
        guard movingItems.count > 1 else { return false }

        let normalizedDestination = request.destination.normalized
        let destinationItems = store.items(in: normalizedDestination)
        let normalizedToIndex = min(max(request.insertionIndex, 0), destinationItems.count)
        if sourceDestination == normalizedDestination,
           let range = sourceItems.indices.filter({ movingIds.contains(sourceItems[$0].id) }).min()
                .flatMap({ firstIndex in
                    sourceItems.indices.filter { movingIds.contains(sourceItems[$0].id) }.max()
                        .map { firstIndex...$0 }
                }),
           range.contains(normalizedToIndex)
        {
            return false
        }

        let targetItems = destinationItems.filter { movingIds.contains($0.id) == false }
        let removedBeforeInsert = destinationItems.prefix(normalizedToIndex).reduce(into: 0) { count, item in
            if movingIds.contains(item.id) {
                count += 1
            }
        }
        let adjustedInsertIndex = min(
            max(0, normalizedToIndex - removedBeforeInsert),
            targetItems.count
        )
        let afterItem = adjustedInsertIndex > 0 ? targetItems[adjustedInsertIndex - 1] : nil

        guard let draggedIndex = sourceItems.firstIndex(where: { $0.id == request.draggedId }) else {
            return false
        }
        let normalizedIndentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(in: sourceItems)
        let draggedIndent = normalizedIndentLevels[draggedIndex]
        let clampedIndent = min(
            max(request.indentLevel, 0),
            afterItem.map { min(TodoItem.maxIndentLevel, $0.indentLevel + 1) } ?? 0
        )
        let indentDelta = clampedIndent - draggedIndent
        let snapshots = movingItems.map(TodoItemSnapshot.init)

        let movedSnapshots = TodoHierarchyBlockEngine.movedSnapshots(
            snapshots,
            sourceItems: sourceItems,
            sourceIndices: movingItems.compactMap { movingItem in
                sourceItems.firstIndex { $0.id == movingItem.id }
            },
            destination: normalizedDestination,
            afterItem: afterItem,
            targetItems: targetItems,
            indentDelta: indentDelta
        )
        guard movedSnapshots.count == snapshots.count else { return false }

        let selectionState = TodoSelectionState(selectionManager: selectionManager)
        return store.undoManager.perform(
            TodoOperation(
                actionName: "移动",
                itemStateChanges: zip(snapshots, movedSnapshots).map {
                    TodoItemStateChange(before: $0.0, after: $0.1)
                },
                selectionChanges: [
                    TodoSelectionChange(
                        selectionManager: selectionManager,
                        before: selectionState,
                        after: selectionState
                    )
                ]
            ),
            store: store
        )
    }
}
