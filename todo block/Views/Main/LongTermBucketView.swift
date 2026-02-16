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
    private let itemHeight: CGFloat = 28

    @State private var dropState: TodoListDropState = .none
    @State private var isDropFinalizing: Bool = false
    @State private var itemFrames: [UUID: CGRect] = [:]

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
                coordinateSpaceName: "long-term-drop-area-\(title)",
                destination: .longTerm(isUrgent: isUrgent),
                items: todoItems,
                selectionManager: selectionManager,
                dropState: $dropState,
                isDropFinalizing: $isDropFinalizing,
                itemFrames: $itemFrames,
                indentWidth: indentWidth,
                itemHeight: itemHeight,
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
            isDropFinalizing = false
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
    let coordinateSpaceName: String
    let destination: TodoDropDestination
    let items: [TodoItem]
    @Bindable var selectionManager: SelectionManager
    @Binding var dropState: TodoListDropState
    @Binding var isDropFinalizing: Bool
    @Binding var itemFrames: [UUID: CGRect]
    let indentWidth: CGFloat
    let itemHeight: CGFloat
    let store: TodoStore
    let onInteraction: (() -> Void)?
    let onAddItem: () -> Void
    let onCreateItemAfter: (TodoItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                LongTermBucketEmptyStateView(onAddItem: onAddItem)
            } else {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    VStack(spacing: 0) {
                        if case .insertAt(let insertIndex, let indentLevel) = dropState,
                            insertIndex == index
                        {
                            TodoInsertionIndicator(
                                indentLevel: indentLevel,
                                indentWidth: indentWidth
                            )
                        }

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
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TodoDropItemFramePreferenceKey.self,
                                    value: [item.id: proxy.frame(in: .named(coordinateSpaceName))]
                                )
                            }
                        }
                        .id(item.id)
                    }
                }

                if case .insertAt(let insertIndex, let indentLevel) = dropState,
                    insertIndex == items.count
                {
                    TodoInsertionIndicator(
                        indentLevel: indentLevel,
                        indentWidth: indentWidth
                    )
                }
            }
        }
        .onDrop(
            of: [.text],
            delegate: TodoDropDelegate(
                destination: destination,
                todoItems: items,
                store: store,
                dropState: $dropState,
                isDropFinalizing: $isDropFinalizing,
                itemFrames: itemFrames,
                indentWidth: indentWidth,
                itemHeight: itemHeight
            )
        )
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(TodoDropItemFramePreferenceKey.self) { value in
            itemFrames = value
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
