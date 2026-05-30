//
//  TodoEditorActions.swift
//  todo block
//

import Foundation

struct TodoEditorActions {
    var titleChanged: (UUID, String) -> Void = { _, _ in }
    var toggleCompleted: (UUID) -> Void = { _ in }

    static let readOnly = TodoEditorActions()
}
