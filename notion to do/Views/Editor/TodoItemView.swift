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
    @State private var shouldFocus: Bool = false
    @State private var refreshId: UUID = UUID()  // 用于强制刷新
    
    private var isFocused: Bool {
        focusedItemId == item.id
    }
    
    private let indentWidth: CGFloat = 24
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
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
        .onChange(of: focusedItemId) { oldValue, newValue in
            if newValue == item.id {
                editingText = item.title
                // 延迟一帧触发焦点
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    shouldFocus = true
                }
            } else if oldValue == item.id {
                shouldFocus = false
            }
        }
        .onChange(of: item.isCompleted) { _, _ in
            // 完成状态变化时强制刷新
            refreshId = UUID()
        }
        .onAppear {
            editingText = item.title
            if isFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldFocus = true
                }
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
            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundColor(item.isCompleted ? .green : .gray)
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .padding(.trailing, 6)
    }
    
    private var textFieldView: some View {
        CustomTextField(
            text: $editingText,
            placeholder: "待办事项",
            isCompleted: item.isCompleted,
            shouldFocus: $shouldFocus,
            onTab: {
                item.indent()
                dataService.scheduleSave()
            },
            onShiftTab: {
                item.outdent()
                dataService.scheduleSave()
            },
            onReturn: onEnterPressed,
            onBackspaceEmpty: onDeleteEmpty,
            onUpArrow: onMoveUp,
            onDownArrow: onMoveDown
        )
        .id(refreshId)  // 强制刷新
        .onChange(of: editingText) { _, newValue in
            item.title = newValue
            dataService.scheduleSave()
        }
    }
    
    // MARK: - 操作
    
    private func toggleComplete() {
        dataService.toggleComplete(item, allItems: allItems)
    }
}

// MARK: - 自定义 TextField（支持完整键盘控制）

struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isCompleted: Bool
    @Binding var shouldFocus: Bool
    
    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onReturn: () -> Void
    var onBackspaceEmpty: () -> Void
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = CustomNSTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 14)
        textField.customCoordinator = context.coordinator
        textField.allowsEditingTextAttributes = true  // 允许编辑时保持富文本属性
        
        // 初始化样式
        applyStyle(to: textField)
        
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        let isEditing = nsView.currentEditor() != nil
        
        // 更新文本（仅在非编辑状态或文本不同时）
        if !isEditing && nsView.stringValue != text {
            nsView.stringValue = text
        }
        
        // 始终更新样式
        applyStyle(to: nsView)
        
        // 处理焦点
        if shouldFocus {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    window.makeFirstResponder(nsView)
                    self.shouldFocus = false
                }
            }
        }
    }
    
    private func applyStyle(to textField: NSTextField) {
        let currentText = textField.stringValue
        
        if isCompleted {
            // 已完成状态：灰色 + 中划线
            let attributedString = NSMutableAttributedString(string: currentText)
            let range = NSRange(location: 0, length: currentText.count)
            attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            attributedString.addAttribute(.foregroundColor, value: NSColor.gray, range: range)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: range)
            textField.attributedStringValue = attributedString
        } else {
            // 未完成状态：正常颜色，无中划线
            let attributedString = NSMutableAttributedString(string: currentText)
            let range = NSRange(location: 0, length: currentText.count)
            attributedString.addAttribute(.strikethroughStyle, value: 0, range: range)
            attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: range)
            textField.attributedStringValue = attributedString
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomTextField
        private var styleTimer: Timer?
        
        init(_ parent: CustomTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
                // 编辑时实时更新样式
                applyEditorStyle(textField: textField)
            }
        }
        
        func controlTextDidBeginEditing(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                applyEditorStyle(textField: textField)
            }
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                DispatchQueue.main.async {
                    self.parent.applyStyle(to: textField)
                }
            }
        }
        
        private func applyEditorStyle(textField: NSTextField) {
            guard let editor = textField.currentEditor() as? NSTextView else { return }
            
            let text = editor.string
            let range = NSRange(location: 0, length: text.count)
            
            if parent.isCompleted {
                // 已完成状态：灰色 + 中划线
                editor.textStorage?.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                editor.textStorage?.addAttribute(.foregroundColor, value: NSColor.gray, range: range)
                editor.insertionPointColor = .gray
            } else {
                // 未完成状态：正常颜色
                editor.textStorage?.addAttribute(.strikethroughStyle, value: 0, range: range)
                editor.textStorage?.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                editor.insertionPointColor = .labelColor
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onReturn()
                return true
            }
            
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                if parent.text.isEmpty {
                    parent.onBackspaceEmpty()
                    return true
                }
                return false
            }
            
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            }
            
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onShiftTab()
                return true
            }
            
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUpArrow()
                return true
            }
            
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDownArrow()
                return true
            }
            
            return false
        }
    }
}

class CustomNSTextField: NSTextField {
    weak var customCoordinator: CustomTextField.Coordinator?
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
