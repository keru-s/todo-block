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
            editorEntry: .readOnly
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

    func testReadOnlyEntryDisablesEditingControls() throws {
        let item = TodoItem(title: "只读待办")
        let selectionManager = SelectionManager()
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: .readOnly
        )

        let textView = try XCTUnwrap(firstSubview(of: TodoEditorTextView.self, in: rowView))
        let completionButton = try XCTUnwrap(firstSubview(of: NSButton.self, in: rowView))
        let dragHandle = try XCTUnwrap(firstSubview(of: TodoEditorDragHandleView.self, in: rowView))

        XCTAssertFalse(textView.isEditable)
        XCTAssertFalse(completionButton.isEnabled)
        XCTAssertTrue(dragHandle.isHidden)
    }

    func testCompletionButtonRoutesThroughEditorEntry() throws {
        let item = TodoItem(title: "完成入口")
        var toggledItemId: UUID?
        let entry = makeEntry(toggleCompleted: { itemId in
            toggledItemId = itemId
        })
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: SelectionManager()),
            editorEntry: entry
        )
        let completionButton = try XCTUnwrap(firstSubview(of: NSButton.self, in: rowView))

        completionButton.performClick(nil)

        XCTAssertEqual(toggledItemId, item.id)
    }

    func testTextInputRoutesThroughEditorEntry() throws {
        let item = TodoItem(title: "a")
        var editedItemId: UUID?
        var editedEvent: TodoTextEditEvent?
        let entry = makeEntry(titleChanged: { itemId, event in
            editedItemId = itemId
            editedEvent = event
        })
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: SelectionManager()),
            editorEntry: entry
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
        textView.synchronizeReportedText("a")
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.insertText("b", replacementRange: NSRange(location: 1, length: 0))

        XCTAssertEqual(editedItemId, item.id)
        XCTAssertEqual(editedEvent?.beforeText, "a")
        XCTAssertEqual(editedEvent?.afterText, "ab")
    }

    func testBackspaceRoutesThroughEditorEntry() throws {
        let item = TodoItem(title: "")
        var deletedItemId: UUID?
        let entry = makeEntry(deletePressed: { itemId, _ in
            deletedItemId = itemId
            return true
        })
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: SelectionManager()),
            editorEntry: entry
        )
        let textView = try XCTUnwrap(firstSubview(of: TodoEditorTextView.self, in: rowView))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(deletedItemId, item.id)
    }

    func testKeyboardStructureCommandsRouteThroughEditorEntry() throws {
        let item = TodoItem(title: "键盘入口")
        var indentedItemId: UUID?
        var outdentedItemId: UUID?
        var focusMoves: [(UUID, TodoEditorFocusMoveDirection, Int, CGFloat?)] = []
        var itemMoves: [(UUID, TodoParentChildGroupMoveDirection)] = []
        let entry = makeEntry(
            indent: { itemId in indentedItemId = itemId },
            outdent: { itemId in outdentedItemId = itemId },
            moveFocus: { itemId, direction, cursorPosition, horizontalOffset in
                focusMoves.append((itemId, direction, cursorPosition, horizontalOffset))
            },
            moveItemByKeyboard: { itemId, direction in
                itemMoves.append((itemId, direction))
            }
        )
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: entry
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
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        textView.doCommand(by: #selector(NSResponder.moveUp(_:)))
        textView.doCommand(by: #selector(NSResponder.moveDown(_:)))

        rowView.keyDown(with: try keyEvent(keyCode: 126, modifierFlags: [.command]))
        rowView.keyDown(with: try keyEvent(keyCode: 125, modifierFlags: [.command]))

        XCTAssertEqual(indentedItemId, item.id)
        XCTAssertEqual(outdentedItemId, item.id)
        XCTAssertEqual(focusMoves.count, 2)
        if focusMoves.count == 2 {
            XCTAssertEqual(focusMoves[0].0, item.id)
            XCTAssertEqual(focusMoves[0].2, 0)
            XCTAssertEqual(focusMoves[1].0, item.id)
            XCTAssertEqual(focusMoves[1].2, 0)
            if case .up = focusMoves[0].1 {
            } else {
                XCTFail("Expected the first focus move to go up")
            }
            if case .down = focusMoves[1].1 {
            } else {
                XCTFail("Expected the second focus move to go down")
            }
        }
        XCTAssertEqual(itemMoves.count, 2)
        if itemMoves.count == 2 {
            XCTAssertEqual(itemMoves[0].0, item.id)
            XCTAssertEqual(itemMoves[1].0, item.id)
            if case .up = itemMoves[0].1 {
            } else {
                XCTFail("Expected the first item move to go up")
            }
            if case .down = itemMoves[1].1 {
            } else {
                XCTFail("Expected the second item move to go down")
            }
        }
    }

    func testMiddleReturnImmediatelyClearsTailFromCurrentTextView() throws {
        let item = TodoItem(title: "abcde")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.cursorPosition = 2

        var capturedAction: EnterAction?
        let entry = makeEntry(enterPressed: { _, action in
            capturedAction = action
            return true
        })

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: entry
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

    func testSuffixReturnEmitsReplacementAction() throws {
        let item = TodoItem(title: "abcde")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.cursorPosition = 2
        selectionManager.textSelectionLength = 3

        var capturedAction: EnterAction?
        let entry = makeEntry(enterPressed: { _, action in
            capturedAction = action
            return true
        })

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: entry
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
        textView.setSelectedRange(NSRange(location: 2, length: 3))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(textView.string, "ab")
        guard case .insertSiblingBelowAfterTextReplacement(
            let beforeTitle,
            let newCurrentTitle,
            let beforeSelection
        ) = capturedAction else {
            return XCTFail("Expected replacement-and-insert action")
        }
        XCTAssertEqual(beforeTitle, "abcde")
        XCTAssertEqual(newCurrentTitle, "ab")
        XCTAssertEqual(beforeSelection, TodoTextSelection(location: 2, length: 3))
    }

    func testApplySnapshotRestoresTextSelectionAfterUndo() throws {
        let item = TodoItem(title: "aXc")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.cursorPosition = 2

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: .readOnly
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
            editorEntry: .readOnly
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

        let entry = makeEntry(
            selectItem: { itemId, shiftPressed, cursorPosition in
            guard itemId == item.id else { return }
            selectionManager.handleSelect(
                item: item,
                allItems: [item],
                shiftPressed: shiftPressed,
                cursorPosition: cursorPosition
            )
            },
            captureDragSelectionBefore: {
            selectionManager.captureDragSelectionBefore()
            },
            discardPreparedDragSelection: {
            selectionManager.discardPreparedDragSelection()
            }
        )

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: entry
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
        let interaction = TodoEditorContinuousInteraction()
        let token = try XCTUnwrap(
            interaction.beginCrossItemSelection(
                itemId: item.id,
                sectionId: UUID()
            )
        )
        rowView.onSelectionDragBeganResult = { (itemId: UUID, _: NSPoint) in
            beganCount += 1
            guard itemId == item.id else { return nil }
            selectionManager.beginDragSelection(item: item, allItems: [item])
            return token
        }
        rowView.onSelectionDragCancelled = { _ in
            cancelledCount += 1
            selectionManager.cancelDragSelection()
        }
        rowView.onSelectionDragEnded = { _, _ in endedCount += 1 }

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

    func testRejectedDragSelectionDoesNotBecomeActive() throws {
        let item = TodoItem(title: "abc")
        let selectionManager = SelectionManager()
        var discardCount = 0
        var changedCount = 0
        var endedCount = 0
        let entry = makeEntry(
            captureDragSelectionBefore: {},
            discardPreparedDragSelection: { discardCount += 1 }
        )
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: entry
        )
        rowView.onSelectionDragBeganResult = { _, _ in nil }
        rowView.onSelectionDragChanged = { _, _, _ in changedCount += 1 }
        rowView.onSelectionDragEnded = { _, _ in endedCount += 1 }

        rowView.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 40, y: 20)))
        rowView.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: NSPoint(x: 40, y: 100)))
        rowView.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: NSPoint(x: 40, y: 100)))

        XCTAssertEqual(discardCount, 1)
        XCTAssertEqual(changedCount, 0)
        XCTAssertEqual(endedCount, 0)
    }

    func testDragSelectionCallbacksKeepTheStartedInteractionToken() throws {
        let item = TodoItem(title: "abc")
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: SelectionManager()),
            editorEntry: .readOnly
        )
        let interaction = TodoEditorContinuousInteraction()
        let token = try XCTUnwrap(
            interaction.beginCrossItemSelection(
                itemId: item.id,
                sectionId: UUID()
            )
        )
        var changedToken: TodoEditorContinuousInteractionToken?
        var endedToken: TodoEditorContinuousInteractionToken?

        rowView.onSelectionDragBeganResult = { _, _ in token }
        rowView.onSelectionDragChanged = { _, _, receivedToken in
            changedToken = receivedToken
        }
        rowView.onSelectionDragEnded = { _, receivedToken in
            endedToken = receivedToken
        }

        rowView.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 40, y: 20)))
        rowView.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: NSPoint(x: 40, y: 100)))
        rowView.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: NSPoint(x: 40, y: 100)))

        XCTAssertEqual(changedToken, token)
        XCTAssertEqual(endedToken, token)
    }

    func testItemDragCallbacksKeepTheStartedInteractionToken() throws {
        let item = TodoItem(title: "abc")
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: SelectionManager()),
            editorEntry: makeEntry()
        )
        let dragHandle = try XCTUnwrap(firstSubview(of: TodoEditorDragHandleView.self, in: rowView))
        let interaction = TodoEditorContinuousInteraction()
        let token = try XCTUnwrap(interaction.beginItemDrag(itemId: item.id))
        var changedToken: TodoEditorContinuousInteractionToken?
        var endedToken: TodoEditorContinuousInteractionToken?

        rowView.onDragBegan = { _, _ in token }
        rowView.onDragChanged = { _, _, receivedToken in
            changedToken = receivedToken
        }
        rowView.onDragEnded = { _, _, receivedToken in
            endedToken = receivedToken
        }

        dragHandle.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 8, y: 8)))
        dragHandle.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: NSPoint(x: 12, y: 12)))
        dragHandle.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: NSPoint(x: 12, y: 12)))

        XCTAssertEqual(changedToken, token)
        XCTAssertEqual(endedToken, token)
    }

    func testExplicitEditorActionRunsTheInterrupterBeforeTheAction() {
        var order: [String] = []
        let item = TodoItem(title: "动作")
        let entry = makeEntry(
            beforeExplicitAction: { order.append("interrupt") },
            toggleCompleted: { _ in order.append("action") }
        )

        entry.toggleCompleted(item.id)

        XCTAssertEqual(order, ["interrupt", "action"])
    }

    func testEscapeClearsCompletedMultipleSelection() throws {
        let item = TodoItem(title: "first")
        let otherItem = TodoItem(title: "second")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id, otherItem.id]

        var clearSelectionCount = 0
        let entry = makeEntry(
            clearSelection: {
            clearSelectionCount += 1
            selectionManager.clearAllSelection()
            },
            hasMultipleSelection: {
                selectionManager.selectedItemIds.count > 1
            }
        )

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: entry
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

    func testMultipleSelectionKeepsRowAsFirstResponder() throws {
        let item = TodoItem(title: "focused")
        let otherItem = TodoItem(title: "other")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id, otherItem.id]

        let entry = makeEntry(
            hasMultipleSelection: { selectionManager.selectedItemIds.count > 1 }
        )
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: entry
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

        rowView.apply(snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager))
        // 等一拍，确认没有异步任务把焦点拉回文字框。
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertTrue(
            window.firstResponder === rowView,
            "多选状态下焦点行应持有行级焦点，实际 firstResponder=\(String(describing: window.firstResponder))"
        )
    }

    func testShiftClickOnRowBlankKeepsRowAsFirstResponder() throws {
        let item = TodoItem(title: "abc")
        let otherItem = TodoItem(title: "other")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = otherItem.id
        selectionManager.selectedItemIds = [otherItem.id]
        selectionManager.lastSelectedId = otherItem.id

        let entry = makeEntry(
            selectItem: { itemId, shiftPressed, cursorPosition in
                guard itemId == item.id else { return }
                selectionManager.handleSelect(
                    item: item,
                    allItems: [otherItem, item],
                    shiftPressed: shiftPressed,
                    cursorPosition: cursorPosition
                )
            },
            hasMultipleSelection: { selectionManager.selectedItemIds.count > 1 }
        )
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: entry
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

        rowView.mouseDown(
            with: try mouseEvent(
                type: .leftMouseDown,
                location: NSPoint(x: 40, y: 20),
                modifierFlags: [.shift]
            )
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(selectionManager.selectedItemIds.count, 2, "Shift 点击应形成多选")
        XCTAssertTrue(
            window.firstResponder === rowView,
            "Shift 多选后焦点应移交行，实际 firstResponder=\(String(describing: window.firstResponder))"
        )
    }

    func testBackspaceWithMultipleSelectionRoutesDeleteThroughEditorEntry() throws {
        let item = TodoItem(title: "first")
        let otherItem = TodoItem(title: "second")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id, otherItem.id]

        var deletedItemIds: [UUID] = []
        let entry = makeEntry(
            hasMultipleSelection: { selectionManager.selectedItemIds.count > 1 },
            deletePressed: { itemId, _ in
                deletedItemIds.append(itemId)
                return true
            }
        )
        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: entry
        )

        // 裸 Backspace 应路由删除；Forward Delete 与带 Cmd/Option 的
        // Backspace 不路由（保留文字编辑语义）。
        rowView.keyDown(with: try keyEvent(keyCode: 51, modifierFlags: []))
        rowView.keyDown(with: try keyEvent(keyCode: 117, modifierFlags: []))
        rowView.keyDown(with: try keyEvent(keyCode: 51, modifierFlags: [.command]))
        rowView.keyDown(with: try keyEvent(keyCode: 51, modifierFlags: [.option]))

        XCTAssertEqual(deletedItemIds, [item.id])
    }

    func testItemLevelFocusKeepsRowAsFirstResponder() throws {
        let item = TodoItem(title: "survivor")
        let selectionManager = SelectionManager()
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        // 条目级焦点（如多选删除后的承接态）：单选也不进入文字编辑。
        selectionManager.focusesText = false

        let rowView = TodoEditorRowView(
            snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager),
            editorEntry: .readOnly
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

        rowView.apply(snapshot: TodoEditorItemSnapshot(item: item, selectionManager: selectionManager))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertTrue(
            window.firstResponder === rowView,
            "条目级焦点应持有行级焦点，实际 firstResponder=\(String(describing: window.firstResponder))"
        )
    }

    private func makeEntry(
        claimCurrentList: @escaping () -> Bool = { true },
        beforeExplicitAction: @escaping () -> Void = {},
        titleChanged: @escaping (UUID, TodoTextEditEvent) -> Void = { _, _ in },
        textSelectionChanged: @escaping (UUID, TodoTextSelection) -> Void = { _, _ in },
        inputSessionEnded: @escaping () -> Void = {},
        selectItem: @escaping (UUID, Bool, Int?) -> Void = { _, _, _ in },
        clearSelection: @escaping () -> Void = {},
        captureDragSelectionBefore: @escaping () -> Void = {},
        discardPreparedDragSelection: @escaping () -> Void = {},
        beginDragSelection: @escaping (UUID, Int?) -> Bool = { _, _ in true },
        updateDragSelection: @escaping (UUID) -> Void = { _ in },
        endDragSelection: @escaping () -> Void = {},
        cancelDragSelection: @escaping () -> Void = {},
        hasMultipleSelection: @escaping () -> Bool = { false },
        addItem: @escaping (TodoDropDestination) -> Void = { _ in },
        enterPressed: @escaping (UUID, EnterAction) -> Bool = { _, _ in false },
        deletePressed: @escaping (UUID, TodoTextSelection) -> Bool = { _, _ in false },
        prepareItemDrag: @escaping (UUID) -> Bool = { _ in true },
        toggleCompleted: @escaping (UUID) -> Void = { _ in },
        indent: @escaping (UUID) -> Void = { _ in },
        outdent: @escaping (UUID) -> Void = { _ in },
        moveFocus: @escaping (UUID, TodoEditorFocusMoveDirection, Int, CGFloat?) -> Void = { _, _, _, _ in },
        moveItemByKeyboard: @escaping (UUID, TodoParentChildGroupMoveDirection) -> Void = { _, _ in },
        moveDraggedItem: @escaping (UUID, TodoDropDestination, Int, Int) -> Void = { _, _, _, _ in },
        moveDraggedItemToSidebar: @escaping (UUID, SidebarDestination) -> Void = { _, _ in },
        sectionDateChanged: @escaping (UUID, Date) -> Void = { _, _ in }
    ) -> TodoEditorEntry {
        TodoEditorEntry(
            access: .editable,
            claimCurrentList: claimCurrentList,
            titleChanged: titleChanged,
            textSelectionChanged: textSelectionChanged,
            inputSessionEnded: inputSessionEnded,
            selectItem: selectItem,
            clearSelection: clearSelection,
            captureDragSelectionBefore: captureDragSelectionBefore,
            discardPreparedDragSelection: discardPreparedDragSelection,
            beginDragSelection: beginDragSelection,
            updateDragSelection: updateDragSelection,
            endDragSelection: endDragSelection,
            cancelDragSelection: cancelDragSelection,
            hasMultipleSelection: hasMultipleSelection,
            addItem: addItem,
            enterPressed: enterPressed,
            deletePressed: deletePressed,
            prepareItemDrag: prepareItemDrag,
            toggleCompleted: toggleCompleted,
            indent: indent,
            outdent: outdent,
            moveFocus: moveFocus,
            moveItemByKeyboard: moveItemByKeyboard,
            moveDraggedItem: moveDraggedItem,
            moveDraggedItemToSidebar: moveDraggedItemToSidebar,
            sectionDateChanged: sectionDateChanged,
            beforeExplicitAction: beforeExplicitAction
        )
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        location: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
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

    private func keyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
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
