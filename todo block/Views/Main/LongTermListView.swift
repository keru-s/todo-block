//
//  LongTermListView.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LongTermListView: View {
    @State private var selectionManager = SelectionManager()

    private var store: TodoStore { TodoStore.shared }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading) {
                    LongTermBucketView(
                        title: "紧急",
                        isUrgent: true,
                        selectionManager: selectionManager,
                        onItemCreated: { itemId in
                            scrollToItem(itemId, proxy: proxy)
                        },
                        onInteraction: {
                            activateClipboardContext()
                        }
                    )

                    LongTermBucketView(
                        title: "重要",
                        isUrgent: false,
                        selectionManager: selectionManager,
                        onItemCreated: { itemId in
                            scrollToItem(itemId, proxy: proxy)
                        },
                        onInteraction: {
                            activateClipboardContext()
                        }
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                activateClipboardContext()
            }
            .onChange(of: selectionManager.focusedItemId) { _, newValue in
                activateClipboardContext()
                if let itemId = newValue {
                    scrollToItem(itemId, proxy: proxy)
                }
            }
            .onChange(of: selectionManager.selectedItemIds) { _, _ in
                activateClipboardContext()
            }
            .onChange(of: store.focusRequestId) { _, newValue in
                guard let itemId = newValue, store.todoItemsCache[itemId] != nil else { return }
                activateClipboardContext()
                selectionManager.restoreFocus(to: itemId)
                scrollToItem(itemId, proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func scrollToItem(_ itemId: UUID, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(itemId, anchor: .center)
        }
    }

    private func activateClipboardContext() {
        TodoClipboardManager.shared.setActiveContext(
            export: { exportSelectedItemsAsMarkdown() },
            import: { markdown in importMarkdownItems(markdown) },
            canCopy: { hasCopyCandidates() }
        )
    }

    private func hasCopyCandidates() -> Bool {
        selectedOrFocusedItems().isEmpty == false
    }

    private func exportSelectedItemsAsMarkdown() -> String? {
        let items = sortItemsForListOrder(selectedOrFocusedItems())
        guard items.isEmpty == false else { return nil }
        return MarkdownTodoCodec.encode(items: items, normalizeBaseIndent: true)
    }

    private func importMarkdownItems(_ markdown: String) -> Bool {
        let target = resolvePasteTarget()
        let parsedEntries = MarkdownTodoCodec.decode(
            markdown,
            baseIndentLevel: target.baseIndentLevel,
            maxIndentLevel: TodoItem.maxIndentLevel
        )
        guard parsedEntries.isEmpty == false else { return false }

        var createdItems: [TodoItem] = []
        var currentAfterItem = target.afterItem

        store.nsUndoManager.beginUndoGrouping()
        defer {
            store.nsUndoManager.endUndoGrouping()
            store.nsUndoManager.setActionName("粘贴")
        }

        for entry in parsedEntries {
            let newItem = store.createItem(
                title: entry.title,
                dayDate: target.dayDate,
                afterItem: currentAfterItem,
                indentLevel: entry.indentLevel,
                containerKind: target.containerKind
            )
            newItem.isCompleted = entry.isCompleted
            newItem.updatedAt = Date()
            createdItems.append(newItem)
            currentAfterItem = newItem
        }

        guard let lastItem = createdItems.last else { return false }

        selectionManager.selectedItemIds = Set(createdItems.map(\.id))
        selectionManager.focusedItemId = lastItem.id
        selectionManager.lastSelectedId = lastItem.id
        store.scheduleSave()
        return true
    }

    private func selectedOrFocusedItems() -> [TodoItem] {
        let selectedItems = selectionManager.selectedItemIds.compactMap { store.todoItemsCache[$0] }
        if selectedItems.isEmpty == false {
            return selectedItems
        }

        guard
            let focusedItemId = selectionManager.focusedItemId,
            let focusedItem = store.todoItemsCache[focusedItemId]
        else {
            return []
        }
        return [focusedItem]
    }

    private func sortItemsForListOrder(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { lhs, rhs in
            if lhs.containerKindRaw == rhs.containerKindRaw {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.containerKindRaw < rhs.containerKindRaw
        }
    }

    private func resolvePasteTarget() -> (
        dayDate: Date,
        containerKind: TodoContainerKind,
        afterItem: TodoItem?,
        baseIndentLevel: Int
    ) {
        let isLongTermContainer: (TodoItem) -> Bool = { item in
            item.containerKind == .longTermUrgent || item.containerKind == .longTermImportant
        }

        if
            let focusedItemId = selectionManager.focusedItemId,
            let focusedItem = store.todoItemsCache[focusedItemId],
            isLongTermContainer(focusedItem)
        {
            return (focusedItem.dayDate, focusedItem.containerKind, focusedItem, focusedItem.indentLevel)
        }

        let selectedItems = sortItemsForListOrder(
            selectionManager.selectedItemIds.compactMap { store.todoItemsCache[$0] }
                .filter(isLongTermContainer)
        )
        if let lastSelectedItem = selectedItems.last {
            return (
                lastSelectedItem.dayDate,
                lastSelectedItem.containerKind,
                lastSelectedItem,
                lastSelectedItem.indentLevel
            )
        }

        let fallbackItems = store.longTermItems(isUrgent: false)
        return (Date(), .longTermImportant, fallbackItems.last, 0)
    }
}

struct LongTermBucketView: View {
    let title: String
    let isUrgent: Bool
    @Bindable var selectionManager: SelectionManager
    var onItemCreated: ((UUID) -> Void)?
    var onInteraction: (() -> Void)?

    @State private var dropState: TodoListDropState = .none
    @State private var itemFrames: [UUID: CGRect] = [:]

    private var store: TodoStore { TodoStore.shared }

    private var todoItems: [TodoItem] {
        store.longTermItems(isUrgent: isUrgent)
    }

    private var containerKind: TodoContainerKind {
        isUrgent ? .longTermUrgent : .longTermImportant
    }

    private let indentWidth: CGFloat = 24
    private let itemHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                if todoItems.isEmpty {
                    Button("添加待办", systemImage: "plus") {
                        addNewItem()
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                } else {
                    ForEach(todoItems, id: \.id) { item in
                        if let index = todoItems.firstIndex(where: { $0.id == item.id }) {
                            VStack(spacing: 0) {
                                if case .insertAt(let insertIndex, let indentLevel) = dropState,
                                    insertIndex == index
                                {
                                    LongTermInsertionIndicator(indentLevel: indentLevel, indentWidth: indentWidth)
                                }

                                TodoItemView(
                                    item: item,
                                    allItems: todoItems,
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
                                            allItems: todoItems,
                                            shiftPressed: shiftPressed
                                        )
                                    },
                                    onFocus: { shiftPressed, cursorPosition in
                                        onInteraction?()
                                        selectionManager.handleSelect(
                                            item: item,
                                            allItems: todoItems,
                                            shiftPressed: shiftPressed,
                                            cursorPosition: cursorPosition
                                        )
                                    },
                                    onEnterPressed: { createNewItemAfter(item) },
                                    onDeletePressed: {
                                        if selectionManager.selectedItemIds.contains(item.id) {
                                            selectionManager.deleteSelectedItems(store: store) { _ in
                                                store.longTermItems(isUrgent: isUrgent)
                                            }
                                        }
                                    },
                                    onMoveUp: { position, horizontalOffset in
                                        selectionManager.moveFocusUp(
                                            from: item,
                                            allItems: todoItems,
                                            cursorPosition: position,
                                            preferredHorizontalOffset: horizontalOffset
                                        )
                                    },
                                    onMoveDown: { position, horizontalOffset in
                                        selectionManager.moveFocusDown(
                                            from: item,
                                            allItems: todoItems,
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
                                            value: [item.id: proxy.frame(in: .named("long-term-drop-area-\(title)"))]
                                        )
                                    }
                                }
                                .id(item.id)
                            }
                        }
                    }

                    if case .insertAt(let insertIndex, let indentLevel) = dropState,
                        insertIndex == todoItems.count
                    {
                        LongTermInsertionIndicator(indentLevel: indentLevel, indentWidth: indentWidth)
                    }
                }
            }
            .onDrop(
                of: [.text],
                delegate: TodoDropDelegate(
                    destination: .longTerm(isUrgent: isUrgent),
                    todoItems: todoItems,
                    store: store,
                    dropState: $dropState,
                    itemFrames: itemFrames,
                    indentWidth: indentWidth,
                    itemHeight: itemHeight
                )
            )
            .coordinateSpace(name: "long-term-drop-area-\(title)")
            .onPreferenceChange(TodoDropItemFramePreferenceKey.self) { value in
                itemFrames = value
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
        )
        .onChange(of: todoItems.map(\.id)) { _, _ in
            dropState = .none
        }
    }

    private func addNewItem() {
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

    private func createNewItemAfter(_ item: TodoItem) {
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

struct LongTermInsertionIndicator: View {
    let indentLevel: Int
    let indentWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 20 + CGFloat(indentLevel) * indentWidth)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .frame(height: 4)
        .transition(.opacity)
    }
}

#Preview {
    LongTermListView()
        .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
