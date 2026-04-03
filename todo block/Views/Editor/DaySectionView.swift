//
//  DaySectionView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI

struct DaySectionView: View {
    @Bindable var section: DaySection
    @Bindable var selectionManager: SelectionManager
    var onItemCreated: ((UUID) -> Void)?
    var onInteraction: (() -> Void)?

    private let indentWidth: CGFloat = 24
    @State private var dropState: TodoListDropState = .none
    @State private var showDatePicker: Bool = false
    @State private var selectedDate: Date = Date()

    private var store: TodoStore { TodoStore.shared }
    private var coordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    private var todoItems: [TodoItem] {
        store.items(for: section.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DaySectionHeaderView(
                title: section.title,
                showDatePicker: $showDatePicker,
                selectedDate: $selectedDate,
                onTitleTap: onDateTitleTapped,
                onConfirm: confirmDateSelection
            )

            DaySectionTodoListView(
                sectionDate: section.date,
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
        )
        .onAppear {
            selectedDate = section.date
        }
        .onChange(of: todoItems.dropResetSnapshot) { _, _ in
            if coordinator.isDragging == false {
                dropState = .none
            }
        }
        .onChange(of: store.dropIndicatorResetTrigger) { _, _ in
            dropState = .none
        }
    }

    private func onDateTitleTapped() {
        selectedDate = section.date
        showDatePicker = true
    }

    private func confirmDateSelection(_ newDate: Date) {
        store.updateSectionDate(section, to: newDate)
        showDatePicker = false
    }

    private func addNewItem() {
        let newItem = store.createItem(dayDate: section.date)
        selectionManager.handleSelect(
            item: newItem,
            allItems: store.items(for: section.date),
            shiftPressed: false
        )
        onItemCreated?(newItem.id)
    }

    private func createNewItemAfter(_ item: TodoItem) {
        let newItem = store.createItem(
            dayDate: section.date,
            afterItem: item,
            indentLevel: item.indentLevel
        )
        selectionManager.handleSelect(
            item: newItem,
            allItems: store.items(for: section.date),
            shiftPressed: false
        )
        onItemCreated?(newItem.id)
    }
}

private struct DaySectionHeaderView: View {
    let title: String
    @Binding var showDatePicker: Bool
    @Binding var selectedDate: Date
    let onTitleTap: () -> Void
    let onConfirm: (Date) -> Void

    var body: some View {
        HStack {
            Button(title) {
                onTitleTap()
            }
            .buttonStyle(.plain)
            .font(.title3)
            .bold()
            .foregroundStyle(.primary)
            .popover(isPresented: $showDatePicker) {
                VStack(spacing: 12) {
                    DatePicker(
                        "选择日期",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    HStack {
                        Button("取消") {
                            showDatePicker = false
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button("确认") {
                            onConfirm(selectedDate)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .frame(width: 300)
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }
}

private struct DaySectionTodoListView: View {
    let sectionDate: Date
    let items: [TodoItem]
    @Bindable var selectionManager: SelectionManager
    @Binding var dropState: TodoListDropState
    let indentWidth: CGFloat
    let store: TodoStore
    let onInteraction: (() -> Void)?
    let onAddItem: () -> Void
    let onCreateItemAfter: (TodoItem) -> Void

    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var listGlobalFrame: CGRect = .zero
    private let itemHeight: CGFloat = 28

    private var coordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    private var dropCoordinateSpaceName: String {
        "day-section-drop-\(sectionDate.timeIntervalSince1970)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    DaySectionEmptyStateView(onAddItem: onAddItem)
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
                            handleDragCoordinateSpace: .named(dropCoordinateSpaceName),
                            onHandleDragBegan: {
                                coordinator.beginDrag(itemId: item.id)
                            },
                            onHandleDragChanged: { location in
                                coordinator.updateDrag(globalLocation: localToGlobal(location))
                                updateDropFromLocal(location)
                            },
                            onHandleDragEnded: { location in
                                coordinator.updateDrag(globalLocation: localToGlobal(location))
                                finalizeDropFromLocal(location)
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
                                    selectionManager.deleteSelectedItems(store: store) { date in
                                        store.items(for: date)
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
            .onPreferenceChange(TodoDropItemFramePreferenceKey.self) { itemFrames = $0 }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { listGlobalFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, newValue in
                            listGlobalFrame = newValue
                        }
                }
            }

            TodoDropIndicatorOverlay(
                dropState: dropState,
                items: items,
                itemFrames: itemFrames,
                itemHeight: itemHeight,
                indentWidth: indentWidth
            )
        }
    }

    // MARK: - Coordinate conversion

    private func localToGlobal(_ local: CGPoint) -> CGPoint {
        CGPoint(
            x: local.x + listGlobalFrame.origin.x,
            y: local.y + listGlobalFrame.origin.y
        )
    }

    // MARK: - Drop state

    private func updateDropFromLocal(_ location: CGPoint) {
        dropState = TodoDropLocationEngine.dropState(
            for: location,
            items: items,
            itemFrames: itemFrames,
            itemHeight: itemHeight,
            indentWidth: indentWidth
        )
    }

    private func finalizeDropFromLocal(_ location: CGPoint) {
        defer {
            coordinator.endDrag()
            dropState = .none
            store.requestDropIndicatorReset()
        }

        guard let draggedId = coordinator.draggedItemId else { return }

        let globalLoc = localToGlobal(location)
        if let sidebarDest = coordinator.sidebarTarget(at: globalLoc),
            let draggedItem = store.todoItemsCache[draggedId]
        {
            performSidebarDrop(item: draggedItem, destination: sidebarDest)
            return
        }

        let finalState = TodoDropLocationEngine.dropState(
            for: location,
            items: items,
            itemFrames: itemFrames,
            itemHeight: itemHeight,
            indentWidth: indentWidth
        )

        guard case .insertAt(let toIndex, let indentLevel) = finalState else { return }

        TodoReorderMoveEngine.performMove(
            draggedId: draggedId,
            toIndex: toIndex,
            indentLevel: indentLevel,
            items: items,
            destination: .scheduled(date: sectionDate),
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

private struct DaySectionEmptyStateView: View {
    let onAddItem: () -> Void

    var body: some View {
        Button(action: onAddItem) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                Text("添加待办")
            }
            .font(.system(size: 14))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)

    let section = DaySection(date: Date(), title: "01-17")
    container.mainContext.insert(section)

    TodoStore.shared.initialize(with: container.mainContext)

    return DaySectionView(
        section: section,
        selectionManager: SelectionManager()
    )
    .modelContainer(container)
    .padding()
}
