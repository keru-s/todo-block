import AppKit
import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoTextEditSessionTests: XCTestCase {
    private var container: ModelContainer!
    private var selectionManager: SelectionManager!
    private var store: TodoStore!
    private var actions: TodoEditorActions!

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
        selectionManager = SelectionManager()
        actions = TodoListActionModule(
            store: store,
            selectionManager: selectionManager
        ).editorActions
    }

    func testContinuousInsertionsSaveImmediatelyAndUndoAsOneStep() {
        let item = makeFocusedItem(title: "a", cursor: 1)

        actions.titleChanged(item.id, event("a", "ab", 1, 2, .insertion))
        actions.titleChanged(item.id, event("ab", "abc", 2, 3, .insertion))

        XCTAssertEqual(item.title, "abc")
        XCTAssertTrue(store.canUndo)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "a")
        XCTAssertEqual(selectionManager.cursorPosition, 1)
        XCTAssertEqual(selectionManager.textSelectionLength, 0)

        XCTAssertTrue(store.redo())
        XCTAssertEqual(item.title, "abc")
        XCTAssertEqual(selectionManager.cursorPosition, 3)
        XCTAssertEqual(selectionManager.textSelectionLength, 0)
    }

    func testChangingEditKindCreatesSeparateHistorySteps() {
        let item = makeFocusedItem(title: "a", cursor: 1)

        actions.titleChanged(item.id, event("a", "ab", 1, 2, .insertion))
        actions.titleChanged(item.id, event("ab", "a", 2, 1, .deletion))

        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "ab")
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "a")
    }

    func testMovingSelectionEndsCurrentSegment() {
        let item = makeFocusedItem(title: "a", cursor: 1)

        actions.titleChanged(item.id, event("a", "ab", 1, 2, .insertion))
        actions.textSelectionChanged(item.id, TodoTextSelection(location: 0, length: 0))
        actions.titleChanged(item.id, event("ab", "Xab", 0, 1, .insertion))

        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "ab")
        XCTAssertEqual(selectionManager.cursorPosition, 0)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "a")
    }

    func testKeyboardFocusChangeEndsCurrentSegment() {
        let item = makeFocusedItem(title: "a", cursor: 1)
        let second = store.createItem(title: "second", dayDate: item.dayDate, afterItem: item)
        store.undoManager.clear()

        actions.titleChanged(item.id, event("a", "ab", 1, 2, .insertion))
        actions.moveFocus(item.id, .down, 2, nil)
        XCTAssertEqual(selectionManager.focusedItemId, second.id)
        actions.moveFocus(second.id, .up, 0, nil)
        XCTAssertEqual(selectionManager.focusedItemId, item.id)
        actions.titleChanged(item.id, event("ab", "abc", 2, 3, .insertion))

        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "ab")
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "a")
    }

    func testStructuralActionFollowsPendingTextEditInGlobalOrder() {
        let item = makeFocusedItem(title: "a", cursor: 1)

        actions.titleChanged(item.id, event("a", "ab", 1, 2, .insertion))
        actions.toggleCompleted(item.id)

        XCTAssertEqual(item.title, "ab")
        XCTAssertTrue(item.isCompleted)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "ab")
        XCTAssertFalse(item.isCompleted)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "a")
    }

    func testOneSecondPauseEndsCurrentSegment() async throws {
        let item = makeFocusedItem(title: "a", cursor: 1)

        actions.titleChanged(item.id, event("a", "ab", 1, 2, .insertion))
        try await Task.sleep(for: .milliseconds(1_100))
        actions.titleChanged(item.id, event("ab", "abc", 2, 3, .insertion))

        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "ab")
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "a")
    }

    func testReplacementRestoresTextSelectionOnUndoAndRedo() {
        let item = makeFocusedItem(title: "abc", cursor: 1, selectionLength: 1)
        let replacement = TodoTextEditEvent(
            beforeText: "abc",
            afterText: "aXc",
            beforeSelection: TodoTextSelection(location: 1, length: 1),
            afterSelection: TodoTextSelection(location: 2, length: 0),
            kind: .replacement
        )

        actions.titleChanged(item.id, replacement)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "abc")
        XCTAssertEqual(selectionManager.cursorPosition, 1)
        XCTAssertEqual(selectionManager.textSelectionLength, 1)
        XCTAssertTrue(store.redo())
        XCTAssertEqual(item.title, "aXc")
        XCTAssertEqual(selectionManager.cursorPosition, 2)
        XCTAssertEqual(selectionManager.textSelectionLength, 0)
    }

    func testUndoRestoresOriginalListSelectionAlongsideText() {
        let first = store.createItem(title: "first", dayDate: .now)
        let edited = store.createItem(title: "second", dayDate: .now, afterItem: first)
        selectionManager.focusedItemId = edited.id
        selectionManager.selectedItemIds = [first.id, edited.id]
        selectionManager.lastSelectedId = first.id
        selectionManager.cursorPosition = 6
        selectionManager.textSelectionLength = 0
        store.undoManager.clear()

        actions.titleChanged(
            edited.id,
            TodoTextEditEvent(
                beforeText: "second",
                afterText: "second!",
                beforeSelection: TodoTextSelection(location: 6, length: 0),
                afterSelection: TodoTextSelection(location: 7, length: 0),
                kind: .insertion
            )
        )

        XCTAssertEqual(selectionManager.selectedItemIds, [edited.id])
        XCTAssertTrue(store.undo())
        XCTAssertEqual(edited.title, "second")
        XCTAssertEqual(selectionManager.selectedItemIds, [first.id, edited.id])
        XCTAssertEqual(selectionManager.focusedItemId, edited.id)
        XCTAssertEqual(selectionManager.lastSelectedId, first.id)
        XCTAssertEqual(selectionManager.cursorPosition, 6)
        XCTAssertEqual(selectionManager.textSelectionLength, 0)
    }

    func testDictationRevisionsStayOneHistoryStepUntilInputEnds() {
        let item = makeFocusedItem(title: "", cursor: 0)
        let session = TodoTextInputSession.dictation(UUID())

        actions.titleChanged(
            item.id,
            TodoTextEditEvent(
                beforeText: "",
                afterText: "明天",
                beforeSelection: TodoTextSelection(location: 0, length: 0),
                afterSelection: TodoTextSelection(location: 2, length: 0),
                kind: .insertion,
                inputSession: session
            )
        )
        actions.titleChanged(
            item.id,
            TodoTextEditEvent(
                beforeText: "明天",
                afterText: "明天开会",
                beforeSelection: TodoTextSelection(location: 2, length: 0),
                afterSelection: TodoTextSelection(location: 4, length: 0),
                kind: .insertion,
                inputSession: session
            )
        )

        XCTAssertEqual(item.title, "明天开会")
        actions.inputSessionEnded()
        XCTAssertTrue(store.undo())
        XCTAssertEqual(item.title, "")
        XCTAssertFalse(store.undo())
        XCTAssertTrue(store.redo())
        XCTAssertEqual(item.title, "明天开会")
        XCTAssertEqual(selectionManager.cursorPosition, 4)
    }

    func testTextDeletionUndoRedoDoesNotRewritePasteboard() throws {
        let item = makeFocusedItem(title: "abc", cursor: 1, selectionLength: 1)
        actions.titleChanged(
            item.id,
            TodoTextEditEvent(
                beforeText: "abc",
                afterText: "ac",
                beforeSelection: TodoTextSelection(location: 1, length: 1),
                afterSelection: TodoTextSelection(location: 1, length: 0),
                kind: .deletion
            )
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("external", forType: .string)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(try XCTUnwrap(pasteboard.string(forType: .string)), "external")
        XCTAssertTrue(store.redo())
        XCTAssertEqual(try XCTUnwrap(pasteboard.string(forType: .string)), "external")
    }

    private func makeFocusedItem(
        title: String,
        cursor: Int,
        selectionLength: Int = 0
    ) -> TodoItem {
        let item = store.createItem(title: title, dayDate: .now)
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.lastSelectedId = item.id
        selectionManager.cursorPosition = cursor
        selectionManager.textSelectionLength = selectionLength
        store.undoManager.clear()
        return item
    }

    private func event(
        _ before: String,
        _ after: String,
        _ beforeCursor: Int,
        _ afterCursor: Int,
        _ kind: TodoTextEditKind
    ) -> TodoTextEditEvent {
        TodoTextEditEvent(
            beforeText: before,
            afterText: after,
            beforeSelection: TodoTextSelection(location: beforeCursor, length: 0),
            afterSelection: TodoTextSelection(location: afterCursor, length: 0),
            kind: kind
        )
    }
}
