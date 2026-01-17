//
//  TodoItemView.swift
//  notion to do
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct TodoItemView: View {
    @Bindable var item: TodoItem
    let allItems: [TodoItem]
    var dataService: TodoDataService
    @Binding var focusedItemId: UUID?
    
    // 回调
    var onEnterPressed: () -> Void
    var onDeleteEmpty: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    
    @State private var isHoveringDragHandle: Bool = false
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    private var isFocused: Bool {
        focusedItemId == item.id
    }
    
    private let indentWidth: CGFloat = 24
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 拖拽句柄
            dragHandle
            
            // 缩进
            if item.indentLevel > 0 {
                Spacer()
                    .frame(width: CGFloat(item.indentLevel) * indentWidth)
            }
            
            // 勾选框
            checkboxView
            
            // 文本编辑区
            textFieldView
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedItemId = item.id
        }
        .onChange(of: focusedItemId) { _, newValue in
            if newValue == item.id {
                editingText = item.title
                isTextFieldFocused = true
            }
        }
        .onAppear {
            editingText = item.title
            if isFocused {
                isTextFieldFocused = true
            }
        }
    }
    
    // MARK: - 子视图
    
    private var dragHandle: some View {
        Rectangle()
            .fill(isHoveringDragHandle ? Color.gray.opacity(0.5) : Color.clear)
            .frame(width: 20, height: 20)
            .overlay {
                if isHoveringDragHandle {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .onHover { hovering in
                isHoveringDragHandle = hovering
            }
            .draggable(item.id.uuidString) {
                Text(item.title.isEmpty ? "待办事项" : item.title)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(4)
                    .shadow(radius: 2)
            }
    }
    
    private var checkboxView: some View {
        Button(action: toggleComplete) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundColor(item.isCompleted ? .green : .gray)
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
    }
    
    private var textFieldView: some View {
        TextField("待办事项", text: $editingText)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .strikethrough(item.isCompleted, color: .gray)
            .foregroundColor(item.isCompleted ? .gray : .primary)
            .focused($isTextFieldFocused)
            .onChange(of: editingText) { _, newValue in
                item.title = newValue
                dataService.scheduleSave()
            }
            .onKeyPress(.return) {
                onEnterPressed()
                return .handled
            }
            .onKeyPress(.delete) {
                if editingText.isEmpty {
                    onDeleteEmpty()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(phases: .down) { keyPress in
                if keyPress.key == .tab {
                    if keyPress.modifiers.contains(.shift) {
                        item.outdent()
                    } else {
                        item.indent()
                    }
                    dataService.scheduleSave()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.upArrow) {
                onMoveUp()
                return .handled
            }
            .onKeyPress(.downArrow) {
                onMoveDown()
                return .handled
            }
    }
    
    // MARK: - 操作
    
    private func toggleComplete() {
        dataService.toggleComplete(item, allItems: allItems)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)
    
    let item = TodoItem(title: "测试待办事项", indentLevel: 0)
    container.mainContext.insert(item)
    
    let dataService = TodoDataService(modelContext: container.mainContext)
    
    return TodoItemView(
        item: item,
        allItems: [item],
        dataService: dataService,
        focusedItemId: .constant(item.id),
        onEnterPressed: {},
        onDeleteEmpty: {},
        onMoveUp: {},
        onMoveDown: {}
    )
    .modelContainer(container)
    .padding()
}
