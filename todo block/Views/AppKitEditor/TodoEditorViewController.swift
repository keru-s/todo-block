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
    private var sectionWidthConstraintsById: [UUID: NSLayoutConstraint] = [:]
    private var emptyLabelWidthConstraint: NSLayoutConstraint?
    private var draggingItemId: UUID?
    private var activeDrop: TodoEditorResolvedDrop?
    private var dragSelectionSectionId: UUID?
    private let dragSession = TodoEditorDragSession.shared

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
        scrollFocusedItemToVisible(in: sections)
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
        if sections.isEmpty {
            removeSections(except: [])
            emptyLabel.stringValue = emptyTitle
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            moveArrangedSubview(emptyLabel, to: 0)
            if emptyLabelWidthConstraint == nil {
                emptyLabelWidthConstraint = emptyLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor)
                emptyLabelWidthConstraint?.isActive = true
            }
            return
        }

        emptyLabelWidthConstraint?.isActive = false
        emptyLabelWidthConstraint = nil
        removeArrangedSubviewIfNeeded(emptyLabel, removeFromSuperview: true)
        let nextSectionIds = Set(sections.map(\.id))
        removeSections(except: nextSectionIds)

        var nextSectionViewsById: [UUID: TodoEditorSectionView] = [:]
        for (offset, section) in sections.enumerated() {
            let existingSectionView = sectionViewsById[section.id]
            let sectionView = existingSectionView ?? TodoEditorSectionView(snapshot: section, actions: actions)
            configureCallbacks(for: sectionView)
            sectionView.apply(snapshot: section, actions: actions)
            moveArrangedSubview(sectionView, to: offset)
            if sectionWidthConstraintsById[section.id] == nil {
                let constraint = sectionView.widthAnchor.constraint(equalTo: stackView.widthAnchor)
                constraint.isActive = true
                sectionWidthConstraintsById[section.id] = constraint
            }
            nextSectionViewsById[section.id] = sectionView
        }
        sectionViewsById = nextSectionViewsById
    }

    private func scrollFocusedItemToVisible(in sections: [TodoEditorSectionSnapshot]) {
        guard let focusedItemId = sections.lazy
            .flatMap(\.items)
            .first(where: \.isFocused)?
            .id
        else { return }
        view.layoutSubtreeIfNeeded()
        for sectionView in sectionViewsById.values
        where sectionView.scrollItemToVisible(focusedItemId) {
            return
        }
    }

    private func handleDragBegan(itemId: UUID, windowLocation: NSPoint) {
        draggingItemId = itemId
        dragSession.begin(itemId: itemId, screenLocation: screenLocation(from: windowLocation))
        actions.selectItem(itemId, false, nil)
        updateDrop(windowLocation: windowLocation)
    }

    private func handleDragChanged(itemId: UUID, windowLocation: NSPoint) {
        guard draggingItemId == itemId else { return }
        dragSession.update(screenLocation: screenLocation(from: windowLocation))
        updateDrop(windowLocation: windowLocation)
    }

    private func handleDragEnded(itemId: UUID, windowLocation: NSPoint) {
        guard draggingItemId == itemId else { return }
        updateDrop(windowLocation: windowLocation)

        defer {
            draggingItemId = nil
            activeDrop = nil
            dropIndicatorView.hide()
            dragSession.end()
            resetDragHandleStates()
        }

        if let activeDrop {
            actions.moveDraggedItem(
                itemId,
                activeDrop.destination,
                activeDrop.index,
                activeDrop.indentLevel
            )
            return
        }

        if let sidebarDestination = dragSession.hoveredSidebarDestination {
            actions.moveDraggedItemToSidebar(itemId, sidebarDestination)
        }
    }

    private func handleSelectionDragBegan(itemId: UUID, windowLocation: NSPoint) {
        dragSelectionSectionId = sectionSnapshot(containing: itemId)?.id
        actions.beginDragSelection(itemId, nil)
        handleSelectionDragChanged(itemId: itemId, windowLocation: windowLocation)
    }

    private func handleSelectionDragChanged(itemId: UUID, windowLocation: NSPoint) {
        let point = documentView.convert(windowLocation, from: nil)
        guard
            let sectionId = dragSelectionSectionId,
            let sectionView = sectionViewsById[sectionId],
            let targetId = sectionView.nearestItemId(at: point, documentView: documentView)
        else { return }

        actions.updateDragSelection(targetId)
    }

    private func handleSelectionDragEnded() {
        dragSelectionSectionId = nil
        actions.endDragSelection()
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
        let resolved = resolveDrop(
            in: section,
            point: point,
            itemFrames: frames,
            sectionView: sectionView
        )
        activeDrop = resolved

        if let indicatorY = indicatorY(for: resolved, section: section, itemFrames: frames, sectionView: sectionView) {
            dropIndicatorView.show(
                x: sectionView.indicatorLeadingX(in: documentView),
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

    private func sectionSnapshot(containing itemId: UUID) -> TodoEditorSectionSnapshot? {
        renderedSections.first { section in
            section.items.contains { $0.id == itemId }
        }
    }

    private func resolveDrop(
        in section: TodoEditorSectionSnapshot,
        point: CGPoint,
        itemFrames: [UUID: CGRect],
        sectionView: TodoEditorSectionView
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

        return TodoEditorDropResolver.resolvedDrop(
            destination: section.destination,
            index: index,
            x: point.x,
            baseX: sectionView.contentLeadingX(in: documentView) + 20,
            previousIndentLevel: index > 0 ? section.items[index - 1].indentLevel : nil
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

    private func screenLocation(from windowLocation: NSPoint) -> CGPoint {
        view.window?.convertPoint(toScreen: windowLocation) ?? windowLocation
    }

    private func resetDragHandleStates() {
        for sectionView in sectionViewsById.values {
            sectionView.resetDragHandleStates()
        }
    }

    private func configureCallbacks(for sectionView: TodoEditorSectionView) {
        sectionView.onDragBegan = { [weak self] itemId, location in
            self?.handleDragBegan(itemId: itemId, windowLocation: location)
        }
        sectionView.onDragChanged = { [weak self] itemId, location in
            self?.handleDragChanged(itemId: itemId, windowLocation: location)
        }
        sectionView.onDragEnded = { [weak self] itemId, location in
            self?.handleDragEnded(itemId: itemId, windowLocation: location)
        }
        sectionView.onSelectionDragBegan = { [weak self] itemId, location in
            self?.handleSelectionDragBegan(itemId: itemId, windowLocation: location)
        }
        sectionView.onSelectionDragChanged = { [weak self] itemId, location in
            self?.handleSelectionDragChanged(itemId: itemId, windowLocation: location)
        }
        sectionView.onSelectionDragEnded = { [weak self] in
            self?.handleSelectionDragEnded()
        }
    }

    private func moveArrangedSubview(_ subview: NSView, to index: Int) {
        if let currentIndex = stackView.arrangedSubviews.firstIndex(of: subview) {
            guard currentIndex != index else { return }
            stackView.removeArrangedSubview(subview)
        }
        stackView.insertArrangedSubview(subview, at: min(index, stackView.arrangedSubviews.count))
    }

    private func removeSections(except keptIds: Set<UUID>) {
        for (id, sectionView) in sectionViewsById where keptIds.contains(id) == false {
            removeArrangedSubviewIfNeeded(sectionView, removeFromSuperview: true)
            sectionWidthConstraintsById[id]?.isActive = false
            sectionWidthConstraintsById[id] = nil
        }
        sectionViewsById = sectionViewsById.filter { keptIds.contains($0.key) }
    }

    private func removeArrangedSubviewIfNeeded(_ subview: NSView, removeFromSuperview: Bool) {
        if stackView.arrangedSubviews.contains(subview) {
            stackView.removeArrangedSubview(subview)
        }
        if removeFromSuperview {
            subview.removeFromSuperview()
        }
    }
}

struct TodoEditorResolvedDrop: Equatable {
    let destination: TodoDropDestination
    let index: Int
    let indentLevel: Int
}

enum TodoEditorDropResolver {
    static func resolvedDrop(
        destination: TodoDropDestination,
        index: Int,
        x: CGFloat,
        baseX: CGFloat,
        previousIndentLevel: Int?
    ) -> TodoEditorResolvedDrop {
        var indentLevel = Int(max(0, x - baseX) / TodoDesignTokens.indentWidth)
        if let previousIndentLevel {
            indentLevel = min(indentLevel, previousIndentLevel + 1)
        } else {
            indentLevel = 0
        }

        return TodoEditorResolvedDrop(
            destination: destination,
            index: index,
            indentLevel: min(indentLevel, TodoItem.maxIndentLevel)
        )
    }
}

private final class TodoEditorDocumentView: NSView {
    override var isFlipped: Bool { true }
}
