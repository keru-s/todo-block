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
