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
        Window("待办", id: "mainWindow") {
            ContentView()
                .onAppear {
                    // 初始化 TodoStore 单例
                    TodoStore.shared.initialize(with: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            // 完全替换默认的撤销/重做菜单
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") {
                    // 首先尝试触发当前 focused 的 TextField 的撤销
                    if let window = NSApp.keyWindow,
                        let firstResponder = window.firstResponder as? NSTextView,
                        firstResponder.undoManager?.canUndo == true
                    {
                        firstResponder.undoManager?.undo()
                    } else {
                        // 如果 TextField 无法撤销，则使用应用层撤销
                        TodoStore.shared.undo()
                    }
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("重做") {
                    // 首先尝试触发当前 focused 的 TextField 的重做
                    if let window = NSApp.keyWindow,
                        let firstResponder = window.firstResponder as? NSTextView,
                        firstResponder.undoManager?.canRedo == true
                    {
                        firstResponder.undoManager?.redo()
                    } else {
                        // 如果 TextField 无法重做，则使用应用层重做
                        TodoStore.shared.redo()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }

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
