import XCTest
@testable import todo_block

@MainActor
final class TodoCompletionRuleTests: XCTestCase {
    func testOverlappingSelectionProducesOneChangePerItemAndKeepsParentChildGroupsTogether() {
        let parent = item("Parent", order: 1000)
        let child = item("Child", indent: 1, order: 2000)
        let sibling = item("Sibling", order: 2000)

        let changes = TodoCompletionRule.transitions(
            in: [parent, child, sibling],
            for: [parent.id, child.id],
            isCompleted: true
        )

        XCTAssertEqual(changes.compactMap { $0.before?.id }, [sibling.id, parent.id, child.id])
        let result = changes.compactMap(\.after)
        XCTAssertEqual(result.map(\.sortOrder), [1000, 2000, 3000])
        XCTAssertEqual(result.map(\.indentLevel), [0, 0, 1])
        XCTAssertEqual(result.map(\.isCompleted), [false, true, true])
    }

    func testReopeningChangesOnlySelectedCompletionAndKeepsExistingSortValues() throws {
        let first = item("First", order: 1000)
        let completed = item("Completed", order: 1000, isCompleted: true)

        let changes = TodoCompletionRule.transitions(
            in: [first, completed],
            for: [completed.id],
            isCompleted: false
        )

        XCTAssertEqual(changes.count, 1)
        let change = try XCTUnwrap(changes.first?.after)
        XCTAssertEqual(change.id, completed.id)
        XCTAssertEqual(change.sortOrder, completed.sortOrder)
        XCTAssertFalse(change.isCompleted)
        XCTAssertTrue(TodoCompletionRule.transitions(
            in: [first, change], for: [change.id], isCompleted: false
        ).isEmpty)
    }

    private func item(
        _ title: String,
        indent: Int = 0,
        order: Double,
        isCompleted: Bool = false
    ) -> TodoItemSnapshot {
        TodoItemSnapshot(
            title: title, isCompleted: isCompleted, indentLevel: indent, sortOrder: order,
            containerKindRaw: TodoContainerKind.scheduled.rawValue,
            dayDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
