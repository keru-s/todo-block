//
//  TodoStore+Clipboard.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import Foundation

extension TodoStore {
    func canCopy(scope: TodoClipboardScope, selection: TodoClipboardSelectionSnapshot) -> Bool {
        copyCandidates(scope: scope, selection: selection).isEmpty == false
    }

    func exportMarkdown(
        scope: TodoClipboardScope,
        selection: TodoClipboardSelectionSnapshot
    ) -> String? {
        let items = sortItemsForClipboard(
            copyCandidates(scope: scope, selection: selection),
            scope: scope
        )
        guard items.isEmpty == false else { return nil }
        return MarkdownTodoCodec.encode(items: items, normalizeBaseIndent: true)
    }

    func importMarkdown(
        _ markdown: String,
        scope: TodoClipboardScope,
        selection: TodoClipboardSelectionSnapshot
    ) -> TodoClipboardImportResult? {
        let target = resolveImportTarget(scope: scope, selection: selection)
        let parsedEntries = normalizeClipboardEntries(
            MarkdownTodoCodec.decode(
                markdown,
                baseIndentLevel: target.baseIndentLevel,
                maxIndentLevel: TodoItem.maxIndentLevel
            ),
            baseIndentLevel: target.baseIndentLevel
        )
        guard parsedEntries.isEmpty == false else { return nil }

        var createdItems: [TodoItem] = []
        var currentAfterItem = target.afterItem

        nsUndoManager.beginUndoGrouping()
        defer {
            nsUndoManager.endUndoGrouping()
            nsUndoManager.setActionName("粘贴")
        }

        for entry in parsedEntries {
            let newItem = createItem(
                title: entry.title,
                isCompleted: entry.isCompleted,
                dayDate: target.dayDate,
                afterItem: currentAfterItem,
                indentLevel: entry.indentLevel,
                containerKind: target.containerKind,
                insertAtBeginning: target.insertAtBeginning && currentAfterItem == nil
            )
            createdItems.append(newItem)
            currentAfterItem = newItem
        }

        guard let focusedItem = createdItems.last else { return nil }
        scheduleSave()
        return TodoClipboardImportResult(
            createdItemIds: createdItems.map(\.id),
            focusedItemId: focusedItem.id
        )
    }

    func updateSectionDate(_ section: DaySection, to newDate: Date) {
        let oldDate = section.date
        let newDateStart = Calendar.current.startOfDay(for: newDate)
        guard newDateStart != oldDate else { return }

        if let existingSection = daySectionsCache.values.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: newDateStart) && $0.id != section.id
        }) {
            let itemsToMove = items(for: oldDate)
            for item in itemsToMove {
                item.dayDate = existingSection.date
                item.updatedAt = Date()
            }
            deleteSection(section)
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        section.title = formatter.string(from: newDateStart)
        section.date = newDateStart

        let itemsToUpdate = items(for: oldDate)
        for item in itemsToUpdate {
            item.dayDate = newDateStart
            item.updatedAt = Date()
        }
        bumpRefreshTrigger()
        scheduleSave()
    }

}

private extension TodoStore {
    func normalizeClipboardEntries(
        _ entries: [MarkdownTodoEntry],
        baseIndentLevel: Int
    ) -> [MarkdownTodoEntry] {
        let normalizedIndentLevels = TodoHierarchyBlockEngine.normalizedIndentLevels(
            entries.map(\.indentLevel),
            baseIndentLevel: baseIndentLevel
        )
        return entries.enumerated().map { index, entry in
            return MarkdownTodoEntry(
                title: entry.title,
                isCompleted: entry.isCompleted,
                indentLevel: normalizedIndentLevels[index]
            )
        }
    }

    struct ClipboardPasteTarget {
        let dayDate: Date
        let containerKind: TodoContainerKind
        let afterItem: TodoItem?
        let baseIndentLevel: Int
        let insertAtBeginning: Bool
    }

    func copyCandidates(
        scope: TodoClipboardScope,
        selection: TodoClipboardSelectionSnapshot
    ) -> [TodoItem] {
        let scopeItems = sortItemsForClipboard(items(inClipboardScope: scope), scope: scope)
        let scopeItemIds = Set(scopeItems.map(\.id))
        var rootIds = selection.selectedItemIds.intersection(scopeItemIds)
        if rootIds.isEmpty,
           let focusedItemId = selection.focusedItemId,
           scopeItemIds.contains(focusedItemId) {
            rootIds = [focusedItemId]
        }
        guard rootIds.isEmpty == false else { return [] }

        var coveredIds = Set<UUID>()
        let itemsByDestination = Dictionary(grouping: scopeItems) {
            destination(for: $0).normalized
        }
        for destinationItems in itemsByDestination.values {
            coveredIds.formUnion(
                TodoHierarchyBlockEngine.itemIdsCoveredByBlocks(
                    rootedAt: rootIds,
                    in: destinationItems
                )
            )
        }
        return scopeItems.filter { coveredIds.contains($0.id) }
    }

