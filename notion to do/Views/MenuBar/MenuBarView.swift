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
    @Environment(\.openWindow) private var openWindow
    
    private var store: TodoStore { TodoStore.shared }
    
    // 状态管理
    @State private var selectionManager = SelectionManager()
    
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
                                focusedItemId: $selectionManager.focusedItemId,
                                isSelected: selectionManager.selectedItemIds.contains(item.id),
                                hasMultipleSelection: selectionManager.selectedItemIds.count > 1,
                                onSelect: { shiftPressed in
                                    selectionManager.handleSelect(item: item, allItems: todayItems, shiftPressed: shiftPressed)
                                },
                                onFocus: { shiftPressed in
                                    selectionManager.handleSelect(item: item, allItems: todayItems, shiftPressed: shiftPressed)
                                },
                                onEnterPressed: { createNewItemAfter(item) },
                                onDeletePressed: {
                                    if selectionManager.selectedItemIds.contains(item.id) {
                                        selectionManager.deleteSelectedItems(store: store) { _ in
                                            // 菜单栏只显示今日，所以上下文总是 todayItems
                                            return todayItems
                                        }
                                    }
                                },
                                onMoveUp: { selectionManager.moveFocusUp(from: item, allItems: todayItems) },
                                onMoveDown: { selectionManager.moveFocusDown(from: item, allItems: todayItems) }
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
        }
        .onTapGesture {
            // 点击空白处取消选择
            selectionManager.clearSelection()
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
        selectionManager.handleSelect(item: newItem, allItems: todayItems, shiftPressed: false)
    }
    
    private func createNewItemAfter(_ item: TodoItem) {
        // 创建新项
        let newItem = store.createItem(
            dayDate: Date(),
            afterItem: item,
            indentLevel: item.indentLevel
        )
        selectionManager.handleSelect(item: newItem, allItems: todayItems, shiftPressed: false)
    }
}

#Preview {
    MenuBarView()
        .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
