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
    private let todayProvider: () -> Date
    private let allowsSidebarMoves: Bool
    private let parentChildGroupMoveModule: TodoParentChildGroupMoveModule
    private var commandScope: TodoClipboardScope?

    /// 未绑定列表参与的编辑器入口，供动作模块行为测试使用。
    /// 可见列表应通过 `makeEditorEntry(claimCurrentList:)` 建立自己的稳定入口。
    var editorEntry: TodoEditorEntry {
        makeEditorEntry()
    }

    /// 建立一份已经连接到本动作模块的编辑器入口。
    ///
    /// 列表参与由调用方提供；直接动作在执行前确认参与，选区、焦点和输入
    /// 结束等被动事实则不会接管当前列表。
    func makeEditorEntry(
        claimCurrentList: @escaping () -> Bool = { true }
    ) -> TodoEditorEntry {
        TodoEditorEntry(
            access: .editable,
            claimCurrentList: claimCurrentList,
            titleChanged: { [self] itemId, event in
                guard claimCurrentList(),
                      let item = self.store.todoItemsCache[itemId]
                else { return }
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
            inputSessionEnded: { [self] in
                store.flushPendingTextEdit()
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
            clearSelection: { [self] in
                prepareForExternalAction()
                selectionManager.clearAllSelection()
            },
            captureDragSelectionBefore: { [self] in
                selectionManager.captureDragSelectionBefore()
            },
            discardPreparedDragSelection: { [self] in
                selectionManager.discardPreparedDragSelection()
            },
            beginDragSelection: { [self] itemId, cursorPosition in
                guard claimCurrentList(),
                      let item = self.store.todoItemsCache[itemId]
                else { return false }
                commitPendingTextInput()
                selectionManager.beginDragSelection(
                    item: item,
                    allItems: store.items(in: store.destination(for: item)),
                    cursorPosition: cursorPosition
                )
                return true
            },
            updateDragSelection: { [self] itemId in
                guard claimCurrentList(),
                      let item = self.store.todoItemsCache[itemId]
                else { return }
                selectionManager.updateDragSelection(
                    to: item,
                    allItems: store.items(in: store.destination(for: item))
                )
            },
            endDragSelection: { [self] in
                selectionManager.endDragSelection()
            },
            cancelDragSelection: { [self] in
                selectionManager.cancelDragSelection()
            },
            hasMultipleSelection: { [self] in
                selectionManager.selectedItemIds.count > 1
            },
            addItem: { [self] destination in
                guard claimCurrentList() else { return }
                prepareForExternalAction()
                addItem(to: destination)
            },
            enterPressed: { [self] itemId, action in
                guard claimCurrentList() else { return false }
                prepareForExternalAction()
                return handleEnter(itemId: itemId, action: action)
            },
            deletePressed: { [self] itemId, textSelection in
                guard textSelection.length == 0,
                      let item = self.store.todoItemsCache[itemId],
                      item.title.isEmpty || selectionManager.selectedItemIds.count > 1
                else { return false }
                guard claimCurrentList() else { return true }
                prepareForExternalAction()
                delete(itemId: itemId)
                return true
            },
            prepareItemDrag: { [self] itemId in
                guard claimCurrentList(),
                      let item = self.store.todoItemsCache[itemId]
                else { return false }
                if selectionManager.selectedItemIds.contains(itemId) == false {
                    selectionManager.handleSelect(
                        item: item,
                        allItems: store.items(in: store.destination(for: item)),
                        shiftPressed: false
                    )
                }
                return true
            },
            toggleCompleted: { [self] itemId in
                guard claimCurrentList() else { return }
                _ = toggleCompleted(itemId: itemId)
            },
            indent: { [self] itemId in
                guard claimCurrentList(),
                      let item = self.store.todoItemsCache[itemId]
                else { return }
                prepareForExternalAction()
                store.indentItem(item, selectionManager: selectionManager)
            },
            outdent: { [self] itemId in
                guard claimCurrentList(),
                      let item = self.store.todoItemsCache[itemId]
                else { return }
                prepareForExternalAction()
                store.outdentItem(item, selectionManager: selectionManager)
            },
            moveFocus: { [self] itemId, direction, cursorPosition, horizontalOffset in
                moveFocus(
                    itemId: itemId,
                    direction: direction,
                    cursorPosition: cursorPosition,
                    horizontalOffset: horizontalOffset
                )
            },
            moveItemByKeyboard: { [self] itemId, direction in
                guard claimCurrentList() else { return }
                _ = moveItemByKeyboard(itemId: itemId, direction: direction)
            },
            moveDraggedItem: { [self] itemId, destination, insertionIndex, indentLevel in
                guard claimCurrentList() else { return }
                prepareForExternalAction()
                _ = parentChildGroupMoveModule.execute(
                    .place(
                        draggedItemId: itemId,
                        destination: destination,
                        insertionIndex: insertionIndex,
                        indentLevel: indentLevel
                    )
                )
            },
            moveDraggedItemToSidebar: { [self] itemId, destination in
                guard claimCurrentList(), allowsSidebarMoves else { return }
                moveDraggedItemToSidebar(itemId: itemId, destination: destination)
            },
            sectionDateChanged: { [self] sectionId, newDate in
                guard claimCurrentList(),
                      let section = sectionById(sectionId)
                else { return }
                prepareForExternalAction()
                store.updateSectionDate(section, to: newDate)
            }
        )
    }

    init(
        store: TodoStore,
        selectionManager: SelectionManager,
        commandScope: TodoClipboardScope? = nil,
        allowsSidebarMoves: Bool = true,
        todayProvider: @escaping () -> Date = { .now },
        activeTextViewProvider: @escaping @MainActor () -> TodoEditorTextView? =
            TodoListActionModule.defaultActiveTextView,
        sectionById: ((UUID) -> DaySection?)? = nil
    ) {
        self.store = store
        self.selectionManager = selectionManager
        self.commandScope = commandScope
        self.allowsSidebarMoves = allowsSidebarMoves
        self.todayProvider = todayProvider
        self.activeTextViewProvider = activeTextViewProvider
        self.sectionById = sectionById ?? { store.daySectionsCache[$0] }
        self.parentChildGroupMoveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
    }

    func updateCommandScope(_ scope: TodoClipboardScope) {
        commandScope = scope
    }

    func activateHistoryContext() {
        selectionManager.activateHistoryContext()
    }

    func restoreHistorySelection(
        _ state: TodoSelectionState?,
        itemId: UUID?,
        sourceHistoryContext: TodoSelectionHistoryContext? = nil
    ) {
        if let state,
           sourceHistoryContext == nil || sourceHistoryContext == selectionManager.historyContext {
            state.apply(to: selectionManager)
        } else if let itemId, store.todoItemsCache[itemId] != nil {
            selectionManager.restoreFocus(to: itemId)
        }
    }

    func clearSelection() {
        prepareForExternalAction()
        selectionManager.clearSelection()
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
        case .selectAll:
            if let activeTextView {
                return activeTextView.string.isEmpty ? .unavailable(nil) : .available
            }
            guard let commandScope else { return .unavailable(nil) }
            return store.commandItems(in: commandScope).isEmpty
                ? .unavailable(nil)
                : .available
        case .moveUp:
            if activeTextView?.isComposingText == true {
                return .unavailable(nil)
            }
            return parentChildGroupMoveModule.availability(
                for: .moveSelectedGroups(direction: .up)
            )
        case .moveDown:
            if activeTextView?.isComposingText == true {
                return .unavailable(nil)
            }
            return parentChildGroupMoveModule.availability(
                for: .moveSelectedGroups(direction: .down)
            )
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
        let canExecute: Bool
        switch command {
        case .undo:
            canExecute = store.textEditSession.hasPendingSegment
                || store.undoManager.canUndo(displayScope: historyDisplayScope)
        case .redo:
            canExecute = store.undoManager.canRedo(displayScope: historyDisplayScope)
        default:
            return .available
        }
        guard canExecute else {
            return commandScope == .today
                ? .unavailable(.openMainWindowForHistory)
                : .unavailable(nil)
        }
        return .available
    }

    @discardableResult
    func perform(
        _ command: TodoListCommand,
        invocation: TodoListCommandInvocation = .menu,
        event: NSEvent? = nil
    ) -> TodoListActionResult {
        let result = performWithoutFeedback(
            command,
            invocation: invocation,
            event: event
        )
        feedbackPresenter.consume(result)
        return result
    }

    private func performWithoutFeedback(
        _ command: TodoListCommand,
        invocation: TodoListCommandInvocation,
        event: NSEvent?
    ) -> TodoListActionResult {
        if invocation == .keyboardShortcut,
           let direction = keyboardMoveDirection(for: command)
        {
            if let activeTextView, activeTextView.isComposingText {
                if let event {
                    activeTextView.routeToInputMethod(event)
                }
                return .noChange
            }
            guard let focusedItemId = selectionManager.focusedItemId else {
                notifyExternalAction()
                return .noChange
            }
            return performKeyboardMove(itemId: focusedItemId, direction: direction)
        }
        if command == .moveUp || command == .moveDown {
            // 菜单移动即使落在边界，也要先提交当前输入；边界判断不能
            // 把已经输入的文字留在编辑器的临时状态里。
            prepareForExternalAction()
        } else {
            notifyExternalAction()
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
            prepareForExternalAction()
            if let activeTextView {
                activeTextView.copy(nil)
                return .performed
            }
            guard let markdown = exportedMarkdown else { return .noChange }
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(markdown, forType: .string)
                ? .performed
                : .noChange
        case .cut:
            prepareForExternalAction()
            if let activeTextView {
                activeTextView.cut(nil)
                return .performed
            }
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
            prepareForExternalAction()
            if let activeTextView {
                activeTextView.paste(nil)
                return .performed
            }
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
        case .selectAll:
            prepareForExternalAction()
            if let activeTextView {
                activeTextView.selectAll(nil)
                return .performed
            }
            guard let commandScope else { return .noChange }
            let items = store.commandItems(in: commandScope)
            guard let firstItem = items.first else { return .noChange }
            selectionManager.selectedItemIds = Set(items.map(\.id))
            if selectionManager.focusedItemId.map(selectionManager.selectedItemIds.contains) != true {
                selectionManager.focusedItemId = firstItem.id
            }
            selectionManager.lastSelectedId = firstItem.id
            selectionManager.textSelectionLength = 0
            return .performed
        case .moveUp:
            prepareForExternalAction()
            return parentChildGroupMoveModule.execute(
                .moveSelectedGroups(direction: .up)
            )
        case .moveDown:
            prepareForExternalAction()
            return parentChildGroupMoveModule.execute(
                .moveSelectedGroups(direction: .down)
            )
        case .undo:
            prepareForExternalAction()
            guard let execution = store.undo(displayScope: historyDisplayScope) else {
                return historyExecutionFailure(for: .undo)
            }
            if let result = execution.presentationResult {
                TodoHistoryPresentationCoordinator.shared.present(result)
            }
            return .performed
        case .redo:
            prepareForExternalAction()
            guard let execution = store.redo(displayScope: historyDisplayScope) else {
                return historyExecutionFailure(for: .redo)
            }
            if let result = execution.presentationResult {
                TodoHistoryPresentationCoordinator.shared.present(result)
            }
            return .performed
        }
    }

    private func keyboardMoveDirection(
        for command: TodoListCommand
    ) -> TodoParentChildGroupMoveDirection? {
        switch command {
        case .moveUp:
            .up
        case .moveDown:
            .down
        default:
            nil
        }
    }

    private var clipboardSelection: TodoClipboardSelectionSnapshot {
        TodoClipboardSelectionSnapshot(
            focusedItemId: selectionManager.focusedItemId,
            selectedItemIds: selectionManager.selectedItemIds
        )
    }

    private var historyDisplayScope: TodoHistoryDisplayScope {
        commandScope == .today
            ? .today(on: todayProvider())
            : .all
    }

    private func historyExecutionFailure(
        for command: TodoListCommand
    ) -> TodoListActionResult {
        guard commandScope == .today else { return .noChange }
        switch command {
        case .undo, .redo:
            return .rejected(.openMainWindowForHistory)
        default:
            return .noChange
        }
    }

    private var exportedMarkdown: String? {
        guard let commandScope else { return nil }
        return store.exportMarkdown(scope: commandScope, selection: clipboardSelection)
    }

    private var activeTextView: TodoEditorTextView? {
        activeTextViewProvider()
    }

    private func prepareForExternalAction() {
        notifyExternalAction()
        commitPendingTextInput()
    }

    private func notifyExternalAction() {
        TodoEditorDragSession.shared.notifyExternalAction()
    }

    private func commitPendingTextInput() {
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
        if selectionManager.selectedItemIds.contains(item.id) {
            store.setCompletion(
                of: selectionManager.selectedItemIds,
                in: store.destination(for: item),
                isCompleted: item.isCompleted == false
            )
        } else {
            store.toggleComplete(item)
        }
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

    @discardableResult
    private func handleEnter(itemId: UUID, action: EnterAction) -> Bool {
        guard let item = store.todoItemsCache[itemId] else { return false }
        let newItem: TodoItem
        switch action {
        case .insertSiblingBelow:
            let destinationItems = store.items(in: store.destination(for: item))
            newItem = store.createItem(
                dayDate: item.dayDate,
                afterItem: item,
                indentLevel: item.title.isEmpty
                    ? item.indentLevel
                    : enterBelowIndentLevel(for: item, in: destinationItems),
                containerKind: item.containerKind,
                selectionManager: selectionManager
            )
        case .insertSiblingBelowAfterTextReplacement(
            let beforeTitle,
            let newCurrentTitle,
            let beforeSelection
        ):
            guard item.title == beforeTitle else { return false }
            let destinationItems = store.items(in: store.destination(for: item))
            guard let createdItem = store.createItemAfterReplacingTitle(
                item,
                newCurrentTitle: newCurrentTitle,
                indentLevel: enterBelowIndentLevel(for: item, in: destinationItems),
                beforeSelection: beforeSelection,
                selectionManager: selectionManager
            ) else { return false }
            newItem = createdItem
        case .insertSiblingAbove:
            newItem = store.createItemBefore(item, selectionManager: selectionManager)
        case .splitIntoChild(let newCurrentTitle, let childTitle):
            guard let splitItem = store.splitItem(
                item,
                newCurrentTitle: newCurrentTitle,
                childTitle: childTitle,
                selectionManager: selectionManager
            ) else { return false }
            newItem = splitItem
        }
        selectionManager.handleSelect(
            item: newItem,
            allItems: store.items(in: store.destination(for: newItem)),
            shiftPressed: false,
            cursorPosition: 0
        )
        return true
    }

    private func enterBelowIndentLevel(for item: TodoItem, in items: [TodoItem]) -> Int {
        guard let itemIndex = items.firstIndex(where: { $0.id == item.id }),
              let block = TodoHierarchyBlockEngine.block(startingAt: itemIndex, in: items),
              block.range.count > 1
        else {
            return item.indentLevel
        }

        return min(item.indentLevel + 1, TodoItem.maxIndentLevel)
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
        direction: TodoParentChildGroupMoveDirection
    ) -> TodoListCommandAvailability {
        parentChildGroupMoveModule.availability(
            for: .step(itemId: itemId, direction: direction)
        )
    }

    @discardableResult
    func moveItemByKeyboard(
        itemId: UUID,
        direction: TodoParentChildGroupMoveDirection
    ) -> TodoListActionResult {
        let result = moveItemByKeyboardWithoutFeedback(itemId: itemId, direction: direction)
        feedbackPresenter.consume(result)
        return result
    }

    private func moveItemByKeyboardWithoutFeedback(
        itemId: UUID,
        direction: TodoParentChildGroupMoveDirection
    ) -> TodoListActionResult {
        performKeyboardMove(itemId: itemId, direction: direction)
    }

    private func performKeyboardMove(
        itemId: UUID,
        direction: TodoParentChildGroupMoveDirection
    ) -> TodoListActionResult {
        prepareForExternalAction()
        return parentChildGroupMoveModule.execute(
            .step(itemId: itemId, direction: direction)
        )
    }

    private func moveDraggedItemToSidebar(
        itemId: UUID,
        destination: SidebarDestination
    ) {
        prepareForExternalAction()
        _ = parentChildGroupMoveModule.execute(
            .placeInSidebar(
                draggedItemId: itemId,
                destination: destination
            )
        )
    }
}
