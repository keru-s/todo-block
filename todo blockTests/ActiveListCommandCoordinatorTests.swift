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
