//
//  CustomNSTextView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import AppKit

final class CustomNSTextView: NSTextView {
    weak var customCoordinator: CustomTextEditor.Coordinator?
    var onMouseDown: ((Bool, Int?) -> Void)?
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
        let cursorPosition = selectedRange().location
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

    // MARK: - Command handling

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
