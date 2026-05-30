//
//  TodoEditorRowView.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorRowView: NSView {
    private let stackView = NSStackView()
    private let indentSpacer = NSView()
    private let handleLabel = NSTextField(labelWithString: "")
    private let completionButton = NSButton()
    private let titleTextView = TodoEditorTextView()
    private let actions: TodoEditorActions
    private var itemId: UUID?
    private var indentConstraint: NSLayoutConstraint?
    private var isApplyingSnapshot = false

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
        stackView.spacing = 6

        handleLabel.stringValue = "≡"
        handleLabel.font = .preferredFont(forTextStyle: .caption1)
        handleLabel.textColor = .tertiaryLabelColor
        handleLabel.alignment = .center

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

        addSubview(stackView)
        stackView.addArrangedSubview(indentSpacer)
        stackView.addArrangedSubview(handleLabel)
        stackView.addArrangedSubview(completionButton)
        stackView.addArrangedSubview(titleTextView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            handleLabel.widthAnchor.constraint(equalToConstant: 20),
            completionButton.widthAnchor.constraint(equalToConstant: 20),
            completionButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func apply(snapshot: TodoEditorItemSnapshot) {
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

        isApplyingSnapshot = true
        titleTextView.string = snapshot.title
        isApplyingSnapshot = false
        titleTextView.textColor = snapshot.isCompleted ? .secondaryLabelColor : .labelColor
    }

    @objc private func toggleCompleted() {
        guard let itemId else { return }
        actions.toggleCompleted(itemId)
    }
}
