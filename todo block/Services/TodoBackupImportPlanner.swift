//
//  TodoBackupImportPlanner.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import Foundation

enum TodoBackupValidationError: LocalizedError {
    case unsupportedFormat(String)
    case unsupportedVersion(Int)
    case duplicateTodoID(UUID)
    case duplicateDaySectionID(UUID)
    case duplicateDaySectionDate(TodoBackupCalendarDate)
    case invalidIndentLevel(UUID, Int)
    case invalidSortOrder(String)
    case missingDaySection(UUID, TodoBackupCalendarDate)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "这不是 Todo Block 全量备份：\(format)"
        case .unsupportedVersion(let version):
            "当前版本不支持备份格式版本 \(version)，请升级 Todo Block 后再导入。"
        case .duplicateTodoID(let id):
            "备份中存在重复待办身份：\(id.uuidString)"
        case .duplicateDaySectionID(let id):
            "备份中存在重复日期分组身份：\(id.uuidString)"
        case .duplicateDaySectionDate(let date):
            "备份中同一日期存在多个日期分组：\(date.canonicalString)"
        case .invalidIndentLevel(let id, let level):
            "待办 \(id.uuidString) 的层级 \(level) 超出允许范围。"
        case .invalidSortOrder(let description):
            "备份包含无效排序值：\(description)"
        case .missingDaySection(let id, let date):
            "计划待办 \(id.uuidString) 缺少对应日期分组：\(date.canonicalString)"
        }
    }
}

@MainActor
enum TodoBackupImportPlanner {
    static func makePlan(
        document: TodoBackupDocument,
        store: TodoStore,
        calendar: Calendar = .current
    ) throws -> TodoBackupMergePlan {
        try validate(document)

        let localItems = Dictionary(
            uniqueKeysWithValues: store.validTodoItems.map {
                ($0.id, TodoBackupWorkflow.snapshot(item: $0, calendar: calendar))
            }
        )

        var additions: [TodoBackupItem] = []
        var updates: [TodoBackupItemChange] = []
        var keptLocal: [TodoBackupItemChange] = []
        var unchangedItemIDs: [UUID] = []
        let importedItemIDs = Set(document.items.map(\.id))

        for imported in document.items {
            guard let local = localItems[imported.id] else {
                additions.append(imported)
                continue
            }

            guard local != imported else {
                unchangedItemIDs.append(imported.id)
                continue
            }

            let change = itemChange(local: local, imported: imported)
            if imported.updatedAt > local.updatedAt {
                updates.append(change)
            } else {
                keptLocal.append(change)
            }
        }

        let localOnlyItemIDs = localItems.keys
            .filter { importedItemIDs.contains($0) == false }
            .sorted { $0.uuidString < $1.uuidString }

        var localSectionsByDate: [TodoBackupCalendarDate: TodoBackupDaySection] = [:]
        for section in store.validDaySections {
            let snapshot = TodoBackupWorkflow.snapshot(section: section, calendar: calendar)
            if let existing = localSectionsByDate[snapshot.date] {
                if snapshot.updatedAt > existing.updatedAt
                    || (
                        snapshot.updatedAt == existing.updatedAt
                            && snapshot.id.uuidString < existing.id.uuidString
                    )
                {
                    localSectionsByDate[snapshot.date] = snapshot
                }
            } else {
                localSectionsByDate[snapshot.date] = snapshot
            }
        }

        var daySectionAdditions: [TodoBackupDaySection] = []
        var daySectionUpdates: [TodoBackupDaySectionChange] = []
        var daySectionsKeptLocal: [TodoBackupDaySectionChange] = []
        var unchangedDaySectionDates: [TodoBackupCalendarDate] = []
        let importedSectionDates = Set(document.daySections.map(\.date))

        for imported in document.daySections {
            guard let local = localSectionsByDate[imported.date] else {
                daySectionAdditions.append(imported)
                continue
            }

            if daySectionsAreSemanticallyEqual(local, imported) {
                unchangedDaySectionDates.append(imported.date)
                continue
            }

            let reason = mergeReason(local: local.updatedAt, imported: imported.updatedAt)
            let change = TodoBackupDaySectionChange(
                local: local,
                imported: imported,
                reason: reason,
                differences: daySectionDifferences(local: local, imported: imported)
            )
            if reason == .importedNewer {
                daySectionUpdates.append(change)
            } else {
                daySectionsKeptLocal.append(change)
            }
        }

        let localOnlyDaySectionDates = localSectionsByDate.keys
            .filter { importedSectionDates.contains($0) == false }
            .sorted { $0.canonicalString < $1.canonicalString }

        return TodoBackupMergePlan(
            sourceDocument: document,
            additions: additions,
            updates: updates,
            keptLocal: keptLocal,
            localOnlyItemIDs: localOnlyItemIDs,
            unchangedItemIDs: unchangedItemIDs,
            daySectionAdditions: daySectionAdditions,
            daySectionUpdates: daySectionUpdates,
            daySectionsKeptLocal: daySectionsKeptLocal,
            localOnlyDaySectionDates: localOnlyDaySectionDates,
            unchangedDaySectionDates: unchangedDaySectionDates
        )
    }

