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
    var preferredHorizontalOffset: CGFloat? = nil
    var verticalMoveDirection: VerticalMoveDirection? = nil

    // 选择回调
    var onSelect: (Bool) -> Void = { _ in }  // 参数：是否按住 Shift
    var onFocus: (Bool, Int?) -> Void = { _, _ in }  // TextField 获取焦点时调用，参数：是否按住 Shift, 光标位置

    // 回调
    var onEnterPressed: () -> Void
    var onDeletePressed: () -> Void  // 改名：多选时删除全部
    var onMoveUp: (Int, CGFloat?) -> Void
    var onMoveDown: (Int, CGFloat?) -> Void
    var onActivateInteraction: () -> Void = {}

    private var store: TodoStore { TodoStore.shared }

    @State private var isHoveringDragHandle: Bool = false
    @State private var editingText: String = ""
    @State private var shouldFocus: Bool = false
    @State private var refreshId: UUID = UUID()
    @State private var isComposingText: Bool = false

    private var isFocused: Bool {
        focusedItemId == item.id
    }

    private let indentWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
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
        .simultaneousGesture(
            TapGesture()
                .modifiers(.shift)
                .onEnded { _ in
                    onActivateInteraction()
                    onSelect(true)  // Shift+Click
                }
        )
        .onTapGesture {
            onActivateInteraction()
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
            .draggable(item.id.uuidString) {
                dragPreview
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
        CustomTextEditor(
            text: $editingText,
            isCompleted: item.isCompleted,
            shouldFocus: $shouldFocus,
            hasMultipleSelection: hasMultipleSelection,
            cursorPosition: cursorPosition,
            preferredHorizontalOffset: preferredHorizontalOffset,
            verticalMoveDirection: verticalMoveDirection,
            onTab: {
                let oldIndent = item.indentLevel
                item.indent()
                if item.indentLevel != oldIndent {
                    store.registerIndentChange(
                        itemId: item.id, oldIndent: oldIndent, newIndent: item.indentLevel)
                }
                store.scheduleSave()
            },
            onShiftTab: {
                let oldIndent = item.indentLevel
                item.outdent()
                if item.indentLevel != oldIndent {
                    store.registerIndentChange(
                        itemId: item.id, oldIndent: oldIndent, newIndent: item.indentLevel)
                }
                store.scheduleSave()
            },
            onReturn: onEnterPressed,
            onBackspace: onDeletePressed,
            onFocus: { shiftPressed, cursorPosition in
                // TextView 获取焦点时，同步选择状态
                onActivateInteraction()
                onFocus(shiftPressed, cursorPosition)
            },
            onCompositionChange: { composing in
                isComposingText = composing
            },
            onUpArrow: { position, horizontalOffset in
                onMoveUp(position, horizontalOffset)
            },
            onDownArrow: { position, horizontalOffset in
                onMoveDown(position, horizontalOffset)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if editingText.isEmpty && isComposingText == false {
                Text("待办事项")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
        .id(refreshId)
        .onChange(of: item.title) { _, newValue in
            // 实时响应外部（如菜单栏）的修改
            if editingText != newValue {
                editingText = newValue
            }
        }
        .onChange(of: editingText) { _, newValue in
            // 文本编辑使用 TextField 原生撤销功能，此处只负责同步数据
            item.title = newValue
            store.scheduleSave()
        }
    }

    // MARK: - 操作

    private func toggleComplete() {
        store.toggleComplete(item)
    }
}

// MARK: - 自定义 TextEditor（支持多行 + 完整键盘控制）

struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isCompleted: Bool
    @Binding var shouldFocus: Bool
    var hasMultipleSelection: Bool = false  // 多选状态
    var cursorPosition: Int = 0  // 光标位置
    var preferredHorizontalOffset: CGFloat? = nil
    var verticalMoveDirection: VerticalMoveDirection? = nil

    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onReturn: () -> Void
    var onBackspace: () -> Void
    var onFocus: (Bool, Int?) -> Void = { _, _ in }  // TextView 获取焦点时调用，参数：是否按住 Shift, 光标位置
    var onCompositionChange: (Bool) -> Void = { _ in }
    var onUpArrow: (Int, CGFloat?) -> Void  // 参数：当前光标位置、水平偏移
    var onDownArrow: (Int, CGFloat?) -> Void  // 参数：当前光标位置、水平偏移

    func makeNSView(context: Context) -> CustomNSTextView {
        let textView = CustomNSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: 14)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.usesFindPanel = false
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true
        textView.customCoordinator = context.coordinator

        textView.onMouseDown = { [self] shiftPressed, cursorPosition in
            self.onFocus(shiftPressed, cursorPosition)
        }
        textView.onCompositionChange = { [self] composing in
            self.onCompositionChange(composing)
        }

        applyStyle(to: textView)

        return textView
    }

    func updateNSView(_ nsView: CustomNSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hasMultipleSelection = hasMultipleSelection
        onCompositionChange(nsView.isComposingText)

        if context.coordinator.isApplyingProgrammaticText == false,
            nsView.isComposingText == false,
            nsView.string != text
        {
            context.coordinator.isApplyingProgrammaticText = true
            nsView.string = text
            context.coordinator.isApplyingProgrammaticText = false
        }
        if nsView.isComposingText == false {
            applyStyle(to: nsView)
        }

        if shouldFocus {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    window.makeFirstResponder(nsView)
                    if let direction = self.verticalMoveDirection,
                        let horizontalOffset = self.preferredHorizontalOffset
                    {
                        let pos = nsView.closestCharacterIndexForVerticalMove(
                            horizontalOffset: horizontalOffset,
                            direction: direction
                        )
                        nsView.setSelectedRange(NSRange(location: pos, length: 0))
                    } else {
                        let textLength = (nsView.string as NSString).length
                        let pos = min(self.cursorPosition, textLength)
                        nsView.setSelectedRange(NSRange(location: pos, length: 0))
                    }
                    self.shouldFocus = false
                }
            }
        }

        DispatchQueue.main.async {
            nsView.invalidateIntrinsicContentSize()
        }
    }

    private func applyStyle(to textView: NSTextView) {
        let currentText = textView.string
        let range = NSRange(location: 0, length: currentText.count)

        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributes(
            [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: isCompleted ? NSColor.gray : NSColor.labelColor,
                .strikethroughStyle: isCompleted ? NSUnderlineStyle.single.rawValue : 0,
            ],
            range: range
        )
        textView.textStorage?.endEditing()
        textView.insertionPointColor = isCompleted ? .gray : .labelColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        var hasMultipleSelection: Bool = false
        var isApplyingProgrammaticText: Bool = false

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            self.hasMultipleSelection = parent.hasMultipleSelection
        }

        func textDidChange(_ notification: Notification) {
            guard isApplyingProgrammaticText == false,
                let textView = notification.object as? NSTextView
            else { return }
            parent.text = textView.string
            parent.onCompositionChange((textView as? CustomNSTextView)?.isComposingText == true)
        }

        func textDidBeginEditing(_ notification: Notification) {
            if let textView = notification.object as? CustomNSTextView {
                parent.onCompositionChange(textView.isComposingText)
                if textView.isComposingText == false {
                    parent.applyStyle(to: textView)
                }
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if let textView = notification.object as? CustomNSTextView {
                parent.onCompositionChange(false)
                DispatchQueue.main.async {
                    if textView.isComposingText == false {
                        self.parent.applyStyle(to: textView)
                    }
                }
            }
        }

        func handleCommand(in textView: NSTextView, commandSelector: Selector) -> Bool {
            // 输入法组合输入阶段，交给系统处理，避免吞拼音/候选词
            if let customTextView = textView as? CustomNSTextView, customTextView.isComposingText {
                return false
            }

            if commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                if modifiers.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
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
                let location = textView.selectedRange().location
                if isOnFirstVisualLine(in: textView) {
                    let horizontalOffset = preferredHorizontalOffsetInWindow(in: textView)
                    parent.onUpArrow(location, horizontalOffset)
                    return true
                }
                return false
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                let location = textView.selectedRange().location
                if isOnLastVisualLine(in: textView) {
                    let horizontalOffset = preferredHorizontalOffsetInWindow(in: textView)
                    parent.onDownArrow(location, horizontalOffset)
                    return true
                }
                return false
            }

            return false
        }

        private func isOnFirstVisualLine(in textView: NSTextView) -> Bool {
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else { return true }

            layoutManager.ensureLayout(for: textContainer)

            let selectedLocation = textView.selectedRange().location
            let nsText = textView.string as NSString
            if nsText.length == 0 { return true }

            let characterIndex = min(max(0, selectedLocation), nsText.length - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)

            var lineRange = NSRange(location: 0, length: 0)
            _ = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            return lineRange.location == 0
        }

        private func isOnLastVisualLine(in textView: NSTextView) -> Bool {
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else { return true }

            layoutManager.ensureLayout(for: textContainer)

            let selectedLocation = textView.selectedRange().location
            let nsText = textView.string as NSString
            if nsText.length == 0 { return true }

            let characterIndex = min(max(0, selectedLocation), nsText.length - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)

            var lineRange = NSRange(location: 0, length: 0)
            _ = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            return NSMaxRange(lineRange) >= layoutManager.numberOfGlyphs
        }

        private func preferredHorizontalOffset(in textView: NSTextView) -> CGFloat {
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else { return 0 }

            layoutManager.ensureLayout(for: textContainer)

            let selectedLocation = textView.selectedRange().location
            let nsText = textView.string as NSString
            if nsText.length == 0 { return 0 }

            let characterIndex = min(max(0, selectedLocation), nsText.length)

            if characterIndex == nsText.length {
                let lastGlyph = max(0, layoutManager.numberOfGlyphs - 1)
                let lastRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: lastGlyph, length: 1),
                    in: textContainer
                )
                return lastRect.maxX
            }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            let rect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            return rect.minX
        }

        private func preferredHorizontalOffsetInWindow(in textView: NSTextView) -> CGFloat {
            let localX = preferredHorizontalOffset(in: textView) + textView.textContainerInset.width
            guard let textViewAsView = textView as? NSView else { return localX }
            let pointInWindow = textViewAsView.convert(NSPoint(x: localX, y: 0), to: nil)
            return pointInWindow.x
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            handleCommand(in: textView, commandSelector: commandSelector)
        }
    }
}

