//
//  TodoEditorRowView.swift
//  todo block
//

import AppKit
import SwiftUI

@MainActor
final class TodoEditorRowView: NSView {
    private let stackView = NSStackView()
    private let indentSpacer = NSView()
    private let handleView = TodoEditorDragHandleView()
    private let completionButton = NSButton()
    private let completionTrailingSpacer = NSView()
    private let titleTextView = TodoEditorTextView()
    private var actions: TodoEditorActions
    private var itemId: UUID?
    private var indentConstraint: NSLayoutConstraint?
    private var isApplyingSnapshot = false
    private var isComposingText = false
    private var latestSnapshot: TodoEditorItemSnapshot?
    private var selectionDragState = TodoEditorLongPressDragState()
    private var selectionDragEventMonitor: Any?
    private var prefersRowFirstResponder = false
    private var lastStyledCompleted: Bool?

    var onDragBegan: ((UUID, NSPoint) -> Void)?
    var onDragChanged: ((UUID, NSPoint) -> Void)?
    var onDragEnded: ((UUID, NSPoint) -> Void)?
    var onSelectionDragBegan: ((UUID, NSPoint) -> Void)?
    var onSelectionDragChanged: ((UUID, NSPoint) -> Void)?
    var onSelectionDragEnded: (() -> Void)?

