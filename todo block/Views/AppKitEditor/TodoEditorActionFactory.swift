//
//  TodoEditorActionFactory.swift
//  todo block
//

import Foundation

@MainActor
enum TodoEditorActionFactory {
    static func make(
        store: TodoStore,
        selectionManager: SelectionManager,
        sectionById: @escaping (UUID) -> DaySection? = { _ in nil }
    ) -> TodoEditorActions {
        TodoEditorActions(
            titleChanged: { itemId, newTitle in
                guard let item = store.todoItemsCache[itemId], item.title != newTitle else {
                    return
                }
                item.title = newTitle
                store.updateItem(item)
            },
            toggleCompleted: { itemId in
                guard let item = store.todoItemsCache[itemId] else { return }
                store.toggleComplete(item)
            },
            selectItem: { itemId, shiftPressed, cursorPosition in
                guard let item = store.todoItemsCache[itemId] else { return }
                selectionManager.handleSelect(
                    item: item,
                    allItems: store.items(in: store.destination(for: item)),
                    shiftPressed: shiftPressed,
                    cursorPosition: cursorPosition
                )
            },
            beginDragSelection: { itemId, cursorPosition in
                guard let item = store.todoItemsCache[itemId] else { return }
                selectionManager.beginDragSelection(
                    item: item,
                    allItems: store.items(in: store.destination(for: item)),
                    cursorPosition: cursorPosition
                )
            },
            updateDragSelection: { itemId in
                guard let item = store.todoItemsCache[itemId] else { return }
                selectionManager.updateDragSelection(
                    to: item,
                    allItems: store.items(in: store.destination(for: item))
                )
            },
            endDragSelection: {
                selectionManager.endDragSelection()
            },
            addItem: { destination in
                let normalizedDestination = destination.normalized
                let newItem: TodoItem
                switch normalizedDestination {
                case .scheduled(let date):
                    newItem = store.createItem(
                        dayDate: date,
                        selectionManager: selectionManager
                    )
                case .longTerm(let isUrgent):
                    newItem = store.createItem(
                        dayDate: Date(),
                        containerKind: isUrgent ? .longTermUrgent : .longTermImportant,
                        selectionManager: selectionManager
                    )
                }
                selectionManager.handleSelect(
                    item: newItem,
                    allItems: store.items(in: normalizedDestination),
                    shiftPressed: false,
                    cursorPosition: 0
                )
            },
            enterPressed: { itemId, action in
                guard let item = store.todoItemsCache[itemId] else { return }
                let newItem: TodoItem
                switch action {
                case .insertSiblingBelow:
                    newItem = store.createItem(
                        dayDate: item.dayDate,
                        afterItem: item,
                        indentLevel: item.indentLevel,
                        containerKind: item.containerKind,
                        selectionManager: selectionManager
                    )
                case .insertSiblingAbove:
                    newItem = store.createItemBefore(
                        item,
                        selectionManager: selectionManager
                    )
                case .splitIntoChild(let newCurrentTitle, let childTitle):
                    guard let splitItem = store.splitItem(
                        item,
                        newCurrentTitle: newCurrentTitle,
                        childTitle: childTitle,
                        selectionManager: selectionManager
                    ) else { return }
                    newItem = splitItem
                }
                selectionManager.handleSelect(
                    item: newItem,
                    allItems: store.items(in: store.destination(for: newItem)),
                    shiftPressed: false,
                    cursorPosition: 0
                )
            },
            deletePressed: { itemId in
                guard let item = store.todoItemsCache[itemId] else { return }
                let destination = store.destination(for: item)
                if selectionManager.selectedItemIds.contains(itemId) == false {
                    selectionManager.handleSelect(
                        item: item,
                        allItems: store.items(in: destination),
                        shiftPressed: false
                    )
                }
                selectionManager.deleteSelectedItems(store: store) { _ in
                    store.items(in: destination)
                }
            },
            indent: { itemId in
                guard let item = store.todoItemsCache[itemId] else { return }
                store.indentItem(item, selectionManager: selectionManager)
            },
            outdent: { itemId in
                guard let item = store.todoItemsCache[itemId] else { return }
                store.outdentItem(item, selectionManager: selectionManager)
            },
            moveFocus: { itemId, direction, cursorPosition, horizontalOffset in
                guard let item = store.todoItemsCache[itemId] else { return }
                let items = store.items(in: store.destination(for: item))
                switch direction {
                case .up:
                    selectionManager.moveFocusUp(
                        from: item,
                        allItems: items,
                        cursorPosition: cursorPosition,
                        preferredHorizontalOffset: horizontalOffset
                    )
                case .down:
                    selectionManager.moveFocusDown(
                        from: item,
                        allItems: items,
                        cursorPosition: cursorPosition,
                        preferredHorizontalOffset: horizontalOffset
                    )
                }
            },
            moveItemByKeyboard: { itemId, direction in
                guard let item = store.todoItemsCache[itemId] else { return }
                let destination = store.destination(for: item)
                _ = TodoKeyboardReorderEngine.move(
                    itemId: itemId,
                    direction: direction,
                    items: store.items(in: destination),
                    destination: destination,
                    store: store,
                    selectionManager: selectionManager,
                    selectionAfter: TodoSelectionState(
                        focusing: itemId,
                        cursorPosition: selectionManager.cursorPosition
                    )
                )
            },
            moveDraggedItem: { itemId, destination, toIndex, indentLevel in
                _ = TodoReorderMoveEngine.performMove(
                    draggedId: itemId,
                    toIndex: toIndex,
                    indentLevel: indentLevel,
                    items: store.items(in: destination),
                    destination: destination,
                    store: store,
                    selectionManager: selectionManager,
                    selectionAfter: TodoSelectionState(
                        focusing: itemId,
                        cursorPosition: selectionManager.cursorPosition
                    )
                )
            },
            moveDraggedItemToSidebar: { itemId, destination in
                guard let item = store.todoItemsCache[itemId] else { return }

                switch destination {
                case .longTerm:
                    store.moveItemWithChildren(
                        item,
                        to: .longTerm(isUrgent: false),
                        afterItem: nil,
                        newIndentLevel: 0,
                        selectionManager: selectionManager,
                        selectionAfter: TodoSelectionState(
                            focusing: itemId,
                            cursorPosition: selectionManager.cursorPosition
                        )
                    )
                case .month(let year, let month):
                    let target = store.tailItemForScheduledMonth(year: year, month: month)
                    store.moveItemWithChildren(
                        item,
                        to: .scheduled(date: target.date),
                        afterItem: nil,
                        newIndentLevel: 0,
                        selectionManager: selectionManager,
                        selectionAfter: TodoSelectionState(
                            focusing: itemId,
                            cursorPosition: selectionManager.cursorPosition
                        )
                    )
                }
            },
            sectionDateChanged: { sectionId, newDate in
                guard let section = sectionById(sectionId) else { return }
                store.updateSectionDate(section, to: newDate)
            }
        )
    }
}
