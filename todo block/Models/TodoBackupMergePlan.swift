//
//  TodoBackupMergePlan.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import Foundation

enum TodoBackupMergeReason: Equatable, Sendable {
    case importedNewer
    case localNewer
    case equalTimestampConflict

    var displayText: String {
        switch self {
        case .importedNewer:
            "导入版本更新时间较新"
        case .localNewer:
            "本地版本更新时间较新"
        case .equalTimestampConflict:
            "更新时间相同但内容不同，保留本地"
        }
    }
}

struct TodoBackupFieldDifference: Equatable, Identifiable, Sendable {
    let fieldName: String
    let localValue: String
    let importedValue: String

    var id: String { fieldName }
}

struct TodoBackupItemChange: Equatable, Identifiable, Sendable {
    let local: TodoBackupItem
    let imported: TodoBackupItem
    let reason: TodoBackupMergeReason
    let differences: [TodoBackupFieldDifference]
    let hasStructuralDifference: Bool

    var id: UUID { imported.id }
}

struct TodoBackupDaySectionChange: Equatable, Identifiable, Sendable {
    let local: TodoBackupDaySection
    let imported: TodoBackupDaySection
    let reason: TodoBackupMergeReason
    let differences: [TodoBackupFieldDifference]

    var id: TodoBackupCalendarDate { imported.date }
}

struct TodoBackupMergePlan: Equatable, Sendable {
    let sourceDocument: TodoBackupDocument

    let additions: [TodoBackupItem]
    let updates: [TodoBackupItemChange]
    let keptLocal: [TodoBackupItemChange]
    let localOnlyItemIDs: [UUID]
    let unchangedItemIDs: [UUID]

    let daySectionAdditions: [TodoBackupDaySection]
    let daySectionUpdates: [TodoBackupDaySectionChange]
    let daySectionsKeptLocal: [TodoBackupDaySectionChange]
    let localOnlyDaySectionDates: [TodoBackupCalendarDate]
    let unchangedDaySectionDates: [TodoBackupCalendarDate]

    var additionCount: Int { additions.count }
    var updateCount: Int { updates.count }

    var previewAdditionCount: Int { additions.count + daySectionAdditions.count }
    var previewUpdateCount: Int { updates.count + daySectionUpdates.count }
    var previewKeptLocalCount: Int {
        keptLocal.count
            + localOnlyItemIDs.count
            + daySectionsKeptLocal.count
            + localOnlyDaySectionDates.count
    }
    var previewUnchangedCount: Int {
        unchangedItemIDs.count + unchangedDaySectionDates.count
    }

    var previewContent: TodoBackupImportPreviewContent {
        TodoBackupImportPreviewContent(
            additionCount: previewAdditionCount,
            keptLocalCount: previewKeptLocalCount,
            unchangedCount: previewUnchangedCount,
            itemUpdates: updates,
            itemsKeptLocal: keptLocal,
            daySectionUpdates: daySectionUpdates,
            daySectionsKeptLocal: daySectionsKeptLocal
        )
    }

    var hasDataChanges: Bool {
        additions.isEmpty == false
            || updates.isEmpty == false
            || daySectionAdditions.isEmpty == false
            || daySectionUpdates.isEmpty == false
    }
}

struct TodoBackupImportPreviewContent: Equatable, Sendable {
    let additionCount: Int
    let keptLocalCount: Int
    let unchangedCount: Int
    let itemUpdates: [TodoBackupItemChange]
    let itemsKeptLocal: [TodoBackupItemChange]
    let daySectionUpdates: [TodoBackupDaySectionChange]
    let daySectionsKeptLocal: [TodoBackupDaySectionChange]

    var updateCount: Int {
        itemUpdates.count + daySectionUpdates.count
    }

    var hasTodoDetails: Bool {
        itemUpdates.isEmpty == false || itemsKeptLocal.isEmpty == false
    }

    var hasDaySectionDetails: Bool {
        daySectionUpdates.isEmpty == false || daySectionsKeptLocal.isEmpty == false
    }

    var hasReviewDetails: Bool {
        hasTodoDetails || hasDaySectionDetails
    }
}
