//
//  TodoDropLocationEngineTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/3/6.
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoDropLocationEngineTests: XCTestCase {
    private var descriptor: ModelContainer!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        descriptor = try ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: descriptor.mainContext)
    }

    func testDropStateResolvesTopInsertionFromCurrentPointerLocation() {
        let first = TodoItem(title: "first", indentLevel: 0)
        let second = TodoItem(title: "second", indentLevel: 1)
        let items = [first, second]
        let frames: [UUID: CGRect] = [
            first.id: CGRect(x: 0, y: 12, width: 240, height: 28),
            second.id: CGRect(x: 0, y: 40, width: 240, height: 28),
        ]

        let state = TodoDropLocationEngine.dropState(
            for: CGPoint(x: 22, y: 32),
            items: items,
            itemFrames: frames,
            itemHeight: 28,
            indentWidth: 24
        )

        XCTAssertEqual(state, .insertAt(index: 0, indentLevel: 0))
    }

    func testIndicatorTopYUsesStableItemBoundary() {
        let first = TodoItem(title: "first", indentLevel: 0)
        let second = TodoItem(title: "second", indentLevel: 0)
        let items = [first, second]
        let frames: [UUID: CGRect] = [
            first.id: CGRect(x: 0, y: 12, width: 240, height: 28),
            second.id: CGRect(x: 0, y: 40, width: 240, height: 28),
        ]

        let topY = TodoDropLocationEngine.indicatorTopY(
            for: .insertAt(index: 1, indentLevel: 0),
            items: items,
            itemFrames: frames,
            itemHeight: 28
        )

        XCTAssertEqual(topY, 38)
    }

    func testDropStateRejectsLocationsOutsideVerticalRangeWhenRequested() {
        let item = TodoItem(title: "single", indentLevel: 0)
        let frames: [UUID: CGRect] = [item.id: CGRect(x: 0, y: 12, width: 240, height: 28)]

        let state = TodoDropLocationEngine.dropState(
            for: CGPoint(x: 20, y: -40),
            items: [item],
            itemFrames: frames,
            itemHeight: 28,
            indentWidth: 24,
            baseX: 0,
            constrainsToVerticalRange: true,
            verticalSlack: 28
        )

        XCTAssertEqual(state, .none)
    }
}
