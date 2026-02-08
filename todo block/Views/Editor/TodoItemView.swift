//
//  TodoItemView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI

struct TodoItemView: View {
    @Bindable var item: TodoItem
    let allItems: [TodoItem]
    @Binding var focusedItemId: UUID?
    var isSelected: Bool = false
    var hasMultipleSelection: Bool = false  // 是否处于多选状态
    var cursorPosition: Int = 0  // 光标位置

    // 选择回调
    var onSelect: (Bool) -> Void = { _ in }  // 参数：是否按住 Shift
    var onFocus: (Bool, Int?) -> Void = { _, _ in }  // TextField 获取焦点时调用，参数：是否按住 Shift, 光标位置

    // 回调
    var onEnterPressed: () -> Void
    var onDeletePressed: () -> Void  // 改名：多选时删除全部
    var onMoveUp: (Int) -> Void
    var onMoveDown: (Int) -> Void

    private var store: TodoStore { TodoStore.shared }

    @State private var isHoveringDragHandle: Bool = false
    @State private var editingText: String = ""
    @State private var shouldFocus: Bool = false
    @State private var refreshId: UUID = UUID()

    private var isFocused: Bool {
        focusedItemId == item.id
    }

    private let indentWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 缩进（在拖拽句柄之前，使句柄跟随缩进）
            if item.indentLevel > 0 {
                Spacer()
                    .frame(width: CGFloat(item.indentLevel) * indentWidth)
            }

            // 拖拽句柄
            dragHandle

            // 勾选框
            checkboxView

            // 文本编辑区
            textFieldView
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .draggable(item.id.uuidString) {
            dragPreview
        }
        .simultaneousGesture(
            TapGesture()
                .modifiers(.shift)
                .onEnded { _ in
                    onSelect(true)  // Shift+Click
                }
        )
        .onTapGesture {
            onSelect(false)  // 普通点击
        }
        .onChange(of: focusedItemId) { oldValue, newValue in
            if newValue == item.id {
                editingText = item.title
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    shouldFocus = true
                }
            } else if oldValue == item.id {
                shouldFocus = false
            }
        }
        .onChange(of: item.isCompleted) { _, _ in
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
    }

    private var dragPreview: some View {
        HStack(spacing: 4) {
            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundColor(item.isCompleted ? .green : .gray)
            Text(item.title.isEmpty ? "待办事项" : item.title)
                .font(.system(size: 14))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
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
            hasMultipleSelection: hasMultipleSelection,
            cursorPosition: cursorPosition,
            onTab: {
                item.indent()
                store.scheduleSave()
            },
            onShiftTab: {
                item.outdent()
                store.scheduleSave()
            },
            onReturn: onEnterPressed,
            onBackspace: onDeletePressed,
            onFocus: { shiftPressed, cursorPosition in
                // TextField 获取焦点时，同步选择状态
                onFocus(shiftPressed, cursorPosition)
            },
            onUpArrow: { position in
                onMoveUp(position)
            },
            onDownArrow: { position in
                onMoveDown(position)
            }
        )
        .id(refreshId)
        .onChange(of: item.title) { _, newValue in
            // 实时响应外部（如菜单栏）的修改
            if editingText != newValue {
                editingText = newValue
            }
        }
        .onChange(of: editingText) { _, newValue in
            item.title = newValue
            store.scheduleSave()
        }
    }

    // MARK: - 操作

    private func toggleComplete() {
        store.toggleComplete(item)
    }
}

// MARK: - 自定义 TextField（支持完整键盘控制）

struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isCompleted: Bool
    @Binding var shouldFocus: Bool
    var hasMultipleSelection: Bool = false  // 多选状态
    var cursorPosition: Int = 0  // 光标位置

    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onReturn: () -> Void
    var onBackspace: () -> Void
    var onFocus: (Bool, Int?) -> Void = { _, _ in }  // TextField 获取焦点时调用，参数：是否按住 Shift, 光标位置
    var onUpArrow: (Int) -> Void  // 参数：当前光标位置
    var onDownArrow: (Int) -> Void  // 参数：当前光标位置

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
        textField.allowsEditingTextAttributes = true

        // 点击时立即调用 onFocus，传递 Shift 状态和光标位置
        textField.onMouseDown = { [self] shiftPressed, cursorPosition in
            self.onFocus(shiftPressed, cursorPosition)
        }

        applyStyle(to: textField)

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // 更新 coordinator 的多选状态
        context.coordinator.hasMultipleSelection = hasMultipleSelection

        let isEditing = nsView.currentEditor() != nil

        if !isEditing && nsView.stringValue != text {
            nsView.stringValue = text
        }

        applyStyle(to: nsView)

        if shouldFocus {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    window.makeFirstResponder(nsView)
                    // 设置光标位置而不是全选
                    if let editor = nsView.currentEditor() as? NSTextView {
                        let pos = min(self.cursorPosition, self.text.count)
                        editor.setSelectedRange(NSRange(location: pos, length: 0))
                    }
                    self.shouldFocus = false
                }
            }
        }
    }

    private func applyStyle(to textField: NSTextField) {
        let currentText = textField.stringValue

        if isCompleted {
            let attributedString = NSMutableAttributedString(string: currentText)
            let range = NSRange(location: 0, length: currentText.count)
            attributedString.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            attributedString.addAttribute(.foregroundColor, value: NSColor.gray, range: range)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: range)
            textField.attributedStringValue = attributedString
        } else {
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
        var hasMultipleSelection: Bool = false

        init(_ parent: CustomTextField) {
            self.parent = parent
            self.hasMultipleSelection = parent.hasMultipleSelection
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
                applyEditorStyle(textField: textField)
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                applyEditorStyle(textField: textField)
                // 注意：选择状态同步已在 mouseDown 中处理
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
                editor.textStorage?.addAttribute(
                    .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                editor.textStorage?.addAttribute(
                    .foregroundColor, value: NSColor.gray, range: range)
                editor.insertionPointColor = .gray
            } else {
                editor.textStorage?.addAttribute(.strikethroughStyle, value: 0, range: range)
                editor.textStorage?.addAttribute(
                    .foregroundColor, value: NSColor.labelColor, range: range)
                editor.insertionPointColor = .labelColor
            }
        }

        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onReturn()
                return true
            }

            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                // 多选状态下：直接删除所有选中项
                // 单选状态下：只有文本为空时才删除
                if hasMultipleSelection || parent.text.isEmpty {
                    parent.onBackspace()
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
                // 获取当前光标位置并传递
                if let editor = textView as? NSTextView {
                    let location = editor.selectedRange().location
                    parent.onUpArrow(location)
                } else {
                    parent.onUpArrow(0)
                }
                return true
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                // 获取当前光标位置并传递
                if let editor = textView as? NSTextView {
                    let location = editor.selectedRange().location
                    parent.onDownArrow(location)
                } else {
                    parent.onDownArrow(0)
                }
                return true
            }

            return false
        }
    }
}

class CustomNSTextField: NSTextField {
    weak var customCoordinator: CustomTextField.Coordinator?
    var onMouseDown: ((Bool, Int?) -> Void)?  // 参数：是否按住 Shift, 光标位置

    override func mouseDown(with event: NSEvent) {
        // 先调用 super 让系统处理光标放置
        super.mouseDown(with: event)

        // 获取 Shift 状态
        let shiftPressed = event.modifierFlags.contains(.shift)

        // 获取当前光标位置
        var cursorPosition: Int? = nil
        if let editor = self.currentEditor() as? NSTextView {
            cursorPosition = editor.selectedRange().location
        }

        // 调用回调
        onMouseDown?(shiftPressed, cursorPosition)
    }
}

#Preview {
    PreviewContent()
}

private struct PreviewContent: View {
    let container: ModelContainer
    let item: TodoItem

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)

        item = TodoItem(title: "测试待办事项", indentLevel: 0)
        container.mainContext.insert(item)

        TodoStore.shared.initialize(with: container.mainContext)
    }

    var body: some View {
        TodoItemView(
            item: item,
            allItems: [item],
            focusedItemId: .constant(item.id),
            onEnterPressed: {},
            onDeletePressed: {},
            onMoveUp: { _ in },
            onMoveDown: { _ in }
        )
        .modelContainer(container)
        .padding()
    }
}
