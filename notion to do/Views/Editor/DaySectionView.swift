//
//  DaySectionView.swift
//  notion to do
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct DaySectionView: View {
    @Bindable var section: DaySection
    @Binding var focusedItemId: UUID?
    var onItemCreated: ((UUID) -> Void)?
    
    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFocused: Bool
    
    private var store: TodoStore { TodoStore.shared }
    
    private var todoItems: [TodoItem] {
        store.items(for: section.date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 日期标题
            titleView
            
            // 待办事项列表
            VStack(alignment: .leading, spacing: 0) {
                ForEach(todoItems) { item in
                    TodoItemView(
                        item: item,
                        allItems: todoItems,
                        focusedItemId: $focusedItemId,
                        onEnterPressed: { createNewItemAfter(item) },
                        onDeleteEmpty: { deleteItemAndMoveFocus(item) },
                        onMoveUp: { moveFocusUp(from: item) },
                        onMoveDown: { moveFocusDown(from: item) }
                    )
                    .id(item.id)
                }
            }
        }
    }
    
    private var titleView: some View {
        Group {
            if isEditingTitle {
                TextField("日期标题", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .bold))
                    .focused($isTitleFocused)
                    .onSubmit {
                        section.title = editingTitle
                        isEditingTitle = false
                        store.scheduleSave()
                    }
                    .onExitCommand {
                        isEditingTitle = false
                    }
            } else {
                Text(section.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .onTapGesture {
                        editingTitle = section.title
                        isEditingTitle = true
                        isTitleFocused = true
                    }
            }
        }
        .padding(.bottom, 4)
    }
    
    // MARK: - 操作方法
    
    private func createNewItemAfter(_ item: TodoItem) {
        let newItem = store.createItem(
            dayDate: section.date,
            afterItem: item,
            indentLevel: item.indentLevel
        )
        focusedItemId = newItem.id
        onItemCreated?(newItem.id)
    }
    
    private func deleteItemAndMoveFocus(_ item: TodoItem) {
        // 动态获取当前数组和位置
        let currentItems = todoItems
        guard let currentIndex = currentItems.firstIndex(where: { $0.id == item.id }) else {
            store.deleteItem(item)
            return
        }
        
        // 计算焦点目标（在删除前）
        var nextFocusId: UUID? = nil
        if currentIndex > 0 {
            nextFocusId = currentItems[currentIndex - 1].id
        } else if currentItems.count > 1 {
            nextFocusId = currentItems[1].id
        }
        
        // 先设置焦点
        focusedItemId = nextFocusId
        
        // 从缓存删除（即时响应）
        store.deleteItem(item)
    }
    
    private func moveFocusUp(from item: TodoItem) {
        let items = todoItems
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }),
              currentIndex > 0 else { return }
        focusedItemId = items[currentIndex - 1].id
    }
    
    private func moveFocusDown(from item: TodoItem) {
        let items = todoItems
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }),
              currentIndex + 1 < items.count else { return }
        focusedItemId = items[currentIndex + 1].id
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
        focusedItemId: .constant(nil)
    )
    .modelContainer(container)
    .padding()
}