    static func validate(_ document: TodoBackupDocument) throws {
        guard document.format == TodoBackupDocument.formatIdentifier else {
            throw TodoBackupValidationError.unsupportedFormat(document.format)
        }
        guard document.version == TodoBackupDocument.currentVersion else {
            throw TodoBackupValidationError.unsupportedVersion(document.version)
        }

        var itemIDs = Set<UUID>()
        for item in document.items {
            guard itemIDs.insert(item.id).inserted else {
                throw TodoBackupValidationError.duplicateTodoID(item.id)
            }
            guard (0 ... TodoItem.maxIndentLevel).contains(item.indentLevel) else {
                throw TodoBackupValidationError.invalidIndentLevel(item.id, item.indentLevel)
            }
            guard item.sortOrder.isFinite else {
                throw TodoBackupValidationError.invalidSortOrder(item.id.uuidString)
            }
        }

        var sectionIDs = Set<UUID>()
        var sectionDates = Set<TodoBackupCalendarDate>()
        for section in document.daySections {
            guard sectionIDs.insert(section.id).inserted else {
                throw TodoBackupValidationError.duplicateDaySectionID(section.id)
            }
            guard sectionDates.insert(section.date).inserted else {
                throw TodoBackupValidationError.duplicateDaySectionDate(section.date)
            }
            guard section.sortOrder.isFinite else {
                throw TodoBackupValidationError.invalidSortOrder(section.date.canonicalString)
            }
        }

        for item in document.items where item.containerKind == .scheduled {
            guard sectionDates.contains(item.dayDate) else {
                throw TodoBackupValidationError.missingDaySection(item.id, item.dayDate)
            }
        }
    }

    private static func itemChange(
        local: TodoBackupItem,
        imported: TodoBackupItem
    ) -> TodoBackupItemChange {
        let reason = mergeReason(local: local.updatedAt, imported: imported.updatedAt)

        return TodoBackupItemChange(
            local: local,
            imported: imported,
            reason: reason,
            differences: itemDifferences(local: local, imported: imported),
            hasStructuralDifference: local.indentLevel != imported.indentLevel
                || local.sortOrder != imported.sortOrder
                || local.containerKind != imported.containerKind
                || local.dayDate != imported.dayDate
        )
    }

    /// 按 `updatedAt` 决定合并原因：导入较新采用导入，本地较新或时间戳相同都保留本地。
    private static func mergeReason(
        local: Date,
        imported: Date
    ) -> TodoBackupMergeReason {
        if imported > local {
            return .importedNewer
        } else if imported < local {
            return .localNewer
        } else {
            return .equalTimestampConflict
        }
    }

    private static func daySectionsAreSemanticallyEqual(
        _ lhs: TodoBackupDaySection,
        _ rhs: TodoBackupDaySection
    ) -> Bool {
        lhs.date == rhs.date
            && lhs.title == rhs.title
            && lhs.sortOrder == rhs.sortOrder
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
    }

    private static func itemDifferences(
        local: TodoBackupItem,
        imported: TodoBackupItem
    ) -> [TodoBackupFieldDifference] {
        var result: [TodoBackupFieldDifference] = []

        appendDifference(
            to: &result,
            fieldName: "标题",
            local: local.title,
            imported: imported.title
        )
        appendDifference(
            to: &result,
            fieldName: "完成状态",
            local: local.isCompleted ? "已完成" : "未完成",
            imported: imported.isCompleted ? "已完成" : "未完成"
        )
        appendDifference(
            to: &result,
            fieldName: "层级",
            local: local.indentLevel.formatted(),
            imported: imported.indentLevel.formatted()
        )
        appendDifference(
            to: &result,
            fieldName: "顺序",
            local: displaySortOrder(local.sortOrder),
            imported: displaySortOrder(imported.sortOrder)
        )
        appendDifference(
            to: &result,
            fieldName: "容器",
            local: local.containerKind.rawValue,
            imported: imported.containerKind.rawValue
        )
        appendDifference(
            to: &result,
            fieldName: "所属日期",
            local: local.dayDate.canonicalString,
            imported: imported.dayDate.canonicalString
        )
        appendDifference(
            to: &result,
            fieldName: "创建时间",
            local: local.createdAt.formatted(.iso8601),
            imported: imported.createdAt.formatted(.iso8601)
        )
        appendDifference(
            to: &result,
            fieldName: "更新时间",
            local: local.updatedAt.formatted(.iso8601),
            imported: imported.updatedAt.formatted(.iso8601)
        )

        return result
    }

    private static func appendDifference(
        to result: inout [TodoBackupFieldDifference],
        fieldName: String,
        local: String,
        imported: String
    ) {
        guard local != imported else { return }
        result.append(
            TodoBackupFieldDifference(
                fieldName: fieldName,
                localValue: local,
                importedValue: imported
            )
        )
    }

    private static func daySectionDifferences(
        local: TodoBackupDaySection,
        imported: TodoBackupDaySection
    ) -> [TodoBackupFieldDifference] {
        var result: [TodoBackupFieldDifference] = []

        appendDifference(
            to: &result,
            fieldName: "标题",
            local: local.title,
            imported: imported.title
        )
        appendDifference(
            to: &result,
            fieldName: "顺序",
            local: displaySortOrder(local.sortOrder),
            imported: displaySortOrder(imported.sortOrder)
        )
        appendDifference(
            to: &result,
            fieldName: "创建时间",
            local: local.createdAt.formatted(.iso8601),
            imported: imported.createdAt.formatted(.iso8601)
        )
        appendDifference(
            to: &result,
            fieldName: "更新时间",
            local: local.updatedAt.formatted(.iso8601),
            imported: imported.updatedAt.formatted(.iso8601)
        )

        return result
    }

    private static func displaySortOrder(_ value: Double) -> String {
        value.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0 ... 6))
        )
    }
}
