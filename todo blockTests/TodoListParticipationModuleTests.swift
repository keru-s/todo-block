import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoListParticipationModuleTests: XCTestCase {
    private var container: ModelContainer?

    override func setUp() async throws {
        let container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
        ActiveListCommandCoordinator.shared.resetForTesting()
    }

    override func tearDown() {
        ActiveListCommandCoordinator.shared.resetForTesting()
    }

    func testActiveLongTermListImmediatelyReceivesAppCommandsAndStopsAfterDeactivation() {
        let store = TodoStore.shared
        let item = store.createItem(
            title: "长期待办",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let selection = SelectionManager(historyContext: .longTerm)
        selection.focusedItemId = item.id
        selection.selectedItemIds = [item.id]
        let participation = makeParticipation(selectionManager: selection)

        participation.update(isActive: true)

        XCTAssertTrue(participation.isCurrentList)
        XCTAssertEqual(ActiveListCommandCoordinator.shared.perform(.copy), .performed)

        participation.update(isActive: false)

        XCTAssertFalse(participation.isCurrentList)
        XCTAssertEqual(ActiveListCommandCoordinator.shared.perform(.copy), .noChange)
    }

    func testPassiveEditorCallbacksDoNotClaimTheCurrentList() {
        let store = TodoStore.shared
        let firstItem = store.createItem(
            title: "first",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let first = makeParticipation()
        let second = makeParticipation()
        first.update(isActive: true)
        second.update(isActive: true)

        first.editorActions.textSelectionChanged(
            firstItem.id,
            TodoTextSelection(location: 0, length: 0)
        )
        first.editorActions.inputSessionEnded()

        XCTAssertFalse(first.isCurrentList)
        XCTAssertTrue(second.isCurrentList)
    }

    func testDirectListActionClaimsBeforeChangingSelection() {
        let store = TodoStore.shared
        let item = store.createItem(
            title: "长期待办",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let secondItem = store.createItem(
            title: "另一项长期待办",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let firstSelection = SelectionManager(historyContext: .longTerm)
        firstSelection.focusedItemId = item.id
        firstSelection.selectedItemIds = [item.id, secondItem.id]
        let first = makeParticipation(selectionManager: firstSelection)
        let second = makeParticipation()
        first.update(isActive: true)
        second.update(isActive: true)

        first.performDirectAction { $0.clearSelection() }

        XCTAssertTrue(first.isCurrentList)
        XCTAssertFalse(second.isCurrentList)
        XCTAssertTrue(firstSelection.selectedItemIds.isEmpty)
        XCTAssertEqual(firstSelection.focusedItemId, item.id)
    }

    func testExistingEditorActionsClaimBeforeDirectMutationAndRespectLaterLifecycleChanges() {
        let store = TodoStore.shared
        let item = store.createItem(
            title: "长期待办",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let participation = makeParticipation()
        let existingActions = participation.editorActions
        store.undoManager.clear()

        participation.update(isActive: false)
        existingActions.toggleCompleted(item.id)

        XCTAssertFalse(item.isCompleted)
        XCTAssertFalse(store.canUndo)

        participation.update(isActive: true)
        existingActions.toggleCompleted(item.id)

        XCTAssertTrue(participation.isCurrentList)
        XCTAssertTrue(item.isCompleted)
        XCTAssertTrue(store.canUndo)
    }

    func testFailedDirectEditorActionDoesNotChangeUserStateOrHistory() {
        let store = TodoStore.shared
        let item = store.createItem(
            title: "长期待办",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let selection = SelectionManager(historyContext: .longTerm)
        selection.focusedItemId = item.id
        selection.selectedItemIds = [item.id]
        let participation = makeParticipation(selectionManager: selection)
        let actions = participation.editorActions
        store.undoManager.clear()

        actions.deletePressed(item.id)

        XCTAssertNotNil(store.todoItemsCache[item.id])
        XCTAssertEqual(selection.focusedItemId, item.id)
        XCTAssertEqual(selection.selectedItemIds, [item.id])
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(store.canRedo)
    }

    func testActiveLongTermListRestoresItsHistoryRevealOnce() {
        let store = TodoStore.shared
        let item = store.createItem(
            title: "长期待办",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let participation = makeParticipation()
        let request = TodoHistoryRevealRequest(
            id: UUID(),
            destination: .longTerm,
            resultDestination: .longTerm(isUrgent: false),
            itemId: item.id,
            selectionState: TodoSelectionState(focusing: item.id, cursorPosition: 2),
            sourceHistoryContext: nil
        )

        participation.receiveHistoryReveal(request)
        participation.update(isActive: true)
        participation.receiveHistoryReveal(request)
        participation.receiveHistoryReveal(request)

        XCTAssertEqual(participation.visibleHistoryRevealRequest?.id, request.id)
        XCTAssertEqual(participation.selectionManager.focusedItemId, item.id)
        XCTAssertEqual(participation.selectionManager.selectedItemIds, [item.id])
        XCTAssertEqual(participation.selectionManager.cursorPosition, 2)
    }

    func testDateListInitiallyRegistersWithoutReplacingTheCurrentListThenClaimsWhenReactivated() {
        let longTerm = makeParticipation()
        let date = makeParticipation(
            claimsCurrentListWhenFirstActivated: false,
            historyRevealMatches: { $0.destination == .month(year: 2026, month: 7) }
        )

        longTerm.update(isActive: true)
        date.appear(isActive: true)

        XCTAssertTrue(longTerm.isCurrentList)
        XCTAssertFalse(date.isCurrentList)

        date.update(isActive: false)
        date.update(isActive: true)

        XCTAssertTrue(date.isCurrentList)
        XCTAssertFalse(longTerm.isCurrentList)
    }

    func testDateListFirstAppearingInactiveClaimsWhenItLaterBecomesActive() {
        let longTerm = makeParticipation()
        let date = makeParticipation(
            claimsCurrentListWhenFirstActivated: false,
            historyRevealMatches: { $0.destination == .month(year: 2026, month: 7) }
        )

        longTerm.update(isActive: true)
        date.appear(isActive: false)
        date.update(isActive: true)

        XCTAssertTrue(date.isCurrentList)
        XCTAssertFalse(longTerm.isCurrentList)
    }

    func testDateEditorActionClaimsBeforeChangingItsItem() {
        let store = TodoStore.shared
        let item = store.createItem(title: "日期待办", dayDate: .now)
        let longTerm = makeParticipation()
        let date = makeParticipation(
            claimsCurrentListWhenFirstActivated: false,
            historyRevealMatches: { $0.destination == .month(year: 2026, month: 7) }
        )

        longTerm.update(isActive: true)
        date.appear(isActive: true)
        date.editorActions.toggleCompleted(item.id)

        XCTAssertTrue(item.isCompleted)
        XCTAssertTrue(date.isCurrentList)
        XCTAssertFalse(longTerm.isCurrentList)
    }

    func testUpdatingDateScopeDoesNotClaimWhileTemporaryListIsActive() {
        let date = makeParticipation(
            claimsCurrentListWhenFirstActivated: false,
            historyRevealMatches: { $0.destination == .month(year: 2026, month: 7) }
        )
        let menuBarModule = TodoListActionModule(
            store: .shared,
            selectionManager: SelectionManager(historyContext: .menuBar),
            commandScope: .today
        )
        let menuBarRegistration = ActiveListCommandCoordinator.shared.register(menuBarModule)

        date.appear(isActive: true)
        let temporaryClaim = ActiveListCommandCoordinator.shared.beginTemporaryClaim(menuBarRegistration)

        date.updateCommandScope(.scheduledMonth(year: 2026, month: 8))

        XCTAssertNotNil(temporaryClaim)
        XCTAssertFalse(date.isCurrentList)
    }

    func testDateListConsumesOnlyItsVisibleMonthHistoryRevealOnce() {
        let store = TodoStore.shared
        let item = store.createItem(title: "八月待办", dayDate: .now)
        let participation = makeParticipation(
            claimsCurrentListWhenFirstActivated: false,
            historyRevealMatches: { $0.destination == .month(year: 2026, month: 8) }
        )
        let otherMonthRequest = TodoHistoryRevealRequest(
            id: UUID(),
            destination: .month(year: 2026, month: 7),
            resultDestination: .scheduled(date: .now),
            itemId: item.id,
            selectionState: TodoSelectionState(focusing: item.id, cursorPosition: 1),
            sourceHistoryContext: nil
        )
        let targetRequest = TodoHistoryRevealRequest(
            id: UUID(),
            destination: .month(year: 2026, month: 8),
            resultDestination: .scheduled(date: .now),
            itemId: item.id,
            selectionState: TodoSelectionState(focusing: item.id, cursorPosition: 2),
            sourceHistoryContext: nil
        )

        participation.receiveHistoryReveal(otherMonthRequest)
        participation.appear(isActive: true)

        XCTAssertNil(participation.visibleHistoryRevealRequest)
        XCTAssertNil(participation.selectionManager.focusedItemId)

        participation.receiveHistoryReveal(targetRequest)
        participation.receiveHistoryReveal(targetRequest)

        XCTAssertEqual(participation.visibleHistoryRevealRequest?.id, targetRequest.id)
        XCTAssertEqual(participation.selectionManager.focusedItemId, item.id)
        XCTAssertEqual(participation.selectionManager.cursorPosition, 2)
    }

    func testMenuBarTemporarilyClaimsThenRestoresThePreviousList() {
        let longTerm = makeParticipation()
        let menuBar = makeParticipation(
            selectionManager: SelectionManager(historyContext: .menuBar),
            retainsHistoryRevealsWhileInactive: false,
            historyRevealMatches: { _ in true }
        )

        longTerm.update(isActive: true)
        menuBar.register()
        menuBar.beginTemporaryParticipation()
        menuBar.beginTemporaryParticipation()

        XCTAssertTrue(menuBar.isCurrentList)
        XCTAssertFalse(longTerm.isCurrentList)

        menuBar.endTemporaryParticipation()
        menuBar.endTemporaryParticipation()

        XCTAssertTrue(longTerm.isCurrentList)
        XCTAssertFalse(menuBar.isCurrentList)
    }

    func testHiddenMenuBarIgnoresHistoryRevealInsteadOfReplayingItOnOpen() {
        let store = TodoStore.shared
        let item = store.createItem(title: "今日待办", dayDate: .now)
        let menuBar = makeParticipation(
            selectionManager: SelectionManager(historyContext: .menuBar),
            retainsHistoryRevealsWhileInactive: false,
            historyRevealMatches: { _ in true }
        )
        let request = TodoHistoryRevealRequest(
            id: UUID(),
            destination: .month(year: 2026, month: 7),
            resultDestination: .scheduled(date: .now),
            itemId: item.id,
            selectionState: TodoSelectionState(focusing: item.id, cursorPosition: 3),
            sourceHistoryContext: nil
        )

        menuBar.register()
        menuBar.receiveHistoryReveal(request)
        menuBar.beginTemporaryParticipation()
        menuBar.receiveHistoryReveal(request)

        XCTAssertNil(menuBar.visibleHistoryRevealRequest)
        XCTAssertNil(menuBar.selectionManager.focusedItemId)
    }

    func testHiddenMenuBarEditorActionDoesNotChangeItemsOrHistory() {
        let store = TodoStore.shared
        let item = store.createItem(title: "今日待办", dayDate: .now)
        let menuBar = makeParticipation(
            selectionManager: SelectionManager(historyContext: .menuBar),
            retainsHistoryRevealsWhileInactive: false,
            historyRevealMatches: { _ in true }
        )
        let actions = menuBar.editorActions
        store.undoManager.clear()

        menuBar.register()
        actions.toggleCompleted(item.id)

        XCTAssertFalse(item.isCompleted)
        XCTAssertFalse(store.canUndo)
    }

    private func makeParticipation(
        selectionManager: SelectionManager? = nil,
        claimsCurrentListWhenFirstActivated: Bool = true,
        retainsHistoryRevealsWhileInactive: Bool = true,
        historyRevealMatches: @escaping TodoListParticipationModule.HistoryRevealMatcher = {
            $0.destination == .longTerm
        }
    ) -> TodoListParticipationModule {
        let selectionManager = selectionManager ?? SelectionManager(historyContext: .longTerm)
        let actionModule = TodoListActionModule(
            store: .shared,
            selectionManager: selectionManager,
            commandScope: .longTerm
        )
        return TodoListParticipationModule(
            actionModule: actionModule,
            claimsCurrentListWhenFirstActivated: claimsCurrentListWhenFirstActivated,
            retainsHistoryRevealsWhileInactive: retainsHistoryRevealsWhileInactive,
            historyRevealMatches: historyRevealMatches
        )
    }
}
