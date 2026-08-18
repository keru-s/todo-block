//
//  TodoEditorViewController.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let clipView = TodoEditorClipView()
    private let documentView = TodoEditorDocumentView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let dropIndicatorView = TodoEditorDropIndicatorView()

    private var renderedSections: [TodoEditorSectionSnapshot] = []
    private var renderedEmptyTitle: String = ""
    private var editorEntry: TodoEditorEntry = .readOnly
    private var renderedEditorAccess: TodoEditorAccess = .readOnly
    private var sectionViewsById: [UUID: TodoEditorSectionView] = [:]
    private var sectionWidthConstraintsById: [UUID: NSLayoutConstraint] = [:]
    private var emptyLabelWidthConstraint: NSLayoutConstraint?
    private var activeDrop: TodoEditorResolvedDrop?
    private var lastRevealRequestId: UUID?
    private var dragSelectionSectionId: UUID?
    private var lastSelectionDragWindowLocation: NSPoint?
    private var selectionAutoscrollTask: Task<Void, Never>?
    private var itemAutoscrollTask: Task<Void, Never>?
    private let continuousInteraction = TodoEditorContinuousInteraction()
    private var itemDragInteractionToken: TodoEditorContinuousInteractionToken?
    private var selectionDragInteractionToken: TodoEditorContinuousInteractionToken?
    private var windowObserverTokens: [NSObjectProtocol] = []
    private let dragSession = TodoEditorDragSession.shared
    private var dragSessionObserverId: TodoEditorDragSession.ObserverID?

    override func loadView() {
        view = NSView()
        configureViewHierarchy()
        configureEmptyLabel()
        installWindowObservers()
        registerDragSessionObserver()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        registerDragSessionObserver()
    }

    private func registerDragSessionObserver() {
        guard dragSessionObserverId == nil else { return }
        dragSessionObserverId = dragSession.addObserver(
            onSidebarTargetInvalidated: { [weak self] destination in
                self?.handleSidebarTargetInvalidated(destination)
            },
            onExternalAction: { [weak self] in
                self?.interruptContinuousInteractionBeforeExplicitAction()
            }
        )
    }

    override func viewWillDisappear() {
        cancelItemDrag()
        if let token = selectionDragInteractionToken {
            handleSelectionDragCancelled(token: token)
        }
        continuousInteraction.clear()
        if let observerId = dragSessionObserverId {
            dragSession.removeObserver(observerId)
            dragSessionObserverId = nil
        }
        super.viewWillDisappear()
    }

    deinit {
        selectionAutoscrollTask?.cancel()
        itemAutoscrollTask?.cancel()
        for token in windowObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func update(
        sections: [TodoEditorSectionSnapshot],
        emptyTitle: String,
        editorEntry: TodoEditorEntry,
        revealRequest: TodoHistoryRevealRequest? = nil
    ) {
        loadViewIfNeeded()
        let coordinatedEditorEntry = editorEntry.withBeforeExplicitAction { [weak self] in
            self?.interruptContinuousInteractionBeforeExplicitAction()
        }
        let contentChanged = sections != renderedSections
            || emptyTitle != renderedEmptyTitle
            || editorEntry.access != renderedEditorAccess

        if contentChanged {
            renderedSections = sections
            renderedEmptyTitle = emptyTitle
            renderedEditorAccess = editorEntry.access
            cleanupItemDragIfTargetDisappeared()
            cleanupSelectionInteractionIfTargetDisappeared()
        }

        self.editorEntry = coordinatedEditorEntry

        if contentChanged {
            rebuildContent(sections: sections, emptyTitle: emptyTitle)
        }

        if let revealRequest,
           revealRequest.id != lastRevealRequestId,
           let itemId = revealRequest.itemId {
            lastRevealRequestId = revealRequest.id
            scrollItemToVisible(itemId)
        }

        cleanupItemDragIfTargetDisappeared()
        cleanupSelectionInteractionIfTargetDisappeared()
    }

    private func configureViewHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentView = clipView

        clipView.onBackgroundClick = { [weak self] in
            self?.handleBackgroundClick()
        }

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.onBackgroundClick = { [weak self] in
            self?.handleBackgroundClick()
        }

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
            let sectionView = existingSectionView
                ?? TodoEditorSectionView(snapshot: section, editorEntry: editorEntry)
            sectionView.configureRow = { [weak self] rowView in
                self?.configureCallbacks(for: rowView)
            }
            sectionView.apply(snapshot: section, editorEntry: editorEntry)
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

    private func scrollItemToVisible(_ itemId: UUID) {
        view.layoutSubtreeIfNeeded()
        for sectionView in sectionViewsById.values
        where sectionView.scrollItemToVisible(itemId) {
            return
        }
    }

    private func handleDragBegan(
        itemId: UUID,
        windowLocation: NSPoint
    ) -> TodoEditorContinuousInteractionToken? {
        guard continuousInteraction.isActive == false,
              editorEntry.prepareItemDrag(itemId)
        else { return nil }
        guard let token = continuousInteraction.beginItemDrag(
            itemId: itemId,
            location: windowLocation
        ) else { return nil }
        itemDragInteractionToken = token
        dragSession.begin(itemId: itemId, screenLocation: screenLocation(from: windowLocation))
        startItemAutoscroll()
        handleDragChanged(
            itemId: itemId,
            windowLocation: windowLocation,
            token: token
        )
        return token
    }

    private func handleDragChanged(
        itemId: UUID,
        windowLocation: NSPoint,
        token: TodoEditorContinuousInteractionToken
    ) {
        guard itemDragInteractionToken == token,
              continuousInteraction.accepts(
                  token: token,
                  itemId: itemId,
                  kind: .itemDrag
        )
        else { return }
        _ = continuousInteraction.updateLocation(
            token: token,
            itemId: itemId,
            location: windowLocation
        )
        dragSession.update(screenLocation: screenLocation(from: windowLocation))
        if let sidebarDestination = dragSession.hoveredSidebarDestination {
            _ = continuousInteraction.update(
                token: token,
                itemId: itemId,
                location: windowLocation,
                sidebarDestination: sidebarDestination
            )
        } else {
            _ = continuousInteraction.clearSidebarTarget(
                token: token,
                itemId: itemId
            )
        }
        updateDrop(windowLocation: windowLocation, token: token)
    }

    private func handleDragEnded(
        itemId: UUID,
        windowLocation: NSPoint,
        token: TodoEditorContinuousInteractionToken
    ) {
        guard itemDragInteractionToken == token,
              continuousInteraction.accepts(
                  token: token,
                  itemId: itemId,
                  kind: .itemDrag
              )
        else { return }

        if let sidebarDestination = continuousInteraction.targetSidebarDestination,
           dragSession.isSidebarTargetRegistered(sidebarDestination) == false {
            cancelItemDrag(token: token)
            return
        }

        handleDragChanged(
            itemId: itemId,
            windowLocation: windowLocation,
            token: token
        )

        // 侧栏目标优先于编辑区落点；编辑区外松开时回退到过程里保存的
        // 最后有效落点。提交前先使 token 失效，避免同步刷新产生迟到回调。
        let sidebarDestination = dragSession.hoveredSidebarDestination
        let resolvedDrop = activeDrop ?? continuousInteraction.lastValidDrop.map {
            TodoEditorResolvedDrop(
                destination: $0.destination,
                index: $0.index,
                indentLevel: $0.indentLevel
            )
        }
        let canSubmitResolvedDrop = resolvedDrop.map(isDropStillAvailable) ?? false
        finishItemDrag(token: token)

        if let sidebarDestination {
            editorEntry.moveDraggedItemToSidebar(itemId, sidebarDestination)
        } else if canSubmitResolvedDrop, let resolvedDrop {
            editorEntry.moveDraggedItem(
                itemId,
                resolvedDrop.destination,
                resolvedDrop.index,
                resolvedDrop.indentLevel
            )
        }
    }

    @discardableResult
    private func handleSelectionDragBegan(
        itemId: UUID,
        windowLocation: NSPoint
    ) -> TodoEditorContinuousInteractionToken? {
        guard let sectionId = sectionSnapshot(containing: itemId)?.id,
              let token = continuousInteraction.beginCrossItemSelection(
                  itemId: itemId,
                  sectionId: sectionId,
                  location: windowLocation
              )
        else { return nil }

        selectionDragInteractionToken = token
        dragSelectionSectionId = sectionId
        guard editorEntry.beginDragSelection(itemId, nil) else {
            editorEntry.discardPreparedDragSelection()
            selectionDragInteractionToken = nil
            dragSelectionSectionId = nil
            _ = continuousInteraction.cancel(token: token)
            return nil
        }
        startSelectionAutoscroll()
        handleSelectionDragChanged(
            itemId: itemId,
            windowLocation: windowLocation,
            token: token
        )
        return token
    }

    private func handleSelectionDragChanged(
        itemId: UUID,
        windowLocation: NSPoint,
        token: TodoEditorContinuousInteractionToken
    ) {
        guard selectionDragInteractionToken == token,
              continuousInteraction.accepts(
                  token: token,
                  itemId: itemId,
                  kind: .crossItemSelection
              )
        else { return }

        let targetId = updateSelectionDragTarget(at: windowLocation)
        _ = continuousInteraction.update(
            token: token,
            itemId: itemId,
            location: windowLocation,
            targetItemId: targetId
        )
        if let lastValidLocation = continuousInteraction.lastValidLocation {
            lastSelectionDragWindowLocation = NSPoint(
                x: lastValidLocation.x,
                y: lastValidLocation.y
            )
        }
        guard targetId != nil else {
            cleanupSelectionInteractionIfTargetDisappeared()
            return
        }
        autoscrollSelectionIfNeeded(at: windowLocation)
    }

    @discardableResult
    private func updateSelectionDragTarget(at windowLocation: NSPoint) -> UUID? {
        let point = documentView.convert(windowLocation, from: nil)
        guard
            let sectionId = dragSelectionSectionId,
            let sectionView = sectionViewsById[sectionId],
            let targetId = sectionView.nearestItemId(at: point, documentView: documentView)
        else { return nil }

        editorEntry.updateDragSelection(targetId)
        return targetId
    }

    @discardableResult
    private func autoscrollSelectionIfNeeded(at windowLocation: NSPoint) -> Bool {
        let clipView = scrollView.contentView
        let location = clipView.convert(windowLocation, from: nil)
        let edgeInset: CGFloat = 24
        let delta: CGFloat
        if location.y < clipView.bounds.minY + edgeInset {
            delta = -8
        } else if location.y > clipView.bounds.maxY - edgeInset {
            delta = 8
        } else {
            return false
        }
        let documentMaximumY = max(0, documentView.bounds.height - clipView.bounds.height)
        let sectionScrollBounds: (minY: CGFloat, maxY: CGFloat) = {
            guard let sectionId = dragSelectionSectionId,
                  let sectionView = sectionViewsById[sectionId]
            else {
                return (0, documentMaximumY)
            }
            let sectionFrame = sectionView.convert(sectionView.bounds, to: documentView)
            let minY = min(max(0, sectionFrame.minY), documentMaximumY)
            let maxY = min(
                documentMaximumY,
                max(minY, sectionFrame.maxY - clipView.bounds.height)
            )
            return (minY, maxY)
        }()
        let origin = NSPoint(
            x: clipView.bounds.origin.x,
            y: min(
                max(
                    sectionScrollBounds.minY,
                    clipView.bounds.origin.y + delta
                ),
                sectionScrollBounds.maxY
            )
        )
        guard origin.y != clipView.bounds.origin.y else { return false }
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    private func handleSelectionDragEnded(
        at windowLocation: NSPoint? = nil,
        token: TodoEditorContinuousInteractionToken
    ) {
        guard selectionDragInteractionToken == token,
              continuousInteraction.accepts(
                  token: token,
                  kind: .crossItemSelection
              )
        else { return }
        if let windowLocation,
           let itemId = continuousInteraction.activeState?.itemId {
            handleSelectionDragChanged(
                itemId: itemId,
                windowLocation: windowLocation,
                token: token
            )
        }
        stopSelectionAutoscroll()
        dragSelectionSectionId = nil
        lastSelectionDragWindowLocation = nil
        selectionDragInteractionToken = nil
        _ = continuousInteraction.end(token: token)
        editorEntry.endDragSelection()
    }

    private func handleSelectionDragCancelled(
        token: TodoEditorContinuousInteractionToken
    ) {
        guard selectionDragInteractionToken == token,
              continuousInteraction.accepts(
                  token: token,
                  kind: .crossItemSelection
              )
        else { return }
        stopSelectionAutoscroll()
        dragSelectionSectionId = nil
        lastSelectionDragWindowLocation = nil
        selectionDragInteractionToken = nil
        _ = continuousInteraction.cancel(token: token)
        editorEntry.cancelDragSelection()
    }

    private func startSelectionAutoscroll() {
        stopSelectionAutoscroll()
        selectionAutoscrollTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                guard let self,
                      let location = lastSelectionDragWindowLocation,
                      dragSelectionSectionId != nil,
                      let token = selectionDragInteractionToken,
                      continuousInteraction.accepts(
                          token: token,
                          kind: .crossItemSelection
                      )
                else { return }
                if autoscrollSelectionIfNeeded(at: location) {
                    let targetId = updateSelectionDragTarget(at: location)
                    if let itemId = continuousInteraction.activeState?.itemId {
                        _ = continuousInteraction.update(
                            token: token,
                            itemId: itemId,
                            location: location,
                            targetItemId: targetId
                        )
                    }
                    if targetId == nil {
                        cleanupSelectionInteractionIfTargetDisappeared()
                    }
                }
            }
        }
    }

    private func stopSelectionAutoscroll() {
        selectionAutoscrollTask?.cancel()
        selectionAutoscrollTask = nil
    }

    private func startItemAutoscroll() {
        stopItemAutoscroll()
        itemAutoscrollTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                guard let self,
                      let token = itemDragInteractionToken,
                      continuousInteraction.accepts(
                          token: token,
                          kind: .itemDrag
                      ),
                      let location = continuousInteraction.lastLocation,
                      let itemId = continuousInteraction.activeState?.itemId
                else { return }

                if autoscrollItemIfNeeded(at: location) {
                    handleDragChanged(
                        itemId: itemId,
                        windowLocation: location,
                        token: token
                    )
                }
            }
        }
    }

    private func stopItemAutoscroll() {
        itemAutoscrollTask?.cancel()
        itemAutoscrollTask = nil
    }

    @discardableResult
    private func autoscrollItemIfNeeded(at windowLocation: NSPoint) -> Bool {
        let location = clipView.convert(windowLocation, from: nil)
        let edgeInset: CGFloat = 24
        let delta: CGFloat
        if location.y < clipView.bounds.minY + edgeInset {
            delta = -8
        } else if location.y > clipView.bounds.maxY - edgeInset {
            delta = 8
        } else {
            return false
        }

        let documentMaximumY = max(0, documentView.bounds.height - clipView.bounds.height)
        let origin = NSPoint(
            x: clipView.bounds.origin.x,
            y: min(
                max(0, clipView.bounds.origin.y + delta),
                documentMaximumY
            )
        )
        guard origin.y != clipView.bounds.origin.y else { return false }
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    private func finishItemDrag(token: TodoEditorContinuousInteractionToken) {
        guard continuousInteraction.accepts(
            token: token,
            kind: .itemDrag
        ) else { return }
        stopItemAutoscroll()
        activeDrop = nil
        dropIndicatorView.hide()
        dragSession.end()
        resetDragHandleStates()
        itemDragInteractionToken = nil
        _ = continuousInteraction.end(token: token)
    }

    private func cancelItemDrag(token expectedToken: TodoEditorContinuousInteractionToken? = nil) {
        guard let token = expectedToken ?? itemDragInteractionToken,
              itemDragInteractionToken == token,
              continuousInteraction.accepts(
                  token: token,
                  kind: .itemDrag
              )
        else { return }
        stopItemAutoscroll()
        activeDrop = nil
        dropIndicatorView.hide()
        dragSession.end()
        resetDragHandleStates()
        itemDragInteractionToken = nil
        _ = continuousInteraction.cancel(token: token)
    }

    private func handleBackgroundClick() {
        view.window?.makeFirstResponder(nil)
        editorEntry.clearSelection()
    }

    private func interruptContinuousInteractionBeforeExplicitAction() {
        if let token = selectionDragInteractionToken {
            handleSelectionDragEnded(token: token)
        }
        if let token = itemDragInteractionToken {
            cancelItemDrag(token: token)
        }
    }

    private func handleSidebarTargetInvalidated(_ destination: SidebarDestination) {
        guard let token = itemDragInteractionToken,
              continuousInteraction.targetSidebarDestination == destination
        else { return }
        cancelItemDrag(token: token)
    }

    private func installWindowObservers() {
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResignMainNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let window = notification.object as? NSWindow,
                          window === self.view.window
                    else { return }
                    self.cancelItemDrag()
                    self.finishSelectionWhenWindowResigns()
                }
            }
            windowObserverTokens.append(token)
        }
    }

    private func finishSelectionWhenWindowResigns() {
        guard let token = selectionDragInteractionToken else { return }
        handleSelectionDragEnded(token: token)
    }

    /// SwiftUI 刷新或列表切换可能移除拖动源或最后命中的目标。此时不再
    /// 尝试提交旧落点，统一取消整个待办拖动过程。
    private func cleanupItemDragIfTargetDisappeared() {
        guard let token = itemDragInteractionToken,
              let state = continuousInteraction.activeState,
              state.token == token,
              state.kind == .itemDrag
        else { return }

        let sourceStillExists = renderedSections.contains { section in
            section.items.contains { $0.id == state.itemId }
        }
        guard sourceStillExists else {
            cancelItemDrag()
            return
        }

        if let targetItemId = state.targetItemId {
            let targetStillExists = renderedSections.contains { section in
                section.id == targetItemId
                    || section.items.contains { $0.id == targetItemId }
            }
            guard targetStillExists else {
                cancelItemDrag()
                return
            }
        }

        if let lastValidDrop = state.lastValidDrop,
           renderedSections.contains(where: {
               $0.destination.normalized == lastValidDrop.destination.normalized
           }) == false {
            cancelItemDrag()
            return
        }

        if let sidebarDestination = state.targetSidebarDestination,
           dragSession.isSidebarTargetRegistered(sidebarDestination) == false {
            cancelItemDrag()
        }
    }

    /// SwiftUI 刷新可能在鼠标事件序列尚未结束时移除起始分组或起始待办。
    /// 这时不能让自动滚动任务和迟到回调继续引用旧目标；结束过程会保留
    /// 当前可见的选择，并清掉 `SelectionManager` 的连续状态。
    private func cleanupSelectionInteractionIfTargetDisappeared() {
        guard let token = selectionDragInteractionToken,
              let state = continuousInteraction.activeState,
              state.token == token,
              state.kind == .crossItemSelection
        else { return }

        let sectionStillExists = renderedSections.contains { $0.id == state.sectionId }
        let sourceStillExists = renderedSections.contains { section in
            section.id == state.sectionId && section.items.contains { $0.id == state.itemId }
        }
        guard sectionStillExists && sourceStillExists else {
            handleSelectionDragCancelled(token: token)
            return
        }

        if let targetItemId = state.targetItemId {
            let targetStillExists = renderedSections.contains { section in
                section.items.contains { $0.id == targetItemId }
            }
            guard targetStillExists else {
                handleSelectionDragCancelled(token: token)
                return
            }
        }
    }

    private func updateDrop(
        windowLocation: NSPoint,
        token: TodoEditorContinuousInteractionToken? = nil
    ) {
        if let token {
            _ = continuousInteraction.updateLocation(
                token: token,
                itemId: continuousInteraction.activeState?.itemId,
                location: windowLocation
            )
        }
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

        if let token,
           let itemId = continuousInteraction.activeState?.itemId,
           continuousInteraction.accepts(
               token: token,
               itemId: itemId,
               kind: .itemDrag
           ) {
            _ = continuousInteraction.update(
                token: token,
                itemId: itemId,
                location: windowLocation,
                targetItemId: dropTargetItemId(for: resolved, section: section),
                validDrop: TodoEditorContinuousDropLocation(
                    destination: resolved.destination,
                    index: resolved.index,
                    indentLevel: resolved.indentLevel
                )
            )
        }

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

    private func dropTargetItemId(
        for drop: TodoEditorResolvedDrop,
        section: TodoEditorSectionSnapshot
    ) -> UUID? {
        guard section.items.isEmpty == false else { return section.id }
        if section.items.indices.contains(drop.index) {
            return section.items[drop.index].id
        }
        return section.items.last?.id ?? section.id
    }

    private func isDropStillAvailable(_ drop: TodoEditorResolvedDrop) -> Bool {
        renderedSections.contains { section in
            section.destination.normalized == drop.destination.normalized
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

    private func configureCallbacks(for rowView: TodoEditorRowView) {
        rowView.onDragBegan = { [weak self] itemId, location in
            self?.handleDragBegan(itemId: itemId, windowLocation: location)
        }
        rowView.onDragChanged = { [weak self] itemId, location, token in
            self?.handleDragChanged(
                itemId: itemId,
                windowLocation: location,
                token: token
            )
        }
        rowView.onDragEnded = { [weak self] itemId, location, token in
            self?.handleDragEnded(
                itemId: itemId,
                windowLocation: location,
                token: token
            )
        }
        rowView.onDragCancelled = { [weak self] token in
            guard let self else { return false }
            cancelItemDrag(token: token)
            return true
        }
        rowView.onSelectionDragBeganResult = { [weak self] itemId, location in
            self?.handleSelectionDragBegan(itemId: itemId, windowLocation: location)
        }
        rowView.onSelectionDragChanged = { [weak self] itemId, location, token in
            self?.handleSelectionDragChanged(
                itemId: itemId,
                windowLocation: location,
                token: token
            )
        }
        rowView.onSelectionDragEnded = { [weak self] location, token in
            self?.handleSelectionDragEnded(at: location, token: token)
        }
        rowView.onSelectionDragCancelled = { [weak self] token in
            self?.handleSelectionDragCancelled(token: token)
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
    var onBackgroundClick: (() -> Void)?

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
    }
}

private final class TodoEditorClipView: NSClipView {
    var onBackgroundClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
    }
}
