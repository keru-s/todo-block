//
//  MenuBarView.swift
//  notion to do
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    
    private var store: TodoStore { TodoStore.shared }
    
    // 状态管理
    @State private var focusedItemId: UUID?
    @State private var selectedItemIds: Set<UUID> = []
    @State private var lastSelectedId: UUID?
    @State private var isDragSelecting: Bool = false
    
    private var todayItems: [TodoItem] {
        store.todayItems()
    }
    
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
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(todayItems) { item in
                            TodoItemView(
                                item: item,
                                allItems: todayItems,
                                focusedItemId: $focusedItemId,
                                isSelected: selectedItemIds.contains(item.id),
                                hasMultipleSelection: selectedItemIds.count > 1,
                                onSelect: { shiftPressed in
                                    handleSelect(item: item, shiftPressed: shiftPressed)
                                },
                                onFocus: { shiftPressed in
                                    handleSelect(item: item, shiftPressed: shiftPressed)
                                },
                                onEnterPressed: { createNewItemAfter(item) },
                                onDeletePressed: {
                                    if selectedItemIds.count > 1 {
                                        deleteSelectedItems()
                                    } else {
                                        deleteItemAndMoveFocus(item)
                                    }
                                },
                                onMoveUp: { moveFocusUp(from: item) },
                                onMoveDown: { moveFocusDown(from: item) }
                            )
                            .id(item.id)
                        }
                    }
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
                .foregroundColor(.pink)
                
                Spacer()
                
                if selectedItemIds.count > 1 {
                    Text("已选 \(selectedItemIds.count) 项")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.trailing, 8)
                }
                
                Button("打开应用") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title.contains("notion") || $0.isKeyWindow == false }) {
                        window.makeKeyAndOrderFront(nil)
                    }
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
        }
        // 点击空白处取消选择
        .onTapGesture {
            if selectedItemIds.count > 1 {
                selectedItemIds.removeAll()
            }
        }
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
        _ = store.getOrCreateTodaySection()
        let newItem = store.createItem(dayDate: Date())
        focusedItemId = newItem.id
        selectedItemIds = [newItem.id]
        lastSelectedId = newItem.id
    }
    
    private func handleSelect(item: TodoItem, shiftPressed: Bool) {
        if shiftPressed, let lastId = lastSelectedId {
            let items = todayItems
            if let startIndex = items.firstIndex(where: { $0.id == lastId }),
               let endIndex = items.firstIndex(where: { $0.id == item.id }) {
                let range = min(startIndex, endIndex)...max(startIndex, endIndex)
                for i in range {
                    selectedItemIds.insert(items[i].id)
                }
            }
        } else {
            selectedItemIds = [item.id]
            lastSelectedId = item.id
        }
        focusedItemId = item.id
    }
    
    private func createNewItemAfter(_ item: TodoItem) {
        // 创建新项
        let newItem = store.createItem(
            dayDate: Date(),
            afterItem: item,
            indentLevel: item.indentLevel
        )
        focusedItemId = newItem.id
        selectedItemIds = [newItem.id]
        lastSelectedId = newItem.id
    }
    
    private func deleteItemAndMoveFocus(_ item: TodoItem) {
        let items = todayItems
        var nextFocusId: UUID? = nil
        
        if let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
            if currentIndex > 0 {
                nextFocusId = items[currentIndex - 1].id
            } else if items.count > 1 {
                nextFocusId = items[1].id
            }
        }
        
        store.deleteItem(item)
        focusedItemId = nextFocusId
        if let nextId = nextFocusId {
            selectedItemIds = [nextId]
            lastSelectedId = nextId
        } else {
            selectedItemIds.removeAll()
        }
    }
    
    private func deleteSelectedItems() {
        guard !selectedItemIds.isEmpty else { return }
        let itemsToDelete = selectedItemIds.compactMap { id in
            store.todoItemsCache[id]
        }
        
        // 计算删除后的焦点
        var nextFocusId: UUID? = nil
        if let firstItem = itemsToDelete.first {
            let items = todayItems
            if let firstIndex = items.firstIndex(where: { $0.id == firstItem.id }) {
                // 尝试找上面的
                for i in stride(from: firstIndex - 1, through: 0, by: -1) {
                    if !selectedItemIds.contains(items[i].id) {
                        nextFocusId = items[i].id
                        break
                    }
                }
                // 没上面的找下面的
                if nextFocusId == nil {
                    for i in (firstIndex + 1)..<items.count {
                        if !selectedItemIds.contains(items[i].id) {
                            nextFocusId = items[i].id
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
        focusedItemId = nextFocusId
        if let nextId = nextFocusId {
            selectedItemIds = [nextId]
            lastSelectedId = nextId
        }
    }
    
    private func moveFocusUp(from item: TodoItem) {
        let items = todayItems
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }),
              currentIndex > 0 else { return }
        let targetId = items[currentIndex - 1].id
        focusedItemId = targetId
        selectedItemIds = [targetId]
        lastSelectedId = targetId
    }
    
    private func moveFocusDown(from item: TodoItem) {
        let items = todayItems
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }),
              currentIndex + 1 < items.count else { return }
        let targetId = items[currentIndex + 1].id
        focusedItemId = targetId
        selectedItemIds = [targetId]
        lastSelectedId = targetId
    }
}

#Preview {
    MenuBarView()
        .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
