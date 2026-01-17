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
    @Binding var selectedItemIds: Set<UUID>
    @Binding var lastSelectedId: UUID?
    var onItemCreated: ((UUID) -> Void)?
    var onDeleteSelected: () -> Void
    
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
                        isSelected: selectedItemIds.contains(item.id),
                        hasMultipleSelection: selectedItemIds.count > 1,
                        onSelect: { shiftPressed in
                            handleSelect(item: item, shiftPressed: shiftPressed)
                        },
                        onFocus: { shiftPressed in
                            // TextField 获取焦点时，同步选择状态
                            handleSelect(item: item, shiftPressed: shiftPressed)
                        },
                        onEnterPressed: { createNewItemAfter(item) },
                        onDeletePressed: { 
                            // 多选时直接删除所有选中项
                            if selectedItemIds.count > 1 {
                                onDeleteSelected()
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
    
    // MARK: - 选择操作
    
    private func handleSelect(item: TodoItem, shiftPressed: Bool) {
        if shiftPressed, let lastId = lastSelectedId {
            // Shift+Click: 范围选择
            let items = todoItems
            if let startIndex = items.firstIndex(where: { $0.id == lastId }),
               let endIndex = items.firstIndex(where: { $0.id == item.id }) {
                let range = min(startIndex, endIndex)...max(startIndex, endIndex)
                for i in range {
                    selectedItemIds.insert(items[i].id)
                }
            }
        } else {
            // 普通点击：单选
            selectedItemIds = [item.id]
            lastSelectedId = item.id
        }
        focusedItemId = item.id
    }
    
    // MARK: - 操作方法
    
    private func createNewItemAfter(_ item: TodoItem) {
        let newItem = store.createItem(
            dayDate: section.date,
            afterItem: item,
            indentLevel: item.indentLevel
        )
        focusedItemId = newItem.id
        selectedItemIds = [newItem.id]
        lastSelectedId = newItem.id
        onItemCreated?(newItem.id)
    }
    
    private func deleteItemAndMoveFocus(_ item: TodoItem) {
        let currentItems = todoItems
        guard let currentIndex = currentItems.firstIndex(where: { $0.id == item.id }) else {
            store.deleteItem(item)
            return
        }
        
        var nextFocusId: UUID? = nil
        if currentIndex > 0 {
            nextFocusId = currentItems[currentIndex - 1].id
        } else if currentItems.count > 1 {
            nextFocusId = currentItems[1].id
        }
        
        focusedItemId = nextFocusId
        if let nextId = nextFocusId {
            selectedItemIds = [nextId]
            lastSelectedId = nextId
        } else {
            selectedItemIds.removeAll()
        }
        
        store.deleteItem(item)
    }
    
    private func moveFocusUp(from item: TodoItem) {
        let items = todoItems
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }),
              currentIndex > 0 else { return }
        let targetId = items[currentIndex - 1].id
        focusedItemId = targetId
        selectedItemIds = [targetId]
        lastSelectedId = targetId
    }
    
    private func moveFocusDown(from item: TodoItem) {
        let items = todoItems
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }),
              currentIndex + 1 < items.count else { return }
        let targetId = items[currentIndex + 1].id
        focusedItemId = targetId
        selectedItemIds = [targetId]
        lastSelectedId = targetId
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
        focusedItemId: .constant(nil),
        selectedItemIds: .constant([]),
        lastSelectedId: .constant(nil),
        onDeleteSelected: {}
    )
    .modelContainer(container)
    .padding()
}
