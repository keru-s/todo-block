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
        WindowGroup(id: "mainWindow") {
            ContentView()
                .onAppear {
                    // 初始化 TodoStore 单例
                    TodoStore.shared.initialize(with: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
        
        // 菜单栏组件
        MenuBarExtra("待办", systemImage: "checklist") {
            MenuBarView()
                .onAppear {
                    // 确保菜单栏也初始化 TodoStore
                    TodoStore.shared.initialize(with: sharedModelContainer.mainContext)
                }
        }
        .menuBarExtraStyle(.window)
        .modelContainer(sharedModelContainer)
    }
}
