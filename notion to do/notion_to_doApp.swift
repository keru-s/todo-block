//
//  notion_to_doApp.swift
//  notion to do
//
//  Created by 宋科儒 on 2026/1/17.
//

import SwiftUI
import SwiftData

@main
struct notion_to_doApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TodoItem.self,
            DaySection.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        
        // 菜单栏组件
        MenuBarExtra("待办", systemImage: "checklist") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(sharedModelContainer)
    }
}
