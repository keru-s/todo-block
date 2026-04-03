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
    @State private var lastMonthDestination: SidebarDestination = .month(
        year: Calendar.current.component(.year, from: Date()),
        month: Calendar.current.component(.month, from: Date())
    )

    @State private var injectionHook = Date()

    private var dragCoordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedDestination: $selectedDestination
            )
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } detail: {
            MainDetailHostView(
                selectedDestination: selectedDestination,
                fallbackMonthDestination: lastMonthDestination
            )
        }
        .frame(minWidth: 600, minHeight: 400)
        .overlay {
            if dragCoordinator.isDragging,
                let loc = dragCoordinator.globalDragLocation,
                let itemId = dragCoordinator.draggedItemId,
                let item = TodoStore.shared.todoItemsCache[itemId]
            {
                TodoItemDragPreviewView(item: item)
                    .position(x: loc.x, y: loc.y)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .coordinateSpace(name: "main-window")
        .id(injectionHook)
        .onChange(of: selectedDestination) { _, newValue in
            if case .month = newValue {
                lastMonthDestination = newValue
            }
        }
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