    init(snapshot: TodoEditorItemSnapshot, actions: TodoEditorActions) {
        self.actions = actions
        super.init(frame: .zero)
        configureViewHierarchy()
        apply(snapshot: snapshot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let selectionDragEventMonitor {
            NSEvent.removeMonitor(selectionDragEventMonitor)
        }
    }

    private func configureViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .top
        stackView.distribution = .fill
        stackView.spacing = 0

        completionButton.isBordered = false
        completionButton.imagePosition = .imageOnly
        completionButton.target = self
        completionButton.action = #selector(toggleCompleted)

        titleTextView.font = .preferredFont(forTextStyle: .body)
        titleTextView.drawsBackground = false
        titleTextView.isRichText = false
        titleTextView.importsGraphics = false
        titleTextView.isHorizontallyResizable = false
        titleTextView.isVerticallyResizable = false
        titleTextView.textContainerInset = NSSize(width: 0, height: 2)
        titleTextView.textContainer?.lineFragmentPadding = 0
        titleTextView.textContainer?.lineBreakMode = .byWordWrapping
        titleTextView.textContainer?.widthTracksTextView = true
        titleTextView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleTextView.onTextDidChange = { [weak self] newText in
            guard let self, let itemId, isApplyingSnapshot == false else { return }
            actions.titleChanged(itemId, newText)
        }
        titleTextView.onMouseFocus = { [weak self] shiftPressed, cursorPosition in
            guard let self, let itemId else { return }
            prefersRowFirstResponder = false
            actions.selectItem(itemId, shiftPressed, cursorPosition)
        }
        titleTextView.onSelectionPressBegan = { [weak self] cursorPosition in
            self?.beginSelectionPress(cursorPosition: cursorPosition, prefersRowFirstResponder: false)
        }
        titleTextView.onSelectionDragBegan = { [weak self] location in
            self?.beginSelectionDragIfNeeded(location: location)
        }
        titleTextView.onSelectionDragChanged = { [weak self] location in
            self?.updateSelectionDrag(location: location)
        }
        titleTextView.onSelectionDragEnded = { [weak self] in
            self?.endSelectionDrag()
        }
        titleTextView.onCompositionChange = { [weak self] composing in
            self?.isComposingText = composing
        }
        titleTextView.onCommand = { [weak self] command in
            guard let self, let itemId else { return false }
            switch command {
            case .return(let action):
                actions.enterPressed(itemId, action)
            case .deleteBackward:
                actions.deletePressed(itemId)
            case .tab:
                actions.indent(itemId)
            case .backtab:
                actions.outdent(itemId)
            case .moveUp(let position, let horizontalOffset):
                actions.moveFocus(itemId, .up, position, horizontalOffset)
            case .moveDown(let position, let horizontalOffset):
                actions.moveFocus(itemId, .down, position, horizontalOffset)
            case .moveItemUp:
                actions.moveItemByKeyboard(itemId, .up)
            case .moveItemDown:
                actions.moveItemByKeyboard(itemId, .down)
            }
            return true
        }

        handleView.onDragBegan = { [weak self] location in
            guard let self, let itemId else { return }
            prefersRowFirstResponder = true
            window?.makeFirstResponder(self)
            onDragBegan?(itemId, location)
        }
        handleView.onDragChanged = { [weak self] location in
            guard let self, let itemId else { return }
            onDragChanged?(itemId, location)
        }
        handleView.onDragEnded = { [weak self] location in
            guard let self, let itemId else { return }
            onDragEnded?(itemId, location)
        }

        addSubview(stackView)
        stackView.addArrangedSubview(indentSpacer)
        stackView.addArrangedSubview(handleView)
        stackView.addArrangedSubview(completionButton)
        stackView.addArrangedSubview(completionTrailingSpacer)
        stackView.addArrangedSubview(titleTextView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            handleView.widthAnchor.constraint(equalToConstant: 20),
            handleView.heightAnchor.constraint(equalToConstant: 20),
            completionButton.widthAnchor.constraint(equalToConstant: 20),
            completionButton.heightAnchor.constraint(equalToConstant: 20),
            completionTrailingSpacer.widthAnchor.constraint(equalToConstant: 6)
        ])
    }

    func apply(snapshot: TodoEditorItemSnapshot, actions: TodoEditorActions? = nil) {
        if let actions {
            self.actions = actions
        }

        latestSnapshot = snapshot
        itemId = snapshot.id

        let indentWidth = CGFloat(snapshot.indentLevel) * TodoDesignTokens.indentWidth
        indentConstraint?.isActive = false
        indentConstraint = indentSpacer.widthAnchor.constraint(equalToConstant: indentWidth)
        indentConstraint?.isActive = true

        let symbolName = snapshot.isCompleted ? "checkmark.square.fill" : "square"
        completionButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: snapshot.isCompleted ? "已完成" : "未完成"
        )
        completionButton.contentTintColor = snapshot.isCompleted ? .systemGreen : .secondaryLabelColor

        titleTextView.deletesOnBackspace = snapshot.hasMultipleSelection

        var didReplaceText = false
        if titleTextView.string != snapshot.title && isComposingText == false {
            let wasFirstResponder = window?.firstResponder === titleTextView
            let selectedRange = titleTextView.selectedRange()
            isApplyingSnapshot = true
            titleTextView.string = snapshot.title
            if wasFirstResponder {
                let length = (snapshot.title as NSString).length
                titleTextView.setSelectedRange(
                    NSRange(location: min(selectedRange.location, length), length: 0)
                )
            }
            isApplyingSnapshot = false
            didReplaceText = true
        }
        if isComposingText == false,
           didReplaceText || lastStyledCompleted != snapshot.isCompleted {
            applyTextStyle(isCompleted: snapshot.isCompleted)
            lastStyledCompleted = snapshot.isCompleted
        }

        wantsLayer = true
        layer?.backgroundColor = snapshot.isSelected
            ? TodoDesignTokens.selectionTint.nsColor.cgColor
            : NSColor.clear.cgColor

        if snapshot.isFocused, prefersRowFirstResponder {
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
        } else if snapshot.isFocused, window?.firstResponder !== titleTextView {
            Task { @MainActor [weak self] in
                guard let self, self.itemId == snapshot.id else { return }
                titleTextView.focus(
                    cursorPosition: snapshot.cursorPosition,
                    preferredHorizontalOffset: snapshot.preferredHorizontalOffset,
                    verticalMoveDirection: snapshot.verticalMoveDirection
                )
            }
        } else if snapshot.isFocused == false {
            prefersRowFirstResponder = false
        }
    }

    func resetDragHandleState() {
        handleView.resetInteractionState()
    }

    @objc private func toggleCompleted() {
        guard let itemId else { return }
        actions.toggleCompleted(itemId)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginSelectionPress(cursorPosition: nil, prefersRowFirstResponder: true)
        if let itemId {
            actions.selectItem(itemId, event.modifierFlags.contains(.shift), nil)
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard itemId != nil else {
            super.mouseDragged(with: event)
            return
        }

        beginSelectionDragIfNeeded(location: event.locationInWindow)
        updateSelectionDrag(location: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        endSelectionDrag()
        super.mouseUp(with: event)
    }

    private func beginSelectionPress(cursorPosition: Int?, prefersRowFirstResponder: Bool) {
        guard let itemId else { return }
        selectionDragState.begin()
        installSelectionDragEventMonitor()
        self.prefersRowFirstResponder = prefersRowFirstResponder
        if prefersRowFirstResponder {
            window?.makeFirstResponder(self)
        }
        if let cursorPosition {
            actions.selectItem(itemId, false, cursorPosition)
        }
    }

    private func beginSelectionDragIfNeeded(location: NSPoint) {
        guard let itemId, selectionDragState.beginDragIfReady() else { return }
        onSelectionDragBegan?(itemId, location)
    }

    private func updateSelectionDrag(location: NSPoint) {
        guard let itemId, selectionDragState.isDragging else { return }
        onSelectionDragChanged?(itemId, location)
    }

    private func endSelectionDrag() {
        if selectionDragState.end() {
            onSelectionDragEnded?()
        }
        removeSelectionDragEventMonitor()
    }

    private func installSelectionDragEventMonitor() {
        removeSelectionDragEventMonitor()
        selectionDragEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            let eventType = event.type
            let location = event.locationInWindow
            let shouldConsume = MainActor.assumeIsolated {
                guard let self else { return false }

                switch eventType {
                case .leftMouseDragged:
                    self.beginSelectionDragIfNeeded(location: location)
                    self.updateSelectionDrag(location: location)
                    return self.selectionDragState.isDragging
                case .leftMouseUp:
                    let wasDragging = self.selectionDragState.isDragging
                    self.endSelectionDrag()
                    return wasDragging
                default:
                    return false
                }
            }
            return shouldConsume ? nil : event
        }
    }

    private func removeSelectionDragEventMonitor() {
        if let selectionDragEventMonitor {
            NSEvent.removeMonitor(selectionDragEventMonitor)
            self.selectionDragEventMonitor = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let itemId else {
            super.keyDown(with: event)
            return
        }

        if event.modifierFlags.contains(.command), event.keyCode == 126 {
            actions.moveItemByKeyboard(itemId, .up)
            return
        }

        if event.modifierFlags.contains(.command), event.keyCode == 125 {
            actions.moveItemByKeyboard(itemId, .down)
            return
        }

        if event.charactersIgnoringModifiers == " " {
            actions.toggleCompleted(itemId)
            return
        }

        super.keyDown(with: event)
    }

    private func applyTextStyle(isCompleted: Bool) {
        let range = NSRange(location: 0, length: (titleTextView.string as NSString).length)
        let wasFirstResponder = window?.firstResponder === titleTextView
        let selectedRange = titleTextView.selectedRange()
        titleTextView.textStorage?.beginEditing()
        titleTextView.textStorage?.setAttributes(
            [
                .font: NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: isCompleted ? NSColor.secondaryLabelColor : NSColor.labelColor,
                .strikethroughStyle: isCompleted ? NSUnderlineStyle.single.rawValue : 0
            ],
            range: range
        )
        titleTextView.textStorage?.endEditing()
        if wasFirstResponder {
            let length = (titleTextView.string as NSString).length
            titleTextView.setSelectedRange(
                NSRange(location: min(selectedRange.location, length), length: 0)
            )
        }
        titleTextView.insertionPointColor = isCompleted ? .secondaryLabelColor : .labelColor
    }
}

private extension Color {
    var nsColor: NSColor {
        NSColor(self)
    }
}
