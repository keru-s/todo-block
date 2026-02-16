//
//  TodoDropDelegate.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import UniformTypeIdentifiers

struct TodoDropDelegate: DropDelegate {
    let destination: TodoDropDestination
    let todoItems: [TodoItem]
    let store: TodoStore
    @Binding var dropState: TodoListDropState
    @Binding var isDropFinalizing: Bool
    let itemFrames: [UUID: CGRect]
    let indentWidth: CGFloat
    let itemHeight: CGFloat

    func dropEntered(info: DropInfo) {
        if isDropFinalizing {
            // A new drag session entered; unlock updates after the previous drop finalized.
            isDropFinalizing = false
        }
        updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isDropFinalizing == false else {
            return DropProposal(operation: .move)
        }
        updateDropState(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearLocalDropState()
    }

    func performDrop(info: DropInfo) -> Bool {
        isDropFinalizing = true

        guard case .insertAt(let insertIndex, let indentLevel) = dropState else {
            finalizeDropState(broadcastReset: true)
            return false
        }

        // Hide insertion indicator immediately while the provider resolves asynchronously.
        dropState = .none

        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else {
            finalizeDropState(broadcastReset: true)
            return false
        }

        provider.loadObject(ofClass: NSString.self) { data, _ in
            Task { @MainActor in
                guard let idString = data as? String,
                    let draggedId = UUID(uuidString: idString)
                else {
                    finalizeDropState(broadcastReset: true)
                    return
                }

                performMove(draggedId: draggedId, toIndex: insertIndex, indentLevel: indentLevel)
                finalizeDropState(broadcastReset: true)
            }
        }

        return true
    }

    private func updateDropState(info: DropInfo) {
        guard info.hasItemsConforming(to: [.text]) else { return }

        let y = info.location.y
        let x = info.location.x

        var insertIndex = todoItems.count
        let hasCompleteFrames = todoItems.allSatisfy { itemFrames[$0.id] != nil }

        if hasCompleteFrames {
            for (index, item) in todoItems.enumerated() {
                guard let frame = itemFrames[item.id] else { continue }
                if y < frame.midY {
                    insertIndex = index
                    break
                }
            }
        } else {
            var accumulatedHeight: CGFloat = 0
            for (index, item) in todoItems.enumerated() {
                let estimatedHeight = estimatedItemHeight(for: item)
                if y < accumulatedHeight + estimatedHeight / 2 {
                    insertIndex = index
                    break
                }
                accumulatedHeight += estimatedHeight
            }
        }

        let baseX: CGFloat = 20
        let relativeX = max(0, x - baseX)
        var indentLevel = Int(relativeX / indentWidth)

        if insertIndex > 0 {
            let previousItem = todoItems[insertIndex - 1]
            indentLevel = min(indentLevel, previousItem.indentLevel + 1)
        } else {
            indentLevel = 0
        }

        indentLevel = min(indentLevel, TodoItem.maxIndentLevel)
        dropState = .insertAt(index: insertIndex, indentLevel: indentLevel)
    }

    private func estimatedItemHeight(for item: TodoItem) -> CGFloat {
        let explicitLineCount = max(1, item.title.components(separatedBy: "\n").count)
        let multiLineHeight = CGFloat(explicitLineCount) * 20 + 8
        return max(itemHeight, multiLineHeight)
    }

    private func performMove(draggedId: UUID, toIndex: Int, indentLevel: Int) {
        guard let draggedItem = store.todoItemsCache[draggedId] else {
            return
        }

        let normalizedToIndex = min(max(toIndex, 0), todoItems.count)
        var remainingItems = todoItems
        var movingItemIds = Set<UUID>()

        let normalizedDestination = destination.normalized

        if store.destination(for: draggedItem) == normalizedDestination,
            let draggedIndex = todoItems.firstIndex(where: { $0.id == draggedId })
        {
            let baseIndent = todoItems[draggedIndex].indentLevel
            movingItemIds.insert(draggedId)

            var nextIndex = draggedIndex + 1
            while nextIndex < todoItems.count {
                let candidate = todoItems[nextIndex]
                if candidate.indentLevel > baseIndent {
                    movingItemIds.insert(candidate.id)
                    nextIndex += 1
                } else {
                    break
                }
            }

            remainingItems.removeAll { movingItemIds.contains($0.id) }
        }

        let removedBeforeInsert = todoItems.prefix(normalizedToIndex).reduce(into: 0) { count, item in
            if movingItemIds.contains(item.id) {
                count += 1
            }
        }

        let adjustedInsertIndex = min(
            max(0, normalizedToIndex - removedBeforeInsert),
            remainingItems.count
        )
        let afterItem = adjustedInsertIndex > 0 ? remainingItems[adjustedInsertIndex - 1] : nil

        var clampedIndentLevel = min(max(indentLevel, 0), TodoItem.maxIndentLevel)
        if let afterItem {
            clampedIndentLevel = min(clampedIndentLevel, afterItem.indentLevel + 1)
        } else {
            clampedIndentLevel = 0
        }

        store.moveItemWithChildren(
            draggedItem,
            to: normalizedDestination,
            afterItem: afterItem,
            newIndentLevel: clampedIndentLevel
        )
    }

    private func clearLocalDropState() {
        dropState = .none
    }

    private func finalizeDropState(broadcastReset: Bool) {
        clearLocalDropState()
        if broadcastReset {
            store.requestDropIndicatorReset()
        }
    }
}
