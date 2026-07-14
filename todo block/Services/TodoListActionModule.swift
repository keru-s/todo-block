import Foundation

struct TodoListActionRejection: Equatable {
    let message: String
}

enum TodoListActionResult: Equatable {
    case performed
    case noChange
    case rejected(TodoListActionRejection)
}

enum TodoListCommandAvailability: Equatable {
    case available
    case unavailable(TodoListActionRejection?)
}

enum TodoTodayAdditionMode: String {
    case carryOver
    case blank
}

@MainActor
final class TodoListActionModule {
    let selectionManager: SelectionManager

    private let store: TodoStore
    private let sectionById: (UUID) -> DaySection?

    var editorActions: TodoEditorActions { makeEditorActions() }

    init(
        store: TodoStore,
        selectionManager: SelectionManager,
        sectionById: ((UUID) -> DaySection?)? = nil
    ) {
        self.store = store
        self.selectionManager = selectionManager
        self.sectionById = sectionById ?? { store.daySectionsCache[$0] }
    }

    @discardableResult
    func toggleCompleted(itemId: UUID) -> TodoListActionResult {
        guard let item = store.todoItemsCache[itemId] else { return .noChange }
        store.toggleComplete(item)
        return .performed
    }

    @discardableResult
    func addToday(mode: TodoTodayAdditionMode) -> TodoListActionResult {
        let today = Calendar.current.startOfDay(for: .now)
        let todaySection = store.validDaySections.first {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }

        if let todaySection {
            let newItem = store.createItem(
                dayDate: todaySection.date,
                selectionManager: selectionManager
            )
            selectionManager.handleSelect(
                item: newItem,
                allItems: store.items(for: todaySection.date),
                shiftPressed: false,
                cursorPosition: 0
            )
            return .performed
        }

        switch mode {
        case .carryOver:
            return store.carryOverIncompleteItems(trigger: .userInitiated) == nil
                ? .noChange
                : .performed
        case .blank:
            _ = store.getOrCreateTodaySection()
            return .performed
        }
    }

    private func makeEditorActions() -> TodoEditorActions {
        TodoEditorActions(
            titleChanged: { [self] itemId, event in
                guard let item = self.store.todoItemsCache[itemId] else { return }
                store.textEditSession.apply(
                    event,
                    to: item,
                    selectionManager: selectionManager,
                    store: store
                )
            },
            textSelectionChanged: { [self] itemId, selection in
                store.textEditSession.selectionDidChange(
                    itemId: itemId,
                    selection: selection,
                    selectionManager: selectionManager,
                    store: store
                )
            },
            toggleCompleted: { [self] itemId in
                self.toggleCompleted(itemId: itemId)
            },
            selectItem: { [self] itemId, shiftPressed, cursorPosition in
                guard let item = self.store.todoItemsCache[itemId] else { return }
                store.flushPendingTextEdit()
                selectionManager.handleSelect(
                    item: item,
                    allItems: store.items(in: store.destination(for: item)),
                    shiftPressed: shiftPressed,
                    cursorPosition: cursorPosition
                )
            },
            beginDragSelection: { [self] itemId, cursorPosition in
                guard let item = self.store.todoItemsCache[itemId] else { return }
                selectionManager.beginDragSelection(
                    item: item,
                    allItems: store.items(in: store.destination(for: item)),
                    cursorPosition: cursorPosition
                )
            },
            updateDragSelection: { [self] itemId in
                guard let item = self.store.todoItemsCache[itemId] else { return }
                selectionManager.updateDragSelection(
                    to: item,
                    allItems: store.items(in: store.destination(for: item))
                )
            },
            endDragSelection: { [self] in
                self.selectionManager.endDragSelection()
            },
            addItem: { [self] destination in
                self.addItem(to: destination)
            },
            enterPressed: { [self] itemId, action in
                self.handleEnter(itemId: itemId, action: action)
            },
            deletePressed: { [self] itemId in
                self.delete(itemId: itemId)
            },
            indent: { [self] itemId in
                guard let item = self.store.todoItemsCache[itemId] else { return }
                store.indentItem(item, selectionManager: selectionManager)
            },
            outdent: { [self] itemId in
                guard let item = self.store.todoItemsCache[itemId] else { return }
                store.outdentItem(item, selectionManager: selectionManager)
            },
            moveFocus: { [self] itemId, direction, cursorPosition, horizontalOffset in
                self.moveFocus(
                    itemId: itemId,
                    direction: direction,
                    cursorPosition: cursorPosition,
                    horizontalOffset: horizontalOffset
                )
            },
            moveItemByKeyboard: { [self] itemId, direction in
                _ = self.moveItemByKeyboard(itemId: itemId, direction: direction)
            },
            moveDraggedItem: { [self] itemId, destination, toIndex, indentLevel in
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
            moveDraggedItemToSidebar: { [self] itemId, destination in
                self.moveDraggedItemToSidebar(itemId: itemId, destination: destination)
            },
            sectionDateChanged: { [self] sectionId, newDate in
                guard let section = self.sectionById(sectionId) else { return }
                store.updateSectionDate(section, to: newDate)
            }
        )
    }

    private func addItem(to destination: TodoDropDestination) {
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
                dayDate: .now,
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
    }

    private func handleEnter(itemId: UUID, action: EnterAction) {
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
            newItem = store.createItemBefore(item, selectionManager: selectionManager)
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
    }

    private func delete(itemId: UUID) {
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
    }

    private func moveFocus(
        itemId: UUID,
        direction: TodoEditorFocusMoveDirection,
        cursorPosition: Int,
        horizontalOffset: CGFloat?
    ) {
        guard let item = store.todoItemsCache[itemId] else { return }
        let items = store.items(in: store.destination(for: item))
        let focusedItemIdBeforeMove = selectionManager.focusedItemId
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
        if selectionManager.focusedItemId != focusedItemIdBeforeMove {
            store.flushPendingTextEdit()
        }
    }

    func keyboardMoveAvailability(
        itemId: UUID,
        direction: TodoKeyboardReorderDirection
    ) -> TodoListCommandAvailability {
        guard let item = store.todoItemsCache[itemId] else {
            return .unavailable(TodoListActionRejection(message: "待办已不存在"))
        }
        let items = store.items(in: store.destination(for: item))
        return TodoKeyboardReorderEngine.canMove(
            itemId: itemId,
            direction: direction,
            items: items
        ) ? .available : .unavailable(nil)
    }

    @discardableResult
    func moveItemByKeyboard(
        itemId: UUID,
        direction: TodoKeyboardReorderDirection
    ) -> TodoListActionResult {
        switch keyboardMoveAvailability(itemId: itemId, direction: direction) {
        case .unavailable(nil):
            return .noChange
        case .unavailable(let rejection?):
            return .rejected(rejection)
        case .available:
            break
        }

        guard let item = store.todoItemsCache[itemId] else {
            return .rejected(TodoListActionRejection(message: "待办已不存在"))
        }
        let destination = store.destination(for: item)
        let didMove = TodoKeyboardReorderEngine.move(
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
        return didMove ? .performed : .noChange
    }

    private func moveDraggedItemToSidebar(
        itemId: UUID,
        destination: SidebarDestination
    ) {
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
    }
}
