//
//  TodoEditorSnapshot.swift
//  todo block
//

import Foundation

struct TodoEditorSectionSnapshot: Equatable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let items: [TodoEditorItemSnapshot]

    init(section: DaySection, items: [TodoItem]) {
        id = section.id
        title = section.title
        subtitle = section.date.formatted(.dateTime.year().month().day())
        self.items = items.map { TodoEditorItemSnapshot(item: $0) }
    }
}

struct TodoEditorItemSnapshot: Equatable, Identifiable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let indentLevel: Int

    init(item: TodoItem) {
        id = item.id
        title = item.title
        isCompleted = item.isCompleted
        indentLevel = item.indentLevel
    }
}
