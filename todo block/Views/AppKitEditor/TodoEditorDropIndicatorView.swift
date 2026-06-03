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

    func show(x: CGFloat, y: CGFloat, indentLevel: Int, width: CGFloat) {
        let indent = 20 + CGFloat(indentLevel) * TodoDesignTokens.indentWidth
        let startX = x + indent
        frame = CGRect(x: startX, y: y - 2, width: max(0, width - startX), height: 4)
        lineLayer.frame = CGRect(x: 6, y: 1, width: max(0, bounds.width - 6), height: 2)
        dotLayer.frame = CGRect(x: 0, y: -1, width: 6, height: 6)
        dotLayer.path = CGPath(ellipseIn: dotLayer.bounds, transform: nil)
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}
