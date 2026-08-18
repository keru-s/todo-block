//
//  TodoEditorDragHandleView.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorDragHandleView: NSView {
    var onDragBegan: ((NSPoint) -> TodoEditorContinuousInteractionToken?)?
    var onDragChanged: ((NSPoint, TodoEditorContinuousInteractionToken) -> Void)?
    var onDragEnded: ((NSPoint, TodoEditorContinuousInteractionToken) -> Void)?

    private var isHovering = false
    private var isDragging = false
    private var dragToken: TodoEditorContinuousInteractionToken?

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
        dragToken = nil
    }

    override func mouseDragged(with event: NSEvent) {
        if isDragging == false {
            isDragging = true
            dragToken = onDragBegan?(event.locationInWindow)
        }
        if let dragToken {
            onDragChanged?(event.locationInWindow, dragToken)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging, let dragToken {
            onDragEnded?(event.locationInWindow, dragToken)
        }
        resetInteractionState()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            resetInteractionState()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func resetInteractionState() {
        guard isHovering || isDragging else { return }
        isHovering = false
        isDragging = false
        dragToken = nil
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
