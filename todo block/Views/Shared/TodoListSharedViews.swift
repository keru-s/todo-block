//
//  TodoListSharedViews.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftUI
import UniformTypeIdentifiers

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

struct TodoDropGutterView: View {
    let index: Int
    let visualHeight: CGFloat
    let hitHeight: CGFloat
    let destination: TodoDropDestination
    let items: [TodoItem]
    let store: TodoStore
    @Binding var dropState: TodoListDropState
    let indentWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear

            if case .insertAt(let currentIndex, let indentLevel) = dropState,
                currentIndex == index
            {
                TodoInsertionIndicator(
                    indentLevel: indentLevel,
                    indentWidth: indentWidth
                )
            }
        }
        .frame(height: visualHeight)
        .overlay {
            Color.clear
                .frame(height: hitHeight)
                .contentShape(.rect)
                .onDrop(
                    of: [.text],
                    delegate: TodoBoundaryDropDelegate(
                        insertIndex: index,
                        destination: destination,
                        todoItems: items,
                        store: store,
                        dropState: $dropState,
                        indentWidth: indentWidth
                    )
                )
                .allowsHitTesting(true)
        }
    }
}
