//
//  TodoBackupMutationSafety.swift
//  todo block
//
//  Created by Codex on 2026/8/30.
//

import Foundation
import SwiftData

@MainActor
enum TodoBackupMutationSafety {
    nonisolated enum Operation {
        case importBackup
        case exactRestore

        /// 操作的单份配置：错误实例与面向用户措辞。
        /// `TodoBackupImportError` / `TodoBackupExactRestoreError` 的 errorDescription
        /// 也从这里取词，保证同一操作的文案只维护这一处。
        var profile: Profile {
            switch self {
            case .importBackup: .importBackup
            case .exactRestore: .exactRestore
            }
        }
    }

    static func prepare(
        store: TodoStore,
        for operation: Operation
    ) throws {
        guard store.hasUnsavedChanges == false else {
            throw operation.profile.unsavedChangesError
        }

        store.flushPendingTextEdit()
        guard store.flushPendingChangesSync() else {
            throw operation.profile.unableToFlushError
        }
    }

    static func requireModelContext(
        from store: TodoStore,
        for operation: Operation
    ) throws -> ModelContext {
        guard let modelContext = store.modelContext else {
            throw operation.profile.missingModelContextError
        }
        return modelContext
    }

    static func withAutosaveDisabled<Result>(
        in modelContext: ModelContext,
        operation: () throws -> Result
    ) rethrows -> Result {
        let wasAutosaveEnabled = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer {
            modelContext.autosaveEnabled = wasAutosaveEnabled
        }
        return try operation()
    }

    static func persist(
        store: TodoStore,
        for operation: Operation
    ) throws {
        guard store.flushPendingChangesSync() else {
            throw operation.profile.persistenceError
        }
    }

    static func rollback(
        modelContext: ModelContext,
        store: TodoStore,
        cleanup: () -> Void
    ) {
        modelContext.rollback()
        cleanup()
        store.initialize(with: modelContext)
    }

    static func date(
        _ calendarDate: TodoBackupCalendarDate,
        calendar: Calendar,
        for operation: Operation
    ) throws -> Date {
        guard let date = calendarDate.date(in: calendar) else {
            throw operation.profile.invalidCalendarDateError(calendarDate)
        }
        return date
    }

    /// 把备份快照写回 SwiftData 模型的字段赋值。导入更新与精确恢复共用同一套赋值，
    /// 只有日历日期转换失败时抛出的错误类型不同（由 `operation` 决定）。
    static func apply(
        _ snapshot: TodoBackupItem,
        to item: TodoItem,
        calendar: Calendar,
        for operation: Operation
    ) throws {
        item.title = snapshot.title
        item.isCompleted = snapshot.isCompleted
        item.indentLevel = snapshot.indentLevel
        item.sortOrder = snapshot.sortOrder
        item.containerKindRaw = snapshot.containerKind.rawValue
        item.dayDate = try date(snapshot.dayDate, calendar: calendar, for: operation)
        item.createdAt = snapshot.createdAt
        item.updatedAt = snapshot.updatedAt
    }

    static func apply(
        _ snapshot: TodoBackupDaySection,
        to section: DaySection,
        calendar: Calendar,
        for operation: Operation
    ) throws {
        section.date = try date(snapshot.date, calendar: calendar, for: operation)
        section.title = snapshot.title
        section.sortOrder = snapshot.sortOrder
        section.createdAt = snapshot.createdAt
        section.updatedAt = snapshot.updatedAt
    }

    /// 从备份快照新建模型：插入 `modelContext` 并写入 store 缓存。
    /// 导入新增与精确恢复共用同一套构造；日期转换失败的错误类型由 `operation` 决定。
    static func insert(
        _ snapshot: TodoBackupItem,
        into modelContext: ModelContext,
        store: TodoStore,
        calendar: Calendar,
        for operation: Operation
    ) throws {
        let item = TodoItem(
            id: snapshot.id,
            title: snapshot.title,
            isCompleted: snapshot.isCompleted,
            indentLevel: snapshot.indentLevel,
            sortOrder: snapshot.sortOrder,
            containerKindRaw: snapshot.containerKind.rawValue,
            dayDate: try date(snapshot.dayDate, calendar: calendar, for: operation),
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
        modelContext.insert(item)
        store.todoItemsCache[item.id] = item
    }

    static func insert(
        _ snapshot: TodoBackupDaySection,
        into modelContext: ModelContext,
        store: TodoStore,
        calendar: Calendar,
        for operation: Operation
    ) throws {
        let section = DaySection(
            id: snapshot.id,
            date: try date(snapshot.date, calendar: calendar, for: operation),
            title: snapshot.title,
            sortOrder: snapshot.sortOrder,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
        modelContext.insert(section)
        store.daySectionsCache[section.id] = section
    }
}

extension TodoBackupMutationSafety.Operation {
    /// 一个备份操作的全部错误实例与面向用户措辞。
    struct Profile: Sendable {
        let unsavedChangesMessage: String
        let unableToFlushMessage: String
        let missingModelContextMessage: String
        let persistenceFailedMessage: String
        /// 无效日历日期错误中对出错文档的称呼（"备份" / "恢复点"）。
        let invalidCalendarDateSubject: String

        let unsavedChangesError: any Error
        let unableToFlushError: any Error
        let missingModelContextError: any Error
        let persistenceError: any Error
        let invalidCalendarDateError: @Sendable (TodoBackupCalendarDate) -> any Error

        func invalidCalendarDateMessage(_ date: TodoBackupCalendarDate) -> String {
            "\(invalidCalendarDateSubject)包含无法恢复的所属日期：\(date.canonicalString)"
        }

        static let importBackup = Self(
            unsavedChangesMessage: "当前有尚未可靠保存的修改。请等待保存恢复正常后再导入备份。",
            unableToFlushMessage: "无法先保存当前修改，因此没有开始导入。",
            missingModelContextMessage: "本地数据存储尚未准备好，无法导入备份。",
            persistenceFailedMessage: "导入结果无法写入本地存储，已撤回本次导入。",
            invalidCalendarDateSubject: "备份",
            unsavedChangesError: TodoBackupImportError.unsavedChanges,
            unableToFlushError: TodoBackupImportError.unableToFlushLocalChanges,
            missingModelContextError: TodoBackupImportError.missingModelContext,
            persistenceError: TodoBackupImportError.persistenceFailed,
            invalidCalendarDateError: { TodoBackupImportError.invalidCalendarDate($0) }
        )

        static let exactRestore = Self(
            unsavedChangesMessage: "当前有尚未可靠保存的修改。请等待保存恢复正常后再执行恢复。",
            unableToFlushMessage: "无法先保存当前修改，因此没有开始恢复。",
            missingModelContextMessage: "本地数据存储尚未准备好，无法恢复。",
            persistenceFailedMessage: "恢复结果无法写入本地存储，已撤回本次恢复。",
            invalidCalendarDateSubject: "恢复点",
            unsavedChangesError: TodoBackupExactRestoreError.unsavedChanges,
            unableToFlushError: TodoBackupExactRestoreError.unableToFlushLocalChanges,
            missingModelContextError: TodoBackupExactRestoreError.missingModelContext,
            persistenceError: TodoBackupExactRestoreError.persistenceFailed,
            invalidCalendarDateError: { TodoBackupExactRestoreError.invalidCalendarDate($0) }
        )
    }
}
