import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoParentChildGroupMoveModuleTests: XCTestCase {
    private var container: ModelContainer!
    private var selectionManager: SelectionManager!

    override func setUp() async throws {
        container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
        selectionManager = SelectionManager()
    }

    func testStepMoveMovesWholeParentChildGroupAndUndoRestoresSelection() {
        let store = TodoStore.shared
        let day = Date.now
        let first = store.createItem(title: "first", dayDate: day)
        let parent = store.createItem(title: "parent", dayDate: day, afterItem: first)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let other = store.createItem(title: "other", dayDate: day, afterItem: child)
        selectionManager.focusedItemId = parent.id
        selectionManager.selectedItemIds = [parent.id, other.id]
        selectionManager.lastSelectedId = other.id
        selectionManager.cursorPosition = 3
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )

        let intent = TodoParentChildGroupMoveIntent.step(
            itemId: parent.id,
            direction: .up
        )

        XCTAssertEqual(moveModule.availability(for: intent), .available)
        XCTAssertFalse(store.canUndo, "查询不能创建操作单元")
        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(store.items(for: day).map(\.id), [parent.id, child.id, first.id, other.id])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.cursorPosition, 3)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, parent.id, child.id, other.id])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id, other.id])
        XCTAssertEqual(selectionManager.lastSelectedId, other.id)
        XCTAssertEqual(selectionManager.cursorPosition, 3)

        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.items(for: day).map(\.id), [parent.id, child.id, first.id, other.id])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.lastSelectedId, parent.id)
        XCTAssertEqual(selectionManager.cursorPosition, 3)
    }

    func testMoveSelectedGroupsDeduplicatesDescendantsAndRestoresThemInOneUndoStep() {
        let store = TodoStore.shared
        let day = Date.now
        let first = store.createItem(title: "first", dayDate: day)
        let parent = store.createItem(title: "parent", dayDate: day, afterItem: first)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let middle = store.createItem(title: "middle", dayDate: day, afterItem: child)
        let independent = store.createItem(title: "independent", dayDate: day, afterItem: middle)
        let tail = store.createItem(title: "tail", dayDate: day, afterItem: independent)
        selectionManager.selectedItemIds = [parent.id, child.id, independent.id]
        selectionManager.focusedItemId = child.id
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )

        let intent = TodoParentChildGroupMoveIntent.moveSelectedGroups(direction: .up)

        XCTAssertEqual(moveModule.availability(for: intent), .available)
        XCTAssertFalse(store.canUndo, "查询不能创建操作单元")
        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [parent.id, child.id, first.id, independent.id, middle.id, tail.id]
        )
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id, child.id, independent.id])
        XCTAssertEqual(selectionManager.focusedItemId, child.id)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [first.id, parent.id, child.id, middle.id, independent.id, tail.id]
        )
        XCTAssertFalse(store.canUndo, "多个父子组只能产生一个操作单元")
    }

    func testMoveSelectedGroupsDoesNotMoveAnyGroupWhenOneIsAtTheBoundary() {
        let store = TodoStore.shared
        let day = Date.now
        let first = store.createItem(title: "first", dayDate: day)
        let middle = store.createItem(title: "middle", dayDate: day, afterItem: first)
        let last = store.createItem(title: "last", dayDate: day, afterItem: middle)
        selectionManager.selectedItemIds = [first.id, last.id]
        selectionManager.focusedItemId = first.id
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )

        let intent = TodoParentChildGroupMoveIntent.moveSelectedGroups(direction: .up)

        XCTAssertEqual(moveModule.availability(for: intent), .unavailable(nil))
        XCTAssertEqual(moveModule.execute(intent), .noChange)
        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, middle.id, last.id])
        XCTAssertFalse(store.canUndo)
    }

    func testStepMoveNormalizesMovedNestedGroupAndUndoRestoresOriginalIndents() {
        let store = TodoStore.shared
        let day = Date.now
        let root = store.createItem(title: "root", dayDate: day, indentLevel: 0)
        let moving = store.createItem(
            title: "moving",
            dayDate: day,
            afterItem: root,
            indentLevel: 3
        )
        let descendant = store.createItem(
            title: "descendant",
            dayDate: day,
            afterItem: moving,
            indentLevel: 4
        )
        let sibling = store.createItem(
            title: "sibling",
            dayDate: day,
            afterItem: descendant,
            indentLevel: 1
        )
        selectionManager.focusedItemId = moving.id
        selectionManager.selectedItemIds = [moving.id]
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )

        XCTAssertEqual(
            moveModule.execute(.step(itemId: moving.id, direction: .down)),
            .performed
        )
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [root.id, sibling.id, moving.id, descendant.id]
        )
        XCTAssertEqual(moving.indentLevel, 1)
        XCTAssertEqual(descendant.indentLevel, 2)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [root.id, moving.id, descendant.id, sibling.id]
        )
        XCTAssertEqual(moving.indentLevel, 3)
        XCTAssertEqual(descendant.indentLevel, 4)
    }

    func testPlaceMovesSelectedGroupsInSourceOrderAsOneUndoStep() {
        let store = TodoStore.shared
        let day = Date.now
        let first = store.createItem(title: "first", dayDate: day)
        let parent = store.createItem(title: "parent", dayDate: day, afterItem: first)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let middle = store.createItem(title: "middle", dayDate: day, afterItem: child)
        let independent = store.createItem(title: "independent", dayDate: day, afterItem: middle)
        let tail = store.createItem(title: "tail", dayDate: day, afterItem: independent)
        selectionManager.selectedItemIds = [parent.id, child.id, independent.id]
        selectionManager.focusedItemId = child.id
        selectionManager.lastSelectedId = independent.id
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.place(
            draggedItemId: parent.id,
            destination: .scheduled(date: day),
            insertionIndex: 6,
            indentLevel: 0
        )

        XCTAssertEqual(moveModule.availability(for: intent), .available)
        XCTAssertFalse(store.canUndo, "查询不能创建操作单元")
        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [first.id, middle.id, tail.id, parent.id, child.id, independent.id]
        )
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id, child.id, independent.id])
        XCTAssertEqual(selectionManager.focusedItemId, child.id)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [first.id, parent.id, child.id, middle.id, independent.id, tail.id]
        )
        XCTAssertFalse(store.canUndo, "多组拖拽只能产生一个操作单元")
    }

    func testPlaceMovesNoncontiguousSelectedGroupsAfterTheFirstSelectedGroup() {
        let store = TodoStore.shared
        let day = Date.now
        let first = store.createItem(title: "first", dayDate: day)
        let middle = store.createItem(title: "middle", dayDate: day, afterItem: first)
        let last = store.createItem(title: "last", dayDate: day, afterItem: middle)
        selectionManager.selectedItemIds = [first.id, last.id]
        selectionManager.focusedItemId = first.id
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.place(
            draggedItemId: first.id,
            destination: .scheduled(date: day),
            insertionIndex: 1,
            indentLevel: 0
        )

        XCTAssertEqual(moveModule.availability(for: intent), .available)
        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, last.id, middle.id])

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, middle.id, last.id])
        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.items(for: day).map(\.id), [first.id, last.id, middle.id])
    }

    func testPlaceFallsBackToSingleGroupWhenSelectionSpansAnotherList() {
        let store = TodoStore.shared
        let sourceDay = Date.now
        let otherDay = Calendar.current.date(byAdding: .day, value: 1, to: sourceDay) ?? sourceDay
        let parent = store.createItem(title: "parent", dayDate: sourceDay)
        let child = store.createItem(
            title: "child",
            dayDate: sourceDay,
            afterItem: parent,
            indentLevel: 1
        )
        let tail = store.createItem(title: "tail", dayDate: sourceDay, afterItem: child)
        let unrelated = store.createItem(title: "unrelated", dayDate: otherDay)
        selectionManager.selectedItemIds = [parent.id, unrelated.id]
        selectionManager.focusedItemId = unrelated.id
        selectionManager.lastSelectedId = unrelated.id
        selectionManager.cursorPosition = 2
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.place(
            draggedItemId: parent.id,
            destination: .scheduled(date: sourceDay),
            insertionIndex: 3,
            indentLevel: 0
        )

        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(store.items(for: sourceDay).map(\.id), [tail.id, parent.id, child.id])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.cursorPosition, 2)
    }

    func testPlaceAcrossDaysUndoRedoRestoresOrderHierarchySelectionAndCursor() {
        let store = TodoStore.shared
        let sourceDay = date(year: 2026, month: 4, day: 1)
        let destinationDay = date(year: 2026, month: 4, day: 2)
        let unrelatedDay = date(year: 2026, month: 4, day: 3)
        let parent = store.createItem(title: "parent", dayDate: sourceDay)
        let child = store.createItem(
            title: "child",
            dayDate: sourceDay,
            afterItem: parent,
            indentLevel: 1
        )
        let unrelated = store.createItem(title: "unrelated", dayDate: unrelatedDay)
        let anchor = store.createItem(title: "anchor", dayDate: destinationDay)
        selectionManager.focusedItemId = unrelated.id
        selectionManager.selectedItemIds = [parent.id, unrelated.id]
        selectionManager.lastSelectedId = unrelated.id
        selectionManager.cursorPosition = 4
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.place(
            draggedItemId: parent.id,
            destination: .scheduled(date: destinationDay),
            insertionIndex: 1,
            indentLevel: 0
        )

        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertTrue(store.items(for: sourceDay).isEmpty)
        XCTAssertEqual(store.items(for: destinationDay).map(\.id), [anchor.id, parent.id, child.id])
        XCTAssertFalse(
            store.sections(year: 2026, month: 4).contains {
                Calendar.current.isDate($0.date, inSameDayAs: sourceDay)
            }
        )
        XCTAssertEqual([parent.indentLevel, child.indentLevel], [0, 1])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.lastSelectedId, parent.id)
        XCTAssertEqual(selectionManager.cursorPosition, 4)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: sourceDay).map(\.id), [parent.id, child.id])
        XCTAssertEqual(store.items(for: destinationDay).map(\.id), [anchor.id])
        XCTAssertTrue(
            store.sections(year: 2026, month: 4).contains {
                Calendar.current.isDate($0.date, inSameDayAs: sourceDay)
            }
        )
        XCTAssertEqual([parent.indentLevel, child.indentLevel], [0, 1])
        XCTAssertEqual(selectionManager.focusedItemId, unrelated.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id, unrelated.id])
        XCTAssertEqual(selectionManager.lastSelectedId, unrelated.id)
        XCTAssertEqual(selectionManager.cursorPosition, 4)

        XCTAssertTrue(store.redo())
        XCTAssertTrue(store.items(for: sourceDay).isEmpty)
        XCTAssertEqual(store.items(for: destinationDay).map(\.id), [anchor.id, parent.id, child.id])
        XCTAssertFalse(
            store.sections(year: 2026, month: 4).contains {
                Calendar.current.isDate($0.date, inSameDayAs: sourceDay)
            }
        )
        XCTAssertEqual([parent.indentLevel, child.indentLevel], [0, 1])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.lastSelectedId, parent.id)
        XCTAssertEqual(selectionManager.cursorPosition, 4)
    }

    func testPlaceKeepsParentAndChildrenAdjacentInTightlyPackedDestination() {
        let store = TodoStore.shared
        let day = date(year: 2026, month: 5, day: 24)
        let first = store.createItem(title: "first", dayDate: day)
        let second = store.createItem(title: "second", dayDate: day, afterItem: first)
        let third = store.createItem(title: "third", dayDate: day, afterItem: second)
        first.sortOrder = 1
        second.sortOrder = 1.001
        third.sortOrder = 1.002
        let parent = store.createItem(title: "parent", dayDate: day, afterItem: third)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let grandchild = store.createItem(
            title: "grandchild",
            dayDate: day,
            afterItem: child,
            indentLevel: 2
        )
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.place(
            draggedItemId: parent.id,
            destination: .scheduled(date: day),
            insertionIndex: 1,
            indentLevel: 0
        )

        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [first.id, parent.id, child.id, grandchild.id, second.id, third.id]
        )
        XCTAssertEqual([parent.indentLevel, child.indentLevel, grandchild.indentLevel], [0, 1, 2])
    }

    func testPlaceInSidebarLongTermMovesWholeGroupBeforeExistingItemsAndSupportsUndoRedo() {
        let store = TodoStore.shared
        let sourceDay = date(year: 2026, month: 4, day: 1)
        let existing = store.createItem(
            title: "existing",
            dayDate: sourceDay,
            containerKind: .longTermImportant
        )
        let parent = store.createItem(title: "parent", dayDate: sourceDay)
        let child = store.createItem(
            title: "child",
            dayDate: sourceDay,
            afterItem: parent,
            indentLevel: 1
        )
        selectionManager.focusedItemId = parent.id
        selectionManager.selectedItemIds = [parent.id]
        selectionManager.lastSelectedId = parent.id
        selectionManager.cursorPosition = 5
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.placeInSidebar(
            draggedItemId: parent.id,
            destination: .longTerm
        )

        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(store.longTermItems(isUrgent: false).map(\.id), [parent.id, child.id, existing.id])
        XCTAssertEqual([parent.indentLevel, child.indentLevel], [0, 1])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.lastSelectedId, parent.id)
        XCTAssertEqual(selectionManager.cursorPosition, 5)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: sourceDay).map(\.id), [parent.id, child.id])
        XCTAssertEqual(store.longTermItems(isUrgent: false).map(\.id), [existing.id])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.lastSelectedId, parent.id)
        XCTAssertEqual(selectionManager.cursorPosition, 5)

        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.longTermItems(isUrgent: false).map(\.id), [parent.id, child.id, existing.id])
        XCTAssertEqual([parent.indentLevel, child.indentLevel], [0, 1])
        XCTAssertEqual(selectionManager.focusedItemId, parent.id)
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id])
        XCTAssertEqual(selectionManager.lastSelectedId, parent.id)
        XCTAssertEqual(selectionManager.cursorPosition, 5)
    }

    func testPlaceLeavesEverySelectedGroupUntouchedWhenTheDropIsInsideAMovingParentChildGroup() {
        let store = TodoStore.shared
        let day = Date.now
        let parent = store.createItem(title: "parent", dayDate: day)
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let middle = store.createItem(title: "middle", dayDate: day, afterItem: child)
        let independent = store.createItem(title: "independent", dayDate: day, afterItem: middle)
        selectionManager.selectedItemIds = [parent.id, independent.id]
        selectionManager.focusedItemId = parent.id
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.place(
            draggedItemId: parent.id,
            destination: .scheduled(date: day),
            insertionIndex: 1,
            indentLevel: 0
        )

        XCTAssertEqual(moveModule.availability(for: intent), .unavailable(nil))
        XCTAssertFalse(store.canUndo, "查询不能创建操作单元")
        XCTAssertEqual(moveModule.execute(intent), .noChange)
        XCTAssertEqual(store.items(for: day).map(\.id), [parent.id, child.id, middle.id, independent.id])
        XCTAssertFalse(store.canUndo)
    }

    func testPlaceCanIndentFollowingGroupWithoutChangingItsPosition() {
        let store = TodoStore.shared
        let day = Date.now
        let parent = store.createItem(title: "parent", dayDate: day)
        let movingParent = store.createItem(
            title: "moving parent",
            dayDate: day,
            afterItem: parent
        )
        let movingChild = store.createItem(
            title: "moving child",
            dayDate: day,
            afterItem: movingParent,
            indentLevel: 1
        )
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.place(
            draggedItemId: movingParent.id,
            destination: .scheduled(date: day),
            insertionIndex: 1,
            indentLevel: 1
        )

        XCTAssertEqual(moveModule.availability(for: intent), .available)
        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [parent.id, movingParent.id, movingChild.id]
        )
        XCTAssertEqual([movingParent.indentLevel, movingChild.indentLevel], [1, 2])
    }

    func testPlaceCanIndentFollowingGroupAfterExistingChild() {
        let store = TodoStore.shared
        let day = Date.now
        let parent = store.createItem(title: "parent", dayDate: day)
        let existingChild = store.createItem(
            title: "existing child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        let movingParent = store.createItem(
            title: "moving parent",
            dayDate: day,
            afterItem: existingChild
        )
        let movingChild = store.createItem(
            title: "moving child",
            dayDate: day,
            afterItem: movingParent,
            indentLevel: 1
        )
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.place(
            draggedItemId: movingParent.id,
            destination: .scheduled(date: day),
            insertionIndex: 2,
            indentLevel: 1
        )

        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [parent.id, existingChild.id, movingParent.id, movingChild.id]
        )
        XCTAssertEqual([movingParent.indentLevel, movingChild.indentLevel], [1, 2])
    }

    func testPlaceCanIndentMultipleSelectedGroupsWithoutChangingTheirPosition() {
        let store = TodoStore.shared
        let day = Date.now
        let parent = store.createItem(title: "parent", dayDate: day)
        let firstMovingGroup = store.createItem(
            title: "first moving group",
            dayDate: day,
            afterItem: parent
        )
        let secondMovingGroup = store.createItem(
            title: "second moving group",
            dayDate: day,
            afterItem: firstMovingGroup
        )
        selectionManager.selectedItemIds = [firstMovingGroup.id, secondMovingGroup.id]
        selectionManager.focusedItemId = firstMovingGroup.id
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.place(
            draggedItemId: firstMovingGroup.id,
            destination: .scheduled(date: day),
            insertionIndex: 1,
            indentLevel: 1
        )

        XCTAssertEqual(moveModule.availability(for: intent), .available)
        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(
            store.items(for: day).map(\.id),
            [parent.id, firstMovingGroup.id, secondMovingGroup.id]
        )
        XCTAssertEqual([firstMovingGroup.indentLevel, secondMovingGroup.indentLevel], [1, 1])

        XCTAssertTrue(store.undo())
        XCTAssertEqual([firstMovingGroup.indentLevel, secondMovingGroup.indentLevel], [0, 0])
        XCTAssertTrue(store.redo())
        XCTAssertEqual([firstMovingGroup.indentLevel, secondMovingGroup.indentLevel], [1, 1])
    }

    func testPlaceInSidebarResolvesMonthAndMovesSelectedGroupsInOneOperation() {
        let store = TodoStore.shared
        let sourceDay = date(year: 2026, month: 4, day: 1)
        let targetOldDay = date(year: 2026, month: 6, day: 3)
        let targetLatestDay = date(year: 2026, month: 6, day: 20)
        _ = store.createItem(title: "old", dayDate: targetOldDay)
        let latest = store.createItem(title: "latest", dayDate: targetLatestDay)
        let parent = store.createItem(
            title: "parent",
            dayDate: sourceDay,
            indentLevel: 1,
            containerKind: .longTermImportant
        )
        let child = store.createItem(
            title: "child",
            dayDate: sourceDay,
            afterItem: parent,
            indentLevel: 2,
            containerKind: .longTermImportant
        )
        let independent = store.createItem(
            title: "independent",
            dayDate: sourceDay,
            afterItem: child,
            containerKind: .longTermImportant
        )
        selectionManager.selectedItemIds = [parent.id, child.id, independent.id]
        selectionManager.focusedItemId = child.id
        selectionManager.lastSelectedId = independent.id
        selectionManager.cursorPosition = 2
        store.undoManager.clear()
        let moveModule = TodoParentChildGroupMoveModule(
            store: store,
            selectionManager: selectionManager
        )
        let intent = TodoParentChildGroupMoveIntent.placeInSidebar(
            draggedItemId: parent.id,
            destination: .month(year: 2026, month: 6)
        )

        XCTAssertEqual(moveModule.availability(for: intent), .available)
        XCTAssertFalse(store.canUndo, "查询不能创建操作单元")
        XCTAssertEqual(moveModule.execute(intent), .performed)
        XCTAssertEqual(
            store.items(for: targetLatestDay).map(\.id),
            [parent.id, child.id, independent.id, latest.id]
        )
        XCTAssertTrue(Calendar.current.isDate(parent.dayDate, inSameDayAs: targetLatestDay))
        XCTAssertTrue(Calendar.current.isDate(child.dayDate, inSameDayAs: targetLatestDay))
        XCTAssertEqual([parent.indentLevel, child.indentLevel, independent.indentLevel], [0, 1, 0])
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id, child.id, independent.id])
        XCTAssertEqual(selectionManager.focusedItemId, child.id)
        XCTAssertEqual(selectionManager.cursorPosition, 2)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.longTermItems(isUrgent: false).map(\.id), [parent.id, child.id, independent.id])
        XCTAssertFalse(store.canUndo, "侧栏多组移动只能产生一个操作单元")

        XCTAssertTrue(store.redo())
        XCTAssertEqual(
            store.items(for: targetLatestDay).map(\.id),
            [parent.id, child.id, independent.id, latest.id]
        )
        XCTAssertEqual([parent.indentLevel, child.indentLevel, independent.indentLevel], [0, 1, 0])
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id, child.id, independent.id])
        XCTAssertEqual(selectionManager.focusedItemId, child.id)
        XCTAssertEqual(selectionManager.lastSelectedId, independent.id)
        XCTAssertEqual(selectionManager.cursorPosition, 2)
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