    func resolveImportTarget(
        scope: TodoClipboardScope,
        selection: TodoClipboardSelectionSnapshot
    ) -> ClipboardPasteTarget {
        switch scope {
        case .scheduledMonth(let year, let month):
            let candidates = sortItemsForClipboard(
                copyCandidates(scope: scope, selection: selection),
                scope: scope
            )
            if let focusedItemId = selection.focusedItemId,
                let focusedItem = candidates.first(where: { $0.id == focusedItemId })
            {
                return ClipboardPasteTarget(
                    dayDate: focusedItem.dayDate,
                    containerKind: .scheduled,
                    afterItem: focusedItem,
                    baseIndentLevel: focusedItem.indentLevel,
                    insertAtBeginning: false
                )
            }
            if let lastSelectedItem = candidates.last {
                return ClipboardPasteTarget(
                    dayDate: lastSelectedItem.dayDate,
                    containerKind: .scheduled,
                    afterItem: lastSelectedItem,
                    baseIndentLevel: lastSelectedItem.indentLevel,
                    insertAtBeginning: false
                )
            }
            if let latestSection = sections(year: year, month: month).first {
                return ClipboardPasteTarget(
                    dayDate: latestSection.date,
                    containerKind: .scheduled,
                    afterItem: nil,
                    baseIndentLevel: 0,
                    insertAtBeginning: true
                )
            }

            let fallbackDate = fallbackDateForEmptyMonth(year: year, month: month)
            let fallbackSection = getOrCreateSection(for: fallbackDate)
            return ClipboardPasteTarget(
                dayDate: fallbackSection.date,
                containerKind: .scheduled,
                afterItem: nil,
                baseIndentLevel: 0,
                insertAtBeginning: true
            )

        case .longTerm:
            let candidates = sortItemsForClipboard(
                copyCandidates(scope: scope, selection: selection),
                scope: scope
            )
            if let focusedItemId = selection.focusedItemId,
                let focusedItem = candidates.first(where: { $0.id == focusedItemId })
            {
                return ClipboardPasteTarget(
                    dayDate: focusedItem.dayDate,
                    containerKind: focusedItem.containerKind,
                    afterItem: focusedItem,
                    baseIndentLevel: focusedItem.indentLevel,
                    insertAtBeginning: false
                )
            }
            if let lastSelectedItem = candidates.last {
                return ClipboardPasteTarget(
                    dayDate: lastSelectedItem.dayDate,
                    containerKind: lastSelectedItem.containerKind,
                    afterItem: lastSelectedItem,
                    baseIndentLevel: lastSelectedItem.indentLevel,
                    insertAtBeginning: false
                )
            }
            let fallbackItems = longTermItems(isUrgent: false)
            return ClipboardPasteTarget(
                dayDate: Date(),
                containerKind: .longTermImportant,
                afterItem: fallbackItems.last,
                baseIndentLevel: 0,
                insertAtBeginning: false
            )

        case .today:
            let candidates = sortItemsForClipboard(
                copyCandidates(scope: scope, selection: selection),
                scope: scope
            )
            if let focusedItemId = selection.focusedItemId,
                let focusedItem = candidates.first(where: { $0.id == focusedItemId })
            {
                return ClipboardPasteTarget(
                    dayDate: focusedItem.dayDate,
                    containerKind: .scheduled,
                    afterItem: focusedItem,
                    baseIndentLevel: focusedItem.indentLevel,
                    insertAtBeginning: false
                )
            }
            if let lastSelectedItem = candidates.last {
                return ClipboardPasteTarget(
                    dayDate: lastSelectedItem.dayDate,
                    containerKind: .scheduled,
                    afterItem: lastSelectedItem,
                    baseIndentLevel: lastSelectedItem.indentLevel,
                    insertAtBeginning: false
                )
            }
            return ClipboardPasteTarget(
                dayDate: Date(),
                containerKind: .scheduled,
                afterItem: todayItems().last,
                baseIndentLevel: 0,
                insertAtBeginning: false
            )
        }
    }

    func items(inClipboardScope scope: TodoClipboardScope) -> [TodoItem] {
        let calendar = Calendar.current
        switch scope {
        case .scheduledMonth(let year, let month):
            let sectionDates = sections(year: year, month: month)
                .map { calendar.startOfDay(for: $0.date) }
            let uniqueDates = Set(sectionDates)
            if uniqueDates.isEmpty, let latestDate = latestScheduledDate(year: year, month: month) {
                return items(for: latestDate).filter {
                    calendar.component(.year, from: $0.dayDate) == year
                        && calendar.component(.month, from: $0.dayDate) == month
                        && $0.containerKind == .scheduled
                }
            }
            return uniqueDates
                .flatMap { items(for: $0) }
                .filter {
                    calendar.component(.year, from: $0.dayDate) == year
                        && calendar.component(.month, from: $0.dayDate) == month
                        && $0.containerKind == .scheduled
                }

        case .longTerm:
            return longTermItems(isUrgent: true) + longTermItems(isUrgent: false)

        case .today:
            return todayItems().filter { $0.containerKind == .scheduled }
        }
    }

    func sortItemsForClipboard(_ items: [TodoItem], scope: TodoClipboardScope) -> [TodoItem] {
        switch scope {
        case .scheduledMonth:
            return items.sorted { lhs, rhs in
                if Calendar.current.isDate(lhs.dayDate, inSameDayAs: rhs.dayDate) {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.dayDate < rhs.dayDate
            }

        case .longTerm:
            return items.sorted { lhs, rhs in
                if lhs.containerKindRaw == rhs.containerKindRaw {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.containerKindRaw < rhs.containerKindRaw
            }

        case .today:
            return items.sorted { $0.sortOrder < $1.sortOrder }
        }
    }
}
