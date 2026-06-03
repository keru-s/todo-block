//
//  TodoEditorSnapshot.swift
//  todo block
//

import Foundation
import CoreGraphics

struct TodoEditorSectionSnapshot: Equatable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let destination: TodoDropDestination
    let editableDate: Date?
    let allowsAdding: Bool
    let items: [TodoEditorItemSnapshot]

    init(
        id: UUID,
        title: String,
        subtitle: String = "",
        destination: TodoDropDestination,
        editableDate: Date? = nil,
        allowsAdding: Bool = true,
        items: [TodoEditorItemSnapshot]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.destination = destination.normalized
        self.editableDate = editableDate
        self.allowsAdding = allowsAdding
        self.items = items
    }

    init(section: DaySection, items: [TodoItem], selectionManager: SelectionManager) {
        id = section.id
        title = section.title
        subtitle = section.date.formatted(.dateTime.year().month().day())
        destination = .scheduled(date: section.date)
        editableDate = section.date
        allowsAdding = true
        self.items = items.map { TodoEditorItemSnapshot(item: $0, selectionManager: selectionManager) }
    }
}

struct TodoEditorItemSnapshot: Equatable, Identifiable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let indentLevel: Int
    let isSelected: Bool
    let isFocused: Bool
    let hasMultipleSelection: Bool
    let cursorPosition: Int
    let preferredHorizontalOffset: CGFloat?
    let verticalMoveDirection: VerticalMoveDirection?

    init(item: TodoItem, selectionManager: SelectionManager) {
        id = item.id
        title = item.title
        isCompleted = item.isCompleted
        indentLevel = item.indentLevel
        isSelected = selectionManager.selectedItemIds.contains(item.id)
        isFocused = selectionManager.focusedItemId == item.id
        hasMultipleSelection = selectionManager.selectedItemIds.count > 1
        cursorPosition = selectionManager.cursorPosition
        preferredHorizontalOffset = selectionManager.preferredHorizontalOffset
        verticalMoveDirection = selectionManager.verticalMoveDirection
    }
}
