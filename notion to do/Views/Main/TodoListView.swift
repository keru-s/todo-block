//
//  TodoListView.swift
//  notion to do
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    
    let year: Int
    let month: Int
    
    @State private var focusedItemId: UUID?
    @State private var selectedItemIds: Set<UUID> = []
    @State private var lastSelectedId: UUID?  // 用于 Shift+Click 范围选择
    
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
                                focusedItemId: $focusedItemId,
                                selectedItemIds: $selectedItemIds,
                                lastSelectedId: $lastSelectedId,
                                onItemCreated: { itemId in
                                    scrollToItem(itemId, proxy: proxy)
                                },
                                onDeleteSelected: deleteSelectedItems
                            )
                            .id(section.id)
                        }
                    }
                    .padding()
                }
                
                // 底部添加按钮
                HStack {
                    Button(action: { addTodaySection(proxy: proxy) }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("添加一个今日待办")
                        }
                        .foregroundColor(.pink)
                        .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    Spacer()
                    
                    // 显示选中数量
                    if selectedItemIds.count > 1 {
                        Text("已选 \(selectedItemIds.count) 项")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 12)
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
            .onChange(of: focusedItemId) { _, newValue in
                if let itemId = newValue {
                    scrollToItem(itemId, proxy: proxy)
                    // 同步选择状态：focusedItemId 变化时自动更新 selectedItemIds
                    if selectedItemIds.count <= 1 {
                        selectedItemIds = [itemId]
                        lastSelectedId = itemId
                    }
                }
            }
        }
    }
    
    private func addTodaySection(proxy: ScrollViewProxy) {
        let section = store.getOrCreateTodaySection()
        let newItem = store.createItem(dayDate: section.date)
        focusedItemId = newItem.id
        selectedItemIds = [newItem.id]
        lastSelectedId = newItem.id
        scrollToItem(newItem.id, proxy: proxy)
    }
    
    private func scrollToItem(_ itemId: UUID, proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(itemId, anchor: .center)
            }
        }
    }
    
    private func deleteSelectedItems() {
        guard !selectedItemIds.isEmpty else { return }
        
        let itemsToDelete = selectedItemIds.compactMap { id in
            store.todoItemsCache[id]
        }
        
        // 计算下一个焦点
        var nextFocusId: UUID? = nil
        if let firstItem = itemsToDelete.first {
            let allItems = store.items(for: firstItem.dayDate)
            if let firstIndex = allItems.firstIndex(where: { $0.id == firstItem.id }) {
                for i in stride(from: firstIndex - 1, through: 0, by: -1) {
                    if !selectedItemIds.contains(allItems[i].id) {
                        nextFocusId = allItems[i].id
                        break
                    }
                }
                if nextFocusId == nil {
                    for i in (firstIndex + 1)..<allItems.count {
                        if !selectedItemIds.contains(allItems[i].id) {
                            nextFocusId = allItems[i].id
                            break
                        }
                    }
                }
            }
        }
        
        for item in itemsToDelete {
            store.deleteItem(item)
        }
        
        selectedItemIds.removeAll()
        lastSelectedId = nextFocusId
        focusedItemId = nextFocusId
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)
    
    TodoStore.shared.initialize(with: container.mainContext)
    
    return TodoListView(year: 2026, month: 1)
        .modelContainer(container)
}