class CustomNSTextView: NSTextView {
    weak var customCoordinator: CustomTextEditor.Coordinator?
    var onMouseDown: ((Bool, Int?) -> Void)?  // 参数：是否按住 Shift, 光标位置
    var onCompositionChange: ((Bool) -> Void)?
    var isComposingText: Bool {
        hasMarkedText()
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 28)
        }
        layoutManager.ensureLayout(for: textContainer)
        let contentHeight = layoutManager.usedRect(for: textContainer).height
        let minHeight: CGFloat = 22
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(minHeight, ceil(contentHeight + textContainerInset.height * 2))
        )
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        let shiftPressed = event.modifierFlags.contains(.shift)
        var cursorPosition: Int? = nil
        cursorPosition = selectedRange().location

        onMouseDown?(shiftPressed, cursorPosition)
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionChange?(true)
    }

    override func unmarkText() {
        super.unmarkText()
        onCompositionChange?(false)
    }

    override func doCommand(by commandSelector: Selector) {
        if let handled = customCoordinator?.handleCommand(in: self, commandSelector: commandSelector),
            handled
        {
            return
        }
        super.doCommand(by: commandSelector)
    }

    func closestCharacterIndexForVerticalMove(
        horizontalOffset: CGFloat,
        direction: VerticalMoveDirection
    ) -> Int {
        guard let layoutManager = layoutManager,
            let textContainer = textContainer
        else { return 0 }

        layoutManager.ensureLayout(for: textContainer)

        let textLength = (string as NSString).length
        if textLength == 0 || layoutManager.numberOfGlyphs == 0 {
            return 0
        }

        let targetGlyph: Int
        switch direction {
        case .up:
            targetGlyph = max(0, layoutManager.numberOfGlyphs - 1)
        case .down:
            targetGlyph = 0
        }

        var lineRange = NSRange(location: 0, length: 0)
        let lineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: targetGlyph,
            effectiveRange: &lineRange,
            withoutAdditionalLayout: true
        )

        let localPointFromWindow = convert(NSPoint(x: horizontalOffset, y: 0), from: nil)
        let point = NSPoint(
            x: localPointFromWindow.x,
            y: lineRect.midY + textContainerInset.height
        )

        let index = characterIndexForInsertion(at: point)
        return min(max(0, index), textLength)
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
            onMoveUp: { _, _ in },
            onMoveDown: { _, _ in }
        )
        .modelContainer(container)
        .padding()
    }
}
