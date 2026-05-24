//
//  TodoListSharedViews.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftUI

enum TodoListDropState: Equatable {
    case none
    case insertAt(index: Int, indentLevel: Int)
}

struct TodoDropResetSnapshot: Equatable {
    let id: UUID
    let sortOrder: Double
    let indentLevel: Int
    let dayDate: Date
    let containerKindRaw: String
}

extension Collection where Element == TodoItem {
    var dropResetSnapshot: [TodoDropResetSnapshot] {
        map { item in
            TodoDropResetSnapshot(
                id: item.id,
                sortOrder: item.sortOrder,
                indentLevel: item.indentLevel,
                dayDate: item.dayDate,
                containerKindRaw: item.containerKindRaw
            )
        }
    }
}

struct TodoDropItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// 拖放系统专用的 frame 缓存。引用类型,赋值它的属性不会触发 SwiftUI body 重算,
/// 用于打破 GeometryReader → @State 写入 → body 重算 → GeometryReader 重测的反馈循环。
@MainActor
final class DropFrameTracker {
    var itemFrames: [UUID: CGRect] = [:]
    var listGlobalFrame: CGRect = .zero
}

struct TodoInsertionIndicator: View {
    static let visualHeight: CGFloat = 4

    let indentLevel: Int
    let indentWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 20 + CGFloat(indentLevel) * indentWidth)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .frame(height: Self.visualHeight)
        .transition(.opacity)
    }
}

/// 框选拖动期间, 把鼠标点击映射回某个 item.
/// 优先返回纵向区间命中的 item, 命中失败时回落到与点击 y 距离最近者,
/// 这样拖出列表上下边界时仍能选中头/尾。
enum TodoDragSelectionHitTester {
    static func nearestItemId(
        at point: CGPoint,
        items: [TodoItem],
        itemFrames: [UUID: CGRect]
    ) -> UUID? {
        guard items.isEmpty == false else { return nil }

        var best: (id: UUID, distance: CGFloat)?
        for item in items {
            guard let frame = itemFrames[item.id] else { continue }
            if frame.minY <= point.y && point.y <= frame.maxY {
                return item.id
            }
            let distance: CGFloat =
                point.y < frame.minY ? frame.minY - point.y : point.y - frame.maxY
            if best == nil || distance < best!.distance {
                best = (item.id, distance)
            }
        }
        return best?.id
    }
}

struct TodoDropIndicatorOverlay: View {
    let dropState: TodoListDropState
    let items: [TodoItem]
    let itemFrames: [UUID: CGRect]
    let itemHeight: CGFloat
    let indentWidth: CGFloat

    var body: some View {
        if case .insertAt(_, let indentLevel) = dropState,
            let indicatorTopY = TodoDropLocationEngine.indicatorTopY(
                for: dropState,
                items: items,
                itemFrames: itemFrames,
                itemHeight: itemHeight
            )
        {
            TodoInsertionIndicator(
                indentLevel: indentLevel,
                indentWidth: indentWidth
            )
            .offset(y: indicatorTopY)
            .allowsHitTesting(false)
        }
    }
}


