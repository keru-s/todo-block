import Foundation

enum TodoParentChildGroupMoveDirection: Equatable {
    case up
    case down
}

enum TodoParentChildGroupMoveIntent: Equatable {
    case step(itemId: UUID, direction: TodoParentChildGroupMoveDirection)
    case moveSelectedGroups(direction: TodoParentChildGroupMoveDirection)
    case place(
        draggedItemId: UUID,
        destination: TodoDropDestination,
        insertionIndex: Int,
        indentLevel: Int
    )
    case placeInSidebar(
        draggedItemId: UUID,
        destination: SidebarDestination
    )
}

@MainActor
final class TodoParentChildGroupMoveModule {
    private let store: TodoStore
    private let selectionManager: SelectionManager

    init(store: TodoStore, selectionManager: SelectionManager) {
        self.store = store
        self.selectionManager = selectionManager
    }

    func availability(for intent: TodoParentChildGroupMoveIntent) -> TodoListCommandAvailability {
        switch intent {
        case .step(let itemId, let direction):
            guard store.todoItemsCache[itemId] != nil else {
                return .unavailable(.itemNoLongerAvailable)
            }
            return plannedStepMoveStateChanges(itemId: itemId, direction: direction) == nil
                ? .unavailable(nil)
                : .available
        case .moveSelectedGroups(let direction):
            return plannedSelectedGroupStateChanges(direction: direction) == nil
                ? .unavailable(nil)
                : .available
        case .place(let draggedItemId, _, _, _),
             .placeInSidebar(let draggedItemId, _):
            guard store.todoItemsCache[draggedItemId] != nil else {
                return .unavailable(.itemNoLongerAvailable)
            }
            return plannedPlacement(for: intent) == nil ? .unavailable(nil) : .available
        }
    }

    @discardableResult
    func execute(_ intent: TodoParentChildGroupMoveIntent) -> TodoListActionResult {
        switch availability(for: intent) {
        case .unavailable(nil):
            return .noChange
        case .unavailable(let rejection?):
            return .rejected(rejection)
        case .available:
            break
        }

        switch intent {
        case .step(let itemId, let direction):
            return executeStepMove(itemId: itemId, direction: direction)
        case .moveSelectedGroups(let direction):
            return executeSelectedGroupMove(direction: direction)
        case .place, .placeInSidebar:
            return executePlacement(intent)
        }
    }

    private struct PlacementRequest {
        let draggedItemId: UUID
        let destination: TodoDropDestination
        let insertionIndex: Int
        let indentLevel: Int
    }

    private struct PlacementPlan {
        let itemStateChanges: [TodoItemStateChange]
        let selectionAfter: TodoSelectionState
    }

    private enum SelectedPlacementPlan {
        case notEligible
        case eligible(PlacementPlan?)
    }

    private func executeStepMove(
        itemId: UUID,
        direction: TodoParentChildGroupMoveDirection
    ) -> TodoListActionResult {
        guard let item = store.todoItemsCache[itemId] else {
            return .rejected(.itemNoLongerAvailable)
        }
        guard let stateChanges = plannedStepMoveStateChanges(
            itemId: itemId,
            direction: direction
        ) else {
            return .noChange
        }
        let selectionBefore = TodoSelectionState(selectionManager: selectionManager)
        let didMove = store.undoManager.perform(
            TodoOperation(
                actionName: "移动",
                itemStateChanges: stateChanges,
                selectionChanges: [
                    TodoSelectionChange(
                        selectionManager: selectionManager,
                        before: selectionBefore,
                        after: TodoSelectionState(
                            focusing: item.id,
                            cursorPosition: selectionManager.cursorPosition
                        )
                    )
                ]
            ),
            store: store
        )
        return didMove ? .performed : .noChange
    }

    private func plannedStepMoveStateChanges(
        itemId: UUID,
        direction: TodoParentChildGroupMoveDirection
    ) -> [TodoItemStateChange]? {
        guard let item = store.todoItemsCache[itemId] else { return nil }
        return plannedStateChanges(
            direction: direction,
            rootIds: [itemId],
            items: store.items(in: store.destination(for: item))
        )
    }

