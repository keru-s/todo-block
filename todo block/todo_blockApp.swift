//
//  todo_blockApp.swift
//  todo block
//
//  Created by 宋科儒 on 2026/1/17.
//

import AppKit
import SwiftData
import SwiftUI

@main
struct todo_blockApp: App {
    var sharedModelContainer: ModelContainer = {
        do {
            return try TodoModelContainerFactory.makeContainer()
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
                .background {
                    MenuBarStatusItemBootstrapView(modelContainer: sharedModelContainer)
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            // 完全替换默认的撤销/重做菜单
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") {
                    ActiveListCommandCoordinator.shared.perform(.undo)
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(
                    !ActiveListCommandCoordinator.shared.availability(of: .undo).allowsAttempt
                )

                Button("恢复") {
                    ActiveListCommandCoordinator.shared.perform(.redo)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(
                    !ActiveListCommandCoordinator.shared.availability(of: .redo).allowsAttempt
                )
            }

            CommandGroup(replacing: .pasteboard) {
                Button("剪切") {
                    ActiveListCommandCoordinator.shared.perform(.cut)
                }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(
                    !ActiveListCommandCoordinator.shared.availability(of: .cut).allowsAttempt
                )

                Button("复制") {
                    ActiveListCommandCoordinator.shared.perform(.copy)
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(
                    !ActiveListCommandCoordinator.shared.availability(of: .copy).allowsAttempt
                )

                Button("粘贴") {
                    ActiveListCommandCoordinator.shared.perform(.paste)
                }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(
                    !ActiveListCommandCoordinator.shared.availability(of: .paste).allowsAttempt
                )

                Divider()

                Button("全选") {
                    ActiveListCommandCoordinator.shared.perform(.selectAll)
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(
                    !ActiveListCommandCoordinator.shared.availability(of: .selectAll).allowsAttempt
                )
            }

            CommandMenu("排序") {
                Button("上移当前待办") {
                    ActiveListCommandCoordinator.shared.perform(.moveUp)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(
                    !ActiveListCommandCoordinator.shared.availability(of: .moveUp).allowsAttempt
                )

                Button("下移当前待办") {
                    ActiveListCommandCoordinator.shared.perform(.moveDown)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(
                    !ActiveListCommandCoordinator.shared.availability(of: .moveDown).allowsAttempt
                )
            }
        }
    }

}
