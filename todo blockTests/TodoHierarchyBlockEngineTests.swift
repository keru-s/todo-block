import XCTest
@testable import todo_block

final class TodoHierarchyBlockEngineTests: XCTestCase {
    func testBlockStartingAtNestedItemContainsAllConsecutiveDescendants() throws {
        let items = [
            TodoItem(title: "root", indentLevel: 0),
            TodoItem(title: "child", indentLevel: 1),
            TodoItem(title: "grandchild", indentLevel: 2),
            TodoItem(title: "great-grandchild", indentLevel: 3),
            TodoItem(title: "sibling", indentLevel: 1),
            TodoItem(title: "tail", indentLevel: 0),
        ]

        let block = try XCTUnwrap(
            TodoHierarchyBlockEngine.block(startingAt: 1, in: items)
        )

        XCTAssertEqual(block.range, 1..<4)
        XCTAssertEqual(block.itemIds, items[1..<4].map(\.id))
    }

    func testNormalizedIndentLevelsClampJumpsWithoutChangingOrder() {
        let items = [
            TodoItem(title: "root", indentLevel: 0),
            TodoItem(title: "jump", indentLevel: 3),
            TodoItem(title: "deeper-jump", indentLevel: 4),
            TodoItem(title: "sibling", indentLevel: 1),
            TodoItem(title: "tail", indentLevel: 0),
        ]

        XCTAssertEqual(
            TodoHierarchyBlockEngine.normalizedIndentLevels(in: items),
            [0, 1, 2, 1, 0]
        )
        XCTAssertEqual(items.map(\.title), ["root", "jump", "deeper-jump", "sibling", "tail"])
    }

    func testInvalidStartIndexDoesNotProduceBlock() {
        let items = [TodoItem(title: "only", indentLevel: 0)]

        XCTAssertNil(TodoHierarchyBlockEngine.block(startingAt: -1, in: items))
        XCTAssertNil(TodoHierarchyBlockEngine.block(startingAt: items.count, in: items))
    }

    func testPrecedingBlockStartSkipsPreviousBlocksDescendants() throws {
        let items = [
            TodoItem(title: "previous", indentLevel: 0),
            TodoItem(title: "child", indentLevel: 1),
            TodoItem(title: "grandchild", indentLevel: 2),
            TodoItem(title: "current", indentLevel: 0),
        ]
        let current = try XCTUnwrap(
            TodoHierarchyBlockEngine.block(startingAt: 3, in: items)
        )

        XCTAssertEqual(
            TodoHierarchyBlockEngine.precedingBlockStart(before: current, in: items),
            0
        )
    }

    func testFollowingInsertionIndexMovesNestedBlockIntoShallowerParent() throws {
        let items = [
            TodoItem(title: "root", indentLevel: 0),
            TodoItem(title: "moving", indentLevel: 1),
            TodoItem(title: "target-parent", indentLevel: 0),
            TodoItem(title: "existing-child", indentLevel: 1),
        ]
        let moving = try XCTUnwrap(
            TodoHierarchyBlockEngine.block(startingAt: 1, in: items)
        )

        XCTAssertEqual(
            TodoHierarchyBlockEngine.followingInsertionIndex(after: moving, in: items),
            3
        )
    }

    func testItemIdsCoveredBySelectedRootsDeduplicatesSelectedDescendants() {
        let items = [
            TodoItem(title: "parent", indentLevel: 0),
            TodoItem(title: "child", indentLevel: 1),
            TodoItem(title: "grandchild", indentLevel: 2),
            TodoItem(title: "other", indentLevel: 0),
        ]

        XCTAssertEqual(
            TodoHierarchyBlockEngine.itemIdsCoveredByBlocks(
                rootedAt: [items[0].id, items[1].id],
                in: items
            ),
            items[0...2].map(\.id)
        )
    }
}
