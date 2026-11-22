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

    private var editorEntry: TodoEditorEntry
    private var snapshot: TodoEditorSectionSnapshot?
    private var rowViewsById: [UUID: TodoEditorRowView] = [:]
    private var rowWidthConstraintsById: [UUID: NSLayoutConstraint] = [:]
    private var popover: NSPopover?

    /// 控制器直接为每个行视图接入原生识别回调；分区本身不再转发动作。
    var configureRow: ((TodoEditorRowView) -> Void)?

    init(snapshot: TodoEditorSectionSnapshot, editorEntry: TodoEditorEntry) {
        self.editorEntry = editorEntry
        super.init(frame: .zero)
        configureViewHierarchy()
        apply(snapshot: snapshot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        editorEntry.clearSelection()
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

    func bind(editorEntry: TodoEditorEntry) {
        self.editorEntry = editorEntry
        for rowView in rowViewsById.values {
            rowView.bind(editorEntry: editorEntry)
        }
    }

    func apply(snapshot: TodoEditorSectionSnapshot) {
        self.snapshot = snapshot

        titleButton.title = snapshot.title
        titleButton.isEnabled = snapshot.editableDate != nil && editorEntry.access.isEditable
        titleButton.toolTip = editorEntry.access.isEditable ? nil : "只读列表"

        if snapshot.items.isEmpty {
            removeRows(except: [])
            if snapshot.allowsAdding {
                emptyButton.isEnabled = editorEntry.access.isEditable
                emptyButton.toolTip = editorEntry.access.isEditable ? nil : "只读列表"
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
            let rowView = existingRowView
                ?? TodoEditorRowView(snapshot: item, editorEntry: self.editorEntry)
            configureRow?(rowView)
            rowView.apply(snapshot: item)
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
        guard editorEntry.access.isEditable, let snapshot else { return }
        editorEntry.addItem(snapshot.destination)
    }

    @objc private func showDatePicker() {
        guard editorEntry.access.isEditable,
              let snapshot,
              let editableDate = snapshot.editableDate
        else { return }
        guard editorEntry.claimCurrentList() else { return }

        closeDatePicker()
        let sectionId = snapshot.id
        let controller = NSHostingController(rootView: TodoEditorDatePicker(
            date: editableDate,
            canConfirm: { [weak self] date in
                guard let self, self.snapshot?.id == sectionId else { return false }
                return self.editorEntry.canChangeSectionDate(editableDate, date)
            },
            onCancel: { [weak self] in self?.closeDatePicker() },
            onConfirm: { [weak self] date in
                guard let self else { return }
                self.closeDatePicker()
                guard self.snapshot?.id == sectionId else { return }
                self.editorEntry.sectionDateChanged(sectionId, date)
            }
        ))

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize

        self.popover = popover
        popover.show(relativeTo: titleButton.bounds, of: titleButton, preferredEdge: .maxY)
    }

    private func closeDatePicker() {
        popover?.close()
        popover = nil
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