    private func executeSelectedGroupMove(
        direction: TodoParentChildGroupMoveDirection
    ) -> TodoListActionResult {
        guard let stateChanges = plannedSelectedGroupStateChanges(direction: direction) else {
            return .noChange
        }
        let selection = TodoSelectionState(selectionManager: selectionManager)
        let didMove = store.undoManager.perform(
            TodoOperation(
                actionName: "移动",
                itemStateChanges: stateChanges,
                selectionChanges: [
                    TodoSelectionChange(
                        selectionManager: selectionManager,
                        before: selection,
                        after: selection
                    )
                ]
            ),
            store: store
        )
        return didMove ? .performed : .noChange
    }

    private func executePlacement(
        _ intent: TodoParentChildGroupMoveIntent
    ) -> TodoListActionResult {
        guard let plan = plannedPlacement(for: intent) else {
            return .noChange
        }
        let selectionBefore = TodoSelectionState(selectionManager: selectionManager)
        let didMove = store.undoManager.perform(
            TodoOperation(
                actionName: "移动",
                itemStateChanges: plan.itemStateChanges,
                selectionChanges: [
                    TodoSelectionChange(
                        selectionManager: selectionManager,
                        before: selectionBefore,
                        after: plan.selectionAfter
                    )
                ]
            ),
            store: store
        )
        return didMove ? .performed : .noChange
    }

    private func plannedPlacement(
        for intent: TodoParentChildGroupMoveIntent
    ) -> PlacementPlan? {
        guard let request = placementRequest(for: intent),
              let draggedItem = store.todoItemsCache[request.draggedItemId]
        else {
            return nil
        }

        switch plannedSelectedPlacement(
            draggedItem: draggedItem,
            destination: request.destination,
            insertionIndex: request.insertionIndex,
            indentLevel: request.indentLevel
        ) {
        case .eligible(let plan):
            return plan
        case .notEligible:
            return plannedSinglePlacement(
                draggedItem: draggedItem,
                destination: request.destination,
                insertionIndex: request.insertionIndex,
                indentLevel: request.indentLevel
            )
        }
    }

    private func placementRequest(
        for intent: TodoParentChildGroupMoveIntent
    ) -> PlacementRequest? {
        switch intent {
        case let .place(draggedItemId, destination, insertionIndex, indentLevel):
            return PlacementRequest(
                draggedItemId: draggedItemId,
                destination: destination,
                insertionIndex: insertionIndex,
                indentLevel: indentLevel
            )
        case let .placeInSidebar(draggedItemId, sidebarDestination):
            switch sidebarDestination {
            case .longTerm:
                let destination = TodoDropDestination.longTerm(isUrgent: false)
                return PlacementRequest(
                    draggedItemId: draggedItemId,
                    destination: destination,
                    insertionIndex: 0,
                    indentLevel: 0
                )
            case .month(let year, let month):
                let target = store.tailItemForScheduledMonth(year: year, month: month)
                let destination = TodoDropDestination.scheduled(date: target.date)
                return PlacementRequest(
                    draggedItemId: draggedItemId,
                    destination: destination,
                    insertionIndex: 0,
                    indentLevel: 0
                )
            }
        case .step, .moveSelectedGroups:
            return nil
        }
    }

