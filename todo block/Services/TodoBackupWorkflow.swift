//
//  TodoBackupWorkflow.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import Foundation

@MainActor
enum TodoBackupWorkflow {
    static func exportData(
        from store: TodoStore,
        exportedAt: Date = .now,
        calendar: Calendar = .current
    ) throws -> Data {
        try TodoBackupCodec.encode(
            makeExportDocument(
                from: store,
                exportedAt: exportedAt,
                calendar: calendar
            )
        )
    }

    static func makeExportDocument(
        from store: TodoStore,
        exportedAt: Date = .now,
        calendar: Calendar = .current
    ) -> TodoBackupDocument {
        // 与普通用户动作一样，先结束当前连续输入段，确保导出的就是界面此刻的最新状态。
        store.flushPendingTextEdit()

        let items = store.validTodoItems
            .map { snapshot(item: $0, calendar: calendar) }
            .sorted(by: backupItemPrecedes)

        let daySections = store.validDaySections
            .map { snapshot(section: $0, calendar: calendar) }
            .sorted(by: backupSectionPrecedes)

        return TodoBackupDocument(
            exportedAt: exportedAt,
            items: items,
            daySections: daySections
        )
    }

    static func previewImport(
        data: Data,
        into store: TodoStore,
        calendar: Calendar = .current
    ) throws -> TodoBackupMergePlan {
        let document = try TodoBackupCodec.decode(data)
        return try TodoBackupImportPlanner.makePlan(
            document: document,
            store: store,
            calendar: calendar
        )
    }

    static func applyImport(
        plan: TodoBackupMergePlan,
        into store: TodoStore,
        recoveryStore: TodoBackupRecoveryStore,
        calendar: Calendar = .current
    ) throws -> TodoBackupImportApplyResult {
        try TodoBackupImportApplier.apply(
            plan: plan,
            to: store,
            recoveryStore: recoveryStore,
            calendar: calendar
        )
    }

    static func restoreLatestImportCheckpoint(
        into store: TodoStore,
        recoveryStore: TodoBackupRecoveryStore,
        calendar: Calendar = .current
    ) throws {
        try TodoBackupExactRestorer.restore(
            into: store,
            recoveryStore: recoveryStore,
            calendar: calendar
        )
    }

    static func defaultExportFilename(
        exportedAt: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let date = TodoBackupCalendarDate(date: exportedAt, calendar: calendar)
        return "TodoBlock-Backup-\(date.canonicalString).json"
    }

    static func snapshot(
        item: TodoItem,
        calendar: Calendar = .current
    ) -> TodoBackupItem {
        TodoBackupItem(
            id: item.id,
            title: item.title,
            isCompleted: item.isCompleted,
            indentLevel: item.indentLevel,
            sortOrder: item.sortOrder,
            containerKind: item.containerKind,
            dayDate: TodoBackupCalendarDate(date: item.dayDate, calendar: calendar),
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }

    static func snapshot(
        section: DaySection,
        calendar: Calendar = .current
    ) -> TodoBackupDaySection {
        TodoBackupDaySection(
            id: section.id,
            date: TodoBackupCalendarDate(date: section.date, calendar: calendar),
            title: section.title,
            sortOrder: section.sortOrder,
            createdAt: section.createdAt,
            updatedAt: section.updatedAt
        )
    }

    private static func backupItemPrecedes(_ lhs: TodoBackupItem, _ rhs: TodoBackupItem) -> Bool {
        if lhs.containerKind != rhs.containerKind {
            return lhs.containerKind.rawValue < rhs.containerKind.rawValue
        }
        if lhs.dayDate.canonicalString != rhs.dayDate.canonicalString {
            return lhs.dayDate.canonicalString < rhs.dayDate.canonicalString
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func backupSectionPrecedes(
        _ lhs: TodoBackupDaySection,
        _ rhs: TodoBackupDaySection
    ) -> Bool {
        if lhs.date.canonicalString != rhs.date.canonicalString {
            return lhs.date.canonicalString < rhs.date.canonicalString
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
