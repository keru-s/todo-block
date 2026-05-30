//
//  TodoEditorSectionView.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorSectionView: NSView {
    private let stackView = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    private let actions: TodoEditorActions

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

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .labelColor

        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabelColor

        addSubview(stackView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func apply(snapshot: TodoEditorSectionSnapshot) {
        titleLabel.stringValue = snapshot.title
        subtitleLabel.stringValue = snapshot.subtitle

        for item in snapshot.items {
            let rowView = TodoEditorRowView(snapshot: item, actions: actions)
            stackView.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }
}
