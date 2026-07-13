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
                    TodoStore.shared.undo()
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("重做") {
                    TodoStore.shared.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("剪切") {
                    performCut()
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("复制") {
                    performCopy()
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("粘贴") {
                    performPaste()
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                Button("全选") {
                    _ = NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            CommandMenu("排序") {
                Button("上移当前待办") {
                    TodoReorderCommandManager.shared.moveSelectionUp()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("下移当前待办") {
                    TodoReorderCommandManager.shared.moveSelectionDown()
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
            }
        }
    }

    private func performCopy() {
        if
            let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
            textView.selectedRange().length > 0
        {
            _ = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            return
        }

        if TodoClipboardManager.shared.copySelectionToPasteboard() {
            return
        }

        _ = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    }

    private func performCut() {
        if
            let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
            textView.selectedRange().length > 0
        {
            _ = NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            return
        }

        if TodoClipboardManager.shared.cutSelectionToPasteboard() {
            return
        }

        _ = NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
    }

    private func performPaste() {
        if TodoClipboardManager.shared.pasteFromPasteboard() {
            return
        }

        _ = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }
}
