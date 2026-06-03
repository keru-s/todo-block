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
