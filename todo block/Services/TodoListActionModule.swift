import AppKit
import Foundation

enum TodoListActionRejection: Equatable {
    case finishCurrentInput
    case openMainWindowForHistory
    case itemNoLongerAvailable
}

enum TodoListActionResult: Equatable {
    case performed
    case noChange
    case rejected(TodoListActionRejection)
}

enum TodoListCommandAvailability: Equatable {
    case available
    case unavailable(TodoListActionRejection?)

    var allowsAttempt: Bool {
        switch self {
        case .available, .unavailable(.some):
            true
        case .unavailable(nil):
            false
        }
    }
}

enum TodoTodayAdditionMode: String {
    case carryOver
    case blank
}

@MainActor
final class TodoListActionModule {
    let selectionManager: SelectionManager
    let feedbackPresenter = TodoListFeedbackPresenter()

    private let store: TodoStore
    private let sectionById: (UUID) -> DaySection?
    private let activeTextViewProvider: @MainActor () -> TodoEditorTextView?
    private let allowsSidebarMoves: Bool
    private var commandScope: TodoClipboardScope?

    var editorActions: TodoEditorActions { makeEditorActions() }

    func editorActions(
        claimCurrentList: @escaping () -> Void
    ) -> TodoEditorActions {
        var actions = makeEditorActions()
        actions.claimCurrentList = claimCurrentList
        return actions
    }

    init(
        store: TodoStore,
        selectionManager: SelectionManager,
        commandScope: TodoClipboardScope? = nil,
        allowsSidebarMoves: Bool = true,
        activeTextViewProvider: @escaping @MainActor () -> TodoEditorTextView? =
            TodoListActionModule.defaultActiveTextView,
        sectionById: ((UUID) -> DaySection?)? = nil
    ) {
        self.store = store
        self.selectionManager = selectionManager
        self.commandScope = commandScope
        self.allowsSidebarMoves = allowsSidebarMoves
        self.activeTextViewProvider = activeTextViewProvider
        self.sectionById = sectionById ?? { store.daySectionsCache[$0] }
    }

    func updateCommandScope(_ scope: TodoClipboardScope) {
        commandScope = scope
    }

    func activateHistoryContext() {
        selectionManager.activateHistoryContext()
        if let commandScope {
            TodoHistoryPresentationCoordinator.shared.activate(scope: commandScope)
        }
    }

    func commandAvailability(_ command: TodoListCommand) -> TodoListCommandAvailability {
        switch command {
        case .copy, .cut:
            if let activeTextView {
                return activeTextView.selectedRange().length > 0
                    ? .available
                    : .unavailable(nil)
            }
            guard let commandScope else { return .unavailable(nil) }
            return store.canCopy(scope: commandScope, selection: clipboardSelection)
                ? .available
                : .unavailable(nil)
        case .paste:
            if activeTextView != nil {
                return NSPasteboard.general.string(forType: .string) == nil
                    ? .unavailable(nil)
                    : .available
            }
            guard commandScope != nil,
                  let content = NSPasteboard.general.string(forType: .string),
                  MarkdownTodoCodec.decode(
                    content,
                    baseIndentLevel: 0,
                    maxIndentLevel: TodoItem.maxIndentLevel
                  ).isEmpty == false
            else { return .unavailable(nil) }
            return .available
        case .moveUp:
            return TodoReorderCommandManager.canMoveSelection(
                direction: .up,
                store: store,
                selectionManager: selectionManager
            ) ? .available : .unavailable(nil)
        case .moveDown:
            return TodoReorderCommandManager.canMoveSelection(
                direction: .down,
                store: store,
                selectionManager: selectionManager
            ) ? .available : .unavailable(nil)
        case .undo:
            if activeTextView?.hasUncommittedTextInput == true {
                return .available
            }
            guard store.canUndo else { return .unavailable(nil) }
            return historyAvailability(for: .undo)
        case .redo:
            if activeTextView?.hasUncommittedTextInput == true {
                return .unavailable(.finishCurrentInput)
            }
            guard store.canRedo else { return .unavailable(nil) }
            return historyAvailability(for: .redo)
        }
    }

    private func historyAvailability(
        for command: TodoListCommand
    ) -> TodoListCommandAvailability {
        guard commandScope == .today else { return .available }
        let affectsToday: Bool?
        switch command {
        case .undo:
            affectsToday = store.undoManager.nextUndoAffectsToday(store: store)
        case .redo:
            affectsToday = store.undoManager.nextRedoAffectsToday(store: store)
        default:
            return .available
        }
        return affectsToday == false
            ? .unavailable(.openMainWindowForHistory)
            : .available
    }

    @discardableResult
    func perform(_ command: TodoListCommand) -> TodoListActionResult {
        let result = performWithoutFeedback(command)
        feedbackPresenter.consume(result)
        return result
    }

