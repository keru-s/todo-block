import SwiftData
import Observation
import XCTest
@testable import todo_block

@MainActor
final class TodoHistoryPresentationTests: XCTestCase {
    private var container: ModelContainer!
    private var store: TodoStore!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: config
        )
        store = TodoStore.shared
        store.reset()
        store.initialize(with: container.mainContext)
    }

    func testTodayResultRemainsInMenuBar() {
        let coordinator = TodoHistoryPresentationCoordinator.shared
        var openCount = 0
        coordinator.install { openCount += 1 }
        coordinator.activate(scope: .today)

        coordinator.reveal(destination: .scheduled(date: .now), itemId: UUID())

        XCTAssertEqual(openCount, 0)
        XCTAssertNotNil(coordinator.revealRequest)
    }

    func testTodayResultWithoutItemStillCarriesEmptySelectionState() {
        let coordinator = TodoHistoryPresentationCoordinator.shared
        let emptySelection = TodoSelectionState(focusing: nil)
        let today = Date.now
        coordinator.activate(scope: .today)

        coordinator.reveal(
            destination: .scheduled(date: today),
            itemId: nil,
            selectionState: emptySelection
        )

        XCTAssertEqual(
            coordinator.revealRequest?.resultDestination,
            .scheduled(date: Calendar.current.startOfDay(for: today))
        )
        XCTAssertEqual(coordinator.revealRequest?.selectionState, emptySelection)
    }

    func testOtherMonthResultOpensMainWindowAndSelectsMonth() {
        let coordinator = TodoHistoryPresentationCoordinator.shared
        var openCount = 0
        var destinationWhenOpening: SidebarDestination?
        coordinator.install {
            openCount += 1
            destinationWhenOpening = coordinator.revealRequest?.destination
        }
        coordinator.activate(scope: .today)
        let targetDate = date(year: 2027, month: 4, day: 8)

        coordinator.reveal(destination: .scheduled(date: targetDate), itemId: nil)

        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(destinationWhenOpening, .month(year: 2027, month: 4))
        XCTAssertEqual(
            coordinator.revealRequest?.destination,
            .month(year: 2027, month: 4)
        )
    }

    func testLongTermResultFromMenuBarOpensMainWindow() {
        let coordinator = TodoHistoryPresentationCoordinator.shared
        var openCount = 0
        coordinator.install { openCount += 1 }
        coordinator.activate(scope: .today)

        coordinator.reveal(destination: .longTerm(isUrgent: true), itemId: nil)

        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(coordinator.revealRequest?.destination, .longTerm)
    }

    func testUndoFromMenuBarRevealsEditedItemInItsMonth() {
        let coordinator = TodoHistoryPresentationCoordinator.shared
        var openCount = 0
        coordinator.install { openCount += 1 }
        coordinator.activate(scope: .today)
        let targetDate = date(year: 2027, month: 4, day: 8)
        let item = store.createItem(title: "abc", dayDate: targetDate)
        let selectionManager = SelectionManager(historyContext: .mainWindow)
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.lastSelectedId = item.id
        selectionManager.cursorPosition = 1
        selectionManager.textSelectionLength = 1
        let actions = TodoEditorActionFactory.make(
            store: store,
            selectionManager: selectionManager
        )
        store.undoManager.clear()
        actions.titleChanged(
            item.id,
            TodoTextEditEvent(
                beforeText: "abc",
                afterText: "aXc",
                beforeSelection: TodoTextSelection(location: 1, length: 1),
                afterSelection: TodoTextSelection(location: 2, length: 0),
                kind: .replacement
            )
        )

        XCTAssertTrue(store.undo())

        XCTAssertEqual(item.title, "abc")
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(
            coordinator.revealRequest?.destination,
            .month(year: 2027, month: 4)
        )
        XCTAssertEqual(coordinator.revealRequest?.itemId, item.id)
        let restoredSelection = try? XCTUnwrap(coordinator.revealRequest?.selectionState)
        XCTAssertEqual(restoredSelection?.focusedItemId, item.id)
        XCTAssertEqual(restoredSelection?.selectedItemIds, [item.id])
        XCTAssertEqual(restoredSelection?.cursorPosition, 1)
        XCTAssertEqual(restoredSelection?.textSelectionLength, 1)

        let replacementManager = SelectionManager(historyContext: .mainWindow)
        restoredSelection?.apply(to: replacementManager)
        XCTAssertEqual(replacementManager.focusedItemId, item.id)
        XCTAssertEqual(replacementManager.selectedItemIds, [item.id])
        XCTAssertEqual(replacementManager.textSelectionLength, 1)
        XCTAssertNil(store.focusRequestId)
    }

    func testNavigationDoesNotClearRedoPath() {
        let item = store.createItem(title: "a", dayDate: .now)
        store.undoManager.clear()
        store.toggleComplete(item)
        XCTAssertTrue(store.undo())
        XCTAssertTrue(store.canRedo)

        let selectionManager = SelectionManager()
        selectionManager.handleSelect(
            item: item,
            allItems: [item],
            shiftPressed: false,
            cursorPosition: 0
        )
        TodoHistoryPresentationCoordinator.shared.activate(scope: .longTerm)
        TodoHistoryPresentationCoordinator.shared.activate(scope: .today)

        XCTAssertTrue(store.canRedo)
        XCTAssertTrue(store.redo())
        XCTAssertTrue(item.isCompleted)
    }

    func testThreeEntryOperationsUndoAndRedoInStrictTimeOrder() {
        let today = store.createItem(title: "today", dayDate: .now)
        let longTerm = store.createItem(
            title: "long",
            dayDate: .now,
            containerKind: .longTermUrgent
        )
        let future = store.createItem(
            title: "future",
            dayDate: date(year: 2027, month: 4, day: 8)
        )
        store.undoManager.clear()

        TodoHistoryPresentationCoordinator.shared.activate(scope: .today)
        store.toggleComplete(today)
        TodoHistoryPresentationCoordinator.shared.activate(scope: .longTerm)
        store.toggleComplete(longTerm)
        TodoHistoryPresentationCoordinator.shared.activate(
            scope: .scheduledMonth(year: 2027, month: 4)
        )
        store.toggleComplete(future)

        XCTAssertTrue(store.undo())
        XCTAssertFalse(future.isCompleted)
        XCTAssertTrue(longTerm.isCompleted)
        XCTAssertTrue(today.isCompleted)

        XCTAssertTrue(store.undo())
        XCTAssertFalse(longTerm.isCompleted)
        XCTAssertTrue(today.isCompleted)

        XCTAssertTrue(store.undo())
        XCTAssertFalse(today.isCompleted)

        XCTAssertTrue(store.redo())
        XCTAssertTrue(today.isCompleted)
        XCTAssertTrue(store.redo())
        XCTAssertTrue(longTerm.isCompleted)
        XCTAssertTrue(store.redo())
        XCTAssertTrue(future.isCompleted)
    }

    func testUndoAvailabilityUpdatesAsSoonAsTextEditingStarts() {
        let item = store.createItem(title: "a", dayDate: .now)
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        let actions = TodoEditorActionFactory.make(
            store: store,
            selectionManager: selectionManager
        )
        store.undoManager.clear()
        var didChange = false
        withObservationTracking {
            _ = store.canUndo
        } onChange: {
            didChange = true
        }

        actions.titleChanged(
            item.id,
            TodoTextEditEvent(
                beforeText: "a",
                afterText: "ab",
                beforeSelection: TodoTextSelection(location: 1, length: 0),
                afterSelection: TodoTextSelection(location: 2, length: 0),
                kind: .insertion
            )
        )

        XCTAssertTrue(didChange)
        XCTAssertTrue(store.canUndo)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
