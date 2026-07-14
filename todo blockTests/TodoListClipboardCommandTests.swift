import AppKit
import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoListClipboardCommandTests: XCTestCase {
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
        selectionManager = SelectionManager()
    }

    func testCutDeletesSelectionAsOneStepAndUndoDoesNotRewritePasteboard() {
        let store = TodoStore.shared
        let day = Date()
        let parent = store.createItem(title: "parent", dayDate: day)
        let child = store.createItem(title: "child", dayDate: day, afterItem: parent, indentLevel: 1)
        selectionManager.selectedItemIds = [parent.id]
        selectionManager.focusedItemId = parent.id
        selectionManager.lastSelectedId = parent.id
        let module = TodoListActionModule(
            store: store,
            selectionManager: selectionManager,
            commandScope: .today
        )
        store.undoManager.clear()

        XCTAssertEqual(module.perform(.cut), .performed)
        XCTAssertNil(store.todoItemsCache[parent.id])
        XCTAssertNil(store.todoItemsCache[child.id])
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            "- [ ] parent\n  - [ ] child"
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("external clipboard", forType: .string)

        XCTAssertTrue(store.undo())
        XCTAssertNotNil(store.todoItemsCache[parent.id])
        XCTAssertNotNil(store.todoItemsCache[child.id])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "external clipboard")

        XCTAssertTrue(store.redo())
        XCTAssertNil(store.todoItemsCache[parent.id])
        XCTAssertNil(store.todoItemsCache[child.id])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "external clipboard")
    }
}
