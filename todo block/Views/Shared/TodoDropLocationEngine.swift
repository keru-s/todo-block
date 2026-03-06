//
//  TodoDropLocationEngine.swift
//  todo block
//
//  Created by Codex on 2026/3/6.
//

import CoreGraphics
import Foundation

struct TodoResolvedDrop: Equatable {
    let index: Int
    let indentLevel: Int
}

enum TodoDropLocationEngine {
    static func dropState(
        for location: CGPoint,
        items: [TodoItem],
        itemFrames: [UUID: CGRect],
        itemHeight: CGFloat,
        indentWidth: CGFloat,
        baseX: CGFloat = 20,
        constrainsToVerticalRange: Bool = false,
        verticalSlack: CGFloat? = nil
    ) -> TodoListDropState {
        guard
            let resolution = resolve(
                location: location,
                items: items,
                itemFrames: itemFrames,
                itemHeight: itemHeight,
                indentWidth: indentWidth,
                baseX: baseX,
                constrainsToVerticalRange: constrainsToVerticalRange,
                verticalSlack: verticalSlack
            )
        else {
            return .none
        }

        return .insertAt(index: resolution.index, indentLevel: resolution.indentLevel)
    }

    static func resolve(
        location: CGPoint,
        items: [TodoItem],
        itemFrames: [UUID: CGRect],
        itemHeight: CGFloat,
        indentWidth: CGFloat,
        baseX: CGFloat = 20,
        constrainsToVerticalRange: Bool = false,
        verticalSlack: CGFloat? = nil
    ) -> TodoResolvedDrop? {
        if items.isEmpty {
            return TodoResolvedDrop(index: 0, indentLevel: 0)
        }

        if constrainsToVerticalRange,
            let dropRange = verticalRange(for: items, itemFrames: itemFrames)
        {
            let slack = verticalSlack ?? itemHeight
            guard
                location.y >= dropRange.lowerBound - slack,
                location.y <= dropRange.upperBound + slack
            else {
                return nil
            }
        }

        let insertIndex = insertionIndex(
            for: location.y,
            items: items,
            itemFrames: itemFrames,
            itemHeight: itemHeight
        )
        let indentLevel = resolvedIndentLevel(
            for: location.x,
            insertIndex: insertIndex,
            items: items,
            indentWidth: indentWidth,
            baseX: baseX
        )

        return TodoResolvedDrop(index: insertIndex, indentLevel: indentLevel)
    }

    static func indicatorTopY(
        for dropState: TodoListDropState,
        items: [TodoItem],
        itemFrames: [UUID: CGRect],
        itemHeight: CGFloat,
        indicatorHeight: CGFloat = TodoInsertionIndicator.visualHeight
    ) -> CGFloat? {
        guard case .insertAt(let insertIndex, _) = dropState else { return nil }
        guard
            let boundaryY = indicatorBoundaryY(
                forInsertIndex: insertIndex,
                items: items,
                itemFrames: itemFrames,
                itemHeight: itemHeight
            )
        else {
            return nil
        }

        return boundaryY - indicatorHeight / 2
    }

    private static func insertionIndex(
        for y: CGFloat,
        items: [TodoItem],
        itemFrames: [UUID: CGRect],
        itemHeight: CGFloat
    ) -> Int {
        var insertIndex = items.count
        let hasCompleteFrames = items.allSatisfy { itemFrames[$0.id] != nil }

        if hasCompleteFrames {
            for (index, item) in items.enumerated() {
                guard let frame = itemFrames[item.id] else { continue }
                let thresholdY = insertionThresholdY(
                    for: index,
                    frame: frame,
                    defaultHeight: itemHeight
                )
                if y < thresholdY {
                    insertIndex = index
                    break
                }
            }
            return insertIndex
        }

        var accumulatedHeight: CGFloat = 0
        for (index, item) in items.enumerated() {
            let estimatedHeight = estimatedItemHeight(for: item, defaultHeight: itemHeight)
            if y < accumulatedHeight + estimatedHeight / 2 {
                insertIndex = index
                break
            }
            accumulatedHeight += estimatedHeight
        }

        return insertIndex
    }

    private static func resolvedIndentLevel(
        for x: CGFloat,
        insertIndex: Int,
        items: [TodoItem],
        indentWidth: CGFloat,
        baseX: CGFloat
    ) -> Int {
        let relativeX = max(0, x - baseX)
        var indentLevel = Int(relativeX / indentWidth)

        if insertIndex > 0 {
            indentLevel = min(indentLevel, items[insertIndex - 1].indentLevel + 1)
        } else {
            indentLevel = 0
        }

        return min(indentLevel, TodoItem.maxIndentLevel)
    }

    private static func insertionThresholdY(
        for index: Int,
        frame: CGRect,
        defaultHeight: CGFloat
    ) -> CGFloat {
        guard index == 0 else { return frame.midY }

        let leadingEdgeBoost = min(defaultHeight * 0.25, 8)
        return min(frame.maxY, frame.midY + leadingEdgeBoost)
    }

    private static func indicatorBoundaryY(
        forInsertIndex insertIndex: Int,
        items: [TodoItem],
        itemFrames: [UUID: CGRect],
        itemHeight: CGFloat
    ) -> CGFloat? {
        guard items.isEmpty == false else { return nil }

        let hasCompleteFrames = items.allSatisfy { itemFrames[$0.id] != nil }
        if hasCompleteFrames {
            if insertIndex <= 0, let firstFrame = itemFrames[items[0].id] {
                return firstFrame.minY
            }

            if insertIndex >= items.count, let lastFrame = itemFrames[items[items.count - 1].id] {
                return lastFrame.maxY
            }

            if let frame = itemFrames[items[insertIndex].id] {
                return frame.minY
            }
        }

        var y: CGFloat = 0
        for offset in 0..<min(insertIndex, items.count) {
            y += estimatedItemHeight(for: items[offset], defaultHeight: itemHeight)
        }
        return y
    }

    private static func verticalRange(
        for items: [TodoItem],
        itemFrames: [UUID: CGRect]
    ) -> ClosedRange<CGFloat>? {
        let availableFrames = items.compactMap { itemFrames[$0.id] }
        guard
            let minY = availableFrames.map(\.minY).min(),
            let maxY = availableFrames.map(\.maxY).max()
        else {
            return nil
        }

        return minY...maxY
    }

    private static func estimatedItemHeight(for item: TodoItem, defaultHeight: CGFloat) -> CGFloat {
        let explicitLineCount = max(1, item.title.components(separatedBy: "\n").count)
        let multiLineHeight = CGFloat(explicitLineCount) * 20 + 8
        return max(defaultHeight, multiLineHeight)
    }
}
