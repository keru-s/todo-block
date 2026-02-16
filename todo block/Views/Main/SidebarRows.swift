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
            if isSelected {
                Text("长期")
                    .bold()
            } else {
                Text("长期")
            }
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
            if isSelected {
                Text("\(month) 月")
                    .bold()
            } else {
                Text("\(month) 月")
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
