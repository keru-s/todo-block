//
//  MarkdownTodoCodecTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/2/15.
//

import XCTest
@testable import todo_block

final class MarkdownTodoCodecTests: XCTestCase {
    func testEncodeNormalizesMinimumIndentLevel() {
        let parent = TodoItem(title: "Parent", isCompleted: false, indentLevel: 2)
        let child = TodoItem(title: "Child", isCompleted: true, indentLevel: 3)

        let output = MarkdownTodoCodec.encode(items: [parent, child], normalizeBaseIndent: true)
        let expected = """
        - [ ] Parent
          - [x] Child
        """

        XCTAssertEqual(output, expected)
    }

    func testDecodeSupportsIndentLevelFour() {
        let markdown = """
        - [ ] L0
          - [ ] L1
            - [ ] L2
              - [ ] L3
                - [ ] L4
        """

        let parsed = MarkdownTodoCodec.decode(markdown)
        XCTAssertEqual(parsed.map(\.indentLevel), [0, 1, 2, 3, 4])
    }

    func testDecodeClampsIndentLevelAboveFour() {
        let markdown = """
        - [ ] L0
          - [ ] L1
            - [ ] L2
              - [ ] L3
                - [ ] L4
                  - [ ] L5
                    - [ ] L6
        """

        let parsed = MarkdownTodoCodec.decode(markdown, maxIndentLevel: TodoItem.maxIndentLevel)
        XCTAssertEqual(parsed.map(\.indentLevel), [0, 1, 2, 3, 4, 4, 4])
    }

    func testDecodeUnderstandsUncheckedAndCheckedMarkers() {
        let markdown = """
        - [ ] open
        - [x] done
        """

        let parsed = MarkdownTodoCodec.decode(markdown)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].title, "open")
        XCTAssertFalse(parsed[0].isCompleted)
        XCTAssertEqual(parsed[1].title, "done")
        XCTAssertTrue(parsed[1].isCompleted)
    }
}
