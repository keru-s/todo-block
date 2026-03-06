//
//  TodoDragCoordinator.swift
//  todo block
//
//  Created by Codex on 2026/3/6.
//

import Foundation
import Observation

@MainActor
@Observable
final class TodoDragCoordinator {
    static let shared = TodoDragCoordinator()

    private(set) var activeSystemDragSessionID: UUID?
    private(set) var activeDraggedItemID: UUID?

    private init() {}

    var hasActiveSystemDrag: Bool {
        activeSystemDragSessionID != nil && activeDraggedItemID != nil
    }

    func beginSystemDrag(itemID: UUID) {
        activeSystemDragSessionID = UUID()
        activeDraggedItemID = itemID
    }

    func finishSystemDrag() {
        activeSystemDragSessionID = nil
        activeDraggedItemID = nil
    }
}