    private func performWithoutFeedback(_ command: TodoListCommand) -> TodoListActionResult {
        if command == .moveUp || command == .moveDown {
            prepareForExternalAction()
        }
        switch commandAvailability(command) {
        case .available:
            break
        case .unavailable(nil):
            return .noChange
        case .unavailable(let rejection?):
            return .rejected(rejection)
        }

        switch command {
        case .copy:
            if let activeTextView {
                activeTextView.copy(nil)
                return .performed
            }
            prepareForExternalAction()
            guard let markdown = exportedMarkdown else { return .noChange }
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(markdown, forType: .string)
                ? .performed
                : .noChange
        case .cut:
            if let activeTextView {
                activeTextView.cut(nil)
                return .performed
            }
            prepareForExternalAction()
            guard let markdown = exportedMarkdown else { return .noChange }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(markdown, forType: .string) else {
                return .noChange
            }
            let itemIds = commandScope.map {
                store.clipboardItemIds(scope: $0, selection: clipboardSelection)
            } ?? []
            return selectionManager.deleteItems(itemIds, store: store)
                ? .performed
                : .noChange
        case .paste:
            if let activeTextView {
                activeTextView.paste(nil)
                return .performed
            }
            prepareForExternalAction()
            guard let commandScope,
                  let content = NSPasteboard.general.string(forType: .string),
                  store.importMarkdown(
                    content,
                    scope: commandScope,
                    selection: clipboardSelection,
                    selectionManager: selectionManager
                  ) != nil
            else { return .noChange }
            return .performed
        case .moveUp:
            return TodoReorderCommandManager.moveSelection(
                direction: .up,
                store: store,
                selectionManager: selectionManager
            ) ? .performed : .noChange
        case .moveDown:
            return TodoReorderCommandManager.moveSelection(
                direction: .down,
                store: store,
                selectionManager: selectionManager
            ) ? .performed : .noChange
        case .undo:
            prepareForExternalAction()
            return store.undo() ? .performed : .noChange
        case .redo:
            prepareForExternalAction()
            return store.redo() ? .performed : .noChange
        }
    }

    private var clipboardSelection: TodoClipboardSelectionSnapshot {
        TodoClipboardSelectionSnapshot(
            focusedItemId: selectionManager.focusedItemId,
            selectedItemIds: selectionManager.selectedItemIds
        )
    }

    private var exportedMarkdown: String? {
        guard let commandScope else { return nil }
        return store.exportMarkdown(scope: commandScope, selection: clipboardSelection)
    }

    private var activeTextView: TodoEditorTextView? {
        activeTextViewProvider()
    }

    private func prepareForExternalAction() {
        activeTextView?.commitPendingTextInput()
        store.flushPendingTextEdit()
    }

    private static func defaultActiveTextView() -> TodoEditorTextView? {
        NSApp.keyWindow?.firstResponder as? TodoEditorTextView
    }

    @discardableResult
    func toggleCompleted(itemId: UUID) -> TodoListActionResult {
        guard let item = store.todoItemsCache[itemId] else {
            let result = TodoListActionResult.rejected(.itemNoLongerAvailable)
            feedbackPresenter.consume(result)
            return result
        }
        prepareForExternalAction()
        store.toggleComplete(item)
        return .performed
    }

    @discardableResult
    func addToday(mode: TodoTodayAdditionMode) -> TodoListActionResult {
        prepareForExternalAction()
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
                prepareForExternalAction()
                selectionManager.handleSelect(
                    item: item,
                    allItems: store.items(in: store.destination(for: item)),
                    shiftPressed: shiftPressed,
                    cursorPosition: cursorPosition
                )
            },
            beginDragSelection: { [self] itemId, cursorPosition in
                guard let item = self.store.todoItemsCache[itemId] else { return }
                prepareForExternalAction()
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
                self.prepareForExternalAction()
                self.addItem(to: destination)
            },
            enterPressed: { [self] itemId, action in
                self.prepareForExternalAction()
                self.handleEnter(itemId: itemId, action: action)
            },
            deletePressed: { [self] itemId in
                self.prepareForExternalAction()
                self.delete(itemId: itemId)
            },
            indent: { [self] itemId in
                guard let item = self.store.todoItemsCache[itemId] else { return }
                prepareForExternalAction()
                store.indentItem(item, selectionManager: selectionManager)
            },
            outdent: { [self] itemId in
                guard let item = self.store.todoItemsCache[itemId] else { return }
                prepareForExternalAction()
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
                prepareForExternalAction()
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
                guard self.allowsSidebarMoves else { return }
                self.moveDraggedItemToSidebar(itemId: itemId, destination: destination)
            },
            sectionDateChanged: { [self] sectionId, newDate in
                guard let section = self.sectionById(sectionId) else { return }
                prepareForExternalAction()
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
            return .unavailable(.itemNoLongerAvailable)
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
        let result = moveItemByKeyboardWithoutFeedback(itemId: itemId, direction: direction)
        feedbackPresenter.consume(result)
        return result
    }

    private func moveItemByKeyboardWithoutFeedback(
        itemId: UUID,
        direction: TodoKeyboardReorderDirection
    ) -> TodoListActionResult {
        prepareForExternalAction()

        switch keyboardMoveAvailability(itemId: itemId, direction: direction) {
        case .unavailable(nil):
            return .noChange
        case .unavailable(let rejection?):
            return .rejected(rejection)
        case .available:
            break
        }

        guard let item = store.todoItemsCache[itemId] else {
            return .rejected(.itemNoLongerAvailable)
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
        prepareForExternalAction()

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
