//
//  DaySectionView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
            dropState = .none
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

    private let topDropZoneVisualHeight: CGFloat = 4
    private let topDropZoneHitHeight: CGFloat = 24
    private let middleDropZoneVisualHeight: CGFloat = 2
    private let middleDropZoneHitHeight: CGFloat = 14
    private let bottomDropZoneVisualHeight: CGFloat = 4
    private let bottomDropZoneHitHeight: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodoDropGutterView(
                index: 0,
                visualHeight: topDropZoneVisualHeight,
                hitHeight: topDropZoneHitHeight,
                destination: .scheduled(date: sectionDate),
                items: items,
                store: store,
                dropState: $dropState,
                indentWidth: indentWidth
            )

            if items.isEmpty {
                DaySectionEmptyStateView(onAddItem: onAddItem)
                    .contentShape(.rect)
                    .onDrop(
                        of: [.text],
                        delegate: TodoBoundaryDropDelegate(
                            insertIndex: 0,
                            destination: .scheduled(date: sectionDate),
                            todoItems: items,
                            store: store,
                            dropState: $dropState,
                            indentWidth: indentWidth
                        )
                    )
            } else {
                ForEach(items.enumerated(), id: \.element.id) { index, item in
                    TodoItemView(
                        item: item,
                        allItems: items,
                        focusedItemId: $selectionManager.focusedItemId,
                        isSelected: selectionManager.selectedItemIds.contains(item.id),
                        hasMultipleSelection: selectionManager.selectedItemIds.count > 1,
                        cursorPosition: selectionManager.cursorPosition,
                        preferredHorizontalOffset: selectionManager.preferredHorizontalOffset,
                        verticalMoveDirection: selectionManager.verticalMoveDirection,
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

                    TodoDropGutterView(
                        index: index + 1,
                        visualHeight: index == items.count - 1
                            ? bottomDropZoneVisualHeight
                            : middleDropZoneVisualHeight,
                        hitHeight: index == items.count - 1
                            ? bottomDropZoneHitHeight
                            : middleDropZoneHitHeight,
                        destination: .scheduled(date: sectionDate),
                        items: items,
                        store: store,
                        dropState: $dropState,
                        indentWidth: indentWidth
                    )
                }
            }
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
