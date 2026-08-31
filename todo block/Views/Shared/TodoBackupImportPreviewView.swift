//
//  TodoBackupImportPreviewView.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import AppKit
import SwiftUI

struct TodoBackupImportPreviewView: View {
    let plan: TodoBackupMergePlan
    let onConfirm: () -> Void
    let onClose: () -> Void

    private var content: TodoBackupImportPreviewContent {
        plan.previewContent
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("导入备份预览")
                .font(.title2)
                .fontWeight(.semibold)

            Text("确认前不会修改任何数据。导入将按下面的规则自动合并。")
                .foregroundStyle(.secondary)

            HStack {
                BackupSummaryCard(title: "新增", value: content.additionCount)
                BackupSummaryCard(title: "更新", value: content.updateCount)
                BackupSummaryCard(title: "保留本地", value: content.keptLocalCount)
                BackupSummaryCard(title: "无变化", value: content.unchangedCount)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading) {
                    if content.hasReviewDetails {
                        BackupReviewDetails(content: content)
                    } else {
                        Label("没有需要额外检查的更新或冲突", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(plan.hasDataChanges ? "确认导入" : "完成", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 460)
    }

}

private struct BackupReviewDetails: View {
    let content: TodoBackupImportPreviewContent

    var body: some View {
        if content.hasTodoDetails {
            Text("待办")
                .font(.headline)

            if content.itemUpdates.isEmpty == false {
                DisclosureGroup("更新（\(content.itemUpdates.count)）") {
                    BackupTodoChangeList(changes: content.itemUpdates)
                }
            }

            if content.itemsKeptLocal.isEmpty == false {
                DisclosureGroup("保留本地 / 冲突（\(content.itemsKeptLocal.count)）") {
                    BackupTodoChangeList(changes: content.itemsKeptLocal)
                }
            }
        }

        if content.hasDaySectionDetails {
            if content.hasTodoDetails {
                Divider()
            }

            Text("日期分组")
                .font(.headline)

            if content.daySectionUpdates.isEmpty == false {
                DisclosureGroup("更新（\(content.daySectionUpdates.count)）") {
                    BackupDaySectionChangeList(changes: content.daySectionUpdates)
                }
            }

            if content.daySectionsKeptLocal.isEmpty == false {
                DisclosureGroup("保留本地 / 冲突（\(content.daySectionsKeptLocal.count)）") {
                    BackupDaySectionChangeList(changes: content.daySectionsKeptLocal)
                }
            }
        }
    }
}

private struct BackupSummaryCard: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value, format: .number)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BackupTodoChangeList: View {
    let changes: [TodoBackupItemChange]

    var body: some View {
        LazyVStack(alignment: .leading) {
            ForEach(changes) { change in
                VStack(alignment: .leading) {
                    HStack {
                        Text(change.imported.title.isEmpty ? "（无标题）" : change.imported.title)
                            .fontWeight(.medium)
                        if change.hasStructuralDifference {
                            Label("结构冲突", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(change.reason.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    BackupFieldDifferenceList(differences: change.differences)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical)
            }
        }
    }
}

private struct BackupDaySectionChangeList: View {
    let changes: [TodoBackupDaySectionChange]

    var body: some View {
        LazyVStack(alignment: .leading) {
            ForEach(changes) { change in
                VStack(alignment: .leading) {
                    Text(change.imported.date.canonicalString)
                        .fontWeight(.medium)
                    Text(change.reason.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BackupFieldDifferenceList(differences: change.differences)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical)
            }
        }
    }
}

private struct BackupFieldDifferenceList: View {
    let differences: [TodoBackupFieldDifference]

    var body: some View {
        ForEach(differences) { difference in
            VStack(alignment: .leading) {
                Text(difference.fieldName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("本地：\(difference.localValue)")
                    .textSelection(.enabled)
                Text("导入：\(difference.importedValue)")
                    .textSelection(.enabled)
            }
            .padding(.leading)
        }
    }
}

@MainActor
enum TodoBackupImportPreviewPresenter {
    private static var windowController: NSWindowController?

    static func present(
        plan: TodoBackupMergePlan,
        onConfirm: @escaping () -> Void
    ) {
        dismiss()

        let hostingController = NSHostingController(
            rootView: TodoBackupImportPreviewView(
                plan: plan,
                onConfirm: onConfirm,
                onClose: { dismiss() }
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "导入备份预览"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 560))
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func dismiss() {
        windowController?.close()
        windowController = nil
    }
}
