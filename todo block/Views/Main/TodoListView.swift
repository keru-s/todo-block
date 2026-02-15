//
//  TodoListView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    
    let year: Int
    let month: Int
    
    @State private var selectionManager = SelectionManager()
    
    private var store: TodoStore { TodoStore.shared }
    
    private var daySections: [DaySection] {
        store.sections(year: year, month: month)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(daySections) { section in
                            DaySectionView(
                                section: section,
                                selectionManager: selectionManager,
                                onItemCreated: { itemId in
                                    scrollToItem(itemId, proxy: proxy)
                                },
                                onInteraction: {
                                    activateClipboardContext()
                                }
                            )
                            .id(section.id)
                        }
                    }
                    .padding()
                }
                .onTapGesture {
                    activateClipboardContext()
                    // 点击空白处取消选择
                    selectionManager.clearSelection()
                }
                
                // 底部添加按钮
                HStack {
                    Button(action: { addTodaySection(proxy: proxy) }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("添加一个今日待办")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    Spacer()
                    
                    // 显示选中数量
                    if selectionManager.selectedItemIds.count > 1 {
                        Text("已选 \(selectionManager.selectedItemIds.count) 项")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 12)
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
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
    }
    
    private func addTodaySection(proxy: ScrollViewProxy) {
        activateClipboardContext()
        let section = store.getOrCreateTodaySection()
        let newItem = store.createItem(dayDate: section.date)
        selectionManager.handleSelect(item: newItem, allItems: store.items(for: section.date), shiftPressed: false)
        scrollToItem(newItem.id, proxy: proxy)
    }
    
    private func scrollToItem(_ itemId: UUID, proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(itemId, anchor: .center)
            }
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
            if Calendar.current.isDate(lhs.dayDate, inSameDayAs: rhs.dayDate) {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.dayDate < rhs.dayDate
        }
    }

    private func resolvePasteTarget() -> (dayDate: Date, afterItem: TodoItem?, baseIndentLevel: Int) {
        if
            let focusedItemId = selectionManager.focusedItemId,
            let focusedItem = store.todoItemsCache[focusedItemId]
        {
            return (focusedItem.dayDate, focusedItem, focusedItem.indentLevel)
        }

        let selectedItems = sortItemsForListOrder(
            selectionManager.selectedItemIds.compactMap { store.todoItemsCache[$0] }
        )
        if let lastSelectedItem = selectedItems.last {
            return (lastSelectedItem.dayDate, lastSelectedItem, lastSelectedItem.indentLevel)
        }

        if let topSection = daySections.first {
            let sectionItems = store.items(for: topSection.date)
            return (topSection.date, sectionItems.last, 0)
        }

        let todaySection = store.getOrCreateTodaySection()
        let todayItems = store.items(for: todaySection.date)
        return (todaySection.date, todayItems.last, 0)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)
    
    TodoStore.shared.initialize(with: container.mainContext)
    
    return TodoListView(year: 2026, month: 1)
        .modelContainer(container)
}
