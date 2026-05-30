//
//  TodoEditorPreviewView.swift
//  todo block
//

import SwiftUI
import SwiftData

#if DEBUG
struct TodoEditorPreviewView: View {
    let year: Int
    let month: Int

    @State private var selectionManager = SelectionManager()

    private var store: TodoStore { TodoStore.shared }

    private var sections: [TodoEditorSectionSnapshot] {
        store.sections(year: year, month: month).map { section in
            TodoEditorSectionSnapshot(
                section: section,
                items: store.items(for: section.date),
                selectionManager: selectionManager
            )
        }
    }

    var body: some View {
        TodoEditorRepresentable(
            sections: sections,
            emptyTitle: "暂无可预览的待办"
        )
    }
}

#Preview("AppKit Editor Skeleton") {
    let container = TodoPreviewSupport.bootstrap()

    return TodoEditorPreviewView(year: 2026, month: 1)
        .modelContainer(container)
        .frame(width: 520, height: 420)
}
#endif
