//
//  TodoBackupImportApplier.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import Foundation
import SwiftData

enum TodoBackupImportApplyResult: Equatable, Sendable {
    case noChanges
    case applied
}

enum TodoBackupImportError: LocalizedError {
    case unsavedChanges
    case unableToFlushLocalChanges
    case stalePreview
    case missingModelContext
    case invalidCalendarDate(TodoBackupCalendarDate)
    case recoveryPointCreationFailed(String)
    case persistenceFailed

    var errorDescription: String? {
        let profile = TodoBackupMutationSafety.Operation.importBackup.profile
        return switch self {
        case .unsavedChanges:
            profile.unsavedChangesMessage
        case .unableToFlushLocalChanges:
            profile.unableToFlushMessage
        case .stalePreview:
            "本地数据在预览后已经发生变化。请重新选择备份并确认新的导入预览。"
        case .missingModelContext:
            profile.missingModelContextMessage
        case .invalidCalendarDate(let date):
            profile.invalidCalendarDateMessage(date)
        case .recoveryPointCreationFailed(let reason):
            "无法创建导入恢复点，因此没有开始导入。\n\(reason)"
        case .persistenceFailed:
            profile.persistenceFailedMessage
        }
    }
}

@MainActor
enum TodoBackupImportApplier {
    static func apply(
        plan: TodoBackupMergePlan,
        to store: TodoStore,
        recoveryStore: TodoBackupRecoveryStore,
        calendar: Calendar = .current
    ) throws -> TodoBackupImportApplyResult {
        try TodoBackupMutationSafety.prepare(store: store, for: .importBackup)

        let refreshedPlan = try TodoBackupImportPlanner.makePlan(
            document: plan.sourceDocument,
            store: store,
            calendar: calendar
        )
        guard refreshedPlan == plan else {
            throw TodoBackupImportError.stalePreview
        }

        guard plan.hasDataChanges else {
            return .noChanges
        }

        let modelContext = try TodoBackupMutationSafety.requireModelContext(
            from: store,
            for: .importBackup
        )

        let checkpoint = TodoBackupWorkflow.makeExportDocument(
            from: store,
            exportedAt: .now,
            calendar: calendar
        )
        do {
            try recoveryStore.reconcileInterruptedConsumption(modelContext: modelContext)
            try recoveryStore.stage(checkpoint)
        } catch {
            throw TodoBackupImportError.recoveryPointCreationFailed(error.localizedDescription)
        }

        return try TodoBackupMutationSafety.withAutosaveDisabled(in: modelContext) {
            do {
                try applyDaySectionChanges(
                    plan,
                    store: store,
                    modelContext: modelContext,
                    calendar: calendar
                )
                try applyTodoChanges(
                    plan,
                    store: store,
                    modelContext: modelContext,
                    calendar: calendar
                )

                store.cleanupAllOrphanSections()
                store.bumpRefreshTrigger()

                try TodoBackupMutationSafety.persist(store: store, for: .importBackup)
            } catch {
                TodoBackupMutationSafety.rollback(
                    modelContext: modelContext,
                    store: store,
                    cleanup: { recoveryStore.discardStaged() }
                )
                throw error
            }

            store.undoManager.clear()

            // 晋升失败时保留 pending 文件；loadRecoveryPoint() 会优先读取它，
            // 因此不把已经成功写盘的导入错误地报告为失败，也不会丢失安全恢复点。
            try? recoveryStore.promoteStaged()
            return .applied
        }
    }

    private static func applyTodoChanges(
        _ plan: TodoBackupMergePlan,
        store: TodoStore,
        modelContext: ModelContext,
        calendar: Calendar
    ) throws {
        for imported in plan.additions {
            try TodoBackupMutationSafety.insert(
                imported,
                into: modelContext,
                store: store,
                calendar: calendar,
                for: .importBackup
            )
        }

        for change in plan.updates {
            guard let item = store.todoItemsCache[change.local.id], store.isValid(model: item) else {
                throw TodoBackupImportError.stalePreview
            }
            try TodoBackupMutationSafety.apply(
                change.imported,
                to: item,
                calendar: calendar,
                for: .importBackup
            )
        }
    }

    /// 冲突的日期分组按 `updatedAt` last-writer-wins 合并：只有导入方较新的分组
    /// 会进入 `daySectionUpdates`，此分支有意用导入的元数据
    /// （title/sortOrder/createdAt/updatedAt）覆盖本地值。
    private static func applyDaySectionChanges(
        _ plan: TodoBackupMergePlan,
        store: TodoStore,
        modelContext: ModelContext,
        calendar: Calendar
    ) throws {
        for imported in plan.daySectionAdditions {
            try TodoBackupMutationSafety.insert(
                imported,
                into: modelContext,
                store: store,
                calendar: calendar,
                for: .importBackup
            )
        }

        for change in plan.daySectionUpdates {
            guard
                let section = store.daySectionsCache[change.local.id],
                store.isValid(model: section)
            else {
                throw TodoBackupImportError.stalePreview
            }
            try TodoBackupMutationSafety.apply(
                change.imported,
                to: section,
                calendar: calendar,
                for: .importBackup
            )
        }
    }

}