    private func plannedSelectedPlacement(
        draggedItem: TodoItem,
        destination: TodoDropDestination,
        insertionIndex: Int,
        indentLevel: Int
    ) -> SelectedPlacementPlan {
        let sourceDestination = store.destination(for: draggedItem).normalized
        let sourceItems = store.items(in: sourceDestination)
        let selectedItemIds = selectionManager.selectedItemIds
        let sourceItemIds = Set(sourceItems.map(\.id))
        guard selectedItemIds.count > 1,
              selectedItemIds.isSubset(of: sourceItemIds),
              selectedItemIds.contains(draggedItem.id)
        else {
            return .notEligible
        }

        let rootIds = TodoHierarchyBlockEngine.blockRootIds(
            selectedFrom: selectedItemIds,
            in: sourceItems
        )
        let movingItemIds = Set(
            TodoHierarchyBlockEngine.itemIdsCoveredByBlocks(
                rootedAt: Set(rootIds),
                in: sourceItems
            )
        )
        let movingItems = sourceItems.filter { movingItemIds.contains($0.id) }
        guard movingItems.count > 1 else {
            return .notEligible
        }

        let normalizedDestination = destination.normalized
        let destinationItems = store.items(in: normalizedDestination)
        let normalizedInsertionIndex = min(max(insertionIndex, 0), destinationItems.count)
        if sourceDestination == normalizedDestination,
           let firstIndex = sourceItems.indices.first(where: { movingItemIds.contains(sourceItems[$0].id) }),
           let lastIndex = sourceItems.indices.last(where: { movingItemIds.contains(sourceItems[$0].id) }),
           normalizedInsertionIndex > firstIndex,
           normalizedInsertionIndex <= lastIndex
        {
            return .eligible(nil)
        }

        guard let draggedIndex = sourceItems.firstIndex(where: { $0.id == draggedItem.id }) else {
            return .eligible(nil)
        }
        let snapshots = movingItems.map(TodoItemSnapshot.init)
        guard let movedSnapshots = plannedMovedSnapshots(
            snapshots: snapshots,
            sourceItems: sourceItems,
            movingItemIds: movingItemIds,
            destination: normalizedDestination,
            insertionIndex: normalizedInsertionIndex,
            indentLevel: indentLevel,
            draggedIndex: draggedIndex,
            sourceIndices: movingItems.compactMap { movingItem in
                sourceItems.firstIndex { $0.id == movingItem.id }
            }
        ) else {
            return .eligible(nil)
        }
        return .eligible(
            placementPlan(
                before: snapshots,
                after: movedSnapshots,
                selectionAfter: TodoSelectionState(selectionManager: selectionManager)
            )
        )
    }

    private func plannedSinglePlacement(
        draggedItem: TodoItem,
        destination: TodoDropDestination,
        insertionIndex: Int,
        indentLevel: Int
    ) -> PlacementPlan? {
        let sourceDestination = store.destination(for: draggedItem).normalized
        let sourceItems = store.items(in: sourceDestination)
        guard let draggedIndex = sourceItems.firstIndex(where: { $0.id == draggedItem.id }),
              let movingBlock = TodoHierarchyBlockEngine.block(
                  startingAt: draggedIndex,
                  in: sourceItems
              )
        else {
            return nil
        }

        let normalizedDestination = destination.normalized
        let destinationItems = store.items(in: normalizedDestination)
        let normalizedInsertionIndex = min(max(insertionIndex, 0), destinationItems.count)
        let movingItemIds = Set(movingBlock.itemIds)
        if sourceDestination == normalizedDestination,
           normalizedInsertionIndex > movingBlock.range.lowerBound,
           normalizedInsertionIndex <= movingBlock.range.upperBound
        {
            return nil
        }

        let snapshots = movingBlock.range.map { TodoItemSnapshot(from: sourceItems[$0]) }
        guard let movedSnapshots = plannedMovedSnapshots(
            snapshots: snapshots,
            sourceItems: sourceItems,
            movingItemIds: movingItemIds,
            destination: normalizedDestination,
            insertionIndex: normalizedInsertionIndex,
            indentLevel: indentLevel,
            draggedIndex: draggedIndex,
            sourceIndices: Array(movingBlock.range)
        ) else {
            return nil
        }
        return placementPlan(
            before: snapshots,
            after: movedSnapshots,
            selectionAfter: TodoSelectionState(
                focusing: draggedItem.id,
                cursorPosition: selectionManager.cursorPosition
            )
        )
    }

