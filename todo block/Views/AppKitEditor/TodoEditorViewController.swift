//
//  TodoEditorViewController.swift
//  todo block
//

import AppKit

@MainActor
final class TodoEditorViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")

    private var renderedSections: [TodoEditorSectionSnapshot] = []
    private var renderedEmptyTitle: String = ""
    private var actions: TodoEditorActions = .readOnly

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

        let visibleSections = sections.filter { $0.items.isEmpty == false }
        if visibleSections.isEmpty {
            emptyLabel.stringValue = emptyTitle
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(emptyLabel)
            emptyLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            return
        }

        for section in visibleSections {
            let sectionView = TodoEditorSectionView(snapshot: section, actions: actions)
            stackView.addArrangedSubview(sectionView)
            sectionView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }
}
