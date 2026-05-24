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

    // MARK: - Full-surface coverage tests

    func testDropOnItemBodyResolvesInsertionBelow() {
        let first = TodoItem(title: "first", indentLevel: 0)
        let second = TodoItem(title: "second", indentLevel: 0)
        let third = TodoItem(title: "third", indentLevel: 0)
        let items = [first, second, third]
        let frames: [UUID: CGRect] = [
            first.id: CGRect(x: 0, y: 0, width: 240, height: 28),
            second.id: CGRect(x: 0, y: 30, width: 240, height: 28),
            third.id: CGRect(x: 0, y: 60, width: 240, height: 28),
        ]

        let state = TodoDropLocationEngine.dropState(
            for: CGPoint(x: 22, y: 50),
            items: items,
            itemFrames: frames,
            itemHeight: 28,
            indentWidth: 24
        )

        XCTAssertEqual(state, .insertAt(index: 2, indentLevel: 0))
    }

    func testDropOnEveryItemRowResolvesNonNone() {
        let items = (0..<5).map { TodoItem(title: "item \($0)", indentLevel: 0) }
        var frames: [UUID: CGRect] = [:]
        for (index, item) in items.enumerated() {
            frames[item.id] = CGRect(x: 0, y: CGFloat(index) * 30, width: 240, height: 28)
        }

        for yOffset in stride(from: 0, through: 140, by: 5) {
            let state = TodoDropLocationEngine.dropState(
                for: CGPoint(x: 22, y: CGFloat(yOffset)),
                items: items,
                itemFrames: frames,
                itemHeight: 28,
                indentWidth: 24
            )
            XCTAssertNotEqual(state, .none, "Drop at y=\(yOffset) should resolve to a valid insertion")
        }
    }

    func testDropBelowLastItemResolvesToEndIndex() {
        let first = TodoItem(title: "first", indentLevel: 0)
        let second = TodoItem(title: "second", indentLevel: 0)
        let items = [first, second]
        let frames: [UUID: CGRect] = [
            first.id: CGRect(x: 0, y: 0, width: 240, height: 28),
            second.id: CGRect(x: 0, y: 30, width: 240, height: 28),
        ]

        let state = TodoDropLocationEngine.dropState(
            for: CGPoint(x: 22, y: 80),
            items: items,
            itemFrames: frames,
            itemHeight: 28,
            indentWidth: 24
        )

        XCTAssertEqual(state, .insertAt(index: 2, indentLevel: 0))
    }

    func testDropOnEmptyListResolvesToIndexZero() {
        let state = TodoDropLocationEngine.dropState(
            for: CGPoint(x: 22, y: 10),
            items: [],
            itemFrames: [:],
            itemHeight: 28,
            indentWidth: 24
        )

        XCTAssertEqual(state, .insertAt(index: 0, indentLevel: 0))
    }

    func testDropWithIndentClampsToParentPlusOne() {
        let parent = TodoItem(title: "parent", indentLevel: 1)
        let items = [parent]
        let frames: [UUID: CGRect] = [
            parent.id: CGRect(x: 0, y: 0, width: 240, height: 28),
        ]

        let state = TodoDropLocationEngine.dropState(
            for: CGPoint(x: 200, y: 25),
            items: items,
            itemFrames: frames,
            itemHeight: 28,
            indentWidth: 24
        )

        if case .insertAt(let index, let indentLevel) = state {
            XCTAssertEqual(index, 1)
            XCTAssertLessThanOrEqual(indentLevel, parent.indentLevel + 1)
        } else {
            XCTFail("Expected insertAt state")
        }
    }

    func testResolveFallsBackToEstimationWithIncompleteFrames() {
        let item = TodoItem(title: "single", indentLevel: 0)

        let resolved = TodoDropLocationEngine.resolve(
            location: CGPoint(x: 20, y: 10),
            items: [item],
            itemFrames: [:],
            itemHeight: 28,
            indentWidth: 24
        )

        XCTAssertNotNil(resolved)
    }

    func testResolveRejectsLocationOutsideVerticalRangeWithFrames() {
        let item = TodoItem(title: "single", indentLevel: 0)
        let frames: [UUID: CGRect] = [item.id: CGRect(x: 0, y: 0, width: 240, height: 28)]

        let resolved = TodoDropLocationEngine.resolve(
            location: CGPoint(x: 20, y: 100),
            items: [item],
            itemFrames: frames,
            itemHeight: 28,
            indentWidth: 24,
            constrainsToVerticalRange: true,
            verticalSlack: 10
        )

        XCTAssertNil(resolved)
    }

    /// 14. resolve 对 containerKind 不敏感：相同 (items, location, frames) 在不同容器下结果一致。
    /// 锁定 P0-1 抽通用列表后引擎层不会因容器变化而行为漂移的契约（Phase 1.F）。
    func testResolveIsContainerKindAgnostic() {
        func makeItems(_ kind: TodoContainerKind) -> [TodoItem] {
            (0..<3).map { i in
                TodoItem(
                    title: "i\(i)",
                    indentLevel: 0,
                    sortOrder: Double(i),
                    containerKindRaw: kind.rawValue,
                    dayDate: Date()
                )
            }
        }

        func framesFor(_ items: [TodoItem]) -> [UUID: CGRect] {
            var dict: [UUID: CGRect] = [:]
            for (i, item) in items.enumerated() {
                dict[item.id] = CGRect(x: 0, y: CGFloat(i) * 28, width: 240, height: 28)
            }
            return dict
        }

        let scheduled = makeItems(.scheduled)
        let urgent = makeItems(.longTermUrgent)
        let important = makeItems(.longTermImportant)

        let probeLocation = CGPoint(x: 30, y: 35)

        let r1 = TodoDropLocationEngine.resolve(
            location: probeLocation,
            items: scheduled,
            itemFrames: framesFor(scheduled),
            itemHeight: 28,
            indentWidth: 24
        )
        let r2 = TodoDropLocationEngine.resolve(
            location: probeLocation,
            items: urgent,
            itemFrames: framesFor(urgent),
            itemHeight: 28,
            indentWidth: 24
        )
        let r3 = TodoDropLocationEngine.resolve(
            location: probeLocation,
            items: important,
            itemFrames: framesFor(important),
            itemHeight: 28,
            indentWidth: 24
        )

        XCTAssertEqual(r1, r2, "scheduled vs longTermUrgent 应得到相同 drop")
        XCTAssertEqual(r2, r3, "longTermUrgent vs longTermImportant 应得到相同 drop")
    }
}
