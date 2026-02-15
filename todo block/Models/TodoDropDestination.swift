//
//  TodoDropDestination.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import Foundation

enum TodoDropDestination: Equatable {
    case scheduled(date: Date)
    case longTerm(isUrgent: Bool)

    var normalized: Self {
        switch self {
        case .scheduled(let date):
            .scheduled(date: Calendar.current.startOfDay(for: date))
        case .longTerm(let isUrgent):
            .longTerm(isUrgent: isUrgent)
        }
    }

    var containerKind: TodoContainerKind {
        switch self {
        case .scheduled:
            .scheduled
        case .longTerm(let isUrgent):
            isUrgent ? .longTermUrgent : .longTermImportant
        }
    }
}
