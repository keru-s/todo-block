import AppKit
import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class ActiveListCommandCoordinatorTests: XCTestCase {
    private var container: ModelContainer?
    private var coordinator: ActiveListCommandCoordinator { .shared }

    override func setUp() async throws {
        let container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
        coordinator.resetForTesting()
        NSPasteboard.general.clearContents()
    }

    override func tearDown() {
        coordinator.resetForTesting()
        NSPasteboard.general.clearContents()
    }

    func testInvalidatedOrStaleRegistrationCannotReceiveCommands() {
        let module = TodoListActionModule(
            store: .shared,
            selectionManager: SelectionManager(),
            commandScope: .today
        )
        let registration = coordinator.register(module)
        XCTAssertTrue(coordinator.claim(registration))

        coordinator.unregister(registration)

        XCTAssertFalse(coordinator.hasCurrentList)
        XCTAssertFalse(coordinator.claim(registration))
        XCTAssertEqual(coordinator.availability(of: .undo), .unavailable(nil))
        XCTAssertEqual(coordinator.perform(.undo), .noChange)
    }

    func testCommandsAndAvailabilityFollowOnlyTheClaimedListModule() {
        let store = TodoStore.shared
        let firstDay = date(year: 2026, month: 4, day: 2)
        let secondDay = date(year: 2026, month: 5, day: 3)
        let firstItem = store.createItem(title: "April", dayDate: firstDay)
        let secondItem = store.createItem(title: "May", dayDate: secondDay)
        let firstSelection = SelectionManager()
        firstSelection.focusedItemId = firstItem.id
        firstSelection.selectedItemIds = [firstItem.id]
        let secondSelection = SelectionManager()
        secondSelection.focusedItemId = secondItem.id
        secondSelection.selectedItemIds = [secondItem.id]
        let firstModule = TodoListActionModule(
            store: store,
            selectionManager: firstSelection,
            commandScope: .scheduledMonth(year: 2026, month: 4)
        )
        let secondModule = TodoListActionModule(
            store: store,
            selectionManager: secondSelection,
            commandScope: .scheduledMonth(year: 2026, month: 5)
        )
        let firstRegistration = coordinator.register(firstModule)
        let secondRegistration = coordinator.register(secondModule)

        XCTAssertTrue(coordinator.claim(firstRegistration))
        XCTAssertEqual(coordinator.availability(of: .copy), .available)
        XCTAssertEqual(coordinator.perform(.copy), .performed)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "- [ ] April")

        XCTAssertTrue(coordinator.claim(secondRegistration))
        XCTAssertEqual(coordinator.perform(.copy), .performed)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "- [ ] May")
    }

    func testDateAndLongTermModulesKeepIndependentSelectionWhenCommandsSwitchTarget() {
        let store = TodoStore.shared
        let dateItem = store.createItem(title: "date", dayDate: .now)
        let longTermItem = store.createItem(
            title: "long term",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let dateSelection = SelectionManager(historyContext: .mainWindow)
        dateSelection.focusedItemId = dateItem.id
        dateSelection.selectedItemIds = [dateItem.id]
        dateSelection.cursorPosition = 2
        dateSelection.textSelectionLength = 1
        let longTermSelection = SelectionManager(historyContext: .longTerm)
        longTermSelection.focusedItemId = longTermItem.id
        longTermSelection.selectedItemIds = [longTermItem.id]
        longTermSelection.cursorPosition = 4
        let dateModule = TodoListActionModule(
            store: store,
            selectionManager: dateSelection,
            commandScope: .today
        )
        let longTermModule = TodoListActionModule(
            store: store,
            selectionManager: longTermSelection,
            commandScope: .longTerm
        )
        let dateRegistration = coordinator.register(dateModule)
        let longTermRegistration = coordinator.register(longTermModule)

        XCTAssertTrue(coordinator.claim(dateRegistration))
        XCTAssertEqual(coordinator.perform(.copy), .performed)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "- [ ] date")

        XCTAssertTrue(coordinator.claim(longTermRegistration))
        XCTAssertEqual(coordinator.perform(.copy), .performed)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "- [ ] long term")
        XCTAssertEqual(dateSelection.focusedItemId, dateItem.id)
        XCTAssertEqual(dateSelection.cursorPosition, 2)
        XCTAssertEqual(dateSelection.textSelectionLength, 1)
        XCTAssertEqual(longTermSelection.focusedItemId, longTermItem.id)
        XCTAssertEqual(longTermSelection.cursorPosition, 4)
    }

    func testClaimedModuleKeepsTitleTextSelectionAheadOfWholeItemCopy() {
        let store = TodoStore.shared
        let item = store.createItem(title: "whole item", dayDate: .now)
        let selection = SelectionManager()
        selection.focusedItemId = item.id
        selection.selectedItemIds = [item.id]
        let textView = TodoEditorTextView()
        textView.string = "selected title"
        textView.setSelectedRange(NSRange(location: 0, length: 8))
        let module = TodoListActionModule(
            store: store,
            selectionManager: selection,
            commandScope: .today,
            activeTextViewProvider: { textView }
        )
        let registration = coordinator.register(module)
        XCTAssertTrue(coordinator.claim(registration))

        XCTAssertEqual(coordinator.availability(of: .copy), .available)
        XCTAssertEqual(coordinator.perform(.copy), .performed)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "selected")
        XCTAssertNotNil(store.todoItemsCache[item.id])

        textView.setSelectedRange(NSRange(location: 8, length: 0))
        XCTAssertEqual(coordinator.availability(of: .copy), .unavailable(nil))
    }

    func testClaimedModuleKeepsTextCutAndPasteAheadOfWholeItemCommands() {
        let store = TodoStore.shared
        let item = store.createItem(title: "whole item", dayDate: .now)
        let selection = SelectionManager()
        selection.focusedItemId = item.id
        selection.selectedItemIds = [item.id]
        let textView = TodoEditorTextView()
        textView.string = "selected title"
        textView.synchronizeReportedText("selected title")
        textView.setSelectedRange(NSRange(location: 0, length: 8))
        let module = TodoListActionModule(
            store: store,
            selectionManager: selection,
            commandScope: .today,
            activeTextViewProvider: { textView }
        )
        let registration = coordinator.register(module)
        XCTAssertTrue(coordinator.claim(registration))

        XCTAssertEqual(coordinator.availability(of: .cut), .available)
        XCTAssertEqual(coordinator.perform(.cut), .performed)
        XCTAssertEqual(textView.string, " title")
        XCTAssertNotNil(store.todoItemsCache[item.id])

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("new", forType: .string)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(coordinator.availability(of: .cut), .unavailable(nil))
        XCTAssertEqual(coordinator.perform(.cut), .noChange)
        XCTAssertNotNil(store.todoItemsCache[item.id])

        XCTAssertEqual(coordinator.availability(of: .paste), .available)
        XCTAssertEqual(coordinator.perform(.paste), .performed)
        XCTAssertEqual(textView.string, "new title")
        XCTAssertEqual(store.todayItems().count, 1)
    }

    func testKeyEventMovesFocusedItemLocallyWhileMenuEventMovesWholeSelection() throws {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 7, day: 14)
        let first = store.createItem(title: "first", dayDate: day)
        let focused = store.createItem(title: "focused", dayDate: day, afterItem: first)
        let selected = store.createItem(title: "selected", dayDate: day, afterItem: focused)
        let tail = store.createItem(title: "tail", dayDate: day, afterItem: selected)
        let selection = SelectionManager()
        selection.focusedItemId = focused.id
        selection.selectedItemIds = [focused.id, selected.id]
        let textView = TodoEditorTextView()
        let module = TodoListActionModule(
            store: store,
            selectionManager: selection,
            commandScope: .scheduledMonth(year: 2026, month: 7),
            activeTextViewProvider: { textView }
        )
        XCTAssertTrue(coordinator.claim(coordinator.register(module)))
        store.undoManager.clear()
        let keyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F700}",
            charactersIgnoringModifiers: "\u{F700}",
            isARepeat: false,
            keyCode: 126
        ))

        XCTAssertEqual(coordinator.perform(.moveUp, event: keyEvent), .performed)
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [focused.id, first.id, selected.id, tail.id]
        )

        XCTAssertTrue(store.undo())
        let menuEvent = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        XCTAssertEqual(coordinator.perform(.moveDown, event: menuEvent), .performed)
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [first.id, tail.id, focused.id, selected.id]
        )
    }

    func testExactMoveShortcutsWithoutTextViewMoveOnlyFocusedParentChildGroup() throws {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 7, day: 14)
        let first = store.createItem(title: "first", dayDate: day)
        let focused = store.createItem(title: "focused", dayDate: day, afterItem: first)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: focused,
            indentLevel: 1
        )
        let otherSelected = store.createItem(
            title: "other selected",
            dayDate: day,
            afterItem: child
        )
        let tail = store.createItem(title: "tail", dayDate: day, afterItem: otherSelected)
        let selection = SelectionManager()
        selection.focusedItemId = focused.id
        selection.selectedItemIds = [focused.id, otherSelected.id]
        let module = TodoListActionModule(
            store: store,
            selectionManager: selection,
            commandScope: .scheduledMonth(year: 2026, month: 7),
            activeTextViewProvider: { nil }
        )
        XCTAssertTrue(coordinator.claim(coordinator.register(module)))
        store.undoManager.clear()

        XCTAssertEqual(
            coordinator.perform(.moveUp, event: try moveKeyEvent(direction: .up)),
            .performed
        )
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [focused.id, child.id, first.id, otherSelected.id, tail.id]
        )

        XCTAssertTrue(store.undo())
        XCTAssertEqual(
            coordinator.perform(.moveDown, event: try moveKeyEvent(direction: .down)),
            .performed
        )
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [first.id, otherSelected.id, focused.id, child.id, tail.id]
        )
    }

    func testExactMoveShortcutsWithoutTextViewStaySilentAtFocusedItemBoundary() throws {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 7, day: 14)
        let first = store.createItem(title: "first", dayDate: day)
        let middle = store.createItem(title: "middle", dayDate: day, afterItem: first)
        let last = store.createItem(title: "last", dayDate: day, afterItem: middle)
        let selection = SelectionManager()
        let module = TodoListActionModule(
            store: store,
            selectionManager: selection,
            commandScope: .scheduledMonth(year: 2026, month: 7),
            activeTextViewProvider: { nil }
        )
        XCTAssertTrue(coordinator.claim(coordinator.register(module)))
        store.undoManager.clear()

        selection.focusedItemId = first.id
        selection.selectedItemIds = [first.id, middle.id]
        XCTAssertEqual(
            coordinator.perform(.moveUp, event: try moveKeyEvent(direction: .up)),
            .noChange
        )

        selection.focusedItemId = last.id
        selection.selectedItemIds = [middle.id, last.id]
        XCTAssertEqual(
            coordinator.perform(.moveDown, event: try moveKeyEvent(direction: .down)),
            .noChange
        )
        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, middle.id, last.id])
        XCTAssertFalse(store.canUndo)
    }

    func testReturnKeyFromKeyboardNavigatedMenuMovesWholeSelection() throws {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 7, day: 14)
        let first = store.createItem(title: "first", dayDate: day)
        let focused = store.createItem(title: "focused", dayDate: day, afterItem: first)
        let selected = store.createItem(title: "selected", dayDate: day, afterItem: focused)
        let tail = store.createItem(title: "tail", dayDate: day, afterItem: selected)
        let selection = SelectionManager()
        selection.focusedItemId = focused.id
        selection.selectedItemIds = [focused.id, selected.id]
        let module = TodoListActionModule(
            store: store,
            selectionManager: selection,
            commandScope: .scheduledMonth(year: 2026, month: 7),
            activeTextViewProvider: { nil }
        )
        XCTAssertTrue(coordinator.claim(coordinator.register(module)))
        store.undoManager.clear()
        let returnEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))

        XCTAssertEqual(coordinator.perform(.moveDown, event: returnEvent), .performed)
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [first.id, tail.id, focused.id, selected.id]
        )
    }

    func testKeyEventDoesNotMoveItemsOrCommitMarkedText() throws {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 7, day: 14)
        let first = store.createItem(title: "first", dayDate: day)
        let focused = store.createItem(title: "focused", dayDate: day, afterItem: first)
        let selection = SelectionManager()
        selection.focusedItemId = focused.id
        selection.selectedItemIds = [focused.id]
        let textView = TodoEditorTextView()
        textView.setMarkedText(
            "中",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let module = TodoListActionModule(
            store: store,
            selectionManager: selection,
            commandScope: .scheduledMonth(year: 2026, month: 7),
            activeTextViewProvider: { textView }
        )
        XCTAssertTrue(coordinator.claim(coordinator.register(module)))
        let keyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F700}",
            charactersIgnoringModifiers: "\u{F700}",
            isARepeat: false,
            keyCode: 126
        ))

        XCTAssertEqual(coordinator.availability(of: .moveUp), .unavailable(nil))
        let menu = NSMenu()
        menu.autoenablesItems = false
        let menuItem = NSMenuItem(
            title: "上移当前待办",
            action: #selector(NSTextView.moveUp(_:)),
            keyEquivalent: "\u{F700}"
        )
        menuItem.target = textView
        menuItem.keyEquivalentModifierMask = .command
        menuItem.isEnabled = coordinator.availability(of: .moveUp).allowsAttempt
        menu.addItem(menuItem)
        XCTAssertFalse(menuItem.isEnabled)

        textView.keyDown(with: keyEvent)
        XCTAssertEqual(coordinator.perform(.moveUp, event: keyEvent), .noChange)
        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, focused.id])
    }

    func testCommandWithoutCurrentListDoesNotChangeUserStateOrHistory() {
        let store = TodoStore.shared
        let item = store.createItem(title: "unchanged", dayDate: .now)
        store.undoManager.clear()

        XCTAssertEqual(coordinator.perform(.cut), .noChange)
        XCTAssertEqual(coordinator.perform(.moveUp), .noChange)
        XCTAssertEqual(coordinator.perform(.undo), .noChange)
        XCTAssertNotNil(store.todoItemsCache[item.id])
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

    private func moveKeyEvent(
        direction: TodoParentChildGroupMoveDirection
    ) throws -> NSEvent {
        let keyCode: UInt16
        let characters: String
        switch direction {
        case .up:
            keyCode = 126
            characters = "\u{F700}"
        case .down:
            keyCode = 125
            characters = "\u{F701}"
        }
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
