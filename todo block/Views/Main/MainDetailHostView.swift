//
//  MainDetailHostView.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftUI

struct MainDetailHostView: View {
    let selectedDestination: SidebarDestination
    let fallbackMonthDestination: SidebarDestination

    private var activeMonth: (year: Int, month: Int) {
        if case .month(let year, let month) = selectedDestination {
            return (year, month)
        }
        if case .month(let year, let month) = fallbackMonthDestination {
            return (year, month)
        }
        return (
            Calendar.current.component(.year, from: Date()),
            Calendar.current.component(.month, from: Date())
        )
    }

    private var isMonthSelected: Bool {
        if case .month = selectedDestination {
            return true
        }
        return false
    }

    private var isLongTermSelected: Bool {
        selectedDestination == .longTerm
    }

    var body: some View {
        ZStack {
            TodoListView(
                year: activeMonth.year,
                month: activeMonth.month,
                isActiveContext: isMonthSelected
            )
            .opacity(isMonthSelected ? 1 : 0)
            .allowsHitTesting(isMonthSelected)
            .accessibilityHidden(isMonthSelected == false)

            LongTermListView(isActiveContext: isLongTermSelected)
                .opacity(isLongTermSelected ? 1 : 0)
                .allowsHitTesting(isLongTermSelected)
                .accessibilityHidden(isLongTermSelected == false)
        }
    }
}
