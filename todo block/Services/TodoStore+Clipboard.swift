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

    func clipboardItemIds(
        scope: TodoClipboardScope,
        selection: TodoClipboardSelectionSnapshot
    ) -> Set<UUID> {
        Set(copyCandidates(scope: scope, selection: selection).map(\.id))
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
        selection: TodoClipboardSelectionSnapshot,
        selectionManager: SelectionManager? = nil
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

        let sortOrders = plannedPasteSortOrders(count: parsedEntries.count, target: target)
        guard sortOrders.count == parsedEntries.count else { return nil }
        let snapshots = zip(parsedEntries, sortOrders).map { entry, sortOrder in
            TodoItemSnapshot(
                title: entry.title,
                isCompleted: entry.isCompleted,
                indentLevel: entry.indentLevel,
                sortOrder: sortOrder,
                containerKindRaw: target.containerKind.rawValue,
                dayDate: target.dayDate
            )
        }
        guard let focusedSnapshot = snapshots.last else { return nil }
        let createdIds = snapshots.map(\.id)
        let selectionChanges: [TodoSelectionChange] = selectionManager.map { manager in
            [
                TodoSelectionChange(
                    selectionManager: manager,
                    before: TodoSelectionState(selectionManager: manager),
                    after: TodoSelectionState(
                        focusedItemId: focusedSnapshot.id,
                        selectedItemIds: Set(createdIds),
                        lastSelectedId: focusedSnapshot.id,
                        cursorPosition: 0
                    )
                )
            ]
        } ?? []
        let operation = TodoOperation(
            actionName: "粘贴",
            itemExistenceChanges: snapshots.map { snapshot in
                TodoItemExistenceChange(
                    snapshot: snapshot,
                    beforeExists: false,
                    afterExists: true
                )
            },
            selectionChanges: selectionChanges
        )
        guard undoManager.perform(operation, store: self) else { return nil }
        return TodoClipboardImportResult(
            createdItemIds: createdIds,
            focusedItemId: focusedSnapshot.id
        )
    }

    func updateSectionDate(_ section: DaySection, to newDate: Date) {
        let oldDate = section.date
        let newDateStart = Calendar.current.startOfDay(for: newDate)
        guard newDateStart != oldDate else { return }
        let oldSnapshots = items(for: oldDate).map { TodoItemSnapshot(from: $0) }
        guard oldSnapshots.isEmpty == false else { return }
        let changes = oldSnapshots.map { snapshot in
            TodoItemStateChange(
                before: snapshot,
                after: snapshot.replacing(dayDate: newDateStart)
            )
        }
        undoManager.perform(
            TodoOperation(actionName: "更改日期", itemStateChanges: changes),
            store: self
        )
    }

    func commandItems(in scope: TodoClipboardScope) -> [TodoItem] {
        items(inClipboardScope: scope)
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
            return ClipboardPasteTarget(
                dayDate: fallbackDate,
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

    func plannedPasteSortOrders(count: Int, target: ClipboardPasteTarget) -> [Double] {
        guard count > 0 else { return [] }
        let destination: TodoDropDestination = switch target.containerKind {
        case .scheduled:
            .scheduled(date: target.dayDate)
        case .longTermUrgent:
            .longTerm(isUrgent: true)
        case .longTermImportant:
            .longTerm(isUrgent: false)
        }
        let currentItems = items(in: destination)
        let insertionIndex: Int
        if
            let afterItem = target.afterItem,
            let index = currentItems.firstIndex(where: { $0.id == afterItem.id })
        {
            insertionIndex = index + 1
        } else if target.insertAtBeginning {
            insertionIndex = 0
        } else {
            insertionIndex = currentItems.count
        }

        let lowerBound = insertionIndex > 0 ? currentItems[insertionIndex - 1].sortOrder : nil
        let upperBound = insertionIndex < currentItems.count
            ? currentItems[insertionIndex].sortOrder
            : nil

        switch (lowerBound, upperBound) {
        case let (lower?, upper?):
            let step = (upper - lower) / Double(count + 1)
            return (1...count).map { lower + step * Double($0) }
        case let (lower?, nil):
            return (1...count).map { lower + 1000 * Double($0) }
        case let (nil, upper?):
            return (0..<count).map { upper - 1000 * Double(count - $0) }
        case (nil, nil):
            return (1...count).map { 1000 * Double($0) }
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
