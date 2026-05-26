//
//  CustomTextEditor.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import AppKit
import SwiftUI

/// 光标位置感知的 Enter 行为分档。`CustomTextEditor` 在拦截 Return 时
/// 当场读取 selectedRange 算出该走哪一档，外层视图据此决定建项 / 拆项。
enum EnterAction {
    /// 光标在 title 最前方：上方新建同级空 item。
    case insertSiblingAbove
    /// 光标在 title 末尾或 title 为空：保持原行为，下方新建同级空 item。
    case insertSiblingBelow
    /// 光标在中间：当前 item title 截到 `newCurrentTitle`，下方紧邻新建子项 title = `childTitle`。
    case splitIntoChild(newCurrentTitle: String, childTitle: String)
}

struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isCompleted: Bool
    @Binding var shouldFocus: Bool
    var hasMultipleSelection: Bool = false
    var cursorPosition: Int = 0
    var preferredHorizontalOffset: CGFloat? = nil
    var verticalMoveDirection: VerticalMoveDirection? = nil

    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onReturn: (EnterAction) -> Void
    var onBackspace: () -> Void
    var onFocus: (Bool, Int?) -> Void = { _, _ in }
    var onCompositionChange: (Bool) -> Void = { _ in }
    var onUpArrow: (Int, CGFloat?) -> Void
    var onDownArrow: (Int, CGFloat?) -> Void

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
            onFocus(shiftPressed, cursorPosition)
        }
        textView.onCompositionChange = { [self] composing in
            onCompositionChange(composing)
        }

        applyStyle(to: textView, coordinator: context.coordinator, force: true)

        return textView
    }

    func updateNSView(_ nsView: CustomNSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hasMultipleSelection = hasMultipleSelection

        var textWasReplaced = false
        if context.coordinator.isApplyingProgrammaticText == false,
            nsView.isComposingText == false,
            nsView.string != text
        {
            context.coordinator.isApplyingProgrammaticText = true
            nsView.string = text
            context.coordinator.isApplyingProgrammaticText = false
            textWasReplaced = true
        }

        if nsView.isComposingText == false {
            applyStyle(to: nsView, coordinator: context.coordinator, force: textWasReplaced)
        }

        if shouldFocus {
            Task { @MainActor in
                guard let window = nsView.window else { return }
                window.makeFirstResponder(nsView)

                if let direction = verticalMoveDirection,
                    let horizontalOffset = preferredHorizontalOffset
                {
                    let pos = nsView.closestCharacterIndexForVerticalMove(
                        horizontalOffset: horizontalOffset,
                        direction: direction
                    )
                    nsView.setSelectedRange(NSRange(location: pos, length: 0))
                } else {
                    let textLength = (nsView.string as NSString).length
                    let pos = min(cursorPosition, textLength)
                    nsView.setSelectedRange(NSRange(location: pos, length: 0))
                }

                shouldFocus = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    fileprivate func applyStyle(
        to textView: NSTextView,
        coordinator: Coordinator,
        force: Bool = false
    ) {
        // textStorage.setAttributes 会触发 layoutManager 失效，进而引发 SwiftUI 重新测量。
        // 仅在样式真的需要更新时执行，避免每次 body 重算都触发布局。
        if force == false, coordinator.lastAppliedIsCompleted == isCompleted {
            return
        }
        coordinator.lastAppliedIsCompleted = isCompleted

        let length = (textView.string as NSString).length
        let range = NSRange(location: 0, length: length)

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
}

extension CustomTextEditor {
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        var hasMultipleSelection: Bool = false
        var isApplyingProgrammaticText: Bool = false
        var lastAppliedIsCompleted: Bool?

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
                    parent.applyStyle(to: textView, coordinator: self, force: true)
                }
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if let textView = notification.object as? CustomNSTextView {
                parent.onCompositionChange(false)
                Task { @MainActor in
                    if textView.isComposingText == false {
                        self.parent.applyStyle(to: textView, coordinator: self, force: true)
                    }
                }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            handleCommand(in: textView, commandSelector: commandSelector)
        }

        func handleCommand(in textView: NSTextView, commandSelector: Selector) -> Bool {
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

                // 选区不为空时，先删掉选区，等价于「先按 Delete 再按 Enter」，
                // 删除走 NSTextView 自身的本地撤销栈。删完后 selectedRange.location
                // 会落到原选区起点，再按光标位置走分档。
                var range = textView.selectedRange()
                if range.length > 0 {
                    textView.insertText("", replacementRange: range)
                    range = textView.selectedRange()
                }

                let fullText = textView.string
                let length = (fullText as NSString).length
                let cursor = range.location

                let action: EnterAction
                if length == 0 {
                    action = .insertSiblingBelow
                } else if cursor == 0 {
                    action = .insertSiblingAbove
                } else if cursor >= length {
                    action = .insertSiblingBelow
                } else {
                    let nsText = fullText as NSString
                    action = .splitIntoChild(
                        newCurrentTitle: nsText.substring(to: cursor),
                        childTitle: nsText.substring(from: cursor)
                    )
                }

                // 创建新 item 前先放弃 first responder。
                // 否则 SwiftUI 把焦点切到新 item 之前，
                // 紧跟其后的 Tab/退格等命令会被旧 NSTextView 截获，
                // 落到旧 item 的 onTab/onBackspace 闭包上。
                textView.window?.makeFirstResponder(nil)
                parent.onReturn(action)
                return true
            }

            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
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
            let pointInWindow = textView.convert(NSPoint(x: localX, y: 0), to: nil)
            return pointInWindow.x
        }
    }
}
