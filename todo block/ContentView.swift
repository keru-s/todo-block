//
//  ContentView.swift
//  todo block
//
//  Created by 宋科儒 on 2026/1/17.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var selectedDestination: SidebarDestination = .month(
        year: Calendar.current.component(.year, from: Date()),
        month: Calendar.current.component(.month, from: Date())
    )

    @State private var injectionHook = Date()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedDestination: $selectedDestination
            )
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } detail: {
            switch selectedDestination {
            case .month(let year, let month):
                TodoListView(
                    year: year,
                    month: month
                )
            case .longTerm:
                LongTermListView()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .id(injectionHook)
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
        ) { _ in
            injectionHook = Date()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
