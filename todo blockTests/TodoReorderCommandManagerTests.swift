import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoReorderCommandManagerTests: XCTestCase {
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

    func testMoveSelectionUsesSelectedParentWhenFocusedItemIsDescendant() {
        let store = TodoStore.shared
        let day = Date.now
        let first = store.createItem(title: "first", dayDate: day, indentLevel: 0)
        let parent = store.createItem(
            title: "parent",
            dayDate: day,
            afterItem: first,
            indentLevel: 0
        )
        let child = store.createItem(
            title: "child",
            dayDate: day,
            afterItem: parent,
            indentLevel: 1
        )
        selectionManager.selectedItemIds = [parent.id, child.id]
        selectionManager.focusedItemId = child.id
        TodoReorderCommandManager.shared.activateListContext(
            store: store,
            selectionManager: selectionManager
        )

        XCTAssertTrue(TodoReorderCommandManager.shared.moveSelectionUp())
        XCTAssertEqual(store.items(for: day).map(\.title), ["parent", "child", "first"])
        XCTAssertEqual(selectionManager.selectedItemIds, [parent.id, child.id])
        XCTAssertEqual(selectionManager.focusedItemId, child.id)
    }

    func testMoveSelectionMovesIndependentBlocksOnceInStableOrder() {
        let store = TodoStore.shared
        let day = Date.now
        let a = store.createItem(title: "a", dayDate: day)
        let b = store.createItem(title: "b", dayDate: day, afterItem: a)
        let c = store.createItem(title: "c", dayDate: day, afterItem: b)
        let d = store.createItem(title: "d", dayDate: day, afterItem: c)
        selectionManager.selectedItemIds = [b.id, d.id]
        selectionManager.focusedItemId = b.id
        store.undoManager.clear()
        TodoReorderCommandManager.shared.activateListContext(
            store: store,
            selectionManager: selectionManager
        )

        XCTAssertTrue(TodoReorderCommandManager.shared.moveSelectionUp())
        XCTAssertEqual(store.items(for: day).map(\.title), ["b", "a", "d", "c"])
        XCTAssertEqual(selectionManager.selectedItemIds, [b.id, d.id])

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items(for: day).map(\.title), ["a", "b", "c", "d"])
        XCTAssertFalse(store.canUndo, "多个选中组必须只占一步")

        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.items(for: day).map(\.title), ["b", "a", "d", "c"])
    }

    func testMoveSelectionDoesNothingWhenAnySelectedBlockCannotMove() {
        let store = TodoStore.shared
        let day = Date.now
        let a = store.createItem(title: "a", dayDate: day)
        let b = store.createItem(title: "b", dayDate: day, afterItem: a)
        let c = store.createItem(title: "c", dayDate: day, afterItem: b)
        _ = store.createItem(title: "d", dayDate: day, afterItem: c)
        selectionManager.selectedItemIds = [a.id, c.id]
        selectionManager.focusedItemId = a.id
        store.undoManager.clear()
        TodoReorderCommandManager.shared.activateListContext(
            store: store,
            selectionManager: selectionManager
        )

        XCTAssertFalse(TodoReorderCommandManager.shared.moveSelectionUp())
        XCTAssertEqual(store.items(for: day).map(\.title), ["a", "b", "c", "d"])
        XCTAssertFalse(store.canUndo)
    }
}
