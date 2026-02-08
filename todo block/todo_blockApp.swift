//
//  todo_blockApp.swift
//  todo block
//
//  Created by 宋科儒 on 2026/1/17.
//

import SwiftData
import SwiftUI

@main
struct todo_blockApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TodoItem.self,
            DaySection.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        #if DEBUG
            Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle")?
                .load()
        #endif
    }

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
