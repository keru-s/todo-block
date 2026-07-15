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
    private var didStartDragSelection = false
    private var textSelectionAnchor: Int?
    private var prefersRowFirstResponder = false
    private var lastStyledCompleted: Bool?
    private var focusUpdateVersion = 0

    var onDragBegan: ((UUID, NSPoint) -> Void)?
    var onDragChanged: ((UUID, NSPoint) -> Void)?
    var onDragEnded: ((UUID, NSPoint) -> Void)?
    var onSelectionDragBegan: ((UUID, NSPoint) -> Void)?
    var onSelectionDragChanged: ((UUID, NSPoint) -> Void)?
    var onSelectionDragEnded: (() -> Void)?
    var onSelectionDragCancelled: (() -> Void)?

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
        titleTextView.allowsUndo = false
        titleTextView.onTextDidChange = { [weak self] event in
            guard let self, let itemId, isApplyingSnapshot == false else { return }
            actions.titleChanged(itemId, event)
        }
        titleTextView.onSelectionDidChange = { [weak self] selection in
            guard let self, let itemId, isApplyingSnapshot == false else { return }
            actions.textSelectionChanged(itemId, selection)
        }
        titleTextView.onInputSessionEnded = { [weak self] in
            self?.actions.inputSessionEnded()
        }
        titleTextView.onMouseFocus = { [weak self] shiftPressed, cursorPosition in
            guard let self, let itemId else { return }
            prefersRowFirstResponder = false
            actions.captureDragSelectionBefore()
            actions.selectItem(itemId, shiftPressed, cursorPosition)
        }
        titleTextView.onMouseInteractionEnded = { [weak self] didCrossItemSelection in
            guard let self, didCrossItemSelection == false else { return }
            actions.discardPreparedDragSelection()
        }
        titleTextView.onEscapePressed = { [weak self] in
            self?.handleEscape() ?? false
        }
        titleTextView.shouldBeginCrossItemSelection = { [weak self] location in
            self?.hasExitedTextSelectionRegion(at: location) ?? false
        }
        titleTextView.onCrossItemSelectionBegan = { [weak self] location, cursorPosition in
            guard let self, let itemId else { return }
            prefersRowFirstResponder = true
            window?.makeFirstResponder(self)
            onSelectionDragBegan?(itemId, location)
        }
        titleTextView.onCrossItemSelectionChanged = { [weak self] location in
            guard let self, let itemId else { return }
            onSelectionDragChanged?(itemId, location)
        }
        titleTextView.onCrossItemSelectionEnded = { [weak self] in
            self?.onSelectionDragEnded?()
        }
        titleTextView.onCrossItemSelectionCancelled = { [weak self] in
            guard let self else { return }
            prefersRowFirstResponder = false
            onSelectionDragCancelled?()
        }
        titleTextView.onUserInteraction = { [weak self] in
            self?.actions.claimCurrentList()
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
            actions.claimCurrentList()
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

        focusUpdateVersion += 1
        let currentFocusUpdateVersion = focusUpdateVersion
        let previousSnapshot = latestSnapshot
        let didRecordedTextSelectionChange = previousSnapshot.map {
            $0.cursorPosition != snapshot.cursorPosition
                || $0.textSelectionLength != snapshot.textSelectionLength
                || $0.isFocused != snapshot.isFocused
        } ?? false
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
            isApplyingSnapshot = true
            titleTextView.string = snapshot.title
            titleTextView.synchronizeReportedText(snapshot.title)
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
        } else if snapshot.isFocused {
            let textLength = (snapshot.title as NSString).length
            let location = min(max(0, snapshot.cursorPosition), textLength)
            let selectionLength = min(
                max(0, snapshot.textSelectionLength),
                textLength - location
            )
            let desiredRange = NSRange(location: location, length: selectionLength)
            if window?.firstResponder !== titleTextView
                || (didReplaceText || didRecordedTextSelectionChange)
                    && titleTextView.selectedRange() != desiredRange
            {
                if window?.firstResponder === titleTextView {
                    titleTextView.focus(
                        cursorPosition: snapshot.cursorPosition,
                        selectionLength: snapshot.textSelectionLength,
                        preferredHorizontalOffset: snapshot.preferredHorizontalOffset,
                        verticalMoveDirection: snapshot.verticalMoveDirection
                    )
                } else {
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.itemId == snapshot.id,
                              focusUpdateVersion == currentFocusUpdateVersion
                        else { return }
                        titleTextView.focus(
                            cursorPosition: snapshot.cursorPosition,
                            selectionLength: snapshot.textSelectionLength,
                            preferredHorizontalOffset: snapshot.preferredHorizontalOffset,
                            verticalMoveDirection: snapshot.verticalMoveDirection
                        )
                    }
                }
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
        actions.claimCurrentList()
        actions.toggleCompleted(itemId)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let itemId {
            actions.claimCurrentList()
            didStartDragSelection = false
            let position = titleCharacterIndex(at: event.locationInWindow)
            textSelectionAnchor = position
            prefersRowFirstResponder = false
            actions.captureDragSelectionBefore()
            actions.selectItem(itemId, event.modifierFlags.contains(.shift), position)
            titleTextView.focus(
                cursorPosition: position,
                selectionLength: 0,
                preferredHorizontalOffset: nil,
                verticalMoveDirection: nil
            )
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let itemId else {
            super.mouseDragged(with: event)
            return
        }

        if didStartDragSelection == false,
           hasExitedTextSelectionRegion(at: event.locationInWindow) {
            didStartDragSelection = true
            onSelectionDragBegan?(itemId, event.locationInWindow)
        }
        if didStartDragSelection {
            onSelectionDragChanged?(itemId, event.locationInWindow)
        } else if let textSelectionAnchor {
            let position = titleCharacterIndex(at: event.locationInWindow)
            titleTextView.setSelectedRange(
                NSRange(
                    location: min(textSelectionAnchor, position),
                    length: abs(textSelectionAnchor - position)
                )
            )
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didStartDragSelection {
            onSelectionDragEnded?()
        } else {
            actions.discardPreparedDragSelection()
        }
        didStartDragSelection = false
        textSelectionAnchor = nil
        super.mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard let itemId else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53, handleEscape() {
            return
        }

        if event.modifierFlags.contains(.command), event.keyCode == 126 {
            actions.claimCurrentList()
            actions.moveItemByKeyboard(itemId, .up)
            return
        }

        if event.modifierFlags.contains(.command), event.keyCode == 125 {
            actions.claimCurrentList()
            actions.moveItemByKeyboard(itemId, .down)
            return
        }

        if event.charactersIgnoringModifiers == " " {
            actions.claimCurrentList()
            actions.toggleCompleted(itemId)
            return
        }

        super.keyDown(with: event)
    }

    private func cancelSelectionDragIfNeeded() -> Bool {
        guard didStartDragSelection else { return false }
        didStartDragSelection = false
        textSelectionAnchor = nil
        prefersRowFirstResponder = false
        onSelectionDragCancelled?()
        return true
    }

    private func handleEscape() -> Bool {
        if cancelSelectionDragIfNeeded() {
            return true
        }
        guard actions.hasMultipleSelection() else { return false }
        actions.clearSelection()
        return true
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

    private func hasExitedTextSelectionRegion(at windowLocation: NSPoint) -> Bool {
        let rowFrame = convert(bounds, to: nil)
        let titleFrame = visibleTitleFrameInWindow()
        let font = titleTextView.font ?? .preferredFont(forTextStyle: .body)
        let protection = ("字" as NSString).size(withAttributes: [.font: font]).width * 3
        return TodoEditorCrossItemDragBoundary.hasExitedTextSelectionRegion(
            at: windowLocation,
            rowFrame: rowFrame,
            titleFrame: titleFrame,
            horizontalProtection: protection
        )
    }

    private func visibleTitleFrameInWindow() -> NSRect {
        guard let layoutManager = titleTextView.layoutManager,
              let textContainer = titleTextView.textContainer
        else {
            return titleTextView.convert(titleTextView.bounds, to: nil)
        }

        layoutManager.ensureLayout(for: textContainer)
        let characterRange = NSRange(
            location: 0,
            length: (titleTextView.string as NSString).length
        )
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        let usedRect = glyphRange.length > 0
            ? layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            : .zero
        let containerOrigin = titleTextView.textContainerOrigin
        let titleFrame = NSRect(
            x: containerOrigin.x + usedRect.minX,
            y: containerOrigin.y + usedRect.minY,
            width: max(1, usedRect.width),
            height: max(1, usedRect.height)
        )
        return titleTextView.convert(titleFrame, to: nil)
    }

    private func titleCharacterIndex(at windowLocation: NSPoint) -> Int {
        let point = titleTextView.convert(windowLocation, from: nil)
        let textLength = (titleTextView.string as NSString).length
        return min(max(0, titleTextView.characterIndexForInsertion(at: point)), textLength)
    }
}

private extension Color {
    var nsColor: NSColor {
        NSColor(self)
    }
}
