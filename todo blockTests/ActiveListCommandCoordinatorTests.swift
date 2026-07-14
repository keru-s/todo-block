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

    func testDirectInteractionClaimsRegisteredListAndPassiveCallbackDoesNotStealClaim() {
        let store = TodoStore.shared
        let firstSelection = SelectionManager()
        let secondSelection = SelectionManager()
        let firstItem = store.createItem(title: "first", dayDate: .now)
        let firstModule = TodoListActionModule(
            store: store,
            selectionManager: firstSelection,
            commandScope: .today
        )
        let secondModule = TodoListActionModule(
            store: store,
            selectionManager: secondSelection,
            commandScope: .today
        )
        let firstRegistration = coordinator.register(firstModule)
        let secondRegistration = coordinator.register(secondModule)

        XCTAssertFalse(coordinator.hasCurrentList)
        XCTAssertTrue(coordinator.claim(firstRegistration))
        XCTAssertTrue(coordinator.isCurrent(firstModule))
        XCTAssertTrue(coordinator.claim(secondRegistration))
        XCTAssertTrue(coordinator.isCurrent(secondModule))

        firstModule.editorActions.textSelectionChanged(
            firstItem.id,
            TodoTextSelection(location: 0, length: 0)
        )

        XCTAssertTrue(coordinator.isCurrent(secondModule))
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

    func testReplacingVisibleMonthRegistrationImmediatelyClaimsTheNewScope() {
        let store = TodoStore.shared
        let aprilItem = store.createItem(
            title: "April",
            dayDate: date(year: 2026, month: 4, day: 2)
        )
        let mayItem = store.createItem(
            title: "May",
            dayDate: date(year: 2026, month: 5, day: 3)
        )
        let selection = SelectionManager(historyContext: .mainWindow)
        selection.focusedItemId = aprilItem.id
        selection.selectedItemIds = [aprilItem.id]
        let module = TodoListActionModule(
            store: store,
            selectionManager: selection,
            commandScope: .scheduledMonth(year: 2026, month: 4)
        )
        let aprilRegistration = coordinator.register(module)
        XCTAssertTrue(coordinator.claim(aprilRegistration))

        selection.focusedItemId = mayItem.id
        selection.selectedItemIds = [mayItem.id]
        module.updateCommandScope(.scheduledMonth(year: 2026, month: 5))
        let mayRegistration = coordinator.replaceAndClaim(
            aprilRegistration,
            with: module
        )

        XCTAssertTrue(coordinator.isCurrent(module))
        XCTAssertFalse(coordinator.claim(aprilRegistration))
        XCTAssertTrue(coordinator.claim(mayRegistration))
        XCTAssertEqual(coordinator.perform(.copy), .performed)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "- [ ] May")
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

    func testLongTermEditorInteractionClaimsItsModuleBeforeChangingItem() {
        let store = TodoStore.shared
        let item = store.createItem(
            title: "long term",
            dayDate: .now,
            containerKind: .longTermUrgent
        )
        let monthModule = TodoListActionModule(
            store: store,
            selectionManager: SelectionManager(historyContext: .mainWindow),
            commandScope: .today
        )
        let longTermSelection = SelectionManager(historyContext: .longTerm)
        let longTermModule = TodoListActionModule(
            store: store,
            selectionManager: longTermSelection,
            commandScope: .longTerm
        )
        let monthRegistration = coordinator.register(monthModule)
        let longTermRegistration = coordinator.register(longTermModule)
        XCTAssertTrue(coordinator.claim(monthRegistration))

        let actions = longTermModule.editorActions(claimCurrentList: {
            self.coordinator.claim(longTermRegistration)
        })
        actions.claimCurrentList()
        actions.toggleCompleted(item.id)

        XCTAssertTrue(item.isCompleted)
        XCTAssertTrue(coordinator.isCurrent(longTermModule))
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
}
