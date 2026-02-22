//
//  TodoReorderEngineTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/2/22.
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoReorderEngineTests: XCTestCase {
    private var descriptor: ModelContainer!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        descriptor = try ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: descriptor.mainContext)
    }

    func testMenuBarDropStateCalculatesInsertIndexAndIndentClamp() {
        let first = TodoItem(title: "first", indentLevel: 0)
        let second = TodoItem(title: "second", indentLevel: 2)
        let third = TodoItem(title: "third", indentLevel: 0)
        let items = [first, second, third]

        let frames: [UUID: CGRect] = [
            first.id: CGRect(x: 0, y: 0, width: 200, height: 28),
            second.id: CGRect(x: 0, y: 28, width: 200, height: 28),
            third.id: CGRect(x: 0, y: 56, width: 200, height: 28),
        ]

        let state = MenuBarManualReorderEngine.dropState(
            for: CGPoint(x: 120, y: 40),
            items: items,
            itemFrames: frames,
            itemHeight: 28,
            indentWidth: 24
        )

        XCTAssertEqual(state, .insertAt(index: 1, indentLevel: 1))
    }

    func testMenuBarDropStateReturnsNoneOutsideVerticalRange() {
        let item = TodoItem(title: "single", indentLevel: 0)
        let items = [item]
        let frames: [UUID: CGRect] = [item.id: CGRect(x: 0, y: 0, width: 200, height: 28)]

        let state = MenuBarManualReorderEngine.dropState(
            for: CGPoint(x: 20, y: -40),
            items: items,
            itemFrames: frames,
            itemHeight: 28,
            indentWidth: 24
        )

        XCTAssertEqual(state, .none)
    }

    func testMenuBarDropStateFallsBackWhenFramesAreIncomplete() {
        let first = TodoItem(title: "first", indentLevel: 0)
        let second = TodoItem(title: "line1\nline2\nline3", indentLevel: 0)
        let items = [first, second]

        let state = MenuBarManualReorderEngine.dropState(
            for: CGPoint(x: 10, y: 20),
            items: items,
            itemFrames: [first.id: CGRect(x: 0, y: 0, width: 200, height: 28)],
            itemHeight: 28,
            indentWidth: 24
        )

        XCTAssertEqual(state, .insertAt(index: 1, indentLevel: 0))
    }

    func testPerformMoveMovesParentAndChildrenAsABlock() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 2, day: 22)

        let parent = store.createItem(title: "parent", dayDate: dayDate, indentLevel: 0)
        let child = store.createItem(
            title: "child",
            dayDate: dayDate,
            afterItem: parent,
            indentLevel: 1
        )
        let sibling = store.createItem(
            title: "sibling",
            dayDate: dayDate,
            afterItem: child,
            indentLevel: 0
        )
        let initialItems = store.items(for: dayDate)

        TodoReorderMoveEngine.performMove(
            draggedId: parent.id,
            toIndex: 3,
            indentLevel: 0,
            items: initialItems,
            destination: .scheduled(date: dayDate),
            store: store
        )

        let reordered = store.items(for: dayDate)
        XCTAssertEqual(reordered.map(\.id), [sibling.id, parent.id, child.id])
        XCTAssertEqual(parent.indentLevel, 0)
        XCTAssertEqual(child.indentLevel, 1)
    }

    func testPerformMoveClampsIndentAgainstPreviousItem() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 2, day: 22)

        let first = store.createItem(title: "first", dayDate: dayDate, indentLevel: 0)
        let dragged = store.createItem(
            title: "dragged",
            dayDate: dayDate,
            afterItem: first,
            indentLevel: 0
        )

        TodoReorderMoveEngine.performMove(
            draggedId: dragged.id,
            toIndex: 1,
            indentLevel: TodoItem.maxIndentLevel,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertEqual(dragged.indentLevel, 1)
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
