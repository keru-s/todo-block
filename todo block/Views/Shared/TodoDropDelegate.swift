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
    let itemFrames: [UUID: CGRect]
    let indentWidth: CGFloat
    let itemHeight: CGFloat

    private var dragCoordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    func dropEntered(info: DropInfo) {
        updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropState(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearLocalDropState()
    }

    func performDrop(info: DropInfo) -> Bool {
        let resolvedDrop = resolveDrop(for: info)
        dragCoordinator.finishSystemDrag()
        finalizeDropState(broadcastReset: true)

        guard let resolvedDrop else {
            return true
        }

        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else {
            return true
        }

        provider.loadObject(ofClass: NSString.self) { data, _ in
            Task { @MainActor in
                guard let idString = data as? String,
                    let draggedId = UUID(uuidString: idString)
                else {
                    return
                }

                performMove(
                    draggedId: draggedId,
                    toIndex: resolvedDrop.index,
                    indentLevel: resolvedDrop.indentLevel
                )
            }
        }

        return true
    }

    private func updateDropState(info: DropInfo) {
        guard info.hasItemsConforming(to: [.text]) else { return }
        guard dragCoordinator.hasActiveSystemDrag else {
            clearLocalDropState()
            return
        }
        dropState = TodoDropLocationEngine.dropState(
            for: info.location,
            items: todoItems,
            itemFrames: itemFrames,
            itemHeight: itemHeight,
            indentWidth: indentWidth
        )
    }

    private func performMove(draggedId: UUID, toIndex: Int, indentLevel: Int) {
        TodoReorderMoveEngine.performMove(
            draggedId: draggedId,
            toIndex: toIndex,
            indentLevel: indentLevel,
            items: todoItems,
            destination: destination,
            store: store
        )
    }

    private func clearLocalDropState() {
        dropState = .none
    }

    private func resolveDrop(for info: DropInfo) -> TodoResolvedDrop? {
        guard info.hasItemsConforming(to: [.text]) else { return nil }
        guard dragCoordinator.hasActiveSystemDrag else { return nil }
        return TodoDropLocationEngine.resolve(
            location: info.location,
            items: todoItems,
            itemFrames: itemFrames,
            itemHeight: itemHeight,
            indentWidth: indentWidth
        )
    }

    private func finalizeDropState(broadcastReset: Bool) {
        clearLocalDropState()
        if broadcastReset {
            store.requestDropIndicatorReset()
        }
    }
}

struct TodoBoundaryDropDelegate: DropDelegate {
    let insertIndex: Int
    let destination: TodoDropDestination
    let todoItems: [TodoItem]
    let store: TodoStore
    @Binding var dropState: TodoListDropState
    let indentWidth: CGFloat

    private var dragCoordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    func dropEntered(info: DropInfo) {
        updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropState(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearLocalDropState()
    }

    func performDrop(info: DropInfo) -> Bool {
        let resolvedDrop = resolveDrop(for: info)
        dragCoordinator.finishSystemDrag()
        finalizeDropState(broadcastReset: true)

        guard let resolvedDrop else {
            return true
        }

        guard let provider = info.itemProviders(for: [.text]).first else {
            return true
        }

        provider.loadObject(ofClass: NSString.self) { data, _ in
            Task { @MainActor in
                guard let idString = data as? String,
                    let draggedId = UUID(uuidString: idString)
                else {
                    return
                }

                TodoReorderMoveEngine.performMove(
                    draggedId: draggedId,
                    toIndex: resolvedDrop.index,
                    indentLevel: resolvedDrop.indentLevel,
                    items: todoItems,
                    destination: destination,
                    store: store
                )
            }
        }

        return true
    }

    private func updateDropState(info: DropInfo) {
        guard info.hasItemsConforming(to: [.text]) else { return }
        guard dragCoordinator.hasActiveSystemDrag else {
            clearLocalDropState()
            return
        }
        dropState = .insertAt(
            index: insertIndex,
            indentLevel: resolvedIndentLevel(for: info.location.x)
        )
    }

    private func resolveDrop(for info: DropInfo) -> TodoResolvedDrop? {
        guard info.hasItemsConforming(to: [.text]) else { return nil }
        guard dragCoordinator.hasActiveSystemDrag else { return nil }
        return TodoResolvedDrop(
            index: insertIndex,
            indentLevel: resolvedIndentLevel(for: info.location.x)
        )
    }

    private func resolvedIndentLevel(for x: CGFloat) -> Int {
        let baseX: CGFloat = 20
        let relativeX = max(0, x - baseX)
        var indentLevel = Int(relativeX / indentWidth)

        if insertIndex > 0 {
            indentLevel = min(indentLevel, todoItems[insertIndex - 1].indentLevel + 1)
        } else {
            indentLevel = 0
        }

        return min(indentLevel, TodoItem.maxIndentLevel)
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
