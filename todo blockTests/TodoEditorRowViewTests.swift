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
