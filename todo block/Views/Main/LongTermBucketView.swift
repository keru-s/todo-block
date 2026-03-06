//
//  LongTermBucketView.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LongTermBucketView: View {
    let title: String
    let isUrgent: Bool
    @Bindable var selectionManager: SelectionManager
    var onItemCreated: ((UUID) -> Void)?
    var onInteraction: (() -> Void)?

    private let indentWidth: CGFloat = 24
    @State private var dropState: TodoListDropState = .none
    private var store: TodoStore { TodoStore.shared }

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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
        )
        .onChange(of: todoItems.dropResetSnapshot) { _, _ in
            dropState = .none
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
                destination: destination,
                items: items,
                store: store,
                dropState: $dropState,
                indentWidth: indentWidth
            )

            if items.isEmpty {
                LongTermBucketEmptyStateView(onAddItem: onAddItem)
                    .contentShape(.rect)
                    .onDrop(
                        of: [.text],
                        delegate: TodoBoundaryDropDelegate(
                            insertIndex: 0,
                            destination: destination,
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

                    TodoDropGutterView(
                        index: index + 1,
                        visualHeight: index == items.count - 1
                            ? bottomDropZoneVisualHeight
                            : middleDropZoneVisualHeight,
                        hitHeight: index == items.count - 1
                            ? bottomDropZoneHitHeight
                            : middleDropZoneHitHeight,
                        destination: destination,
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
