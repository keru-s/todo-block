import AppKit
import XCTest
@testable import todo_block

@MainActor
final class TodoEditorTextViewTests: XCTestCase {
    func testCommittedTypingReportsCompleteBeforeAndAfterState() throws {
        let textView = TodoEditorTextView()
        textView.synchronizeReportedText("a")
        textView.string = "a"
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        var events: [TodoTextEditEvent] = []
        textView.onTextDidChange = { events.append($0) }

        textView.insertText(
            "b",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.beforeText, "a")
        XCTAssertEqual(event.afterText, "ab")
        XCTAssertEqual(event.beforeSelection, TodoTextSelection(location: 1, length: 0))
        XCTAssertEqual(event.afterSelection, TodoTextSelection(location: 2, length: 0))
        XCTAssertEqual(event.kind, .insertion)
    }

    func testMarkedTextIsReportedOnlyAfterCompositionCommits() throws {
        let textView = TodoEditorTextView()
        textView.synchronizeReportedText("")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        var events: [TodoTextEditEvent] = []
        textView.onTextDidChange = { events.append($0) }

        textView.setMarkedText(
            "中",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(textView.hasMarkedText())

        textView.unmarkText()

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.beforeText, "")
        XCTAssertEqual(event.afterText, "中")
        XCTAssertEqual(event.kind, .insertion)
    }

    func testDynamicMarkedTextRevisionsReportOnlyTheFinalComposition() throws {
        let textView = TodoEditorTextView()
        textView.synchronizeReportedText("明")
        textView.string = "明"
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        var events: [TodoTextEditEvent] = []
        textView.onTextDidChange = { events.append($0) }

        textView.setMarkedText(
            "天",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        textView.setMarkedText(
            "晚",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: textView.markedRange()
        )

        XCTAssertTrue(events.isEmpty)
        textView.unmarkText()

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.beforeText, "明")
        XCTAssertEqual(event.afterText, "明晚")
        XCTAssertEqual(event.kind, .insertion)
    }

    func testSelectionChangesAreReported() {
        let textView = TodoEditorTextView()
        textView.string = "abc"
        var selections: [TodoTextSelection] = []
        textView.onSelectionDidChange = { selections.append($0) }

        textView.setSelectedRange(NSRange(location: 1, length: 1))

        XCTAssertEqual(selections.last, TodoTextSelection(location: 1, length: 1))
    }
}
