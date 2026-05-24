//
//  TodoDroppableList.swift
//  todo block
//

import SwiftUI

/// 跨列表共享的 todo 列表容器：含拖放注册、drop indicator、Option 拖选、
/// 跨列表 drop 路由（包括 sidebar 落点）。
///
/// 由 DaySectionView (`.scheduled(date:)`) 和 LongTermBucketView
/// (`.longTerm(isUrgent:)`) 共用。MenuBarView 因为走 menu-bar 内部
/// 自反 reorder 引擎，不通过本组件。
///
/// 使用方提供：
/// - `items`：当前列表内容
/// - `destination`：本列表对应的逻辑容器（用于注册 drop zone + items lookup）
/// - `dropCoordinateSpaceName`：本列表的 SwiftUI coordinateSpace 名（drop zone id）
/// - `emptyContent`：列表为空时的占位视图
struct TodoDroppableList<EmptyContent: View>: View {
    let items: [TodoItem]
    let destination: TodoDropDestination
    let dropCoordinateSpaceName: String
    @Bindable var selectionManager: SelectionManager
    @Binding var dropState: TodoListDropState
    let store: TodoStore
    let onInteraction: (() -> Void)?
    let onCreateItemAfter: (TodoItem) -> Void
    let emptyContent: () -> EmptyContent

    @State private var frameTracker = DropFrameTracker()

    private let indentWidth: CGFloat = TodoDesignTokens.indentWidth
    private let itemHeight: CGFloat = TodoDesignTokens.itemHeight

    private var coordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    init(
        items: [TodoItem],
        destination: TodoDropDestination,
        dropCoordinateSpaceName: String,
        selectionManager: SelectionManager,
        dropState: Binding<TodoListDropState>,
        store: TodoStore,
        onInteraction: (() -> Void)? = nil,
        onCreateItemAfter: @escaping (TodoItem) -> Void,
        @ViewBuilder emptyContent: @escaping () -> EmptyContent
    ) {
        self.items = items
        self.destination = destination
        self.dropCoordinateSpaceName = dropCoordinateSpaceName
        self.selectionManager = selectionManager
        self._dropState = dropState
        self.store = store
        self.onInteraction = onInteraction
        self.onCreateItemAfter = onCreateItemAfter
        self.emptyContent = emptyContent
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    emptyContent()
                } else {
                    ForEach(items.enumerated(), id: \.element.id) { _, item in
                        rowView(for: item)
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
                            store.items(in: destination)
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

    @ViewBuilder
    private func rowView(for item: TodoItem) -> some View {
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
                    selectionManager.deleteSelectedItems(store: store) { [items] _ in items }
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

        // 2. 由各 list 自身确定的 active zone（避免 coordinator.dropZone(at:) 的过期 frame 问题）
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

        // 3. 没有 active zone — item 留在原处（no-op）
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
        let targetItems = store.items(in: targetDestination)

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
