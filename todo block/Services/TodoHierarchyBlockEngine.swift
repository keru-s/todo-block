import Foundation

struct TodoHierarchyBlock: Equatable {
    let range: Range<Int>
    let itemIds: [UUID]
    let rootIndentLevel: Int
}

enum TodoHierarchyBlockEngine {
    static func block(startingAt startIndex: Int, in items: [TodoItem]) -> TodoHierarchyBlock? {
        guard items.indices.contains(startIndex) else { return nil }

        let indentLevels = normalizedIndentLevels(in: items)
        let rootIndentLevel = indentLevels[startIndex]
        var endIndex = startIndex + 1

        while endIndex < items.count, indentLevels[endIndex] > rootIndentLevel {
            endIndex += 1
        }

        let range = startIndex..<endIndex
        return TodoHierarchyBlock(
            range: range,
            itemIds: range.map { items[$0].id },
            rootIndentLevel: rootIndentLevel
        )
    }

    static func normalizedIndentLevels(in items: [TodoItem]) -> [Int] {
        var previousIndentLevel = 0

        return items.enumerated().map { index, item in
            let maximumIndentLevel = index == 0 ? 0 : previousIndentLevel + 1
            let normalizedIndentLevel = min(
                max(item.indentLevel, 0),
                min(maximumIndentLevel, TodoItem.maxIndentLevel)
            )
            previousIndentLevel = normalizedIndentLevel
            return normalizedIndentLevel
        }
    }

    static func precedingBlockStart(
        before block: TodoHierarchyBlock,
        in items: [TodoItem]
    ) -> Int? {
        guard block.range.lowerBound > 0 else { return nil }

        let indentLevels = normalizedIndentLevels(in: items)
        var startIndex = block.range.lowerBound - 1

        while startIndex > 0, indentLevels[startIndex] > block.rootIndentLevel {
            startIndex -= 1
        }

        return startIndex
    }

    static func followingInsertionIndex(
        after block: TodoHierarchyBlock,
        in items: [TodoItem]
    ) -> Int? {
        let nextBlockStart = block.range.upperBound
        guard items.indices.contains(nextBlockStart) else { return nil }

        let indentLevels = normalizedIndentLevels(in: items)
        if block.rootIndentLevel > indentLevels[nextBlockStart] {
            return nextBlockStart + 1
        }

        return self.block(startingAt: nextBlockStart, in: items)?.range.upperBound
    }
}
