//
//  ContentView.swift
//  todo block
//
//  Created by 宋科儒 on 2026/1/17.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    private var historyPresentation: TodoHistoryPresentationCoordinator {
        .shared
    }

    @State private var selectedDestination: SidebarDestination = .month(
        year: Calendar.current.component(.year, from: Date()),
        month: Calendar.current.component(.month, from: Date())
    )
    @State private var lastMonthDestination: SidebarDestination = .month(
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
            MainDetailHostView(
                selectedDestination: selectedDestination,
                fallbackMonthDestination: lastMonthDestination
            )
        }
        .frame(minWidth: 600, minHeight: 400)
        .coordinateSpace(name: "main-window")
        .id(injectionHook)
        .onAppear {
            if let request = historyPresentation.revealRequest {
                selectedDestination = request.destination
            }
        }
        .onChange(of: selectedDestination) { _, newValue in
            if case .month = newValue {
                lastMonthDestination = newValue
            }
        }
        .onChange(of: historyPresentation.revealRequest) { _, request in
            guard let request else { return }
            selectedDestination = request.destination
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
    let container = TodoPreviewSupport.bootstrap()
    return ContentView()
        .modelContainer(container)
}
