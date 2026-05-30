//
//  TodoEditorDropIndicatorView.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorDropIndicatorView: NSView {
    private let lineLayer = CALayer()
    private let dotLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(lineLayer)
        layer?.addSublayer(dotLayer)
        isHidden = true
        lineLayer.backgroundColor = NSColor.controlAccentColor.cgColor
        dotLayer.fillColor = NSColor.controlAccentColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show(y: CGFloat, indentLevel: Int, width: CGFloat) {
        let indent = 20 + CGFloat(indentLevel) * TodoDesignTokens.indentWidth
        frame = CGRect(x: 0, y: y - 2, width: width, height: 4)
        lineLayer.frame = CGRect(x: indent + 6, y: 1, width: max(0, width - indent - 6), height: 2)
        dotLayer.frame = CGRect(x: indent, y: -1, width: 6, height: 6)
        dotLayer.path = CGPath(ellipseIn: dotLayer.bounds, transform: nil)
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}

