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
    var dataService: TodoDataService
    @Binding var focusedItemId: UUID?
    
    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFocused: Bool
    
    private var todoItems: [TodoItem] {
        dataService.fetchTodoItems(for: section.date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 日期标题
            titleView
            
            // 待办事项列表
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(todoItems.enumerated()), id: \.element.id) { index, item in
                    TodoItemView(
                        item: item,
                        allItems: todoItems,
                        dataService: dataService,
                        focusedItemId: $focusedItemId,
                        onEnterPressed: { createNewItemAfter(item) },
                        onDeleteEmpty: { deleteItemAndMoveFocus(item, at: index) },
                        onMoveUp: { moveFocusUp(from: index) },
                        onMoveDown: { moveFocusDown(from: index) }
                    )
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
                        dataService.scheduleSave()
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
        let newItem = dataService.createTodoItem(
            dayDate: section.date,
            afterItem: item,
            indentLevel: item.indentLevel
        )
        focusedItemId = newItem.id
    }
    
    private func deleteItemAndMoveFocus(_ item: TodoItem, at index: Int) {
        // 先移动焦点到上一个项目
        if index > 0 {
            focusedItemId = todoItems[index - 1].id
        } else if todoItems.count > 1 {
            focusedItemId = todoItems[1].id
        } else {
            focusedItemId = nil
        }
        
        dataService.deleteTodoItem(item)
    }
    
    private func moveFocusUp(from index: Int) {
        if index > 0 {
            focusedItemId = todoItems[index - 1].id
        }
    }
    
    private func moveFocusDown(from index: Int) {
        if index < todoItems.count - 1 {
            focusedItemId = todoItems[index + 1].id
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)
    
    let section = DaySection(date: Date(), title: "01-17")
    container.mainContext.insert(section)
    
    let dataService = TodoDataService(modelContext: container.mainContext)
    
    return DaySectionView(
        section: section,
        dataService: dataService,
        focusedItemId: .constant(nil)
    )
    .modelContainer(container)
    .padding()
}
