//
//  TodoEditorRowViewTests.swift
//  todo blockTests
//

import AppKit
import XCTest
@testable import todo_block

@MainActor
final class TodoEditorRowViewTests: XCTestCase {
    func testApplySnapshotPreservesInsertionPointWhileEditing() throws {
        let item = TodoItem(title: "12")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.cursorPosition = 2

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            actions: .readOnly
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentLayoutRect)
        window.contentView = contentView
        rowView.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
        contentView.addSubview(rowView)
        contentView.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(firstSubview(of: TodoEditorTextView.self, in: rowView))
        window.makeFirstResponder(textView)
        textView.string = "123"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        item.title = "123"
        rowView.apply(snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager))

        XCTAssertEqual(textView.string, "123")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testMiddleReturnImmediatelyClearsTailFromCurrentTextView() throws {
        let item = TodoItem(title: "abcde")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.cursorPosition = 2

        var capturedAction: EnterAction?
        var actions = TodoEditorActions.readOnly
        actions.enterPressed = { _, action in
            capturedAction = action
        }

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            actions: actions
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentLayoutRect)
        window.contentView = contentView
        rowView.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
        contentView.addSubview(rowView)
        contentView.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(firstSubview(of: TodoEditorTextView.self, in: rowView))
        window.makeFirstResponder(textView)
        textView.string = "abcde"
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(textView.string, "ab")
        guard case .splitIntoChild(let newCurrentTitle, let childTitle) = capturedAction else {
            return XCTFail("Expected split action")
        }
        XCTAssertEqual(newCurrentTitle, "ab")
        XCTAssertEqual(childTitle, "cde")
    }

    func testApplySnapshotRestoresTextSelectionAfterUndo() throws {
        let item = TodoItem(title: "aXc")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.cursorPosition = 2

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            actions: .readOnly
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentLayoutRect)
        window.contentView = contentView
        rowView.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
        contentView.addSubview(rowView)
        contentView.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(firstSubview(of: TodoEditorTextView.self, in: rowView))
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        item.title = "abc"
        selectionManager.cursorPosition = 1
        selectionManager.textSelectionLength = 1
        rowView.apply(snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(textView.string, "abc")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 1))
    }

    func testApplySnapshotRestoresChangedSelectionWhenTitleIsUnchanged() throws {
        let item = TodoItem(title: "abc")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.cursorPosition = 2

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            actions: .readOnly
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentLayoutRect)
        window.contentView = contentView
        rowView.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
        contentView.addSubview(rowView)
        contentView.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(firstSubview(of: TodoEditorTextView.self, in: rowView))
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        selectionManager.cursorPosition = 1
        selectionManager.textSelectionLength = 1
        rowView.apply(snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager))

        XCTAssertEqual(textView.string, "abc")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 1))
    }

    func testEscapeCancelsDragSelectionStartedFromRowBlankSpace() throws {
        let item = TodoItem(title: "abc")
        let previouslySelectedItem = TodoItem(title: "previous")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = previouslySelectedItem.id
        selectionManager.selectedItemIds = [previouslySelectedItem.id]
        selectionManager.lastSelectedId = previouslySelectedItem.id
        selectionManager.cursorPosition = 3
        selectionManager.textSelectionLength = 2

        var actions = TodoEditorActions.readOnly
        actions.captureDragSelectionBefore = {
            selectionManager.captureDragSelectionBefore()
        }
        actions.selectItem = { itemId, shiftPressed, cursorPosition in
            guard itemId == item.id else { return }
            selectionManager.handleSelect(
                item: item,
                allItems: [item],
                shiftPressed: shiftPressed,
                cursorPosition: cursorPosition
            )
        }
        actions.discardPreparedDragSelection = {
            selectionManager.discardPreparedDragSelection()
        }

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            actions: actions
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentLayoutRect)
        window.contentView = contentView
        rowView.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
        contentView.addSubview(rowView)
        contentView.layoutSubtreeIfNeeded()

        var beganCount = 0
        var cancelledCount = 0
        var endedCount = 0
        rowView.onSelectionDragBegan = { itemId, _ in
            beganCount += 1
            guard itemId == item.id else { return }
            selectionManager.beginDragSelection(item: item, allItems: [item])
        }
        rowView.onSelectionDragCancelled = {
            cancelledCount += 1
            selectionManager.cancelDragSelection()
        }
        rowView.onSelectionDragEnded = { endedCount += 1 }

        rowView.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 40, y: 20)))
        rowView.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: NSPoint(x: 40, y: 100)))

        let textView = try XCTUnwrap(firstSubview(of: TodoEditorTextView.self, in: rowView))
        textView.keyDown(with: try escapeKeyEvent())
        rowView.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: NSPoint(x: 40, y: 100)))

        XCTAssertEqual(beganCount, 1)
        XCTAssertEqual(cancelledCount, 1)
        XCTAssertEqual(endedCount, 0)
        XCTAssertEqual(selectionManager.selectedItemIds, [previouslySelectedItem.id])
        XCTAssertEqual(selectionManager.focusedItemId, previouslySelectedItem.id)
        XCTAssertEqual(selectionManager.cursorPosition, 3)
        XCTAssertEqual(selectionManager.textSelectionLength, 2)
    }

    func testEscapeClearsCompletedMultipleSelection() throws {
        let item = TodoItem(title: "first")
        let otherItem = TodoItem(title: "second")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id, otherItem.id]

        var clearSelectionCount = 0
        var actions = TodoEditorActions.readOnly
        actions.hasMultipleSelection = {
            selectionManager.selectedItemIds.count > 1
        }
        actions.clearSelection = {
            clearSelectionCount += 1
            selectionManager.clearAllSelection()
        }

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            actions: actions
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentLayoutRect)
        window.contentView = contentView
        rowView.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
        contentView.addSubview(rowView)
        contentView.layoutSubtreeIfNeeded()

        rowView.keyDown(with: try escapeKeyEvent())

        XCTAssertEqual(clearSelectionCount, 1)
        XCTAssertTrue(selectionManager.selectedItemIds.isEmpty)
        XCTAssertNil(selectionManager.focusedItemId)
    }

    private func mouseEvent(type: NSEvent.EventType, location: NSPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func escapeKeyEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
    }

    private func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let matchingView = view as? T {
            return matchingView
        }
        for subview in view.subviews {
            if let matchingView = firstSubview(of: type, in: subview) {
                return matchingView
            }
        }
        return nil
    }
}
