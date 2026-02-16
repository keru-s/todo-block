//
//  SidebarDropDelegates.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftUI
import UniformTypeIdentifiers

struct SidebarLongTermDropDelegate: DropDelegate {
    let store: TodoStore
    let selectedDestination: Binding<SidebarDestination>

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard
                let idString = object as? String,
                let itemId = UUID(uuidString: idString)
            else {
                return
            }

            Task { @MainActor in
                guard let draggedItem = store.todoItemsCache[itemId] else { return }
                let newIndent = SidebarDropIndentResolver.resolveIndent(
                    draggedItem: draggedItem,
                    afterItem: nil
                )
                store.moveItemWithChildren(
                    draggedItem,
                    to: .longTerm(isUrgent: false),
                    afterItem: nil,
                    newIndentLevel: newIndent
                )
                selectedDestination.wrappedValue = .longTerm
            }
        }

        return true
    }
}

struct SidebarMonthDropDelegate: DropDelegate {
    let year: Int
    let month: Int
    let store: TodoStore
    let selectedDestination: Binding<SidebarDestination>

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard
                let idString = object as? String,
                let itemId = UUID(uuidString: idString)
            else {
                return
            }

            Task { @MainActor in
                guard let draggedItem = store.todoItemsCache[itemId] else { return }

                let target = store.tailItemForScheduledMonth(year: year, month: month)
                let newIndent = SidebarDropIndentResolver.resolveIndent(
                    draggedItem: draggedItem,
                    afterItem: nil
                )
                store.moveItemWithChildren(
                    draggedItem,
                    to: .scheduled(date: target.date),
                    afterItem: nil,
                    newIndentLevel: newIndent
                )
                selectedDestination.wrappedValue = .month(year: year, month: month)
            }
        }

        return true
    }
}

enum SidebarDropIndentResolver {
    static func resolveIndent(draggedItem: TodoItem, afterItem: TodoItem?) -> Int {
        if let afterItem {
            return min(draggedItem.indentLevel, afterItem.indentLevel + 1)
        }
        return 0
    }
}
