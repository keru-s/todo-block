//
//  TodoBackupRecoveryCoordinator.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class TodoBackupRecoveryCoordinator {
    static let shared = TodoBackupRecoveryCoordinator()

    private(set) var hasRecoveryPoint = false

    private init() {}

    func refreshAvailability(store: TodoStore) {
        do {
            let recoveryStore = try TodoBackupRecoveryStore.applicationSupportStore()
            let currentDocument = TodoBackupWorkflow.makeExportDocument(from: store)
            if let modelContext = store.modelContext {
                try recoveryStore.reconcileInterruptedConsumption(
                    modelContext: modelContext
                )
            }
            try recoveryStore.reconcileInterruptedImport(currentDocument: currentDocument)
            hasRecoveryPoint = recoveryStore.hasRecoveryPoint
        } catch {
            do {
                let recoveryStore = try TodoBackupRecoveryStore.applicationSupportStore()
                hasRecoveryPoint = recoveryStore.hasRecoveryPoint
            } catch {
                hasRecoveryPoint = false
            }
        }
    }

    func presentRestoreConfirmation(store: TodoStore) {
        Task { @MainActor in
            await Task.yield()
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "恢复到最近一次导入前？"
            alert.informativeText = "当前全部 Todo 和日期分组都会精确恢复到最近一次导入开始前的状态。导入之后新增或修改的数据也会丢失。"
            alert.addButton(withTitle: "取消")
            alert.addButton(withTitle: "恢复")

            alert.beginSheetModal(for: window) { response in
                guard response == .alertSecondButtonReturn else { return }
                self.restoreLatestImportCheckpoint(store: store)
            }
        }
    }

    private func restoreLatestImportCheckpoint(store: TodoStore) {
        do {
            let recoveryStore = try TodoBackupRecoveryStore.applicationSupportStore()
            try TodoBackupWorkflow.restoreLatestImportCheckpoint(
                into: store,
                recoveryStore: recoveryStore
            )
            refreshAvailability(store: store)

            let successAlert = NSAlert()
            successAlert.messageText = "已恢复到最近一次导入前"
            successAlert.informativeText = "导入恢复点已使用并移除。"
            successAlert.addButton(withTitle: "好")
            successAlert.runModal()
        } catch {
            refreshAvailability(store: store)

            NSAlert.presentError(message: "恢复失败", error: error)
        }
    }
}
