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

struct TodoInsertionIndicator: View {
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
        .frame(height: 4)
        .transition(.opacity)
    }
}
