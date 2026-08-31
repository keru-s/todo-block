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
    @NSApplicationDelegateAdaptor(TodoBlockApplicationDelegate.self)
    private var applicationDelegate

    @State private var backupRecoveryCoordinator = TodoBackupRecoveryCoordinator.shared

    /// UI 测试模式（-UITestInMemoryStore）：使用内存容器，不读写用户真实数据。
    /// fileprivate：同文件的 TodoBlockApplicationDelegate 也用它做测试模式的
    /// 强制激活（见 applicationDidFinishLaunching）。
    fileprivate static let isUITestMode = ProcessInfo.processInfo.arguments
        .contains("-UITestInMemoryStore")

    var sharedModelContainer: ModelContainer = {
        do {
            // UI 测试支持：带 -UITestInMemoryStore 启动时使用内存容器，
            // 避免测试读写用户真实 SwiftData 数据。
            return try TodoModelContainerFactory.makeContainer(inMemory: isUITestMode)
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
                    ContentSeedUITestHook.applyIfNeeded()
                    BackupRecoveryUITestHook.applyIfNeeded()
                    backupRecoveryCoordinator.refreshAvailability(store: TodoStore.shared)
                }
                .background {
                    MenuBarStatusItemBootstrapView(modelContainer: sharedModelContainer)
                }
        }
        .modelContainer(sharedModelContainer)
        // UI 测试模式：关闭窗口状态恢复与保存。用户若以「主窗口已关闭」的状态退出过
        // app，恢复的 savedState 会让测试启动时没有主窗口——菜单栏 bootstrap 挂在
        // ContentView 上，无窗口即完全无 UI，app 停在后台导致 XCUIApplication.launch()
        // 超时。沙盒 UI 测试 runner 对用户容器只有只读权限，无法从外部删除 savedState，
        // 只能由 app 自身在测试模式下关闭恢复（顺带避免测试运行覆盖用户的窗口状态）。
        .restorationBehavior(Self.isUITestMode ? .disabled : .automatic)
        // UI 测试模式：强制启动即呈现主窗口。automatic 在 app 未激活时可能不呈现
        // 窗口（terminate 后立刻 relaunch 的竞态下实测出现无窗口启动）。
        .defaultLaunchBehavior(Self.isUITestMode ? .presented : .automatic)
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

            CommandGroup(after: .saveItem) {
                Divider()

                Button("导入备份…") {
                    TodoBackupFileImporter.presentOpenPanel(store: TodoStore.shared)
                }

                Button("导出备份…") {
                    TodoBackupFileExporter.presentSavePanel(store: TodoStore.shared)
                }

                Divider()

                Button("恢复到最近一次导入前…") {
                    backupRecoveryCoordinator.presentRestoreConfirmation(store: TodoStore.shared)
                }
                .disabled(!backupRecoveryCoordinator.hasRecoveryPoint)
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

/// UI 测试专用钩子：仅当带 `-UITestRecoveryState <none|seeded>` 启动时生效。
/// 该参数同时让 TodoBackupRecoveryStore 重定向到测试专用目录
/// （Application Support/TodoBlock/UITestBackupRecovery），这里只在启动时
/// 重置该目录的状态：none 清空（模拟无恢复点）、seeded 写入一个已晋升的
/// 检查点（模拟最近一次导入前的恢复点存在）。真实的 BackupRecovery 目录不受影响。
@MainActor
private enum BackupRecoveryUITestHook {
    static func applyIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-UITestRecoveryState"),
              arguments.indices.contains(index + 1),
              let store = try? TodoBackupRecoveryStore.applicationSupportStore()
        else { return }

        try? FileManager.default.removeItem(at: store.directoryURL)
        guard arguments[index + 1] == "seeded" else { return }

        let document = TodoBackupWorkflow.makeExportDocument(from: TodoStore.shared)
        try? store.stage(document)
        try? store.promoteStaged()
    }
}

/// UI 测试专用钩子：仅当带 `-UITestSeedContent` 启动时生效。
/// 实际的播种入口在 TodoStore+UITestSeeding.swift（store 内部字段的直写
/// 必须留在 friendship 边界内，见 docs/agents/architecture.md），这里只负责转发。
@MainActor
private enum ContentSeedUITestHook {
    static func applyIfNeeded() {
        TodoStore.shared.seedUITestContentIfNeeded()
    }
}

@MainActor
final class TodoBlockApplicationDelegate: NSObject, NSApplicationDelegate {
    /// 单元测试可替换提示展示；生产环境使用下方原生警告框。
    var unsavedChangesAlertPresenter: (() -> Void)?

    /// UI 测试模式（-UITestInMemoryStore）下的启动加固。
    /// XCUITest 以后台方式启动 app（LSLaunchDoNotBringFrontmost），Window scene
    /// 偶发不创建主窗口；而此时 app 无窗口且不活跃，会被 macOS 的 Automatic
    /// Termination 在十几秒后杀掉——测试侧表现为启动后查询报
    /// "Application com.insight.to-do-block is not running"。
    /// 对策：关掉 Automatic Termination（保活），并持续重试激活。
    /// 窗口真的不出现时由测试侧通过 LaunchServices 重发 reopen 兜底
    /// （见 BackupMenuUITests.mainWindow / CopyMarkdownFeedbackLoopUITests.mainWindow）。
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard todo_blockApp.isUITestMode else { return }
        ProcessInfo.processInfo.disableAutomaticTermination("UI 测试")
        activateForUITest(attempt: 0)
    }

    /// 每 0.5 秒重试一次激活（上限 20 次），直到有可见窗口。
    @MainActor
    private func activateForUITest(attempt: Int) {
        NSApp.activate(ignoringOtherApps: true)
        guard NSApp.windows.contains(where: { $0.isVisible }) == false, attempt < 20 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            activateForUITest(attempt: attempt + 1)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard TodoStore.shared.prepareForTermination() == false else {
            return .terminateNow
        }

        if let unsavedChangesAlertPresenter {
            unsavedChangesAlertPresenter()
            return .terminateCancel
        }

        let alert = NSAlert()
        alert.messageText = "待办尚未保存"
        alert.informativeText = "应用暂时无法保存你的最新修改。它会继续自动重试；请保留应用打开，直到顶部提示消失后再退出。"
        alert.addButton(withTitle: "继续使用")
        alert.runModal()
        return .terminateCancel
    }
}
