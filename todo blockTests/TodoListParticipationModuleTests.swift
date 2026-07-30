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
        TodoHistoryPresentationCoordinator.shared.resetForTesting()
    }

    override func tearDown() {
        ActiveListCommandCoordinator.shared.resetForTesting()
        TodoHistoryPresentationCoordinator.shared.resetForTesting()
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
        let request = presentHistoryReveal(
            destination: .longTerm(isUrgent: false),
            itemId: item.id,
            selectionState: TodoSelectionState(focusing: item.id, cursorPosition: 2)
        )

        participation.receiveHistoryReveal(request)
        participation.update(isActive: true)
        participation.receiveHistoryReveal(request)
        participation.receiveHistoryReveal(request)

        XCTAssertEqual(participation.visibleHistoryRevealRequest?.id, request?.id)
        XCTAssertEqual(participation.selectionManager.focusedItemId, item.id)
        XCTAssertEqual(participation.selectionManager.selectedItemIds, [item.id])
        XCTAssertEqual(participation.selectionManager.cursorPosition, 2)
    }

    func testActiveDateListImmediatelyClaimsWhenItFirstAppears() {
        let longTerm = makeParticipation()
        let date = makeParticipation(
            historyRevealMatches: { $0.destination == .month(year: 2026, month: 7) }
        )

        longTerm.update(isActive: true)
        date.appear(isActive: true)

        XCTAssertFalse(longTerm.isCurrentList)
        XCTAssertTrue(date.isCurrentList)

        date.update(isActive: false)
        date.update(isActive: true)

        XCTAssertTrue(date.isCurrentList)
        XCTAssertFalse(longTerm.isCurrentList)
    }

    func testDateListFirstAppearingInactiveClaimsWhenItLaterBecomesActive() {
        let longTerm = makeParticipation()
        let date = makeParticipation(
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
            historyRevealMatches: { $0.destination == .month(year: 2026, month: 7) }
        )
        let menuBar = makeParticipation(
            selectionManager: SelectionManager(historyContext: .menuBar),
            participationIdentity: .menuBar,
            retainsHistoryRevealsWhileInactive: false,
            historyRevealMatches: { _ in true }
        )

        date.appear(isActive: true)
        menuBar.register()
        menuBar.beginTemporaryParticipation()

        date.updateCommandScope(.scheduledMonth(year: 2026, month: 8))

        XCTAssertTrue(menuBar.isCurrentList)
        XCTAssertFalse(date.isCurrentList)
    }

    func testDateListConsumesOnlyItsVisibleMonthHistoryRevealOnce() {
        let store = TodoStore.shared
        let item = store.createItem(title: "八月待办", dayDate: .now)
        let participation = makeParticipation(
            historyRevealMatches: { $0.destination == .month(year: 2026, month: 8) }
        )
        let otherMonthRequest = presentHistoryReveal(
            destination: .scheduled(date: date(year: 2026, month: 7, day: 1)),
            itemId: item.id,
            selectionState: TodoSelectionState(focusing: item.id, cursorPosition: 1)
        )

        participation.receiveHistoryReveal(otherMonthRequest)
        participation.appear(isActive: true)

        XCTAssertNil(participation.visibleHistoryRevealRequest)
        XCTAssertNil(participation.selectionManager.focusedItemId)

        let targetRequest = presentHistoryReveal(
            destination: .scheduled(date: date(year: 2026, month: 8, day: 1)),
            itemId: item.id,
            selectionState: TodoSelectionState(focusing: item.id, cursorPosition: 2)
        )
        participation.receiveHistoryReveal(targetRequest)
        participation.receiveHistoryReveal(targetRequest)

        XCTAssertEqual(participation.visibleHistoryRevealRequest?.id, targetRequest?.id)
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
        let request = presentHistoryReveal(
            destination: .scheduled(date: .now),
            itemId: item.id,
            selectionState: TodoSelectionState(focusing: item.id, cursorPosition: 3)
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

    func testRebuiltLogicalListDoesNotReplayAnAlreadyHandledHistoryReveal() {
        let store = TodoStore.shared
        let item = store.createItem(
            title: "长期待办",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let coordinator = TodoHistoryPresentationCoordinator.shared
        coordinator.present(
            TodoHistoryApplicationResult(
                destination: .longTerm(isUrgent: false),
                itemId: item.id,
                sourceHistoryContext: .mainWindow,
                sourceSelectionState: TodoSelectionState(focusing: item.id, cursorPosition: 2)
            )
        )
        let request = try? XCTUnwrap(coordinator.revealRequest)

        let original = makeParticipation()
        original.update(isActive: true)
        original.receiveHistoryReveal(request)

        let rebuilt = makeParticipation()
        rebuilt.update(isActive: true)
        rebuilt.receiveHistoryReveal(request)

        XCTAssertEqual(original.visibleHistoryRevealRequest?.id, request?.id)
        XCTAssertNil(rebuilt.visibleHistoryRevealRequest)
    }

    func testInactiveTargetKeepsOnlyTheLatestRelevantHistoryReveal() {
        let store = TodoStore.shared
        let firstItem = store.createItem(
            title: "第一个",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let secondItem = store.createItem(
            title: "第二个",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let coordinator = TodoHistoryPresentationCoordinator.shared
        let participation = makeParticipation()

        coordinator.present(
            TodoHistoryApplicationResult(
                destination: .longTerm(isUrgent: false),
                itemId: firstItem.id,
                sourceHistoryContext: .mainWindow,
                sourceSelectionState: TodoSelectionState(focusing: firstItem.id)
            )
        )
        let firstRequest = try? XCTUnwrap(coordinator.revealRequest)
        participation.receiveHistoryReveal(firstRequest)

        coordinator.present(
            TodoHistoryApplicationResult(
                destination: .longTerm(isUrgent: false),
                itemId: secondItem.id,
                sourceHistoryContext: .mainWindow,
                sourceSelectionState: TodoSelectionState(focusing: secondItem.id, cursorPosition: 3)
            )
        )
        let latestRequest = try? XCTUnwrap(coordinator.revealRequest)
        participation.receiveHistoryReveal(latestRequest)
        participation.update(isActive: true)

        XCTAssertEqual(participation.visibleHistoryRevealRequest?.id, latestRequest?.id)
        XCTAssertEqual(participation.selectionManager.focusedItemId, secondItem.id)
        XCTAssertEqual(participation.selectionManager.cursorPosition, 0)
    }

    func testSupersededHistoryRevealIsNotVisibleBeforeTheNextCallbackArrives() {
        let store = TodoStore.shared
        let firstItem = store.createItem(
            title: "第一个",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let secondItem = store.createItem(
            title: "第二个",
            dayDate: .now,
            containerKind: .longTermImportant
        )
        let coordinator = TodoHistoryPresentationCoordinator.shared
        let participation = makeParticipation()
        participation.update(isActive: true)

        coordinator.present(
            TodoHistoryApplicationResult(
                destination: .longTerm(isUrgent: false),
                itemId: firstItem.id,
                sourceHistoryContext: .mainWindow,
                sourceSelectionState: nil
            )
        )
        participation.receiveHistoryReveal(coordinator.revealRequest)
        XCTAssertNotNil(participation.visibleHistoryRevealRequest)

        coordinator.present(
            TodoHistoryApplicationResult(
                destination: .longTerm(isUrgent: false),
                itemId: secondItem.id,
                sourceHistoryContext: .mainWindow,
                sourceSelectionState: nil
            )
        )

        XCTAssertNil(participation.visibleHistoryRevealRequest)
    }

    func testCrossEntryUndoRestoresTheSourceWithoutChangingOtherLists() {
        let store = TodoStore.shared
        let item = store.createItem(title: "日期待办", dayDate: .now)
        let sourceSelection = SelectionManager(historyContext: .longTerm)
        sourceSelection.focusedItemId = item.id
        sourceSelection.selectedItemIds = [item.id]
        sourceSelection.lastSelectedId = item.id
        sourceSelection.cursorPosition = 1
        sourceSelection.textSelectionLength = 1
        let source = makeParticipation(selectionManager: sourceSelection)
        let destinationSelection = SelectionManager(historyContext: .mainWindow)
        let destination = makeParticipation(
            selectionManager: destinationSelection,
            participationIdentity: .mainWindow,
            historyRevealMatches: { _ in true }
        )
        let otherSelection = SelectionManager(historyContext: .menuBar)
        let otherFocusedItemId = UUID()
        otherSelection.focusedItemId = otherFocusedItemId
        let other = makeParticipation(
            selectionManager: otherSelection,
            participationIdentity: .menuBar,
            retainsHistoryRevealsWhileInactive: false,
            historyRevealMatches: { _ in true }
        )
        store.undoManager.clear()

        source.update(isActive: true)
        destination.appear(isActive: true)
        other.register()
        source.editorActions.titleChanged(
            item.id,
            TodoTextEditEvent(
                beforeText: "日期待办",
                afterText: "已修改",
                beforeSelection: TodoTextSelection(location: 1, length: 1),
                afterSelection: TodoTextSelection(location: 3, length: 0),
                kind: .replacement
            )
        )

        XCTAssertEqual(ActiveListCommandCoordinator.shared.perform(.undo), .performed)
        let request = try? XCTUnwrap(TodoHistoryPresentationCoordinator.shared.revealRequest)
        destination.receiveHistoryReveal(request)
        other.receiveHistoryReveal(request)

        XCTAssertEqual(item.title, "日期待办")
        XCTAssertEqual(sourceSelection.focusedItemId, item.id)
        XCTAssertEqual(sourceSelection.cursorPosition, 1)
        XCTAssertEqual(sourceSelection.textSelectionLength, 1)
        XCTAssertEqual(destinationSelection.focusedItemId, item.id)
        XCTAssertEqual(otherSelection.focusedItemId, otherFocusedItemId)
        XCTAssertNil(other.visibleHistoryRevealRequest)
    }

    private func makeParticipation(
        selectionManager: SelectionManager? = nil,
        participationIdentity: TodoListParticipationIdentity = .longTerm,
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
            participationIdentity: participationIdentity,
            claimsCurrentListWhenFirstActivated: claimsCurrentListWhenFirstActivated,
            retainsHistoryRevealsWhileInactive: retainsHistoryRevealsWhileInactive,
            historyRevealMatches: historyRevealMatches
        )
    }

    private func presentHistoryReveal(
        destination: TodoDropDestination,
        itemId: UUID,
        selectionState: TodoSelectionState
    ) -> TodoHistoryRevealRequest? {
        let coordinator = TodoHistoryPresentationCoordinator.shared
        coordinator.present(
            TodoHistoryApplicationResult(
                destination: destination,
                itemId: itemId,
                sourceHistoryContext: nil,
                sourceSelectionState: selectionState
            )
        )
        return coordinator.revealRequest
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
