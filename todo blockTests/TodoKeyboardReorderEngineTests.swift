//
//  TodoKeyboardReorderEngineTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/3/11.
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoKeyboardReorderEngineTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: config
        )

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
    }

    func testMoveUpMovesBlockBeforePreviousItemAndPreservesIndent() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let first = store.createItem(title: "first", dayDate: dayDate, indentLevel: 0)
        let current = store.createItem(
            title: "current",
            dayDate: dayDate,
            afterItem: first,
            indentLevel: 1
        )
        let child = store.createItem(
            title: "child",
            dayDate: dayDate,
            afterItem: current,
            indentLevel: 2
        )
        let tail = store.createItem(
            title: "tail",
            dayDate: dayDate,
            afterItem: child,
            indentLevel: 0
        )

        let didMove = TodoKeyboardReorderEngine.move(
            itemId: current.id,
            direction: .up,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertTrue(didMove)
        let reordered = store.items(for: dayDate)
        XCTAssertEqual(reordered.map(\.id), [current.id, child.id, first.id, tail.id])
        XCTAssertEqual(current.indentLevel, 1)
        XCTAssertEqual(child.indentLevel, 2)
    }

    func testMoveDownPlacesBlockAfterNextBlock() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let current = store.createItem(title: "current", dayDate: dayDate, indentLevel: 0)
        let child = store.createItem(
            title: "child",
            dayDate: dayDate,
            afterItem: current,
            indentLevel: 1
        )
        let next = store.createItem(
            title: "next",
            dayDate: dayDate,
            afterItem: child,
            indentLevel: 0
        )
        let nextChild = store.createItem(
            title: "next-child",
            dayDate: dayDate,
            afterItem: next,
            indentLevel: 1
        )
        let tail = store.createItem(
            title: "tail",
            dayDate: dayDate,
            afterItem: nextChild,
            indentLevel: 0
        )

        let didMove = TodoKeyboardReorderEngine.move(
            itemId: current.id,
            direction: .down,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertTrue(didMove)
        let reordered = store.items(for: dayDate)
        XCTAssertEqual(reordered.map(\.id), [next.id, nextChild.id, current.id, child.id, tail.id])
        XCTAssertEqual(current.indentLevel, 0)
        XCTAssertEqual(child.indentLevel, 1)
    }

    func testMoveDownIntoShallowerParentBecomesFirstChild() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let root = store.createItem(title: "root", dayDate: dayDate, indentLevel: 0)
        let moving = store.createItem(
            title: "moving",
            dayDate: dayDate,
            afterItem: root,
            indentLevel: 1
        )
        let targetParent = store.createItem(
            title: "target-parent",
            dayDate: dayDate,
            afterItem: moving,
            indentLevel: 0
        )
        let existingChild = store.createItem(
            title: "existing-child",
            dayDate: dayDate,
            afterItem: targetParent,
            indentLevel: 1
        )

        let didMove = TodoKeyboardReorderEngine.move(
            itemId: moving.id,
            direction: .down,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertTrue(didMove)
        let reordered = store.items(for: dayDate)
        XCTAssertEqual(
            reordered.map(\.id),
            [root.id, targetParent.id, moving.id, existingChild.id]
        )
        XCTAssertEqual(moving.indentLevel, 1)
    }

    func testMovementStopsAtBounds() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let first = store.createItem(title: "first", dayDate: dayDate, indentLevel: 0)
        let second = store.createItem(
            title: "second",
            dayDate: dayDate,
            afterItem: first,
            indentLevel: 0
        )

        XCTAssertFalse(
            TodoKeyboardReorderEngine.canMove(
                itemId: first.id,
                direction: .up,
                items: store.items(for: dayDate)
            )
        )
        XCTAssertFalse(
            TodoKeyboardReorderEngine.canMove(
                itemId: second.id,
                direction: .down,
                items: store.items(for: dayDate)
            )
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar.current
        return calendar.startOfDay(for: calendar.date(from: components) ?? Date())
    }
}
