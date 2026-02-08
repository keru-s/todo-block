//
//  ContentView.swift
//  todo block
//
//  Created by 宋科儒 on 2026/1/17.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())

    @State private var injectionHook = Date()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedYear: $selectedYear,
                selectedMonth: $selectedMonth
            )
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } detail: {
            TodoListView(
                year: selectedYear,
                month: selectedMonth
            )
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
