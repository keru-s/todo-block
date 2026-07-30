import SwiftData
import Observation
import XCTest
@testable import todo_block

@MainActor
final class TodoHistoryPresentationTests: XCTestCase {
    private var container: ModelContainer!
    private var store: TodoStore!
    private var participations: [TodoListParticipationModule] = []

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
        participations = []
        ActiveListCommandCoordinator.shared.resetForTesting()
        TodoHistoryPresentationCoordinator.shared.resetForTesting()
    }

    override func tearDown() {
        ActiveListCommandCoordinator.shared.resetForTesting()
        TodoHistoryPresentationCoordinator.shared.resetForTesting()
    }

    func testUndoAppliesHistoryWithoutIssuingAnyPresentationRequest() {
        let item = store.createItem(title: "a", dayDate: .now)
        store.undoManager.clear()
        store.toggleComplete(item)

        XCTAssertTrue(store.undo())

        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(TodoHistoryPresentationCoordinator.shared.revealRequest)
    }

    func testTodayOnlyHistoryExecutionDoesNotSkipRecentOtherListOperation() {
        let today = store.createItem(title: "today", dayDate: .now)
        let future = store.createItem(
            title: "future",
            dayDate: date(year: 2027, month: 4, day: 8)
        )
        store.undoManager.clear()
        store.toggleComplete(today)
        store.toggleComplete(future)

        let execution = store.undoManager.undo(
            displayScope: .today(on: .now),
            store: store
        )

        XCTAssertNil(execution)
        XCTAssertTrue(today.isCompleted)
        XCTAssertTrue(future.isCompleted)
    }

    func testTodayOnlyHistoryRecoveryDoesNotSkipRecentOtherListOperation() {
        let future = store.createItem(
            title: "future",
            dayDate: date(year: 2027, month: 4, day: 8)
        )
        store.undoManager.clear()
        store.toggleComplete(future)
        XCTAssertTrue(store.undo())

        let execution = store.undoManager.redo(
            displayScope: .today(on: .now),
            store: store
        )

        XCTAssertNil(execution)
        XCTAssertFalse(future.isCompleted)
    }

    func testOtherEntryFocusesResultWithoutOverwritingOriginalListTextSelection() {
        let item = store.createItem(title: "abc", dayDate: .now)
        let originalSelection = SelectionManager(historyContext: .mainWindow)
        originalSelection.focusedItemId = item.id
        originalSelection.selectedItemIds = [item.id]
        originalSelection.lastSelectedId = item.id
        originalSelection.cursorPosition = 1
        originalSelection.textSelectionLength = 1
        let menuSelection = SelectionManager(historyContext: .menuBar)
        let menu = makeParticipation(
            selectionManager: menuSelection,
            participationIdentity: .menuBar,
            commandScope: .today,
            retainsHistoryRevealsWhileInactive: false,
            historyRevealMatches: { _ in true }
        )
        menu.update(isActive: true)
        store.undoManager.clear()

        let before = TodoItemSnapshot(from: item)
        let operation = TodoOperationUnit(
            actionName: "完成",
            itemTransitions: [
                TodoItemTransition(before: before, after: before.replacing(isCompleted: true))
            ],
            selectionTransitions: [
                TodoSelectionTransition(
                    selectionManager: originalSelection,
                    before: TodoSelectionState(selectionManager: originalSelection),
                    after: TodoSelectionState(selectionManager: originalSelection)
                )
            ]
        )
        XCTAssertTrue(store.undoManager.perform(operation, store: store))

        XCTAssertEqual(
            ActiveListCommandCoordinator.shared.perform(.undo),
            .performed
        )

        let request = try? XCTUnwrap(
            TodoHistoryPresentationCoordinator.shared.revealRequest
        )
        menu.receiveHistoryReveal(request)

        XCTAssertEqual(originalSelection.focusedItemId, item.id)
        XCTAssertEqual(originalSelection.cursorPosition, 1)
        XCTAssertEqual(originalSelection.textSelectionLength, 1)
        XCTAssertEqual(menuSelection.focusedItemId, item.id)
        XCTAssertEqual(menuSelection.textSelectionLength, 0)
    }

    func testCrossEntryUndoSurvivesWhenOriginalListHasGoneAway() {
        let item = store.createItem(title: "a", dayDate: .now)
        let menuSelection = SelectionManager(historyContext: .menuBar)
        let menu = makeParticipation(
            selectionManager: menuSelection,
            participationIdentity: .menuBar,
            commandScope: .today,
            retainsHistoryRevealsWhileInactive: false,
            historyRevealMatches: { _ in true }
        )
        menu.update(isActive: true)
        store.undoManager.clear()

        func recordMainWindowOperation() {
            let mainSelection = SelectionManager(historyContext: .mainWindow)
            mainSelection.focusedItemId = item.id
            mainSelection.selectedItemIds = [item.id]
            mainSelection.cursorPosition = 3
            mainSelection.textSelectionLength = 1
            let before = TodoItemSnapshot(from: item)
            let operation = TodoOperationUnit(
                actionName: "完成",
                itemTransitions: [
                    TodoItemTransition(before: before, after: before.replacing(isCompleted: true))
                ],
                selectionTransitions: [
                    TodoSelectionTransition(
                        selectionManager: mainSelection,
                        before: TodoSelectionState(selectionManager: mainSelection),
                        after: TodoSelectionState(selectionManager: mainSelection)
                    )
                ]
            )
            XCTAssertTrue(store.undoManager.perform(operation, store: store))
        }

        recordMainWindowOperation()

        XCTAssertEqual(ActiveListCommandCoordinator.shared.perform(.undo), .performed)
        let request = try? XCTUnwrap(
            TodoHistoryPresentationCoordinator.shared.revealRequest
        )
        menu.receiveHistoryReveal(request)
        XCTAssertFalse(item.isCompleted)
        XCTAssertEqual(menuSelection.focusedItemId, item.id)

        let returningMainSelection = SelectionManager(historyContext: .mainWindow)
        returningMainSelection.activateHistoryContext()
        XCTAssertEqual(returningMainSelection.focusedItemId, item.id)
        XCTAssertEqual(returningMainSelection.selectedItemIds, [item.id])
        XCTAssertEqual(returningMainSelection.cursorPosition, 3)
        XCTAssertEqual(returningMainSelection.textSelectionLength, 1)
    }

    func testStoreResetClearsDeferredHistorySelection() {
        let itemId = UUID()
        SelectionManager.applyHistoryState(
            TodoSelectionState(
                focusing: itemId,
                cursorPosition: 3
            ),
            for: .mainWindow
        )

        store.reset()

        let mainSelection = SelectionManager(historyContext: .mainWindow)
        mainSelection.activateHistoryContext()
        XCTAssertNil(mainSelection.focusedItemId)
        XCTAssertTrue(mainSelection.selectedItemIds.isEmpty)
        XCTAssertEqual(mainSelection.cursorPosition, 0)
    }

    func testEphemeralSelectionContextDoesNotKeepDeferredHistoryState() {
        let context = TodoSelectionHistoryContext.ephemeral(UUID())
        let itemId = UUID()
        SelectionManager.applyHistoryState(
            TodoSelectionState(focusing: itemId),
            for: context
        )

        let selection = SelectionManager(historyContext: context)
        selection.activateHistoryContext()
        XCTAssertNil(selection.focusedItemId)
        XCTAssertTrue(selection.selectedItemIds.isEmpty)
    }

    func testOperationAttentionSuppliesPresentationDestinationForCrossListResult() {
        let today = Calendar.current.startOfDay(for: .now)
        let future = date(year: 2027, month: 4, day: 8)
        let first = store.createItem(title: "first", dayDate: today)
        let second = store.createItem(title: "second", dayDate: future)
        let firstBefore = TodoItemSnapshot(from: first)
        let secondBefore = TodoItemSnapshot(from: second)
        store.undoManager.clear()

        let operation = TodoOperationUnit(
            actionName: "交换日期",
            itemTransitions: [
                TodoItemTransition(
                    before: firstBefore,
                    after: firstBefore.replacing(dayDate: future)
                ),
                TodoItemTransition(
                    before: secondBefore,
                    after: secondBefore.replacing(dayDate: today)
                ),
            ],
            attention: .destination(.scheduled(date: today))
        )
        XCTAssertTrue(store.undoManager.perform(operation, store: store))

        let execution = store.undoManager.undo(displayScope: .all, store: store)

        XCTAssertEqual(
            execution?.presentationResult?.destination,
            .scheduled(date: today)
        )
    }

    func testUndoFromMainWindowPublishesEditedItemForItsMonth() {
        let targetDate = date(year: 2027, month: 4, day: 8)
        let item = store.createItem(title: "abc", dayDate: targetDate)
        let selectionManager = SelectionManager(historyContext: .mainWindow)
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.lastSelectedId = item.id
        selectionManager.cursorPosition = 1
        selectionManager.textSelectionLength = 1
        let participation = makeParticipation(
            selectionManager: selectionManager,
            participationIdentity: .mainWindow,
            commandScope: .scheduledMonth(year: 2027, month: 4),
            claimsCurrentListWhenFirstActivated: true,
            historyRevealMatches: { $0.destination == .month(year: 2027, month: 4) }
        )
        participation.update(isActive: true)
        let actions = participation.editorActions
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

        XCTAssertEqual(ActiveListCommandCoordinator.shared.perform(.undo), .performed)

        XCTAssertEqual(item.title, "abc")
        let coordinator = TodoHistoryPresentationCoordinator.shared
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
        claimList(scope: .longTerm)
        claimList(scope: .today)

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

        claimList(scope: .today)
        store.toggleComplete(today)
        claimList(scope: .longTerm)
        store.toggleComplete(longTerm)
        claimList(scope: .scheduledMonth(year: 2027, month: 4))
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
        let actions = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        ).editorActions
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

    private func makeParticipation(
        selectionManager: SelectionManager,
        participationIdentity: TodoListParticipationIdentity,
        commandScope: TodoClipboardScope,
        claimsCurrentListWhenFirstActivated: Bool = true,
        retainsHistoryRevealsWhileInactive: Bool = true,
        historyRevealMatches: @escaping TodoListParticipationModule.HistoryRevealMatcher
    ) -> TodoListParticipationModule {
        let actionModule = TodoListActionModule(
            store: store,
            selectionManager: selectionManager,
            commandScope: commandScope
        )
        let participation = TodoListParticipationModule(
            actionModule: actionModule,
            participationIdentity: participationIdentity,
            claimsCurrentListWhenFirstActivated: claimsCurrentListWhenFirstActivated,
            retainsHistoryRevealsWhileInactive: retainsHistoryRevealsWhileInactive,
            historyRevealMatches: historyRevealMatches
        )
        participations.append(participation)
        return participation
    }

    private func claimList(scope: TodoClipboardScope) {
        let selectionManager = SelectionManager()
        let participation = makeParticipation(
            selectionManager: selectionManager,
            participationIdentity: .ephemeral(UUID()),
            commandScope: scope,
            claimsCurrentListWhenFirstActivated: true,
            historyRevealMatches: { _ in true }
        )
        participation.update(isActive: true)
    }
}
