//
//  TodoBackupImportPreviewTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/8/26.
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoBackupImportPreviewTests: XCTestCase {
    private var modelContainer: ModelContainer?

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: configuration
        )
        modelContainer = container
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
    }

    override func tearDown() async throws {
        TodoStore.shared.reset()
        modelContainer = nil
    }

    func testPreviewClassifiesMergeWithoutMutatingLocalData() throws {
        let store = TodoStore.shared
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)

        let updateID = UUID()
        let localWinsID = UUID()
        let tieID = UUID()
        let unchangedID = UUID()
        let additionID = UUID()

        let updateLocal = try insertLocalItem(
            id: updateID,
            title: "old title",
            updatedAt: baseTime,
            dayDate: date
        )
        let localWins = try insertLocalItem(
            id: localWinsID,
            title: "local newer",
            updatedAt: baseTime.addingTimeInterval(30),
            dayDate: date
        )
        let tie = try insertLocalItem(
            id: tieID,
            title: "local tie",
            updatedAt: baseTime.addingTimeInterval(40),
            dayDate: date
        )
        let unchanged = try insertLocalItem(
            id: unchangedID,
            title: "same",
            updatedAt: baseTime.addingTimeInterval(50),
            dayDate: date
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

        let plan = try TodoBackupWorkflow.previewImport(
            data: TodoBackupCodec.encode(document),
            into: store
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

        XCTAssertEqual(updateLocal.title, "old title")
        XCTAssertEqual(localWins.title, "local newer")
        XCTAssertEqual(tie.title, "local tie")
        XCTAssertEqual(unchanged.title, "same")
        XCTAssertNil(store.todoItemsCache[additionID])
    }

    func testSameContentWithDifferentIdentityIsStillAnAddition() throws {
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let updatedAt = Date(timeIntervalSince1970: 1_787_000_000)
        _ = try insertLocalItem(
            id: UUID(),
            title: "same content",
            updatedAt: updatedAt,
            dayDate: date
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

        let plan = try TodoBackupWorkflow.previewImport(
            data: TodoBackupCodec.encode(document),
            into: TodoStore.shared
        )

        XCTAssertEqual(plan.additions.map(\.id), [importedID])
    }

    func testEmptyBackupCountsAndPreservesLocalOnlyTodoAndDaySection() throws {
        let store = TodoStore.shared
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(date.date())
        let local = store.createItem(title: "keep local", dayDate: localDate)
        XCTAssertTrue(store.flushPendingChangesSync())

        let document = TodoBackupDocument(
            exportedAt: Date(timeIntervalSince1970: 1_787_000_000),
            items: [],
            daySections: []
        )
        let plan = try TodoBackupWorkflow.previewImport(
            data: TodoBackupCodec.encode(document),
            into: store
        )

        XCTAssertEqual(plan.localOnlyItemIDs, [local.id])
        XCTAssertEqual(plan.localOnlyDaySectionDates, [date])
        XCTAssertEqual(plan.previewKeptLocalCount, 2)
        XCTAssertTrue(plan.keptLocal.isEmpty)
        XCTAssertTrue(plan.daySectionsKeptLocal.isEmpty)

        let previewContent = plan.previewContent
        XCTAssertEqual(previewContent.keptLocalCount, 2)
        XCTAssertFalse(previewContent.hasReviewDetails)

        let recoveryStore = TodoBackupRecoveryStore(
            directoryURL: URL.temporaryDirectory.appending(
                path: "recovery",
                directoryHint: .isDirectory
            )
        )
        XCTAssertEqual(
            try TodoBackupWorkflow.applyImport(
                plan: plan,
                into: store,
                recoveryStore: recoveryStore
            ),
            .noChanges
        )
        XCTAssertEqual(store.validTodoItems.map(\.id), [local.id])
        XCTAssertEqual(
            store.validDaySections.map { TodoBackupCalendarDate(date: $0.date) },
            [date]
        )
    }

    func testDaySectionsMergeByCalendarDateRatherThanPersistedID() throws {
        let store = TodoStore.shared
        let backupDate = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(backupDate.date())
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let itemID = UUID()
        let localSectionID = UUID()
        let importedSectionID = UUID()

        let localItem = TodoItem(
            id: itemID,
            title: "scheduled",
            isCompleted: false,
            indentLevel: 0,
            sortOrder: 10,
            containerKindRaw: TodoContainerKind.scheduled.rawValue,
            dayDate: localDate,
            createdAt: baseTime,
            updatedAt: baseTime
        )
        try insertLocalModel(localItem, id: itemID)

        let localSection = DaySection(
            id: localSectionID,
            date: localDate,
            title: "Local title",
            sortOrder: 1,
            createdAt: baseTime,
            updatedAt: baseTime
        )
        try insertLocalSection(localSection)

        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(100),
            items: [
                TodoBackupItem(
                    id: itemID,
                    title: "scheduled",
                    isCompleted: false,
                    indentLevel: 0,
                    sortOrder: 10,
                    containerKind: .scheduled,
                    dayDate: backupDate,
                    createdAt: baseTime,
                    updatedAt: baseTime
                )
            ],
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

        let plan = try TodoBackupWorkflow.previewImport(
            data: TodoBackupCodec.encode(document),
            into: store
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
        XCTAssertEqual(localSection.title, "Local title")
    }

    func testInvalidRecordRejectsWholePreviewWithoutMutation() throws {
        let store = TodoStore.shared
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let updatedAt = Date(timeIntervalSince1970: 1_787_000_000)
        let localID = UUID()
        let local = try insertLocalItem(
            id: localID,
            title: "local",
            updatedAt: updatedAt,
            dayDate: date
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
            try TodoBackupWorkflow.previewImport(
                data: TodoBackupCodec.encode(document),
                into: store
            )
        )
        XCTAssertEqual(local.title, "local")
        XCTAssertEqual(store.validTodoItems.map(\.id), [localID])
    }

    func testFutureBackupVersionIsRejectedWithoutMutation() throws {
        let store = TodoStore.shared
        let exportedAt = Date(timeIntervalSince1970: 1_787_000_000)
        let document = TodoBackupDocument(
            version: TodoBackupDocument.currentVersion + 1,
            exportedAt: exportedAt,
            items: [],
            daySections: []
        )

        XCTAssertThrowsError(
            try TodoBackupWorkflow.previewImport(
                data: TodoBackupCodec.encode(document),
                into: store
            )
        )
        XCTAssertTrue(store.validTodoItems.isEmpty)
        XCTAssertTrue(store.validDaySections.isEmpty)
    }

    func testMalformedFileIsRejectedWithoutMutation() throws {
        let store = TodoStore.shared
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let local = try insertLocalItem(
            id: UUID(),
            title: "keep local",
            updatedAt: Date(timeIntervalSince1970: 1_787_000_000),
            dayDate: date
        )

        XCTAssertThrowsError(
            try TodoBackupWorkflow.previewImport(
                data: Data(#"{"format":"todo-block-backup","version":1,"items":["#.utf8),
                into: store
            )
        )
        XCTAssertEqual(store.validTodoItems.map(\.id), [local.id])
        XCTAssertEqual(local.title, "keep local")
    }

    func testStructuralDifferencesAreFlaggedWhileNewerImportStillWins() throws {
        let store = TodoStore.shared
        let localDate = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let importedDate = TodoBackupCalendarDate(year: 2026, month: 8, day: 27)
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let local = try insertLocalItem(
            id: UUID(),
            title: "same identity",
            updatedAt: baseTime,
            dayDate: localDate
        )
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

        let plan = try TodoBackupWorkflow.previewImport(
            data: TodoBackupCodec.encode(document),
            into: store
        )

        let change = try XCTUnwrap(plan.updates.first)
        XCTAssertTrue(change.hasStructuralDifference)
        XCTAssertEqual(change.reason, .importedNewer)
        XCTAssertEqual(
            Set(change.differences.map(\.fieldName)),
            Set(["层级", "顺序", "容器", "所属日期", "更新时间"])
        )
    }

    private func insertLocalItem(
        id: UUID,
        title: String,
        updatedAt: Date,
        dayDate: TodoBackupCalendarDate
    ) throws -> TodoItem {
        let date = try XCTUnwrap(dayDate.date())
        let item = TodoItem(
            id: id,
            title: title,
            isCompleted: false,
            indentLevel: 0,
            sortOrder: 10,
            containerKindRaw: TodoContainerKind.longTermImportant.rawValue,
            dayDate: date,
            createdAt: updatedAt.addingTimeInterval(-100),
            updatedAt: updatedAt
        )
        try insertLocalModel(item, id: id)
        return item
    }

    private func insertLocalModel(_ item: TodoItem, id: UUID) throws {
        let context = try XCTUnwrap(TodoStore.shared.modelContext)
        context.insert(item)
        TodoStore.shared.todoItemsCache[id] = item
    }

    private func insertLocalSection(_ section: DaySection) throws {
        let context = try XCTUnwrap(TodoStore.shared.modelContext)
        context.insert(section)
        TodoStore.shared.daySectionsCache[section.id] = section
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
