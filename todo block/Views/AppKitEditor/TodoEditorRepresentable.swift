//
//  TodoEditorRepresentable.swift
//  todo block
//

import SwiftUI

struct TodoEditorRepresentable: NSViewControllerRepresentable {
    let sections: [TodoEditorSectionSnapshot]
    var emptyTitle: String = "暂无待办"
    var editorEntry: TodoEditorEntry = .readOnly
    var revealRequest: TodoHistoryRevealRequest? = nil

    init(
        sections: [TodoEditorSectionSnapshot],
        emptyTitle: String = "暂无待办",
        editorEntry: TodoEditorEntry = .readOnly,
        revealRequest: TodoHistoryRevealRequest? = nil
    ) {
        self.sections = sections
        self.emptyTitle = emptyTitle
        self.editorEntry = editorEntry
        self.revealRequest = revealRequest
    }

    func makeNSViewController(context: Context) -> TodoEditorViewController {
        let controller = TodoEditorViewController()
        controller.update(
            sections: sections,
            emptyTitle: emptyTitle,
            editorEntry: editorEntry,
            revealRequest: revealRequest
        )
        return controller
    }

    func updateNSViewController(
        _ nsViewController: TodoEditorViewController,
        context: Context
    ) {
        nsViewController.update(
            sections: sections,
            emptyTitle: emptyTitle,
            editorEntry: editorEntry,
            revealRequest: revealRequest
        )
    }
}
