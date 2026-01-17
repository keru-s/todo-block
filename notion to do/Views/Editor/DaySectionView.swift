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
    @Bindable var selectionManager: SelectionManager
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
                        focusedItemId: $selectionManager.focusedItemId,
                        isSelected: selectionManager.selectedItemIds.contains(item.id),
                        hasMultipleSelection: selectionManager.selectedItemIds.count > 1,
                        onSelect: { shiftPressed in
                            selectionManager.handleSelect(item: item, allItems: todoItems, shiftPressed: shiftPressed)
                        },
                        onFocus: { shiftPressed in
                            selectionManager.handleSelect(item: item, allItems: todoItems, shiftPressed: shiftPressed)
                        },
                        onEnterPressed: { createNewItemAfter(item) },
                        onDeletePressed: {
                            // 调用 Manager 的删除逻辑
                            // 我们需要给 Manager 提供上下文，这里只处理当前 Section 的删除
                            // 但如果跨 Section 多选呢？目前 SelectionManager 设计是通用的
                            // 此时我们先简单处理：如果是多选且包含此项，则交给 Manager 删除选中项
                            // 如果是单选（Backsapce 删除空行），也交给 Manager
                            
                            // 修正：TodoItemView 的 onDeletePressed 在 Backspace 且空或者是多选删除时触发
                            if selectionManager.selectedItemIds.contains(item.id) {
                                selectionManager.deleteSelectedItems(store: store) { date in
                                    store.items(for: date)
                                }
                            }
                        },
                        onMoveUp: { selectionManager.moveFocusUp(from: item, allItems: todoItems) },
                        onMoveDown: { selectionManager.moveFocusDown(from: item, allItems: todoItems) }
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
        // 使用 manager 更新选中与焦点
        selectionManager.handleSelect(item: newItem, allItems: store.items(for: section.date), shiftPressed: false)
        onItemCreated?(newItem.id)
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
        selectionManager: SelectionManager()
    )
    .modelContainer(container)
    .padding()
}
