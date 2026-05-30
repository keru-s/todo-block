//
//  TodoEditorViewController.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let documentView = TodoEditorDocumentView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let dropIndicatorView = TodoEditorDropIndicatorView()

    private var renderedSections: [TodoEditorSectionSnapshot] = []
    private var renderedEmptyTitle: String = ""
    private var actions: TodoEditorActions = .readOnly
    private var sectionViewsById: [UUID: TodoEditorSectionView] = [:]
    private var draggingItemId: UUID?
    private var activeDrop: TodoEditorResolvedDrop?

    override func loadView() {
        view = NSView()
        configureViewHierarchy()
        configureEmptyLabel()
    }

    func update(
        sections: [TodoEditorSectionSnapshot],
        emptyTitle: String,
        actions: TodoEditorActions
    ) {
        loadViewIfNeeded()
        self.actions = actions

        guard sections != renderedSections || emptyTitle != renderedEmptyTitle else {
            return
        }

        renderedSections = sections
        renderedEmptyTitle = emptyTitle
        rebuildContent(sections: sections, emptyTitle: emptyTitle)
    }

    private func configureViewHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        documentView.translatesAutoresizingMaskIntoConstraints = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 24

        view.addSubview(scrollView)
        documentView.addSubview(stackView)
        documentView.addSubview(dropIndicatorView)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -16)
        ])
    }

    private func configureEmptyLabel() {
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byWordWrapping
        emptyLabel.maximumNumberOfLines = 0
    }

    private func rebuildContent(sections: [TodoEditorSectionSnapshot], emptyTitle: String) {
        stackView.arrangedSubviews.forEach { subview in
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        if sections.isEmpty {
            sectionViewsById = [:]
            emptyLabel.stringValue = emptyTitle
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(emptyLabel)
            emptyLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            return
        }

        var nextSectionViewsById: [UUID: TodoEditorSectionView] = [:]
        for section in sections {
            let existingSectionView = sectionViewsById[section.id]
            let sectionView = existingSectionView ?? TodoEditorSectionView(snapshot: section, actions: actions)
            sectionView.onDragBegan = { [weak self] itemId, location in
                self?.handleDragBegan(itemId: itemId, windowLocation: location)
            }
            sectionView.onDragChanged = { [weak self] itemId, location in
                self?.handleDragChanged(itemId: itemId, windowLocation: location)
            }
            sectionView.onDragEnded = { [weak self] itemId, location in
                self?.handleDragEnded(itemId: itemId, windowLocation: location)
            }
            sectionView.apply(snapshot: section, actions: actions)
            stackView.addArrangedSubview(sectionView)
            sectionView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            nextSectionViewsById[section.id] = sectionView
        }
        sectionViewsById = nextSectionViewsById
    }

    private func handleDragBegan(itemId: UUID, windowLocation: NSPoint) {
        draggingItemId = itemId
        actions.selectItem(itemId, false, nil)
        updateDrop(windowLocation: windowLocation)
    }

    private func handleDragChanged(itemId: UUID, windowLocation: NSPoint) {
        guard draggingItemId == itemId else { return }
        updateDrop(windowLocation: windowLocation)
    }

    private func handleDragEnded(itemId: UUID, windowLocation: NSPoint) {
        guard draggingItemId == itemId else { return }
        updateDrop(windowLocation: windowLocation)

        defer {
            draggingItemId = nil
            activeDrop = nil
            dropIndicatorView.hide()
        }

        guard let activeDrop else { return }
        actions.moveDraggedItem(
            itemId,
            activeDrop.destination,
            activeDrop.index,
            activeDrop.indentLevel
        )
    }

    private func updateDrop(windowLocation: NSPoint) {
        let point = documentView.convert(windowLocation, from: nil)
        guard let section = sectionSnapshot(at: point),
              let sectionView = sectionViewsById[section.id]
        else {
            activeDrop = nil
            dropIndicatorView.hide()
            return
        }

        let frames = sectionView.itemFrames(in: documentView)
        let resolved = resolveDrop(in: section, point: point, itemFrames: frames)
        activeDrop = resolved

        if let indicatorY = indicatorY(for: resolved, section: section, itemFrames: frames, sectionView: sectionView) {
            dropIndicatorView.show(
                y: indicatorY,
                indentLevel: resolved.indentLevel,
                width: documentView.bounds.width
            )
        } else {
            dropIndicatorView.hide()
        }
    }

    private func sectionSnapshot(at point: CGPoint) -> TodoEditorSectionSnapshot? {
        for section in renderedSections {
            guard let sectionView = sectionViewsById[section.id] else { continue }
            if sectionView.contains(pointInDocument: point, documentView: documentView) {
                return section
            }
        }
        return nil
    }

    private func resolveDrop(
        in section: TodoEditorSectionSnapshot,
        point: CGPoint,
        itemFrames: [UUID: CGRect]
    ) -> TodoEditorResolvedDrop {
        guard section.items.isEmpty == false else {
            return TodoEditorResolvedDrop(destination: section.destination, index: 0, indentLevel: 0)
        }

        var index = section.items.count
        for (offset, item) in section.items.enumerated() {
            guard let frame = itemFrames[item.id] else { continue }
            let threshold = offset == 0 ? min(frame.maxY, frame.midY + 8) : frame.midY
            if point.y < threshold {
                index = offset
                break
            }
        }

        let relativeX = max(0, point.x - 20)
        var indentLevel = Int(relativeX / TodoDesignTokens.indentWidth)
        if index > 0 {
            indentLevel = min(indentLevel, section.items[index - 1].indentLevel + 1)
        } else {
            indentLevel = 0
        }

        return TodoEditorResolvedDrop(
            destination: section.destination,
            index: index,
            indentLevel: min(indentLevel, TodoItem.maxIndentLevel)
        )
    }

    private func indicatorY(
        for drop: TodoEditorResolvedDrop,
        section: TodoEditorSectionSnapshot,
        itemFrames: [UUID: CGRect],
        sectionView: TodoEditorSectionView
    ) -> CGFloat? {
        if section.items.isEmpty {
            return sectionView.convert(sectionView.bounds, to: documentView).maxY - 20
        }

        if drop.index <= 0, let first = section.items.first, let frame = itemFrames[first.id] {
            return frame.minY
        }

        if drop.index >= section.items.count,
           let last = section.items.last,
           let frame = itemFrames[last.id] {
            return frame.maxY
        }

        let item = section.items[drop.index]
        return itemFrames[item.id]?.minY
    }
}

private struct TodoEditorResolvedDrop {
    let destination: TodoDropDestination
    let index: Int
    let indentLevel: Int
}

private final class TodoEditorDocumentView: NSView {
    override var isFlipped: Bool { true }
}
