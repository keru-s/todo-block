//
//  TodoEditorDragHandleView.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorDragHandleView: NSView {
    var onDragBegan: ((NSPoint) -> Void)?
    var onDragChanged: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?

    private var isHovering = false
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHovering || isDragging {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3).fill()

            NSColor.secondaryLabelColor.setStroke()
            let path = NSBezierPath()
            for offset in [7.0, 10.0, 13.0] {
                path.move(to: NSPoint(x: 5, y: offset))
                path.line(to: NSPoint(x: bounds.width - 5, y: offset))
            }
            path.lineWidth = 1
            path.stroke()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        if isDragging == false {
            isDragging = true
            onDragBegan?(event.locationInWindow)
        }
        onDragChanged?(event.locationInWindow)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnded?(event.locationInWindow)
        }
        isDragging = false
        needsDisplay = true
    }

    private func addTrackingArea() {
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
        )
    }
}

