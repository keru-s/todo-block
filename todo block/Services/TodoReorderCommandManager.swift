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

        let selectionBefore = TodoSelectionState(selectionManager: selectionManager)
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
            guard rootIds.isEmpty == false else { return false }
            guard let destinationChanges = plannedStateChanges(
                direction: direction,
                rootIds: rootIds,
                items: currentItems
            ) else { return false }
            stateChanges.append(contentsOf: destinationChanges)
        }

        return store.undoManager.perform(
            TodoOperation(
                actionName: "移动",
                itemStateChanges: stateChanges,
                selectionChanges: [
                    TodoSelectionChange(
                        selectionManager: selectionManager,
                        before: selectionBefore,
                        after: selectionBefore
                    )
                ]
            ),
            store: store
        )
    }

    private static func plannedStateChanges(
        direction: TodoKeyboardReorderDirection,
        rootIds: [UUID],
        items: [TodoItem]
    ) -> [TodoItemStateChange]? {
        let beforeSnapshots = items.map { TodoItemSnapshot(from: $0) }
        var workingSnapshots = beforeSnapshots
        let moveOrder = direction == .up ? rootIds : Array(rootIds.reversed())

        for rootId in moveOrder {
            guard let moved = plannedMove(
                itemId: rootId,
                direction: direction,
                snapshots: workingSnapshots
            ) else { return nil }
            workingSnapshots = moved
        }

        let afterById = Dictionary(uniqueKeysWithValues: workingSnapshots.map { ($0.id, $0) })
        return beforeSnapshots.compactMap { before in
            guard
                let after = afterById[before.id],
                before.matchesUserState(of: after) == false
            else { return nil }
            return TodoItemStateChange(before: before, after: after)
        }
    }

    private static func plannedMove(
        itemId: UUID,
        direction: TodoKeyboardReorderDirection,
        snapshots: [TodoItemSnapshot]
    ) -> [TodoItemSnapshot]? {
        guard let currentIndex = snapshots.firstIndex(where: { $0.id == itemId }) else {
            return nil
        }
        let indentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(
            snapshots.map(\.indentLevel),
            baseIndentLevel: 0
        )
        let movingRange = blockRange(
            startingAt: currentIndex,
            indentLevels: indentLevels
        )
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
            if movingIds.contains(snapshot.id) { count += 1 }
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
           let afterIndex = remainingSnapshots.firstIndex(where: { $0.id == afterSnapshot.id }) {
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

    private static func blockRange(
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
