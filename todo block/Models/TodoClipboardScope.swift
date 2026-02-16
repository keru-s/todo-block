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
    case today
}

struct TodoClipboardSelectionSnapshot: Equatable {
    let focusedItemId: UUID?
    let selectedItemIds: Set<UUID>
}

struct TodoClipboardImportResult: Equatable {
    let createdItemIds: [UUID]
    let focusedItemId: UUID
}