    private func placementPlan(
        before snapshots: [TodoItemSnapshot],
        after movedSnapshots: [TodoItemSnapshot],
        selectionAfter: TodoSelectionState
    ) -> PlacementPlan? {
        guard snapshots.count == movedSnapshots.count else { return nil }
        let itemStateChanges: [TodoItemStateChange] = zip(snapshots, movedSnapshots).compactMap { pair -> TodoItemStateChange? in
            let (before, after) = pair
            guard before.matchesUserState(of: after) == false else { return nil }
            return TodoItemStateChange(before: before, after: after)
        }
        guard itemStateChanges.isEmpty == false else { return nil }
        return PlacementPlan(
            itemStateChanges: itemStateChanges,
            selectionAfter: selectionAfter
        )
    }

    private func plannedMovedSnapshots(
        snapshots: [TodoItemSnapshot],
        sourceItems: [TodoItem],
        movingItemIds: Set<UUID>,
        destination: TodoDropDestination,
        insertionIndex: Int,
        indentLevel: Int,
        draggedIndex: Int,
        sourceIndices: [Int]
    ) -> [TodoItemSnapshot]? {
        guard snapshots.count == sourceIndices.count else { return nil }

        let destinationItems = store.items(in: destination)
        let targetItems = destinationItems.filter { movingItemIds.contains($0.id) == false }
        let removedBeforeInsertion = destinationItems.prefix(insertionIndex).reduce(into: 0) {
            count, item in
            if movingItemIds.contains(item.id) {
                count += 1
            }
        }
        let adjustedInsertionIndex = min(
            max(0, insertionIndex - removedBeforeInsertion),
            targetItems.count
        )
        let afterItem = adjustedInsertionIndex > 0 ? targetItems[adjustedInsertionIndex - 1] : nil
        let requestedIndent = min(max(indentLevel, 0), TodoItem.maxIndentLevel)
        let clampedIndent = min(
            requestedIndent,
            afterItem.map { min(TodoItem.maxIndentLevel, $0.indentLevel + 1) } ?? 0
        )
        let normalizedIndentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(in: sourceItems)
        guard normalizedIndentLevels.indices.contains(draggedIndex) else { return nil }

        return TodoHierarchyBlockEngine.movedSnapshots(
            snapshots,
            sourceItems: sourceItems,
            sourceIndices: sourceIndices,
            destination: destination,
            afterItem: afterItem,
            targetItems: targetItems,
            indentDelta: clampedIndent - normalizedIndentLevels[draggedIndex]
        )
    }

    private func plannedSelectedGroupStateChanges(
        direction: TodoParentChildGroupMoveDirection
    ) -> [TodoItemStateChange]? {
        var selectedIds = selectionManager.selectedItemIds
        if selectedIds.isEmpty, let focusedItemId = selectionManager.focusedItemId {
            selectedIds = [focusedItemId]
        }
        let selectedItems = selectedIds.compactMap { store.todoItemsCache[$0] }
        guard selectedItems.isEmpty == false, selectedItems.count == selectedIds.count else {
            return nil
        }

        let selectedByDestination = Dictionary(grouping: selectedItems) {
            store.destination(for: $0).normalized
        }
        var stateChanges: [TodoItemStateChange] = []

        for (destination, destinationSelection) in selectedByDestination {
            let currentItems = store.items(in: destination)
            let rootIds = TodoHierarchyBlockEngine.blockRootIds(
                selectedFrom: Set(destinationSelection.map(\.id)),
                in: currentItems
            )
            guard rootIds.isEmpty == false,
                  let destinationChanges = plannedStateChanges(
                      direction: direction,
                      rootIds: rootIds,
                      items: currentItems
                  )
            else {
                return nil
            }
            stateChanges.append(contentsOf: destinationChanges)
        }

        return stateChanges.isEmpty ? nil : stateChanges
    }

    private func plannedStateChanges(
        direction: TodoParentChildGroupMoveDirection,
        rootIds: [UUID],
        items: [TodoItem]
    ) -> [TodoItemStateChange]? {
        let beforeSnapshots = items.map(TodoItemSnapshot.init)
        var workingSnapshots = beforeSnapshots
        let moveOrder = direction == .up ? rootIds : Array(rootIds.reversed())

        for rootId in moveOrder {
            guard let moved = plannedMove(
                itemId: rootId,
                direction: direction,
                snapshots: workingSnapshots
            ) else {
                return nil
            }
            workingSnapshots = moved
        }

        let afterById = Dictionary(uniqueKeysWithValues: workingSnapshots.map { ($0.id, $0) })
        return beforeSnapshots.compactMap { before in
            guard let after = afterById[before.id], before.matchesUserState(of: after) == false else {
                return nil
            }
            return TodoItemStateChange(before: before, after: after)
        }
    }

