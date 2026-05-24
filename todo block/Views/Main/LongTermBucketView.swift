//
//  LongTermBucketView.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftData
import SwiftUI

struct LongTermBucketView: View {
    let title: String
    let isUrgent: Bool
    @Bindable var selectionManager: SelectionManager
    var onItemCreated: ((UUID) -> Void)?
    var onInteraction: (() -> Void)?

    private let indentWidth: CGFloat = TodoDesignTokens.indentWidth
    @State private var dropState: TodoListDropState = .none
    private var store: TodoStore { TodoStore.shared }
    private var coordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    private var todoItems: [TodoItem] {
        store.longTermItems(isUrgent: isUrgent)
    }

    private var containerKind: TodoContainerKind {
        isUrgent ? .longTermUrgent : .longTermImportant
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LongTermBucketHeaderView(title: title)

            LongTermBucketListView(
                destination: .longTerm(isUrgent: isUrgent),
                items: todoItems,
                selectionManager: selectionManager,
                dropState: $dropState,
                indentWidth: indentWidth,
                store: store,
                onInteraction: onInteraction,
                onAddItem: addNewItem,
                onCreateItemAfter: createNewItemAfter
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: TodoDesignTokens.bucketCornerRadius)
                .fill(TodoDesignTokens.bucketTint)
        )
        .onChange(of: todoItems.dropResetSnapshot) { _, _ in
            if coordinator.isDragging == false {
                dropState = .none
            }
        }
        .onChange(of: store.dropIndicatorResetTrigger) { _, _ in
            dropState = .none
        }
    }
}

private extension LongTermBucketView {
    func addNewItem() {
        let newItem = store.createItem(
            dayDate: Date(),
            containerKind: containerKind
        )
        selectionManager.handleSelect(
            item: newItem,
            allItems: todoItems,
            shiftPressed: false
        )
        onItemCreated?(newItem.id)
    }

    func createNewItemAfter(_ item: TodoItem) {
        let newItem = store.createItem(
            dayDate: item.dayDate,
            afterItem: item,
            indentLevel: item.indentLevel,
            containerKind: containerKind
        )
        selectionManager.handleSelect(
            item: newItem,
            allItems: todoItems,
            shiftPressed: false
        )
        onItemCreated?(newItem.id)
    }
}

private struct LongTermBucketHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

private struct LongTermBucketListView: View {
    let destination: TodoDropDestination
    let items: [TodoItem]
    @Bindable var selectionManager: SelectionManager
    @Binding var dropState: TodoListDropState
    let indentWidth: CGFloat
    let store: TodoStore
    let onInteraction: (() -> Void)?
    let onAddItem: () -> Void
    let onCreateItemAfter: (TodoItem) -> Void

    @State private var frameTracker = DropFrameTracker()
    private let itemHeight: CGFloat = TodoDesignTokens.itemHeight

