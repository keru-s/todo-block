//
//  TodoItemTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/2/15.
//

import XCTest
@testable import todo_block

final class TodoItemTests: XCTestCase {
    func testInitClampsIndentLevelToMaxLevel() {
        let item = TodoItem(indentLevel: 999)
        XCTAssertEqual(item.indentLevel, TodoItem.maxIndentLevel)
    }

    func testIndentStopsAtMaxLevel() {
        let item = TodoItem(indentLevel: 0)
        for _ in 0..<(TodoItem.maxIndentLevel + 3) {
            item.indent()
        }
        XCTAssertEqual(item.indentLevel, TodoItem.maxIndentLevel)
    }
}