    private func plannedMove(
        itemId: UUID,
        direction: TodoParentChildGroupMoveDirection,
        snapshots: [TodoItemSnapshot]
    ) -> [TodoItemSnapshot]? {
        guard let currentIndex = snapshots.firstIndex(where: { $0.id == itemId }) else {
            return nil
        }
        let indentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(
            snapshots.map(\.indentLevel),
            baseIndentLevel: 0
        )
        let movingRange = blockRange(startingAt: currentIndex, indentLevels: indentLevels)
        let rootIndentLevel = indentLevels[currentIndex]
        let targetInsertIndex: Int

        switch direction {
        case .up:
            guard movingRange.lowerBound > 0 else { return nil }
            var precedingStart = movingRange.lowerBound - 1
            while precedingStart > 0, indentLevels[precedingStart] > rootIndentLevel {
                precedingStart -= 1
            }
            targetInsertIndex = precedingStart
        case .down:
            let nextBlockStart = movingRange.upperBound
            guard snapshots.indices.contains(nextBlockStart) else { return nil }
            if rootIndentLevel > indentLevels[nextBlockStart] {
                targetInsertIndex = nextBlockStart + 1
            } else {
                targetInsertIndex = blockRange(
                    startingAt: nextBlockStart,
                    indentLevels: indentLevels
                ).upperBound
            }
        }

        let movingSnapshots = movingRange.map { snapshots[$0] }
        let movingIds = Set(movingSnapshots.map(\.id))
        let remainingSnapshots = snapshots.filter { movingIds.contains($0.id) == false }
        let removedBeforeInsert = snapshots.prefix(targetInsertIndex).reduce(into: 0) {
            count, snapshot in
            if movingIds.contains(snapshot.id) {
                count += 1
            }
        }
        let adjustedInsertIndex = min(
            max(0, targetInsertIndex - removedBeforeInsert),
            remainingSnapshots.count
        )
        let afterSnapshot = adjustedInsertIndex > 0
            ? remainingSnapshots[adjustedInsertIndex - 1]
            : nil
        let baseSortOrder: Double
        let stepSize: Double
        if let afterSnapshot,
           let afterIndex = remainingSnapshots.firstIndex(where: { $0.id == afterSnapshot.id })
        {
            if afterIndex + 1 < remainingSnapshots.count {
                let gap = remainingSnapshots[afterIndex + 1].sortOrder - afterSnapshot.sortOrder
                stepSize = gap / Double(movingSnapshots.count + 1)
                baseSortOrder = afterSnapshot.sortOrder + stepSize
            } else {
                baseSortOrder = afterSnapshot.sortOrder + 1000
                stepSize = 0.001
            }
        } else if let firstSnapshot = remainingSnapshots.first {
            baseSortOrder = firstSnapshot.sortOrder - 1000
            stepSize = 0.001
        } else {
            baseSortOrder = 1000
            stepSize = 0.001
        }

        let movedSnapshots = movingSnapshots.enumerated().map { offset, snapshot in
            snapshot.replacing(
                indentLevel: indentLevels[movingRange.lowerBound + offset],
                sortOrder: baseSortOrder + Double(offset) * stepSize
            )
        }
        return (remainingSnapshots + movedSnapshots).sorted { $0.sortOrder < $1.sortOrder }
    }

    private func blockRange(
        startingAt startIndex: Int,
        indentLevels: [Int]
    ) -> Range<Int> {
        let rootIndentLevel = indentLevels[startIndex]
        var endIndex = startIndex + 1
        while endIndex < indentLevels.count, indentLevels[endIndex] > rootIndentLevel {
            endIndex += 1
        }
        return startIndex..<endIndex
    }

}
