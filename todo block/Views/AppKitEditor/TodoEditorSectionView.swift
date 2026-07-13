//
//  TodoEditorSectionView.swift
//  todo block
//

import AppKit
import SwiftUI

@MainActor
final class TodoEditorSectionView: NSView {
    private let stackView = NSStackView()
    private let titleButton = NSButton(title: "", target: nil, action: nil)
    private let emptyButton = NSButton(title: "添加待办", target: nil, action: nil)

    private var actions: TodoEditorActions
    private var snapshot: TodoEditorSectionSnapshot?
    private var rowViewsById: [UUID: TodoEditorRowView] = [:]
    private var rowWidthConstraintsById: [UUID: NSLayoutConstraint] = [:]
    private var popover: NSPopover?
    private var activeDatePicker: NSDatePicker?

    var onDragBegan: ((UUID, NSPoint) -> Void)?
    var onDragChanged: ((UUID, NSPoint) -> Void)?
    var onDragEnded: ((UUID, NSPoint) -> Void)?
    var onSelectionDragBegan: ((UUID, NSPoint) -> Void)?
    var onSelectionDragChanged: ((UUID, NSPoint) -> Void)?
    var onSelectionDragEnded: (() -> Void)?

    init(snapshot: TodoEditorSectionSnapshot, actions: TodoEditorActions) {
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
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 0

        titleButton.isBordered = false
        titleButton.alignment = .left
        titleButton.font = .systemFont(ofSize: 20, weight: .bold)
        titleButton.contentTintColor = .labelColor
        titleButton.target = self
        titleButton.action = #selector(showDatePicker)

        emptyButton.isBordered = false
        emptyButton.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "添加待办")
        emptyButton.imagePosition = .imageLeading
        emptyButton.contentTintColor = .controlAccentColor
        emptyButton.target = self
        emptyButton.action = #selector(addItem)

        wantsLayer = true
        layer?.backgroundColor = NSColor(TodoDesignTokens.bucketTint).cgColor
        layer?.cornerRadius = TodoDesignTokens.bucketCornerRadius

