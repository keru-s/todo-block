//
//  TodoEditorTextView.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorTextView: NSTextView {
    var onTextDidChange: ((String) -> Void)?

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
        onTextDidChange?(string)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            invalidateIntrinsicContentSize()
        }
    }
}
