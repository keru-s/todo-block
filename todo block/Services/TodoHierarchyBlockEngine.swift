import Foundation

struct TodoHierarchyBlock: Equatable {
    let range: Range<Int>
    let itemIds: [UUID]
    let rootIndentLevel: Int
}

enum TodoHierarchyBlockEngine {
    static func topLevelBlocks(in items: [TodoItem]) -> [TodoHierarchyBlock] {
        let indentLevels = normalizedIndentLevels(in: items)
        var blocks: [TodoHierarchyBlock] = []
        var startIndex = 0

        while startIndex < items.count {
            guard let block = block(
                startingAt: startIndex,
                in: items,
                normalizedIndentLevels: indentLevels
            ) else { break }
            blocks.append(block)
            startIndex = block.range.upperBound
        }

        return blocks
    }

    static func block(startingAt startIndex: Int, in items: [TodoItem]) -> TodoHierarchyBlock? {
        guard items.indices.contains(startIndex) else { return nil }

        return block(
            startingAt: startIndex,
            in: items,
            normalizedIndentLevels: normalizedIndentLevels(in: items)
        )
    }

    private static func block(
        startingAt startIndex: Int,
        in items: [TodoItem],
        normalizedIndentLevels indentLevels: [Int]
    ) -> TodoHierarchyBlock? {
        guard items.indices.contains(startIndex) else { return nil }

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
        normalizedIndentLevels(items.map(\.indentLevel), baseIndentLevel: 0)
    }

    static func normalizedIndentLevels(
        _ indentLevels: [Int],
        baseIndentLevel: Int
    ) -> [Int] {
        let clampedBaseIndentLevel = min(
            max(baseIndentLevel, 0),
            TodoItem.maxIndentLevel
        )
        var previousIndentLevel = clampedBaseIndentLevel

        return indentLevels.enumerated().map { index, indentLevel in
            let maximumIndentLevel =
                index == 0 ? clampedBaseIndentLevel : previousIndentLevel + 1
            let normalizedIndentLevel = min(
                max(indentLevel, 0),
                min(maximumIndentLevel, TodoItem.maxIndentLevel)
            )
            previousIndentLevel = normalizedIndentLevel
            return normalizedIndentLevel
        }
    }

    static func movedSnapshots(
        _ snapshots: [TodoItemSnapshot],
        sourceItems: [TodoItem],
        sourceIndices: [Int],
        destination: TodoDropDestination,
        afterItem: TodoItem?,
        targetItems: [TodoItem],
        indentDelta: Int
    ) -> [TodoItemSnapshot] {
        guard snapshots.count == sourceIndices.count,
              sourceIndices.allSatisfy({ sourceItems.indices.contains($0) })
        else { return [] }

        let normalizedDestination = destination.normalized
        let normalizedIndentLevels = normalizedIndentLevels(in: sourceItems)
        let baseSortOrder: Double
        let stepSize: Double

        if let afterItem,
           let afterIndex = targetItems.firstIndex(where: { $0.id == afterItem.id })
        {
            if afterIndex + 1 < targetItems.count {
                let gap = targetItems[afterIndex + 1].sortOrder - afterItem.sortOrder
                stepSize = gap / Double(snapshots.count + 1)
                baseSortOrder = afterItem.sortOrder + stepSize
            } else {
                baseSortOrder = afterItem.sortOrder + 1000
                stepSize = 0.001
            }
        } else if let firstItem = targetItems.first {
            baseSortOrder = firstItem.sortOrder - 1000
            stepSize = 0.001
        } else {
            baseSortOrder = 1000
            stepSize = 0.001
        }

        return zip(snapshots, sourceIndices).enumerated().map { offset, pair in
            let (snapshot, sourceIndex) = pair
            let movedDate: Date = if case .scheduled(let date) = normalizedDestination {
                date
            } else {
                snapshot.dayDate
            }
            return snapshot.replacing(
                indentLevel: min(
                    TodoItem.maxIndentLevel,
                    max(0, normalizedIndentLevels[sourceIndex] + indentDelta)
                ),
                sortOrder: baseSortOrder + Double(offset) * stepSize,
                containerKindRaw: normalizedDestination.containerKind.rawValue,
                dayDate: movedDate
            )
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

    static func itemIdsCoveredByBlocks(
        rootedAt rootIds: Set<UUID>,
        in items: [TodoItem]
    ) -> [UUID] {
        selectedBlocks(rootedAt: rootIds, in: items).flatMap(\.itemIds)
    }

    static func blockRootIds(
        selectedFrom selectedIds: Set<UUID>,
        in items: [TodoItem]
    ) -> [UUID] {
        selectedBlocks(rootedAt: selectedIds, in: items).compactMap { block in
            block.itemIds.first
        }
    }

    private static func selectedBlocks(
        rootedAt rootIds: Set<UUID>,
        in items: [TodoItem]
    ) -> [TodoHierarchyBlock] {
        var blocks: [TodoHierarchyBlock] = []
        var coveredIds = Set<UUID>()

        for (index, item) in items.enumerated()
        where rootIds.contains(item.id) && coveredIds.contains(item.id) == false {
            guard let block = block(startingAt: index, in: items) else { continue }
            blocks.append(block)
            coveredIds.formUnion(block.itemIds)
        }

        return blocks
    }
}
