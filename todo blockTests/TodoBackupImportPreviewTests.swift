//
//  TodoBackupImportPreviewTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/8/26.
//

import XCTest
@testable import todo_block

@MainActor
final class TodoBackupImportPreviewTests: XCTestCase {

    func testPreviewClassifiesMerge() throws {
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)

        let updateID = UUID()
        let localWinsID = UUID()
        let tieID = UUID()
        let unchangedID = UUID()
        let additionID = UUID()

        let localSnapshot = TodoBackupLocalSnapshot(
            items: [
                backupItem(
                    id: updateID,
                    title: "old title",
                    updatedAt: baseTime,
                    dayDate: date
                ),
                backupItem(
                    id: localWinsID,
                    title: "local newer",
                    updatedAt: baseTime.addingTimeInterval(30),
                    dayDate: date
                ),
                backupItem(
                    id: tieID,
                    title: "local tie",
                    updatedAt: baseTime.addingTimeInterval(40),
                    dayDate: date
                ),
                backupItem(
                    id: unchangedID,
                    title: "same",
                    updatedAt: baseTime.addingTimeInterval(50),
                    dayDate: date
                )
            ],
            daySections: []
        )
        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(100),
            items: [
                backupItem(
                    id: updateID,
                    title: "imported newer",
                    updatedAt: baseTime.addingTimeInterval(20),
                    dayDate: date
                ),
                backupItem(
                    id: localWinsID,
                    title: "imported older",
                    updatedAt: baseTime.addingTimeInterval(10),
                    dayDate: date
                ),
                backupItem(
                    id: tieID,
                    title: "different at same time",
                    updatedAt: baseTime.addingTimeInterval(40),
                    dayDate: date
                ),
                backupItem(
                    id: unchangedID,
                    title: "same",
                    updatedAt: baseTime.addingTimeInterval(50),
                    dayDate: date
                ),
                backupItem(
                    id: additionID,
                    title: "new item",
                    updatedAt: baseTime.addingTimeInterval(60),
                    dayDate: date
                )
            ],
            daySections: []
        )

        let plan = try TodoBackupImportPlanner.makePlan(
            document: document,
            localSnapshot: localSnapshot
        )

        XCTAssertEqual(plan.additions.map(\.id), [additionID])
        XCTAssertEqual(plan.updates.map(\.id), [updateID])
        XCTAssertEqual(Set(plan.keptLocal.map(\.id)), Set([localWinsID, tieID]))
        XCTAssertEqual(plan.unchangedItemIDs, [unchangedID])
        XCTAssertEqual(
            plan.keptLocal.first { $0.id == localWinsID }?.reason,
            .localNewer
        )
        XCTAssertEqual(
            plan.keptLocal.first { $0.id == tieID }?.reason,
            .equalTimestampConflict
        )

        let previewContent = plan.previewContent
        XCTAssertEqual(previewContent.additionCount, 1)
        XCTAssertEqual(previewContent.unchangedCount, 1)
        XCTAssertEqual(previewContent.itemUpdates.map(\.id), [updateID])
        XCTAssertEqual(
            Set(previewContent.itemsKeptLocal.map(\.id)),
            Set([localWinsID, tieID])
        )
    }

    func testSameContentWithDifferentIdentityIsStillAnAddition() throws {
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let updatedAt = Date(timeIntervalSince1970: 1_787_000_000)
        let localSnapshot = TodoBackupLocalSnapshot(
            items: [
                backupItem(
                    id: UUID(),
                    title: "same content",
                    updatedAt: updatedAt,
                    dayDate: date
                )
            ],
            daySections: []
        )
        let importedID = UUID()
        let document = TodoBackupDocument(
            exportedAt: updatedAt,
            items: [
                backupItem(
                    id: importedID,
                    title: "same content",
                    updatedAt: updatedAt,
                    dayDate: date
                )
            ],
            daySections: []
        )

        let plan = try TodoBackupImportPlanner.makePlan(
            document: document,
            localSnapshot: localSnapshot
        )

        XCTAssertEqual(plan.additions.map(\.id), [importedID])
    }

    func testEmptyBackupCountsLocalOnlyTodoAndDaySection() throws {
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let updatedAt = Date(timeIntervalSince1970: 1_787_000_000)
        let local = TodoBackupItem(
            id: UUID(),
            title: "keep local",
            isCompleted: false,
            indentLevel: 0,
            sortOrder: 10,
            containerKind: .scheduled,
            dayDate: date,
            createdAt: updatedAt.addingTimeInterval(-100),
            updatedAt: updatedAt
        )
        let localSnapshot = TodoBackupLocalSnapshot(
            items: [local],
            daySections: [
                TodoBackupDaySection(
                    id: UUID(),
                    date: date,
                    title: "Local day",
                    sortOrder: 1,
                    createdAt: updatedAt.addingTimeInterval(-100),
                    updatedAt: updatedAt
                )
            ]
        )
        let document = TodoBackupDocument(
            exportedAt: updatedAt,
            items: [],
            daySections: []
        )

        let plan = try TodoBackupImportPlanner.makePlan(
            document: document,
            localSnapshot: localSnapshot
        )

        XCTAssertEqual(plan.localOnlyItemIDs, [local.id])
        XCTAssertEqual(plan.localOnlyDaySectionDates, [date])
        XCTAssertEqual(plan.previewKeptLocalCount, 2)
        XCTAssertTrue(plan.keptLocal.isEmpty)
        XCTAssertTrue(plan.daySectionsKeptLocal.isEmpty)

        let previewContent = plan.previewContent
        XCTAssertEqual(previewContent.keptLocalCount, 2)
        XCTAssertFalse(previewContent.hasReviewDetails)
    }

    func testDaySectionsMergeByCalendarDateRatherThanPersistedID() throws {
        let backupDate = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let localSectionID = UUID()
        let importedSectionID = UUID()

        let localItem = TodoBackupItem(
            id: UUID(),
            title: "scheduled",
            isCompleted: false,
            indentLevel: 0,
            sortOrder: 10,
            containerKind: .scheduled,
            dayDate: backupDate,
            createdAt: baseTime,
            updatedAt: baseTime
        )
        let localSection = TodoBackupDaySection(
            id: localSectionID,
            date: backupDate,
            title: "Local title",
            sortOrder: 1,
            createdAt: baseTime,
            updatedAt: baseTime
        )
        let localSnapshot = TodoBackupLocalSnapshot(
            items: [localItem],
            daySections: [localSection]
        )
        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(100),
            items: [localItem],
            daySections: [
                TodoBackupDaySection(
                    id: importedSectionID,
                    date: backupDate,
                    title: "Imported newer title",
                    sortOrder: 2,
                    createdAt: baseTime,
                    updatedAt: baseTime.addingTimeInterval(20)
                )
            ]
        )

        let plan = try TodoBackupImportPlanner.makePlan(
            document: document,
            localSnapshot: localSnapshot
        )

        XCTAssertTrue(plan.daySectionAdditions.isEmpty)
        let change = try XCTUnwrap(plan.daySectionUpdates.first)
        XCTAssertEqual(change.local.id, localSectionID)
        XCTAssertEqual(change.imported.id, importedSectionID)
        XCTAssertEqual(change.imported.date, backupDate)
        XCTAssertEqual(plan.previewAdditionCount, 0)
        XCTAssertEqual(plan.previewUpdateCount, 1)
        XCTAssertEqual(plan.previewKeptLocalCount, 0)
        XCTAssertEqual(plan.previewUnchangedCount, 1)
        XCTAssertEqual(change.differences.map(\.fieldName), ["标题", "顺序", "更新时间"])
    }

    func testInvalidRecordRejectsWholePreview() throws {
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let updatedAt = Date(timeIntervalSince1970: 1_787_000_000)
        let localSnapshot = TodoBackupLocalSnapshot(
            items: [
                backupItem(
                    id: UUID(),
                    title: "local",
                    updatedAt: updatedAt,
                    dayDate: date
                )
            ],
            daySections: []
        )
        let invalid = TodoBackupItem(
            id: UUID(),
            title: "invalid indent",
            isCompleted: false,
            indentLevel: TodoItem.maxIndentLevel + 1,
            sortOrder: 1,
            containerKind: .longTermImportant,
            dayDate: date,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
        let document = TodoBackupDocument(
            exportedAt: updatedAt,
            items: [invalid],
            daySections: []
        )

        XCTAssertThrowsError(
            try TodoBackupImportPlanner.makePlan(
                document: document,
                localSnapshot: localSnapshot
            )
        )
    }

    func testFutureBackupVersionIsRejected() throws {
        let document = TodoBackupDocument(
            version: TodoBackupDocument.currentVersion + 1,
            exportedAt: Date(timeIntervalSince1970: 1_787_000_000),
            items: [],
            daySections: []
        )

        XCTAssertThrowsError(
            try TodoBackupImportPlanner.makePlan(
                document: document,
                localSnapshot: TodoBackupLocalSnapshot(items: [], daySections: [])
            )
        )
    }

    func testStructuralDifferencesAreFlaggedWhileNewerImportStillWins() throws {
        let localDate = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let importedDate = TodoBackupCalendarDate(year: 2026, month: 8, day: 27)
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let local = backupItem(
            id: UUID(),
            title: "same identity",
            updatedAt: baseTime,
            dayDate: localDate
        )
        let localSnapshot = TodoBackupLocalSnapshot(items: [local], daySections: [])
        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(200),
            items: [
                TodoBackupItem(
                    id: local.id,
                    title: local.title,
                    isCompleted: local.isCompleted,
                    indentLevel: 2,
                    sortOrder: 99,
                    containerKind: .longTermUrgent,
                    dayDate: importedDate,
                    createdAt: local.createdAt,
                    updatedAt: baseTime.addingTimeInterval(100)
                )
            ],
            daySections: []
        )

        let plan = try TodoBackupImportPlanner.makePlan(
            document: document,
            localSnapshot: localSnapshot
        )

        let change = try XCTUnwrap(plan.updates.first)
        XCTAssertTrue(change.hasStructuralDifference)
        XCTAssertEqual(change.reason, .importedNewer)
        XCTAssertEqual(
            Set(change.differences.map(\.fieldName)),
            Set(["层级", "顺序", "容器", "所属日期", "更新时间"])
        )
    }

    private func backupItem(
        id: UUID,
        title: String,
        updatedAt: Date,
        dayDate: TodoBackupCalendarDate
    ) -> TodoBackupItem {
        TodoBackupItem(
            id: id,
            title: title,
            isCompleted: false,
            indentLevel: 0,
            sortOrder: 10,
            containerKind: .longTermImportant,
            dayDate: dayDate,
            createdAt: updatedAt.addingTimeInterval(-100),
            updatedAt: updatedAt
        )
    }
}
