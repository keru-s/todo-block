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

    // MARK: - 带子项的 reorder 全套回归（覆盖跨 sibling block 的 up/down）

    /// 截图复现：当前是 indent-0 root 带 1 个 child，上面是另一个 indent-0 root 带 2 个 child。
    /// .up 必须跳过上一个 root 的整个 block，不能插到其 children 中间。
    func testMoveUpRootSkipsPrevRootChildrenBlock() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let jfy = store.createItem(title: "jfy", dayDate: dayDate, indentLevel: 0)
        let c1 = store.createItem(title: "确认", dayDate: dayDate, afterItem: jfy, indentLevel: 1)
        _ = store.createItem(title: "准备", dayDate: dayDate, afterItem: c1, indentLevel: 1)
        let okr = store.createItem(title: "OKR", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "kr", dayDate: dayDate, afterItem: okr, indentLevel: 1)

        let didMove = TodoKeyboardReorderEngine.move(
            itemId: okr.id,
            direction: .up,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(
            store.items(for: dayDate).map(\.title),
            ["OKR", "kr", "jfy", "确认", "准备"]
        )
    }

    /// 同 parent 内 child 之间 .up swap（不跨 block）
    func testMoveUpChildSwapsWithSiblingUnderSameParent() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let parent = store.createItem(title: "p", dayDate: dayDate, indentLevel: 0)
        let c1 = store.createItem(title: "c1", dayDate: dayDate, afterItem: parent, indentLevel: 1)
        let c2 = store.createItem(title: "c2", dayDate: dayDate, afterItem: c1, indentLevel: 1)

        _ = TodoKeyboardReorderEngine.move(
            itemId: c2.id,
            direction: .up,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertEqual(store.items(for: dayDate).map(\.title), ["p", "c2", "c1"])
    }

    /// .up 跨越 child 自带 grandchild 的 nested block
    func testMoveUpRootSkipsNestedGrandchildren() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let p1 = store.createItem(title: "p1", dayDate: dayDate, indentLevel: 0)
        let c1 = store.createItem(title: "c1", dayDate: dayDate, afterItem: p1, indentLevel: 1)
        _ = store.createItem(title: "gc1", dayDate: dayDate, afterItem: c1, indentLevel: 2)
        let p2 = store.createItem(title: "p2", dayDate: dayDate, indentLevel: 0)

        _ = TodoKeyboardReorderEngine.move(
            itemId: p2.id,
            direction: .up,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertEqual(store.items(for: dayDate).map(\.title), ["p2", "p1", "c1", "gc1"])
    }

    /// .up 到达列表顶部应为 no-op（first item 不能再上移）
    func testMoveUpReturnsFalseAtTopWithChildren() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let p = store.createItem(title: "p", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c", dayDate: dayDate, afterItem: p, indentLevel: 1)

        let didMove = TodoKeyboardReorderEngine.move(
            itemId: p.id,
            direction: .up,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )
        XCTAssertFalse(didMove)
        XCTAssertEqual(store.items(for: dayDate).map(\.title), ["p", "c"])
    }

    /// .down 对称：当前 root 带 child，下方也是 root 带 child，整体跳过下个 block
    func testMoveDownRootSkipsNextRootChildrenBlockSymmetry() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let p1 = store.createItem(title: "p1", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c1", dayDate: dayDate, afterItem: p1, indentLevel: 1)
        let p2 = store.createItem(title: "p2", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c2", dayDate: dayDate, afterItem: p2, indentLevel: 1)

        _ = TodoKeyboardReorderEngine.move(
            itemId: p1.id,
            direction: .down,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate),
            store: store
        )

        XCTAssertEqual(store.items(for: dayDate).map(\.title), ["p2", "c2", "p1", "c1"])
    }

    /// 多次 .up 连续移动，每次跳过一个完整 block
    func testRepeatedMoveUpProgressesOneSiblingBlockEachTime() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let p1 = store.createItem(title: "p1", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c1", dayDate: dayDate, afterItem: p1, indentLevel: 1)
        let p2 = store.createItem(title: "p2", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c2", dayDate: dayDate, afterItem: p2, indentLevel: 1)
        let p3 = store.createItem(title: "p3", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c3", dayDate: dayDate, afterItem: p3, indentLevel: 1)

        // p3 上移 1 次 → [p1, c1, p3, c3, p2, c2]
        _ = TodoKeyboardReorderEngine.move(
            itemId: p3.id, direction: .up,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate), store: store
        )
        XCTAssertEqual(
            store.items(for: dayDate).map(\.title),
            ["p1", "c1", "p3", "c3", "p2", "c2"]
        )

        // 再上移 1 次 → [p3, c3, p1, c1, p2, c2]
        _ = TodoKeyboardReorderEngine.move(
            itemId: p3.id, direction: .up,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate), store: store
        )
        XCTAssertEqual(
            store.items(for: dayDate).map(\.title),
            ["p3", "c3", "p1", "c1", "p2", "c2"]
        )
    }

    /// .down 的对称多次移动
    func testRepeatedMoveDownProgressesOneSiblingBlockEachTime() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let p1 = store.createItem(title: "p1", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c1", dayDate: dayDate, afterItem: p1, indentLevel: 1)
        let p2 = store.createItem(title: "p2", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c2", dayDate: dayDate, afterItem: p2, indentLevel: 1)
        let p3 = store.createItem(title: "p3", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c3", dayDate: dayDate, afterItem: p3, indentLevel: 1)

        _ = TodoKeyboardReorderEngine.move(
            itemId: p1.id, direction: .down,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate), store: store
        )
        XCTAssertEqual(
            store.items(for: dayDate).map(\.title),
            ["p2", "c2", "p1", "c1", "p3", "c3"]
        )

        _ = TodoKeyboardReorderEngine.move(
            itemId: p1.id, direction: .down,
            items: store.items(for: dayDate),
            destination: .scheduled(date: dayDate), store: store
        )
        XCTAssertEqual(
            store.items(for: dayDate).map(\.title),
            ["p2", "c2", "p3", "c3", "p1", "c1"]
        )
    }

    /// 拖放 engine: 把带 child 的 parent 拖到另一个 parent 的 child 中间 — 整体落在那个 parent 的 block 之后（不应被劈开）
    /// 注：此 case 直接受 moveItemWithChildren gap 修复保护，键盘 engine 不会产生这种 toIndex；
    /// 留作 cross-engine 行为基线。
    func testReorderEngineDropIntoChildrenAreaKeepsBlockTogether() {
        let store = TodoStore.shared
        let dayDate = date(year: 2026, month: 3, day: 11)

        let p1 = store.createItem(title: "p1", dayDate: dayDate, indentLevel: 0)
        let c1a = store.createItem(title: "c1a", dayDate: dayDate, afterItem: p1, indentLevel: 1)
        _ = store.createItem(title: "c1b", dayDate: dayDate, afterItem: c1a, indentLevel: 1)
        let p2 = store.createItem(title: "p2", dayDate: dayDate, indentLevel: 0)
        _ = store.createItem(title: "c2", dayDate: dayDate, afterItem: p2, indentLevel: 1)

        // 模拟拖放 p2 到 p1 后面 1 位（即 c1a 前）— 此处 toIndex = 1 (即 c1a 位置)
        let beforeItems = store.items(for: dayDate)
        TodoReorderMoveEngine.performMove(
            draggedId: p2.id,
            toIndex: 1,
            indentLevel: 0,
            items: beforeItems,
            destination: .scheduled(date: dayDate),
            store: store
        )

        // p2 + c2 必须紧挨；不能被 c1a / c1b 隔开
        let resultTitles = store.items(for: dayDate).map(\.title)
        let p2Idx = resultTitles.firstIndex(of: "p2")!
        let c2Idx = resultTitles.firstIndex(of: "c2")!
        XCTAssertEqual(c2Idx, p2Idx + 1, "p2 与 c2 必须相邻，实际: \(resultTitles)")
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
