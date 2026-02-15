//
//  MenuBarView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    private var store: TodoStore { TodoStore.shared }

    // 状态管理
    @State private var selectionManager = SelectionManager()
    @State private var dropState: TodoListDropState = .none
    @State private var itemFrames: [UUID: CGRect] = [:]

    private var todayItems: [TodoItem] {
        store.todayItems()
    }

    private let indentWidth: CGFloat = 24
    private let itemHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("今日待办")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(formattedToday)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if todayItems.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    todoListView
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 50, maxHeight: 350)
            }

            Divider()

            // 底部操作栏
            HStack {
                Button(action: addTodayItem) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                if selectionManager.selectedItemIds.count > 1 {
                    Text("已选 \(selectionManager.selectedItemIds.count) 项")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.trailing, 8)
                }

                Button("打开应用") {
                    openWindow(id: "mainWindow")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if store.todoItemsCache.isEmpty {
                store.initialize(with: modelContext)
            }
            activateClipboardContext()
        }
        .onTapGesture {
            activateClipboardContext()
            // 点击空白处取消选择
            selectionManager.clearSelection()
        }
        .onChange(of: store.focusRequestId) { _, newValue in
            guard let itemId = newValue, store.todoItemsCache[itemId] != nil else { return }
            activateClipboardContext()
            selectionManager.restoreFocus(to: itemId)
        }
        .onChange(of: todayItems.map(\.id)) { _, _ in
            dropState = .none
            activateClipboardContext()
        }
        .onChange(of: selectionManager.focusedItemId) { _, _ in
            activateClipboardContext()
        }
        .onChange(of: selectionManager.selectedItemIds) { _, _ in
            activateClipboardContext()
        }
    }

    // MARK: - 待办列表（带拖拽支持）

    private var todoListView: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(todayItems.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 0) {
                    // 插入线（在当前项上方）
                    if case .insertAt(let insertIndex, let indentLevel) = dropState,
                        insertIndex == index
                    {
                        insertionIndicator(indentLevel: indentLevel)
                    }

                    TodoItemView(
                        item: item,
                        allItems: todayItems,
                        focusedItemId: $selectionManager.focusedItemId,
                        isSelected: selectionManager.selectedItemIds.contains(item.id),
                        hasMultipleSelection: selectionManager.selectedItemIds.count > 1,
                        cursorPosition: selectionManager.cursorPosition,
                        preferredHorizontalOffset: selectionManager.preferredHorizontalOffset,
                        verticalMoveDirection: selectionManager.verticalMoveDirection,
                        onSelect: { shiftPressed in
                            activateClipboardContext()
                            selectionManager.handleSelect(
                                item: item, allItems: todayItems, shiftPressed: shiftPressed)
                        },
                        onFocus: { shiftPressed, cursorPosition in
                            activateClipboardContext()
                            selectionManager.handleSelect(
                                item: item, allItems: todayItems, shiftPressed: shiftPressed,
                                cursorPosition: cursorPosition)
                        },
                        onEnterPressed: { createNewItemAfter(item) },
                        onDeletePressed: {
                            if selectionManager.selectedItemIds.contains(item.id) {
                                selectionManager.deleteSelectedItems(store: store) { _ in
                                    return todayItems
                                }
                            }
                        },
                        onMoveUp: { position, horizontalOffset in
                            selectionManager.moveFocusUp(
                                from: item,
                                allItems: todayItems,
                                cursorPosition: position,
                                preferredHorizontalOffset: horizontalOffset
                            )
                        },
                        onMoveDown: { position, horizontalOffset in
                            selectionManager.moveFocusDown(
                                from: item,
                                allItems: todayItems,
                                cursorPosition: position,
                                preferredHorizontalOffset: horizontalOffset
                            )
                        },
                        onActivateInteraction: {
                            activateClipboardContext()
                        }
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TodoDropItemFramePreferenceKey.self,
                                value: [item.id: proxy.frame(in: .named("menubar-drop-area"))]
                            )
                        }
                    }
                    .id(item.id)
                }
            }

            // 插入线（在列表末尾）
            if case .insertAt(let insertIndex, let indentLevel) = dropState,
                insertIndex == todayItems.count
            {
                insertionIndicator(indentLevel: indentLevel)
            }
        }
        .onDrop(
            of: [.text],
            delegate: TodoDropDelegate(
                targetDate: Date(),
                todoItems: todayItems,
                store: store,
                dropState: $dropState,
                itemFrames: itemFrames,
                indentWidth: indentWidth,
                itemHeight: itemHeight
            ))
        .coordinateSpace(name: "menubar-drop-area")
        .onPreferenceChange(TodoDropItemFramePreferenceKey.self) { value in
            itemFrames = value
        }
    }

    // MARK: - 插入线指示器

    private func insertionIndicator(indentLevel: Int) -> some View {
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

    private var emptyStateView: some View {
        VStack {
            Text("今天没有待办事项")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            Button("添加待办") {
                addTodayItem()
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - 逻辑操作

    private func addTodayItem() {
        activateClipboardContext()
        _ = store.getOrCreateTodaySection()
        let newItem = store.createItem(dayDate: Date())
        selectionManager.handleSelect(item: newItem, allItems: todayItems, shiftPressed: false)
    }

    private func createNewItemAfter(_ item: TodoItem) {
        activateClipboardContext()
        let newItem = store.createItem(
            dayDate: Date(),
            afterItem: item,
            indentLevel: item.indentLevel
        )
        selectionManager.handleSelect(item: newItem, allItems: todayItems, shiftPressed: false)
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
                indentLevel: entry.indentLevel
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
            lhs.sortOrder < rhs.sortOrder
        }
    }

    private func resolvePasteTarget() -> (dayDate: Date, afterItem: TodoItem?, baseIndentLevel: Int) {
        if
            let focusedItemId = selectionManager.focusedItemId,
            let focusedItem = store.todoItemsCache[focusedItemId],
            Calendar.current.isDateInToday(focusedItem.dayDate)
        {
            return (focusedItem.dayDate, focusedItem, focusedItem.indentLevel)
        }

        let selectedItems = sortItemsForListOrder(
            selectionManager.selectedItemIds.compactMap { store.todoItemsCache[$0] }
        )
        if let lastSelectedItem = selectedItems.last {
            return (lastSelectedItem.dayDate, lastSelectedItem, lastSelectedItem.indentLevel)
        }

        return (Date(), todayItems.last, 0)
    }
}

#Preview {
    MenuBarView()
        .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
