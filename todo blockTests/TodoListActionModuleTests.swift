import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoListActionModuleTests: XCTestCase {
    private var container: ModelContainer!
    private var selectionManager: SelectionManager!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: config
        )

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
        selectionManager = SelectionManager(historyContext: .mainWindow)
    }

    func testCompletingParentThroughModuleUpdatesWholeParentChildGroupAndCanUndo() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let parent = store.createItem(title: "parent", dayDate: day)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        )
        store.undoManager.clear()

        let result = module.toggleCompleted(itemId: parent.id)

        XCTAssertEqual(result, .performed)
        XCTAssertTrue(parent.isCompleted)
        XCTAssertTrue(child.isCompleted)
        XCTAssertTrue(store.undo())
        XCTAssertFalse(parent.isCompleted)
        XCTAssertFalse(child.isCompleted)
    }

    func testAddingTodayThroughModuleCreatesAndFocusesItemWhenTodayAlreadyExists() {
        let store = TodoStore.shared
        let today = Calendar.current.startOfDay(for: .now)
        let existing = store.createItem(title: "existing", dayDate: today)
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        )
        selectionManager.handleSelect(
            item: existing,
            allItems: [existing],
            shiftPressed: false
        )
        store.undoManager.clear()

        let result = module.addToday(mode: .blank)

        XCTAssertEqual(result, .performed)
        XCTAssertEqual(store.todayItems().map(\.title), ["existing", ""])
        XCTAssertEqual(selectionManager.focusedItemId, store.todayItems().last?.id)
        XCTAssertEqual(selectionManager.cursorPosition, 0)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.todayItems().map(\.title), ["existing"])
        XCTAssertEqual(selectionManager.focusedItemId, existing.id)
    }

    func testCarryingOverYesterdayThroughModuleMovesIncompleteParentChildGroupAndCanUndo() throws {
        let store = TodoStore.shared
        let yesterday = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )
        let parent = store.createItem(title: "parent", dayDate: yesterday)
        let child = store.createItem(
            title: "child",
            dayDate: yesterday,
            afterItem: parent,
            indentLevel: 1
        )
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        )
        store.undoManager.clear()

        let result = module.addToday(mode: .carryOver)

        XCTAssertEqual(result, .performed)
        XCTAssertEqual(store.todayItems().map(\.id), [parent.id, child.id])
        XCTAssertEqual(store.todayItems().map(\.indentLevel), [0, 1])
        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: yesterday).map(\.id), [parent.id, child.id])
        XCTAssertTrue(store.todayItems().isEmpty)
    }

    func testEditorActionsFromModulePreserveUserStateAcrossRefreshesAndStructuralEdits() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let first = store.createItem(title: "first", dayDate: day)
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        )
        store.undoManager.clear()

        module.editorActions.selectItem(first.id, false, 3)
        let refreshedActions = module.editorActions
        refreshedActions.addItem(.scheduled(date: day))

        let added = store.items(for: day)[1]
        XCTAssertEqual(selectionManager.focusedItemId, added.id)
        XCTAssertEqual(selectionManager.cursorPosition, 0)

        refreshedActions.indent(added.id)
        XCTAssertEqual(added.indentLevel, 1)
        refreshedActions.outdent(added.id)
        XCTAssertEqual(added.indentLevel, 0)
        refreshedActions.indent(added.id)

        refreshedActions.deletePressed(added.id)
        XCTAssertEqual(store.items(for: day).map(\.id), [first.id])
        XCTAssertEqual(selectionManager.focusedItemId, first.id)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, added.id])
        XCTAssertEqual(selectionManager.focusedItemId, added.id)
        XCTAssertEqual(added.indentLevel, 1)
    }

    func testTextEditingThroughModuleRestoresTextAndCursorAsOneOperation() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let item = store.createItem(title: "buy", dayDate: day)
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        )
        selectionManager.handleSelect(
            item: item,
            allItems: [item],
            shiftPressed: false,
            cursorPosition: 3
        )
        store.undoManager.clear()

        module.editorActions.titleChanged(
            item.id,
            TodoTextEditEvent(
                beforeText: "buy",
                afterText: "buy milk",
                beforeSelection: TodoTextSelection(location: 3, length: 0),
                afterSelection: TodoTextSelection(location: 8, length: 0),
                kind: .insertion
            )
        )

        XCTAssertEqual(item.title, "buy milk")
        XCTAssertEqual(selectionManager.focusedItemId, item.id)
        XCTAssertEqual(selectionManager.cursorPosition, 8)
        module.editorActions.textSelectionChanged(
            item.id,
            TodoTextSelection(location: 4, length: 2)
        )
        XCTAssertEqual(selectionManager.cursorPosition, 4)
        XCTAssertEqual(selectionManager.textSelectionLength, 2)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "buy")
        XCTAssertEqual(selectionManager.focusedItemId, item.id)
        XCTAssertEqual(selectionManager.cursorPosition, 3)
    }

    func testExternalActionCommitsMarkedTextBeforeChangingTheItem() {
        let store = TodoStore.shared
        let item = store.createItem(title: "明", dayDate: .now)
        selectionManager.handleSelect(
            item: item,
            allItems: [item],
            shiftPressed: false,
            cursorPosition: 1
        )
        let textView = TodoEditorTextView()
        textView.string = "明"
        textView.synchronizeReportedText("明")
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager,
            activeTextViewProvider: { textView }
        )
        let actions = module.editorActions
        textView.onTextDidChange = { event in
            actions.titleChanged(item.id, event)
        }
        store.undoManager.clear()

        textView.setMarkedText(
            "晚",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())

        XCTAssertEqual(module.toggleCompleted(itemId: item.id), .performed)

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(item.title, "明晚")
        XCTAssertTrue(item.isCompleted)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "明晚")
        XCTAssertFalse(item.isCompleted)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "明")
    }

    func testUndoCommitsAndRevertsTheCurrentCompositionAsOneStep() {
        let store = TodoStore.shared
        let item = store.createItem(title: "原", dayDate: .now)
        selectionManager.handleSelect(
            item: item,
            allItems: [item],
            shiftPressed: false,
            cursorPosition: 1
        )
        let textView = TodoEditorTextView()
        textView.string = "原"
        textView.synchronizeReportedText("原")
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager,
            commandScope: .today,
            activeTextViewProvider: { textView }
        )
        let actions = module.editorActions
        textView.onTextDidChange = { event in
            actions.titleChanged(item.id, event)
        }
        store.undoManager.clear()

        textView.setMarkedText(
            "文",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertEqual(module.commandAvailability(.undo), .available)
        XCTAssertEqual(module.perform(.undo), .performed)
        XCTAssertEqual(item.title, "原")
        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertTrue(store.canRedo)
    }

    func testChangingSectionDateThroughModuleMovesWholeParentChildGroupAndCanUndo() throws {
        let store = TodoStore.shared
        let sourceDay = date(year: 2026, month: 5, day: 31)
        let targetDay = date(year: 2026, month: 6, day: 2)
        let parent = store.createItem(title: "parent", dayDate: sourceDay)
        let child = store.createItem(
            title: "child",
            dayDate: sourceDay,
            afterItem: parent,
            indentLevel: 1
        )
        let section = try XCTUnwrap(store.validDaySections.first {
            Calendar.current.isDate($0.date, inSameDayAs: sourceDay)
        })
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        )
        store.undoManager.clear()

        module.editorActions.sectionDateChanged(section.id, targetDay)

        XCTAssertEqual(store.items(for: targetDay).map(\.id), [parent.id, child.id])
        XCTAssertTrue(store.items(for: sourceDay).isEmpty)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: sourceDay).map(\.id), [parent.id, child.id])
    }

    func testKeyboardMoveReportsBoundaryAndHiddenRejectionWithoutChangingHistory() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let item = store.createItem(title: "only", dayDate: day)
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        )
        store.undoManager.clear()

        XCTAssertEqual(
            module.keyboardMoveAvailability(itemId: item.id, direction: .up),
            .unavailable(nil)
        )
        XCTAssertEqual(
            module.moveItemByKeyboard(itemId: item.id, direction: .up),
            .noChange
        )

        let missingId = UUID()
        let rejection = TodoListActionRejection(message: "待办已不存在")
        XCTAssertEqual(
            module.keyboardMoveAvailability(itemId: missingId, direction: .down),
            .unavailable(rejection)
        )
        XCTAssertEqual(
            module.moveItemByKeyboard(itemId: missingId, direction: .down),
            .rejected(rejection)
        )

        XCTAssertFalse(store.canUndo)
    }

    func testEnterVariantsAndFocusNavigationThroughModuleKeepExpectedUserState() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 31)
        let first = store.createItem(title: "first", dayDate: day)
        let second = store.createItem(title: "second", dayDate: day, afterItem: first)
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        )
        store.undoManager.clear()

        module.editorActions.moveFocus(first.id, .down, 2, 24)
        XCTAssertEqual(selectionManager.focusedItemId, second.id)
        XCTAssertEqual(selectionManager.cursorPosition, 2)
        module.editorActions.moveFocus(second.id, .up, 1, 16)
        XCTAssertEqual(selectionManager.focusedItemId, first.id)
        XCTAssertEqual(selectionManager.cursorPosition, 1)
        XCTAssertFalse(store.canUndo)

        module.editorActions.enterPressed(first.id, .insertSiblingAbove)
        let above = store.items(for: day)[0]
        XCTAssertEqual(selectionManager.focusedItemId, above.id)
        XCTAssertEqual(store.items(for: day).map(\.title), ["", "first", "second"])

        module.editorActions.enterPressed(second.id, .insertSiblingBelow)
        let below = store.items(for: day).last
        XCTAssertEqual(selectionManager.focusedItemId, below?.id)
        XCTAssertEqual(store.items(for: day).map(\.title), ["", "first", "second", ""])
    }

    func testMenuBarModuleDoesNotMoveTodayItemToMainWindowSidebar() {
        let store = TodoStore.shared
        let item = store.createItem(title: "today", dayDate: .now)
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager,
            commandScope: .today,
            allowsSidebarMoves: false
        )
        store.undoManager.clear()

        module.editorActions.moveDraggedItemToSidebar(item.id, .longTerm)

        XCTAssertEqual(store.destination(for: item), .scheduled(date: .now).normalized)
        XCTAssertFalse(store.canUndo)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? .now
    }
}
