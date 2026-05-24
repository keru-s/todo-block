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

    @State private var dropState: TodoListDropState = .none
    private var store: TodoStore { TodoStore.shared }
    private var coordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    private var todoItems: [TodoItem] {
        store.longTermItems(isUrgent: isUrgent)
    }

    private var containerKind: TodoContainerKind {
        isUrgent ? .longTermUrgent : .longTermImportant
    }

    private var dropCoordinateSpaceName: String {
        "longterm-drop-\(isUrgent ? "urgent" : "important")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LongTermBucketHeaderView(title: title)

            TodoDroppableList(
                items: todoItems,
                destination: .longTerm(isUrgent: isUrgent),
                dropCoordinateSpaceName: dropCoordinateSpaceName,
                selectionManager: selectionManager,
                dropState: $dropState,
                store: store,
                onInteraction: onInteraction,
                onCreateItemAfter: createNewItemAfter,
                emptyContent: {
                    LongTermBucketEmptyStateView(onAddItem: addNewItem)
                }
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
