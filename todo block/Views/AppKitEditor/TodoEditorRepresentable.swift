//
//  TodoEditorRepresentable.swift
//  todo block
//

import SwiftUI

struct TodoEditorRepresentable: NSViewControllerRepresentable {
    let sections: [TodoEditorSectionSnapshot]
    var emptyTitle: String = "暂无待办"
    var actions: TodoEditorActions = .readOnly
    var revealRequest: TodoHistoryRevealRequest? = nil

    func makeNSViewController(context: Context) -> TodoEditorViewController {
        let controller = TodoEditorViewController()
        controller.update(
            sections: sections,
            emptyTitle: emptyTitle,
            actions: actions,
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
            actions: actions,
            revealRequest: revealRequest
        )
    }
}
