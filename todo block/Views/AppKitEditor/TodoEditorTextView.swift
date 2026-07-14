//
//  TodoEditorTextView.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorTextView: NSTextView {
    var onTextDidChange: ((TodoTextEditEvent) -> Void)?
    var onSelectionDidChange: ((TodoTextSelection) -> Void)?
    var onMouseFocus: ((Bool, Int?) -> Void)?
    var onUserInteraction: (() -> Void)?
    var onCommand: ((TodoEditorTextCommand) -> Bool)?
    var onCompositionChange: ((Bool) -> Void)?
    var deletesOnBackspace: Bool = false
    private var isApplyingHandledCommandText = false
    private var lastReportedText = ""
    private var pendingBeforeSelection: TodoTextSelection?
    private var pendingEditKind: TodoTextEditKind?

    var isComposingText: Bool {
        hasMarkedText()
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 22)
        }

        layoutManager.ensureLayout(for: textContainer)
        let contentHeight = layoutManager.usedRect(for: textContainer).height
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(22, ceil(contentHeight + textContainerInset.height * 2))
        )
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
        let composing = isComposingText
        onCompositionChange?(composing)
        if composing == false && isApplyingHandledCommandText == false {
            reportCommittedTextIfNeeded()
        }
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(
            ranges,
            affinity: affinity,
            stillSelecting: stillSelectingFlag
        )
        guard
            pendingBeforeSelection == nil,
            isComposingText == false,
            isApplyingHandledCommandText == false
        else { return }
        onSelectionDidChange?(TodoTextSelection(selectedRange()))
    }

    override func shouldChangeText(
        in affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        if isApplyingHandledCommandText == false, pendingBeforeSelection == nil {
            pendingBeforeSelection = TodoTextSelection(selectedRange())
            let replacementLength = ((replacementString ?? "") as NSString).length
            if affectedCharRange.length == 0, replacementLength > 0 {
                pendingEditKind = .insertion
            } else if affectedCharRange.length > 0, replacementLength == 0 {
                pendingEditKind = .deletion
            } else {
                pendingEditKind = .replacement
            }
        }
        return super.shouldChangeText(
            in: affectedCharRange,
            replacementString: replacementString
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            invalidateIntrinsicContentSize()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onUserInteraction?()
        super.mouseDown(with: event)
        onMouseFocus?(event.modifierFlags.contains(.shift), selectedRange().location)
    }

    override func keyDown(with event: NSEvent) {
        onUserInteraction?()
        super.keyDown(with: event)
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
        reportCommittedTextIfNeeded()
    }

    override func doCommand(by commandSelector: Selector) {
        if handleCommand(commandSelector) {
            return
        }

        super.doCommand(by: commandSelector)
    }

    func focus(
        cursorPosition: Int,
        selectionLength: Int,
        preferredHorizontalOffset: CGFloat?,
        verticalMoveDirection: VerticalMoveDirection?
    ) {
        guard let window else { return }
        window.makeFirstResponder(self)

        if let verticalMoveDirection, let preferredHorizontalOffset {
            let position = closestCharacterIndexForVerticalMove(
                horizontalOffset: preferredHorizontalOffset,
                direction: verticalMoveDirection
            )
            setSelectedRange(NSRange(location: position, length: 0))
            return
        }

        let textLength = (string as NSString).length
        let position = min(max(0, cursorPosition), textLength)
        let length = min(max(0, selectionLength), textLength - position)
        setSelectedRange(NSRange(location: position, length: length))
    }

    func synchronizeReportedText(_ text: String) {
        lastReportedText = text
        pendingBeforeSelection = nil
        pendingEditKind = nil
    }

    func closestCharacterIndexForVerticalMove(
        horizontalOffset: CGFloat,
        direction: VerticalMoveDirection
    ) -> Int {
        guard let layoutManager, let textContainer else { return 0 }

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

    private func handleCommand(_ commandSelector: Selector) -> Bool {
        if isComposingText {
            return false
        }

        let modifiers = NSApp.currentEvent?.modifierFlags ?? []

        if modifiers.contains(.command) {
            if commandSelector == #selector(NSResponder.moveUp(_:))
                || commandSelector == #selector(NSResponder.moveToBeginningOfDocument(_:))
            {
                return onCommand?(.moveItemUp) == true
            }

            if commandSelector == #selector(NSResponder.moveDown(_:))
                || commandSelector == #selector(NSResponder.moveToEndOfDocument(_:))
            {
                return onCommand?(.moveItemDown) == true
            }
        }

        if commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
            insertNewlineIgnoringFieldEditor(nil)
            return true
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if modifiers.contains(.shift) {
                insertNewlineIgnoringFieldEditor(nil)
                return true
            }

            var range = selectedRange()
            if range.length > 0 {
                insertText("", replacementRange: range)
                range = selectedRange()
            }

            let fullText = string
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

            if case .splitIntoChild(let newCurrentTitle, _) = action {
                replaceTextForHandledCommand(newCurrentTitle)
            }
            window?.makeFirstResponder(nil)
            let handled = onCommand?(.return(action)) == true
            if handled == false, case .splitIntoChild = action {
                replaceTextForHandledCommand(fullText)
            }
            return handled
        }

        if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            if deletesOnBackspace || string.isEmpty {
                return onCommand?(.deleteBackward) == true
            }
            return false
        }

        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return onCommand?(.tab) == true
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return onCommand?(.backtab) == true
        }

        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            if isOnFirstVisualLine {
                return onCommand?(.moveUp(selectedRange().location, preferredHorizontalOffsetInWindow)) == true
            }
            return false
        }

        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            if isOnLastVisualLine {
                return onCommand?(.moveDown(selectedRange().location, preferredHorizontalOffsetInWindow)) == true
            }
            return false
        }

        return false
    }

    private func replaceTextForHandledCommand(_ newText: String) {
        isApplyingHandledCommandText = true
        string = newText
        let length = (newText as NSString).length
        setSelectedRange(NSRange(location: length, length: 0))
        invalidateIntrinsicContentSize()
        isApplyingHandledCommandText = false
    }

    private func reportCommittedTextIfNeeded() {
        guard string != lastReportedText else {
            pendingBeforeSelection = nil
            pendingEditKind = nil
            return
        }
        let beforeSelection = pendingBeforeSelection ?? TodoTextSelection(selectedRange())
        let afterSelection = TodoTextSelection(selectedRange())
        let kind = pendingEditKind ?? inferredEditKind(
            beforeText: lastReportedText,
            afterText: string,
            beforeSelection: beforeSelection
        )
        let event = TodoTextEditEvent(
            beforeText: lastReportedText,
            afterText: string,
            beforeSelection: beforeSelection,
            afterSelection: afterSelection,
            kind: kind
        )
        lastReportedText = string
        pendingBeforeSelection = nil
        pendingEditKind = nil
        onTextDidChange?(event)
    }

    private func inferredEditKind(
        beforeText: String,
        afterText: String,
        beforeSelection: TodoTextSelection
    ) -> TodoTextEditKind {
        if beforeSelection.length > 0 {
            return .replacement
        }
        let beforeLength = (beforeText as NSString).length
        let afterLength = (afterText as NSString).length
        return afterLength >= beforeLength ? .insertion : .deletion
    }

    private var isOnFirstVisualLine: Bool {
        guard let layoutManager, let textContainer else { return true }

        layoutManager.ensureLayout(for: textContainer)

        let selectedLocation = selectedRange().location
        let nsText = string as NSString
        if nsText.length == 0 { return true }

        let characterIndex = min(max(0, selectedLocation), nsText.length - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)

        var lineRange = NSRange(location: 0, length: 0)
        _ = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
        return lineRange.location == 0
    }

    private var isOnLastVisualLine: Bool {
        guard let layoutManager, let textContainer else { return true }

        layoutManager.ensureLayout(for: textContainer)

        let selectedLocation = selectedRange().location
        let nsText = string as NSString
        if nsText.length == 0 { return true }

        let characterIndex = min(max(0, selectedLocation), nsText.length - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)

        var lineRange = NSRange(location: 0, length: 0)
        _ = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
        return NSMaxRange(lineRange) >= layoutManager.numberOfGlyphs
    }

    private var preferredHorizontalOffsetInWindow: CGFloat {
        guard let layoutManager, let textContainer else { return 0 }

        layoutManager.ensureLayout(for: textContainer)

        let selectedLocation = selectedRange().location
        let nsText = string as NSString
        if nsText.length == 0 { return 0 }

        let characterIndex = min(max(0, selectedLocation), nsText.length)
        let localX: CGFloat

        if characterIndex == nsText.length {
            let lastGlyph = max(0, layoutManager.numberOfGlyphs - 1)
            let lastRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: lastGlyph, length: 1),
                in: textContainer
            )
            localX = lastRect.maxX
        } else {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            let rect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            localX = rect.minX
        }

        let pointInWindow = convert(NSPoint(x: localX + textContainerInset.width, y: 0), to: nil)
        return pointInWindow.x
    }
}

enum TodoEditorTextCommand {
    case `return`(EnterAction)
    case deleteBackward
    case tab
    case backtab
    case moveUp(Int, CGFloat?)
    case moveDown(Int, CGFloat?)
    case moveItemUp
    case moveItemDown
}
