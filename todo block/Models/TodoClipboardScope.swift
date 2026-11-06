//
//  TodoClipboardScope.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import Foundation

enum TodoClipboardScope: Equatable {
    case scheduledMonth(year: Int, month: Int)
    case longTerm
    case day(Date)

    /// 便捷地捕获当日范围；打开菜单栏时会重新捕获，已打开的范围不会随时钟漂移。
    static var today: Self { .day(Calendar.current.startOfDay(for: .now)) }

    var isDaily: Bool {
        if case .day = self { return true }
        return false
    }
}

struct TodoClipboardSelectionSnapshot: Equatable {
    let focusedItemId: UUID?
    let selectedItemIds: Set<UUID>
}

struct TodoClipboardImportResult: Equatable {
    let createdItemIds: [UUID]
    let focusedItemId: UUID
}
