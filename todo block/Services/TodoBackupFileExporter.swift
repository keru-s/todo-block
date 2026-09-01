//
//  TodoBackupFileExporter.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum TodoBackupFileExporter {
    static func presentSavePanel(store: TodoStore) {
        // 先把 app 激活到前台：沙盒 app 的存储面板由 openAndSavePanelService
        // 远程呈现，app 处于后台且无窗口时面板会静默不出现（命令已触发但
        // 用户看不到任何反应）。外部工具（快捷指令、菜单搜索类启动器）可以
        // 在 app 未激活时直接触发菜单命令，必须兜底。
        NSApp.activate(ignoringOtherApps: true)
        let exportedAt = Date.now
        let panel = NSSavePanel()
        panel.title = "导出备份"
        panel.prompt = "导出"
        panel.nameFieldStringValue = TodoBackupWorkflow.defaultExportFilename(exportedAt: exportedAt)
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let data = try TodoBackupWorkflow.exportData(from: store, exportedAt: exportedAt)
                try data.write(to: url, options: .atomic)
            } catch {
                NSAlert.presentError(message: "备份导出失败", error: error)
            }
        }
    }
}
