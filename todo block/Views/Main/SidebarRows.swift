//
//  SidebarRows.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftUI

struct LongTermRow: View {
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "infinity")
            Text("长期")
                .fontWeight(isSelected ? .bold : .regular)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

struct MonthRow: View {
    let year: Int
    let month: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            Text("\(month) 月")
                .fontWeight(isSelected ? .bold : .regular)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
