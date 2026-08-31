//
//  TodoBackupFileImporter.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum TodoBackupFileImporter {
    static func presentOpenPanel(store: TodoStore) {
        let panel = NSOpenPanel()
        panel.title = "导入备份"
        panel.prompt = "预览"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)
                let plan = try TodoBackupWorkflow.previewImport(data: data, into: store)
                TodoBackupImportPreviewPresenter.present(plan: plan) {
                    confirmImport(plan: plan, store: store)
                }
            } catch {
                NSAlert.presentError(message: "无法预览备份", error: error)
            }
        }
    }

    private static func confirmImport(
        plan: TodoBackupMergePlan,
        store: TodoStore
    ) {
        do {
            let recoveryStore = try TodoBackupRecoveryStore.applicationSupportStore()
            let result = try TodoBackupWorkflow.applyImport(
                plan: plan,
                into: store,
                recoveryStore: recoveryStore
            )
            TodoBackupRecoveryCoordinator.shared.refreshAvailability(store: store)
            TodoBackupImportPreviewPresenter.dismiss()

            let completion = result.completionPresentation(plan: plan)
            let alert = NSAlert()
            alert.messageText = completion.title
            alert.informativeText = completion.detail
            alert.addButton(withTitle: "好")
            alert.runModal()
        } catch {
            NSAlert.presentError(message: "备份导入失败", error: error)
        }
    }
}

private struct TodoBackupImportCompletionPresentation {
    let title: String
    let detail: String
}

private extension TodoBackupImportApplyResult {
    func completionPresentation(
        plan: TodoBackupMergePlan
    ) -> TodoBackupImportCompletionPresentation {
        switch self {
        case .applied:
            TodoBackupImportCompletionPresentation(
                title: "备份导入完成",
                detail: "新增 \(plan.previewAdditionCount) 条记录，更新 \(plan.previewUpdateCount) 条记录，保留本地 \(plan.previewKeptLocalCount) 条记录。"
            )
        case .noChanges:
            TodoBackupImportCompletionPresentation(
                title: "无需导入",
                detail: "当前数据已经符合这份备份的合并结果。"
            )
        }
    }
}
