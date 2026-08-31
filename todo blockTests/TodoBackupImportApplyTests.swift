//
//  TodoBackupImportApplyTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/8/26.
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoBackupImportApplyTests: XCTestCase {
    private enum SimulatedSaveFailure: Error {
        case unavailable
    }

    private var modelContainer: ModelContainer?
    private var temporaryDirectory: URL?

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            TodoBackupConsumptionState.self,
            configurations: configuration
        )
        modelContainer = container
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)

        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        temporaryDirectory = directory
    }

    override func tearDown() async throws {
        TodoStore.shared.reset()
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        modelContainer = nil
    }

    func testConfirmedImportAppliesPlanPreservesTimestampsAndCreatesRecoveryPoint() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(date.date())
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)

        let existing = store.createItem(title: "local", dayDate: localDate)
        existing.createdAt = baseTime.addingTimeInterval(-100)
        existing.updatedAt = baseTime
        XCTAssertTrue(store.flushPendingChangesSync())
        XCTAssertTrue(store.canUndo)

        let importedCreatedAt = baseTime.addingTimeInterval(-200)
        let importedUpdatedAt = baseTime.addingTimeInterval(100)
        let addedID = UUID()
        let localSection = try XCTUnwrap(store.validDaySections.first)
        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(200),
            items: [
                TodoBackupItem(
                    id: existing.id,
                    title: "imported newer",
                    isCompleted: true,
                    indentLevel: 1,
                    sortOrder: 20,
                    containerKind: .scheduled,
                    dayDate: date,
                    createdAt: importedCreatedAt,
                    updatedAt: importedUpdatedAt
                ),
                TodoBackupItem(
                    id: addedID,
                    title: "added",
                    isCompleted: false,
                    indentLevel: 0,
                    sortOrder: 30,
                    containerKind: .scheduled,
                    dayDate: date,
                    createdAt: importedCreatedAt.addingTimeInterval(10),
                    updatedAt: importedUpdatedAt.addingTimeInterval(10)
                )
            ],
            daySections: [
                TodoBackupDaySection(
                    id: UUID(),
                    date: date,
                    title: "Imported day",
                    sortOrder: localSection.sortOrder,
                    createdAt: localSection.createdAt,
                    updatedAt: importedUpdatedAt
                )
            ]
        )
        let plan = try TodoBackupImportPlanner.makePlan(document: document, store: store)

        let result = try TodoBackupWorkflow.applyImport(
            plan: plan,
            into: store,
            recoveryStore: recoveryStore
        )

        XCTAssertEqual(result, .applied)
        let updated = try XCTUnwrap(store.todoItemsCache[existing.id])
        XCTAssertEqual(updated.title, "imported newer")
        XCTAssertTrue(updated.isCompleted)
        XCTAssertEqual(updated.indentLevel, 1)
        XCTAssertEqual(updated.sortOrder, 20)
        XCTAssertEqual(updated.createdAt, importedCreatedAt)
        XCTAssertEqual(updated.updatedAt, importedUpdatedAt)

        let added = try XCTUnwrap(store.todoItemsCache[addedID])
        XCTAssertEqual(added.id, addedID)
        XCTAssertEqual(added.createdAt, importedCreatedAt.addingTimeInterval(10))
        XCTAssertEqual(added.updatedAt, importedUpdatedAt.addingTimeInterval(10))
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(store.canRedo)
        XCTAssertTrue(recoveryStore.hasRecoveryPoint)

        let checkpoint = try recoveryStore.loadRecoveryPoint()
        let checkpointExisting = try XCTUnwrap(checkpoint.items.first { $0.id == existing.id })
        XCTAssertEqual(checkpointExisting.title, "local")
        XCTAssertNil(checkpoint.items.first { $0.id == addedID })
    }

    func testConfirmedImportCreatesRestorableRecoveryPointWhenDirectoryContainsSpaces() throws {
        let store = TodoStore.shared
        let root = try XCTUnwrap(temporaryDirectory)
        let recoveryStore = TodoBackupRecoveryStore(
            directoryURL: root.appending(
                path: "Application Support/BackupRecovery",
                directoryHint: .isDirectory
            )
        )
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(date.date())
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let local = store.createItem(title: "before import", dayDate: localDate)
        local.updatedAt = baseTime
        XCTAssertTrue(store.flushPendingChangesSync())

        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(200),
            items: [
                TodoBackupItem(
                    id: local.id,
                    title: "after import",
                    isCompleted: false,
                    indentLevel: local.indentLevel,
                    sortOrder: local.sortOrder,
                    containerKind: local.containerKind,
                    dayDate: date,
                    createdAt: local.createdAt,
                    updatedAt: baseTime.addingTimeInterval(100)
                )
            ],
            daySections: store.validDaySections.map { TodoBackupWorkflow.snapshot(section: $0) }
        )
        let plan = try TodoBackupImportPlanner.makePlan(document: document, store: store)

        XCTAssertEqual(
            try TodoBackupWorkflow.applyImport(
                plan: plan,
                into: store,
                recoveryStore: recoveryStore
            ),
            .applied
        )
        XCTAssertTrue(recoveryStore.hasRecoveryPoint)
        XCTAssertEqual(try recoveryStore.loadRecoveryPoint().items.first?.title, "before import")
    }

    func testUnsavedPersistenceFailureBlocksImportBeforeCreatingRecoveryPoint() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        store.saveStatus = .unsaved
        let plan = try emptyPlan(store: store)

        XCTAssertThrowsError(
            try TodoBackupWorkflow.applyImport(
                plan: plan,
                into: store,
                recoveryStore: recoveryStore
            )
        )
        XCTAssertFalse(recoveryStore.hasRecoveryPoint)
        XCTAssertEqual(store.saveStatus, .unsaved)
    }

    func testQueuedLocalSaveIsFlushedBeforeImportCreatesRecoveryPoint() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(date.date())
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let local = store.createItem(title: "queued local", dayDate: localDate)
        local.updatedAt = baseTime
        XCTAssertEqual(store.saveStatus, .queued)

        var saveCount = 0
        store.saveAction = { context in
            saveCount += 1
            try context.save()
        }
        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(200),
            items: [
                TodoBackupItem(
                    id: local.id,
                    title: "imported after flush",
                    isCompleted: false,
                    indentLevel: 0,
                    sortOrder: local.sortOrder,
                    containerKind: .scheduled,
                    dayDate: date,
                    createdAt: local.createdAt,
                    updatedAt: baseTime.addingTimeInterval(100)
                )
            ],
            daySections: store.validDaySections.map { TodoBackupWorkflow.snapshot(section: $0) }
        )
        let plan = try TodoBackupImportPlanner.makePlan(document: document, store: store)

        XCTAssertEqual(
            try TodoBackupWorkflow.applyImport(
                plan: plan,
                into: store,
                recoveryStore: recoveryStore
            ),
            .applied
        )

        XCTAssertEqual(saveCount, 2)
        XCTAssertEqual(store.todoItemsCache[local.id]?.title, "imported after flush")
        XCTAssertEqual(try recoveryStore.loadRecoveryPoint().items.first?.title, "queued local")
    }

    func testRecoveryPointCreationFailureBlocksImportBeforeMutation() throws {
        let store = TodoStore.shared
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(date.date())
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let local = store.createItem(title: "local", dayDate: localDate)
        local.updatedAt = baseTime
        XCTAssertTrue(store.flushPendingChangesSync())

        let blockedDirectory = try XCTUnwrap(temporaryDirectory)
        try Data("not a directory".utf8).write(to: blockedDirectory)
        let recoveryStore = TodoBackupRecoveryStore(directoryURL: blockedDirectory)
        let document = TodoBackupDocument(
            exportedAt: baseTime,
            items: [
                TodoBackupItem(
                    id: local.id,
                    title: "should not apply",
                    isCompleted: false,
                    indentLevel: 0,
                    sortOrder: local.sortOrder,
                    containerKind: .scheduled,
                    dayDate: date,
                    createdAt: local.createdAt,
                    updatedAt: baseTime.addingTimeInterval(100)
                )
            ],
            daySections: store.validDaySections.map { TodoBackupWorkflow.snapshot(section: $0) }
        )
        let plan = try TodoBackupImportPlanner.makePlan(document: document, store: store)

        XCTAssertThrowsError(
            try TodoBackupWorkflow.applyImport(
                plan: plan,
                into: store,
                recoveryStore: recoveryStore
            )
        )
        XCTAssertEqual(local.title, "local")
    }

    func testSaveFailureRollsBackAllImportedChangesAndPreservesPreviousRecoveryPoint() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(date.date())
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let local = store.createItem(title: "before", dayDate: localDate)
        local.updatedAt = baseTime
        XCTAssertTrue(store.flushPendingChangesSync())

        let olderCheckpoint = TodoBackupWorkflow.makeExportDocument(
            from: store,
            exportedAt: baseTime.addingTimeInterval(-100)
        )
        try recoveryStore.stage(olderCheckpoint)
        try recoveryStore.promoteStaged()

        let addedID = UUID()
        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(200),
            items: [
                TodoBackupItem(
                    id: local.id,
                    title: "after",
                    isCompleted: false,
                    indentLevel: 0,
                    sortOrder: local.sortOrder,
                    containerKind: .scheduled,
                    dayDate: date,
                    createdAt: local.createdAt,
                    updatedAt: baseTime.addingTimeInterval(100)
                ),
                TodoBackupItem(
                    id: addedID,
                    title: "new",
                    isCompleted: false,
                    indentLevel: 0,
                    sortOrder: local.sortOrder + 1,
                    containerKind: .scheduled,
                    dayDate: date,
                    createdAt: baseTime,
                    updatedAt: baseTime.addingTimeInterval(100)
                )
            ],
            daySections: store.validDaySections.map { TodoBackupWorkflow.snapshot(section: $0) }
        )
        let plan = try TodoBackupImportPlanner.makePlan(document: document, store: store)

        store.saveAction = { _ in throw SimulatedSaveFailure.unavailable }

        XCTAssertThrowsError(
            try TodoBackupWorkflow.applyImport(
                plan: plan,
                into: store,
                recoveryStore: recoveryStore
            )
        )
        XCTAssertEqual(store.todoItemsCache[local.id]?.title, "before")
        XCTAssertNil(store.todoItemsCache[addedID])
        XCTAssertEqual(store.saveStatus, .saved)

        let retainedCheckpoint = try recoveryStore.loadRecoveryPoint()
        XCTAssertEqual(retainedCheckpoint, olderCheckpoint)
    }

    func testFailedImportWithCleanupFailureThenOrdinaryEditAndRestartPreservesPreviousRecoveryPoint() throws {
        let store = TodoStore.shared
        let recoveryDirectory = try XCTUnwrap(temporaryDirectory).appending(
            path: "recovery",
            directoryHint: .isDirectory
        )
        let recoveryStore = TodoBackupRecoveryStore(
            directoryURL: recoveryDirectory,
            discardStagedOverride: {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o500],
                    ofItemAtPath: recoveryDirectory.path()
                )
                return false
            }
        )
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(date.date())
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let local = store.createItem(title: "before", dayDate: localDate)
        local.updatedAt = baseTime
        XCTAssertTrue(store.flushPendingChangesSync())

        let previousCheckpoint = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(-100),
            items: [
                TodoBackupItem(
                    id: local.id,
                    title: "older recovery",
                    isCompleted: false,
                    indentLevel: local.indentLevel,
                    sortOrder: local.sortOrder,
                    containerKind: local.containerKind,
                    dayDate: date,
                    createdAt: local.createdAt,
                    updatedAt: baseTime.addingTimeInterval(-100)
                )
            ],
            daySections: []
        )
        try recoveryStore.stage(previousCheckpoint)
        try recoveryStore.promoteStaged()

        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(200),
            items: [
                TodoBackupItem(
                    id: local.id,
                    title: "imported",
                    isCompleted: false,
                    indentLevel: local.indentLevel,
                    sortOrder: local.sortOrder,
                    containerKind: local.containerKind,
                    dayDate: date,
                    createdAt: local.createdAt,
                    updatedAt: baseTime.addingTimeInterval(100)
                )
            ],
            daySections: store.validDaySections.map { TodoBackupWorkflow.snapshot(section: $0) }
        )
        let plan = try TodoBackupImportPlanner.makePlan(document: document, store: store)

        store.saveAction = { _ in throw SimulatedSaveFailure.unavailable }

        XCTAssertThrowsError(
            try TodoBackupWorkflow.applyImport(
                plan: plan,
                into: store,
                recoveryStore: recoveryStore
            )
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: recoveryDirectory.path()
        )
        store.saveAction = nil

        let ordinary = store.createItem(title: "ordinary edit", dayDate: localDate)
        XCTAssertTrue(store.flushPendingChangesSync())
        XCTAssertEqual(ordinary.title, "ordinary edit")

        let restartedRecoveryStore = TodoBackupRecoveryStore(directoryURL: recoveryDirectory)
        let currentDocument = TodoBackupWorkflow.makeExportDocument(from: store)
        try restartedRecoveryStore.reconcileInterruptedImport(currentDocument: currentDocument)

        XCTAssertEqual(
            try restartedRecoveryStore.loadRecoveryPoint(),
            previousCheckpoint,
            "失败导入遗留的 pending 不得在重启时覆盖旧恢复点"
        )
    }

    func testFailedImportCannotResurrectCheckpointFromCompletedRestore() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(date.date())
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let local = store.createItem(title: "restored data", dayDate: localDate)
        local.updatedAt = baseTime
        XCTAssertTrue(store.flushPendingChangesSync())

        let consumedCheckpoint = TodoBackupWorkflow.makeExportDocument(from: store)
        try recoveryStore.stage(consumedCheckpoint)
        try recoveryStore.promoteStaged()
        let token = try recoveryStore.stageConsumption()
        let modelContext = try XCTUnwrap(store.modelContext)
        modelContext.autosaveEnabled = false
        try recoveryStore.stageConsumptionState(token: token, in: modelContext)
        try modelContext.save()
        modelContext.autosaveEnabled = true
        XCTAssertFalse(recoveryStore.hasRecoveryPoint)

        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(200),
            items: [
                TodoBackupItem(
                    id: local.id,
                    title: "failed import",
                    isCompleted: false,
                    indentLevel: local.indentLevel,
                    sortOrder: local.sortOrder,
                    containerKind: local.containerKind,
                    dayDate: date,
                    createdAt: local.createdAt,
                    updatedAt: baseTime.addingTimeInterval(100)
                )
            ],
            daySections: store.validDaySections.map { TodoBackupWorkflow.snapshot(section: $0) }
        )
        let plan = try TodoBackupImportPlanner.makePlan(document: document, store: store)
        store.saveAction = { _ in throw SimulatedSaveFailure.unavailable }

        XCTAssertThrowsError(
            try TodoBackupWorkflow.applyImport(
                plan: plan,
                into: store,
                recoveryStore: recoveryStore
            )
        )

        XCTAssertEqual(store.todoItemsCache[local.id]?.title, "restored data")
        XCTAssertFalse(recoveryStore.hasRecoveryPoint)
        XCTAssertThrowsError(
            try TodoBackupWorkflow.restoreLatestImportCheckpoint(
                into: store,
                recoveryStore: recoveryStore
            )
        )
    }

    func testSecondIdenticalImportIsNoOpAndDoesNotReplaceRecoveryPoint() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let date = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let localDate = try XCTUnwrap(date.date())
        let baseTime = Date(timeIntervalSince1970: 1_787_000_000)
        let local = store.createItem(title: "before", dayDate: localDate)
        local.updatedAt = baseTime
        XCTAssertTrue(store.flushPendingChangesSync())

        let document = TodoBackupDocument(
            exportedAt: baseTime.addingTimeInterval(100),
            items: [
                TodoBackupItem(
                    id: local.id,
                    title: "after",
                    isCompleted: false,
                    indentLevel: 0,
                    sortOrder: local.sortOrder,
                    containerKind: .scheduled,
                    dayDate: date,
                    createdAt: local.createdAt,
                    updatedAt: baseTime.addingTimeInterval(50)
                )
            ],
            daySections: store.validDaySections.map { TodoBackupWorkflow.snapshot(section: $0) }
        )

        let firstPlan = try TodoBackupImportPlanner.makePlan(document: document, store: store)
        XCTAssertEqual(
            try TodoBackupWorkflow.applyImport(
                plan: firstPlan,
                into: store,
                recoveryStore: recoveryStore
            ),
            .applied
        )
        let firstCheckpoint = try recoveryStore.loadRecoveryPoint()
        XCTAssertEqual(firstCheckpoint.items.first?.title, "before")

        let secondPlan = try TodoBackupImportPlanner.makePlan(document: document, store: store)
        XCTAssertEqual(
            try TodoBackupWorkflow.applyImport(
                plan: secondPlan,
                into: store,
                recoveryStore: recoveryStore
            ),
            .noChanges
        )
        XCTAssertEqual(try recoveryStore.loadRecoveryPoint(), firstCheckpoint)
    }

    private func makeRecoveryStore() throws -> TodoBackupRecoveryStore {
        let root = try XCTUnwrap(temporaryDirectory)
        return TodoBackupRecoveryStore(
            directoryURL: root.appending(path: "recovery", directoryHint: .isDirectory)
        )
    }

    private func emptyPlan(store: TodoStore) throws -> TodoBackupMergePlan {
        let document = TodoBackupWorkflow.makeExportDocument(from: store)
        return try TodoBackupImportPlanner.makePlan(document: document, store: store)
    }
}
