//
//  TodoEditorSectionView.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorSectionView: NSView {
    private let stackView = NSStackView()
    private let titleButton = NSButton(title: "", target: nil, action: nil)
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let emptyButton = NSButton(title: "添加待办", target: nil, action: nil)

    private var actions: TodoEditorActions
    private var snapshot: TodoEditorSectionSnapshot?
    private var rowViewsById: [UUID: TodoEditorRowView] = [:]
    private var popover: NSPopover?
    private var activeDatePicker: NSDatePicker?

    var onDragBegan: ((UUID, NSPoint) -> Void)?
    var onDragChanged: ((UUID, NSPoint) -> Void)?
    var onDragEnded: ((UUID, NSPoint) -> Void)?

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
        stackView.spacing = 6

        titleButton.isBordered = false
        titleButton.alignment = .left
        titleButton.font = .preferredFont(forTextStyle: .headline)
        titleButton.contentTintColor = .labelColor
        titleButton.target = self
        titleButton.action = #selector(showDatePicker)

        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 1

        emptyButton.isBordered = false
        emptyButton.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "添加待办")
        emptyButton.imagePosition = .imageLeading
        emptyButton.contentTintColor = .controlAccentColor
        emptyButton.target = self
        emptyButton.action = #selector(addItem)

        addSubview(stackView)
        stackView.addArrangedSubview(titleButton)
        stackView.addArrangedSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func apply(snapshot: TodoEditorSectionSnapshot, actions: TodoEditorActions? = nil) {
        if let actions {
            self.actions = actions
        }
        self.snapshot = snapshot

        titleButton.title = snapshot.title
        titleButton.isEnabled = snapshot.editableDate != nil
        subtitleLabel.stringValue = snapshot.subtitle

        removeRowsAndEmptyButtonFromStack()

        if snapshot.items.isEmpty {
            if snapshot.allowsAdding {
                stackView.addArrangedSubview(emptyButton)
            }
            return
        }

        var nextRowsById: [UUID: TodoEditorRowView] = [:]
        for item in snapshot.items {
            let existingRowView = rowViewsById[item.id]
            let rowView = existingRowView ?? TodoEditorRowView(snapshot: item, actions: self.actions)
            rowView.onDragBegan = { [weak self] itemId, location in
                self?.onDragBegan?(itemId, location)
            }
            rowView.onDragChanged = { [weak self] itemId, location in
                self?.onDragChanged?(itemId, location)
            }
            rowView.onDragEnded = { [weak self] itemId, location in
                self?.onDragEnded?(itemId, location)
            }
            rowView.apply(snapshot: item)
            stackView.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
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

    private func removeRowsAndEmptyButtonFromStack() {
        for view in stackView.arrangedSubviews.dropFirst(2) {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}
