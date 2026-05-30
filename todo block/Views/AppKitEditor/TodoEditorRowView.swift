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
    private let completionImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init(snapshot: TodoEditorItemSnapshot) {
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

        completionImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        completionImageView.contentTintColor = .secondaryLabelColor

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(stackView)
        stackView.addArrangedSubview(indentSpacer)
        stackView.addArrangedSubview(handleLabel)
        stackView.addArrangedSubview(completionImageView)
        stackView.addArrangedSubview(titleLabel)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            handleLabel.widthAnchor.constraint(equalToConstant: 20),
            completionImageView.widthAnchor.constraint(equalToConstant: 20),
            completionImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func apply(snapshot: TodoEditorItemSnapshot) {
        let indentWidth = CGFloat(snapshot.indentLevel) * TodoDesignTokens.indentWidth
        indentSpacer.widthAnchor.constraint(equalToConstant: indentWidth).isActive = true

        let symbolName = snapshot.isCompleted ? "checkmark.square.fill" : "square"
        completionImageView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: snapshot.isCompleted ? "已完成" : "未完成"
        )
        completionImageView.contentTintColor = snapshot.isCompleted ? .systemGreen : .secondaryLabelColor

        titleLabel.stringValue = snapshot.title.isEmpty ? "待办事项" : snapshot.title
        titleLabel.textColor = snapshot.isCompleted ? .secondaryLabelColor : .labelColor
    }
}