        addSubview(stackView)
        stackView.addArrangedSubview(titleButton)
        stackView.setCustomSpacing(12, after: titleButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    func apply(snapshot: TodoEditorSectionSnapshot, actions: TodoEditorActions? = nil) {
        if let actions {
            self.actions = actions
        }
        self.snapshot = snapshot

        titleButton.title = snapshot.title
        titleButton.isEnabled = snapshot.editableDate != nil

        if snapshot.items.isEmpty {
            removeRows(except: [])
            if snapshot.allowsAdding {
                moveArrangedSubview(emptyButton, to: 1)
            } else {
                removeArrangedSubviewIfNeeded(emptyButton, removeFromSuperview: true)
            }
            return
        }

        removeArrangedSubviewIfNeeded(emptyButton, removeFromSuperview: true)
        let nextIds = Set(snapshot.items.map(\.id))
        removeRows(except: nextIds)

        var nextRowsById: [UUID: TodoEditorRowView] = [:]
        for (offset, item) in snapshot.items.enumerated() {
            let existingRowView = rowViewsById[item.id]
            let rowView = existingRowView ?? TodoEditorRowView(snapshot: item, actions: self.actions)
            configureCallbacks(for: rowView)
            rowView.apply(snapshot: item, actions: self.actions)
            moveArrangedSubview(rowView, to: offset + 1)
            if rowWidthConstraintsById[item.id] == nil {
                let constraint = rowView.widthAnchor.constraint(equalTo: stackView.widthAnchor)
                constraint.isActive = true
                rowWidthConstraintsById[item.id] = constraint
            }
            nextRowsById[item.id] = rowView
        }
        rowViewsById = nextRowsById
    }

    func itemFrames(in targetView: NSView) -> [UUID: CGRect] {
        rowViewsById.reduce(into: [:]) { result, element in
            result[element.key] = element.value.convert(element.value.bounds, to: targetView)
        }
    }

    func contains(pointInDocument: CGPoint, documentView: NSView) -> Bool {
        let frame = convert(bounds, to: documentView)
        return frame.contains(pointInDocument)
    }

    func contentLeadingX(in documentView: NSView) -> CGFloat {
        stackView.convert(stackView.bounds, to: documentView).minX
    }

    func indicatorLeadingX(in documentView: NSView) -> CGFloat {
        contentLeadingX(in: documentView)
    }

    func nearestItemId(at pointInDocument: CGPoint, documentView: NSView) -> UUID? {
        guard rowViewsById.isEmpty == false else { return nil }

        var best: (id: UUID, distance: CGFloat)?
        for (id, rowView) in rowViewsById {
            let frame = rowView.convert(rowView.bounds, to: documentView)
            if frame.minY <= pointInDocument.y && pointInDocument.y <= frame.maxY {
                return id
            }

            let distance = pointInDocument.y < frame.minY
                ? frame.minY - pointInDocument.y
                : pointInDocument.y - frame.maxY
            if best == nil || distance < best!.distance {
                best = (id, distance)
            }
        }

        return best?.id
    }

    func resetDragHandleStates() {
        for rowView in rowViewsById.values {
            rowView.resetDragHandleState()
        }
    }

    @discardableResult
    func scrollItemToVisible(_ itemId: UUID) -> Bool {
        guard let rowView = rowViewsById[itemId] else { return false }
        rowView.scrollToVisible(rowView.bounds.insetBy(dx: 0, dy: -8))
        return true
    }

    @objc private func addItem() {
        guard let snapshot else { return }
        actions.addItem(snapshot.destination)
    }

    @objc private func showDatePicker() {
        guard let snapshot, let editableDate = snapshot.editableDate else { return }

        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.dateValue = editableDate

        let confirmButton = NSButton(title: "确认", target: nil, action: nil)
        let cancelButton = NSButton(title: "取消", target: nil, action: nil)
        let buttonStack = NSStackView(views: [cancelButton, NSView(), confirmButton])
        buttonStack.orientation = .horizontal
        buttonStack.distribution = .fill

        let contentStack = NSStackView(views: [picker, buttonStack])
        contentStack.orientation = .vertical
        contentStack.spacing = 12
        contentStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let controller = NSViewController()
        controller.view = contentStack
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.widthAnchor.constraint(equalToConstant: 300),
            contentStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller

        cancelButton.target = self
        cancelButton.action = #selector(closeDatePicker)
        confirmButton.target = self
        confirmButton.action = #selector(confirmDatePicker(_:))
        activeDatePicker = picker

        self.popover = popover
        popover.show(relativeTo: titleButton.bounds, of: titleButton, preferredEdge: .maxY)
    }

    @objc private func closeDatePicker() {
        popover?.close()
        popover = nil
        activeDatePicker = nil
    }

    @objc private func confirmDatePicker(_ sender: NSButton) {
        guard
            let snapshot,
            let picker = activeDatePicker
        else { return }

        actions.sectionDateChanged(snapshot.id, picker.dateValue)
        closeDatePicker()
    }

    private func configureCallbacks(for rowView: TodoEditorRowView) {
        rowView.onDragBegan = { [weak self] itemId, location in
            self?.onDragBegan?(itemId, location)
        }
        rowView.onDragChanged = { [weak self] itemId, location in
            self?.onDragChanged?(itemId, location)
        }
        rowView.onDragEnded = { [weak self] itemId, location in
            self?.onDragEnded?(itemId, location)
        }
        rowView.onSelectionDragBegan = { [weak self] itemId, location in
            self?.onSelectionDragBegan?(itemId, location)
        }
        rowView.onSelectionDragChanged = { [weak self] itemId, location in
            self?.onSelectionDragChanged?(itemId, location)
        }
        rowView.onSelectionDragEnded = { [weak self] in
            self?.onSelectionDragEnded?()
        }
    }

    private func moveArrangedSubview(_ subview: NSView, to index: Int) {
        if let currentIndex = stackView.arrangedSubviews.firstIndex(of: subview) {
            guard currentIndex != index else { return }
            stackView.removeArrangedSubview(subview)
        }
        stackView.insertArrangedSubview(subview, at: min(index, stackView.arrangedSubviews.count))
    }

    private func removeRows(except keptIds: Set<UUID>) {
        for (id, rowView) in rowViewsById where keptIds.contains(id) == false {
            removeArrangedSubviewIfNeeded(rowView, removeFromSuperview: true)
            rowWidthConstraintsById[id]?.isActive = false
            rowWidthConstraintsById[id] = nil
        }
        rowViewsById = rowViewsById.filter { keptIds.contains($0.key) }
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