    private var coordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    private var dropCoordinateSpaceName: String {
        "longterm-drop-\(destination == .longTerm(isUrgent: true) ? "urgent" : "important")"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    LongTermBucketEmptyStateView(onAddItem: onAddItem)
                } else {
                    ForEach(items.enumerated(), id: \.element.id) { _, item in
                        TodoItemView(
                            item: item,
                            allItems: items,
                            focusedItemId: $selectionManager.focusedItemId,
                            isSelected: selectionManager.selectedItemIds.contains(item.id),
                            hasMultipleSelection: selectionManager.selectedItemIds.count > 1,
                            cursorPosition: selectionManager.cursorPosition,
                            preferredHorizontalOffset: selectionManager.preferredHorizontalOffset,
                            verticalMoveDirection: selectionManager.verticalMoveDirection,
                            useSystemDragAndDrop: false,
                            handleDragCoordinateSpace: .global,
                            onHandleDragBegan: {
                                guard selectionManager.isDragSelecting == false else { return }
                                coordinator.beginDrag(itemId: item.id)
                            },
                            onHandleDragChanged: { location in
                                guard selectionManager.isDragSelecting == false else { return }
                                coordinator.updateDrag(globalLocation: location)
                            },
                            onHandleDragEnded: { location in
                                guard selectionManager.isDragSelecting == false else { return }
                                coordinator.updateDrag(globalLocation: location)
                                finalizeDrop()
                            },
                            onSelect: { shiftPressed in
                                onInteraction?()
                                selectionManager.handleSelect(
                                    item: item,
                                    allItems: items,
                                    shiftPressed: shiftPressed
                                )
                            },
                            onFocus: { shiftPressed, cursorPosition in
                                onInteraction?()
                                selectionManager.handleSelect(
                                    item: item,
                                    allItems: items,
                                    shiftPressed: shiftPressed,
                                    cursorPosition: cursorPosition
                                )
                            },
                            onEnterPressed: { onCreateItemAfter(item) },
                            onDeletePressed: {
                                if selectionManager.selectedItemIds.contains(item.id) {
                                    selectionManager.deleteSelectedItems(store: store) { _ in
                                        items
                                    }
                                }
                            },
                            onMoveUp: { position, horizontalOffset in
                                selectionManager.moveFocusUp(
                                    from: item,
                                    allItems: items,
                                    cursorPosition: position,
                                    preferredHorizontalOffset: horizontalOffset
                                )
                            },
                            onMoveDown: { position, horizontalOffset in
                                selectionManager.moveFocusDown(
                                    from: item,
                                    allItems: items,
                                    cursorPosition: position,
                                    preferredHorizontalOffset: horizontalOffset
                                )
                            },
                            onActivateInteraction: {
                                onInteraction?()
                            }
                        )
                        .id(item.id)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TodoDropItemFramePreferenceKey.self,
                                    value: [item.id: proxy.frame(in: .named(dropCoordinateSpaceName))]
                                )
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: dropCoordinateSpaceName)
            .onPreferenceChange(TodoDropItemFramePreferenceKey.self) { [frameTracker] in
                frameTracker.itemFrames = $0
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            let frame = proxy.frame(in: .global)
                            frameTracker.listGlobalFrame = frame
                            coordinator.registerDropZone(
                                id: dropCoordinateSpaceName,
                                destination: destination,
                                frame: frame
                            )
                        }
                        .onChange(of: proxy.frame(in: .global)) { [frameTracker] _, newValue in
                            frameTracker.listGlobalFrame = newValue
                            coordinator.updateDropZoneFrame(
                                id: dropCoordinateSpaceName,
                                frame: newValue
                            )
                        }
                }
            }
            .onAppear {
                OptionDragSelectionMonitor.shared.register(
                    .init(
                        id: dropCoordinateSpaceName,
                        frameTracker: frameTracker,
                        itemsProvider: { [store, destination] in
                            switch destination {
                            case .scheduled(let date):
                                return store.items(for: date)
                            case .longTerm(let isUrgent):
                                return store.longTermItems(isUrgent: isUrgent)
                            }
                        },
                        selectionManager: selectionManager,
                        onInteraction: onInteraction
                    )
                )
            }
            .onDisappear {
                coordinator.unregisterDropZone(id: dropCoordinateSpaceName)
                OptionDragSelectionMonitor.shared.unregister(id: dropCoordinateSpaceName)
            }

            TodoDropIndicatorOverlay(
                dropState: dropState,
                items: items,
                itemFrames: frameTracker.itemFrames,
                itemHeight: itemHeight,
                indentWidth: indentWidth
            )
        }
        .onChange(of: coordinator.globalDragLocation) { _, _ in
            updateDropStateFromCoordinator()
        }
        .onChange(of: coordinator.isDragging) { _, isDragging in
            if !isDragging {
                dropState = .none
                coordinator.updateDropZoneState(id: dropCoordinateSpaceName, state: .none)
            }
        }
    }

    // MARK: - Drop state observation

    private func updateDropStateFromCoordinator() {
        let listGlobalFrame = frameTracker.listGlobalFrame
        guard coordinator.isDragging,
            let globalLoc = coordinator.globalDragLocation,
            listGlobalFrame.width > 0,
            listGlobalFrame.contains(globalLoc)
        else {
            if dropState != .none {
                dropState = .none
                coordinator.updateDropZoneState(id: dropCoordinateSpaceName, state: .none)
            }
            if coordinator.activeDropZoneId == dropCoordinateSpaceName {
                coordinator.setActiveDropZone(nil)
            }
            return
        }

        coordinator.setActiveDropZone(dropCoordinateSpaceName)

        let localPoint = CGPoint(
            x: globalLoc.x - listGlobalFrame.origin.x,
            y: globalLoc.y - listGlobalFrame.origin.y
        )
        let newState = TodoDropLocationEngine.dropState(
            for: localPoint,
            items: items,
            itemFrames: frameTracker.itemFrames,
            itemHeight: itemHeight,
            indentWidth: indentWidth
        )
        dropState = newState
        coordinator.updateDropZoneState(id: dropCoordinateSpaceName, state: newState)
    }

    // MARK: - Drop finalization

    private func finalizeDrop() {
        defer {
            coordinator.endDrag()
            dropState = .none
            store.requestDropIndicatorReset()
        }

        guard let draggedId = coordinator.draggedItemId,
            let globalLoc = coordinator.globalDragLocation
        else { return }

        // 1. Sidebar target
        if let sidebarDest = coordinator.sidebarTarget(at: globalLoc),
            let draggedItem = store.todoItemsCache[draggedId]
        {
            performSidebarDrop(item: draggedItem, destination: sidebarDest)
            return
        }

        // 2. Use the active zone determined by each list's own local check.
        if let activeId = coordinator.activeDropZoneId,
            let zoneInfo = coordinator.dropZoneInfo(for: activeId)
        {
            if activeId == dropCoordinateSpaceName {
                performLocalDrop(draggedId: draggedId)
            } else {
                performCrossListDrop(
                    draggedId: draggedId,
                    targetDestination: zoneInfo.destination,
                    targetDropState: zoneInfo.currentDropState
                )
            }
            return
        }

        // 3. No active zone — item stays in place (no-op)
    }

    private func performLocalDrop(draggedId: UUID) {
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

    private func performCrossListDrop(
        draggedId: UUID,
        targetDestination: TodoDropDestination,
        targetDropState: TodoListDropState
    ) {
        let targetItems = resolveItems(for: targetDestination)

        guard case .insertAt(let toIndex, let indentLevel) = targetDropState else {
            TodoReorderMoveEngine.performMove(
                draggedId: draggedId,
                toIndex: targetItems.count,
                indentLevel: 0,
                items: targetItems,
                destination: targetDestination,
                store: store
            )
            return
        }

        TodoReorderMoveEngine.performMove(
            draggedId: draggedId,
            toIndex: toIndex,
            indentLevel: indentLevel,
            items: targetItems,
            destination: targetDestination,
            store: store
        )
    }

    private func resolveItems(for dest: TodoDropDestination) -> [TodoItem] {
        switch dest {
        case .scheduled(let date):
            return store.items(for: date)
        case .longTerm(let isUrgent):
            return store.longTermItems(isUrgent: isUrgent)
        }
    }

    private func performSidebarDrop(item: TodoItem, destination: SidebarDestination) {
        switch destination {
        case .longTerm:
            store.moveItemWithChildren(
                item,
                to: .longTerm(isUrgent: false),
                afterItem: nil,
                newIndentLevel: 0
            )
        case .month(let year, let month):
            let target = store.tailItemForScheduledMonth(year: year, month: month)
            store.moveItemWithChildren(
                item,
                to: .scheduled(date: target.date),
                afterItem: nil,
                newIndentLevel: 0
            )
        }
    }
}

private struct LongTermBucketEmptyStateView: View {
    let onAddItem: () -> Void

    var body: some View {
        Button("添加待办", systemImage: "plus") {
            onAddItem()
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }
}
