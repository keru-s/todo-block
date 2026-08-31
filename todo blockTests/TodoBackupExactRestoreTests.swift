//
//  TodoBackupExactRestoreTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/8/26.
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoBackupExactRestoreTests: XCTestCase {
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
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    override func tearDown() async throws {
        TodoStore.shared.reset()
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        modelContainer = nil
    }

    func testExactRestoreReturnsDatasetToCheckpointAndConsumesRecoveryPoint() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let checkpointDate = try makeDate(year: 2026, month: 8, day: 26)
        let original = store.createItem(title: "before import", dayDate: checkpointDate)
        original.isCompleted = false
        original.indentLevel = 1
        original.sortOrder = 42
        original.createdAt = Date(timeIntervalSince1970: 1_786_000_000)
        original.updatedAt = Date(timeIntervalSince1970: 1_787_000_000)
        let originalSection = try XCTUnwrap(store.validDaySections.first)
        originalSection.title = "Original day"
        originalSection.sortOrder = 9
        XCTAssertTrue(store.flushPendingChangesSync())

        let checkpoint = TodoBackupWorkflow.makeExportDocument(
            from: store,
            exportedAt: Date(timeIntervalSince1970: 1_787_100_000)
        )
        try recoveryStore.stage(checkpoint)
        try recoveryStore.promoteStaged()

        original.title = "edited after import"
        original.isCompleted = true
        original.indentLevel = 3
        original.sortOrder = 999
        original.updatedAt = Date(timeIntervalSince1970: 1_787_200_000)
        originalSection.title = "Changed day"
        originalSection.sortOrder = 100
        let extra = store.createItem(title: "created after import", dayDate: checkpointDate)
        XCTAssertTrue(store.flushPendingChangesSync())
        XCTAssertTrue(store.canUndo)

        try TodoBackupWorkflow.restoreLatestImportCheckpoint(
            into: store,
            recoveryStore: recoveryStore
        )

        XCTAssertEqual(store.validTodoItems.count, 1)
        let restored = try XCTUnwrap(store.todoItemsCache[original.id])
        XCTAssertEqual(restored.title, "before import")
        XCTAssertFalse(restored.isCompleted)
        XCTAssertEqual(restored.indentLevel, 1)
        XCTAssertEqual(restored.sortOrder, 42)
        XCTAssertEqual(restored.createdAt, Date(timeIntervalSince1970: 1_786_000_000))
        XCTAssertEqual(restored.updatedAt, Date(timeIntervalSince1970: 1_787_000_000))
        XCTAssertNil(store.todoItemsCache[extra.id])

        XCTAssertEqual(store.validDaySections.count, 1)
        let restoredSection = try XCTUnwrap(store.daySectionsCache[originalSection.id])
        XCTAssertEqual(restoredSection.title, "Original day")
        XCTAssertEqual(restoredSection.sortOrder, 9)
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(store.canRedo)
        XCTAssertFalse(recoveryStore.hasRecoveryPoint)
    }

    func testExactRestoreRecreatesCheckpointObjectsDeletedAfterImport() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let checkpointDate = try makeDate(year: 2026, month: 8, day: 26)
        let laterDate = try makeDate(year: 2026, month: 8, day: 27)
        let original = store.createItem(title: "must return", dayDate: checkpointDate)
        original.createdAt = Date(timeIntervalSince1970: 1_786_000_000)
        original.updatedAt = Date(timeIntervalSince1970: 1_787_000_000)
        let originalSection = try XCTUnwrap(store.validDaySections.first)
        originalSection.title = "Must return day"
        originalSection.createdAt = Date(timeIntervalSince1970: 1_785_000_000)
        originalSection.updatedAt = Date(timeIntervalSince1970: 1_787_000_100)
        XCTAssertTrue(store.flushPendingChangesSync())

        let checkpoint = TodoBackupWorkflow.makeExportDocument(from: store)
        try recoveryStore.stage(checkpoint)
        try recoveryStore.promoteStaged()

        store.deleteItem(original)
        let postCheckpoint = store.createItem(title: "must disappear", dayDate: laterDate)
        XCTAssertTrue(store.flushPendingChangesSync())
        XCTAssertNil(store.todoItemsCache[original.id])
        XCTAssertNil(store.daySectionsCache[originalSection.id])

        try TodoBackupWorkflow.restoreLatestImportCheckpoint(
            into: store,
            recoveryStore: recoveryStore
        )

        let restored = try XCTUnwrap(store.todoItemsCache[original.id])
        XCTAssertEqual(restored.title, "must return")
        XCTAssertEqual(restored.createdAt, Date(timeIntervalSince1970: 1_786_000_000))
        XCTAssertEqual(restored.updatedAt, Date(timeIntervalSince1970: 1_787_000_000))
        let restoredSection = try XCTUnwrap(store.daySectionsCache[originalSection.id])
        XCTAssertEqual(restoredSection.title, "Must return day")
        XCTAssertEqual(
            restoredSection.createdAt,
            Date(timeIntervalSince1970: 1_785_000_000)
        )
        XCTAssertEqual(
            restoredSection.updatedAt,
            Date(timeIntervalSince1970: 1_787_000_100)
        )
        XCTAssertNil(store.todoItemsCache[postCheckpoint.id])
        XCTAssertEqual(
            TodoBackupWorkflow.makeExportDocument(from: store).items,
            checkpoint.items
        )
        XCTAssertEqual(
            TodoBackupWorkflow.makeExportDocument(from: store).daySections,
            checkpoint.daySections
        )
    }

    func testRestoreFailureRollsBackCurrentDataAndKeepsRecoveryPoint() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let date = try makeDate(year: 2026, month: 8, day: 26)
        let item = store.createItem(title: "checkpoint", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())
        let checkpoint = TodoBackupWorkflow.makeExportDocument(from: store)
        try recoveryStore.stage(checkpoint)
        try recoveryStore.promoteStaged()

        item.title = "current data"
        let extra = store.createItem(title: "keep on failure", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())
        store.saveAction = { _ in throw SimulatedSaveFailure.unavailable }

        XCTAssertThrowsError(
            try TodoBackupWorkflow.restoreLatestImportCheckpoint(
                into: store,
                recoveryStore: recoveryStore
            )
        )

        XCTAssertEqual(store.todoItemsCache[item.id]?.title, "current data")
        XCTAssertNotNil(store.todoItemsCache[extra.id])
        XCTAssertTrue(recoveryStore.hasRecoveryPoint)
        XCTAssertEqual(try recoveryStore.loadRecoveryPoint(), checkpoint)
    }

    func testRecoveryConsumptionWriteFailureDoesNotPartiallyRestoreData() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let date = try makeDate(year: 2026, month: 8, day: 26)
        let item = store.createItem(title: "checkpoint", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())
        let checkpoint = TodoBackupWorkflow.makeExportDocument(from: store)
        try recoveryStore.stage(checkpoint)
        try recoveryStore.promoteStaged()

        item.title = "current data"
        let extra = store.createItem(title: "keep when restore cannot finish", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: recoveryStore.directoryURL.path()
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: recoveryStore.directoryURL.path()
            )
        }

        XCTAssertThrowsError(
            try TodoBackupWorkflow.restoreLatestImportCheckpoint(
                into: store,
                recoveryStore: recoveryStore
            )
        )

        XCTAssertEqual(store.todoItemsCache[item.id]?.title, "current data")
        XCTAssertNotNil(store.todoItemsCache[extra.id])
        XCTAssertTrue(recoveryStore.hasRecoveryPoint)
        XCTAssertEqual(try recoveryStore.loadRecoveryPoint(), checkpoint)
    }

    func testRecoveryConsumptionFinalizeFailureRevertsPersistedRestore() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let date = try makeDate(year: 2026, month: 8, day: 26)
        let item = store.createItem(title: "checkpoint", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())
        let checkpoint = TodoBackupWorkflow.makeExportDocument(from: store)
        try recoveryStore.stage(checkpoint)
        try recoveryStore.promoteStaged()

        item.title = "current data"
        let extra = store.createItem(title: "keep after finalize failure", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())

        var saveCount = 0
        store.saveAction = { context in
            saveCount += 1
            try context.save()
            if saveCount == 1 {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o500],
                    ofItemAtPath: recoveryStore.directoryURL.path()
                )
            }
        }
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: recoveryStore.directoryURL.path()
            )
        }

        XCTAssertThrowsError(
            try TodoBackupWorkflow.restoreLatestImportCheckpoint(
                into: store,
                recoveryStore: recoveryStore
            )
        )

        XCTAssertEqual(saveCount, 2)
        XCTAssertEqual(store.todoItemsCache[item.id]?.title, "current data")
        XCTAssertNotNil(store.todoItemsCache[extra.id])
        XCTAssertFalse(recoveryStore.hasRecoveryPoint)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: recoveryStore.directoryURL.path()
        )
        try recoveryStore.reconcileInterruptedConsumption(
            modelContext: try XCTUnwrap(store.modelContext)
        )
        XCTAssertTrue(recoveryStore.hasRecoveryPoint)
        XCTAssertEqual(try recoveryStore.loadRecoveryPoint(), checkpoint)
    }

    func testFinalizeAndCompensationFailureCompletesOnRestart() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let date = try makeDate(year: 2026, month: 8, day: 26)
        let item = store.createItem(title: "checkpoint", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())
        let checkpoint = TodoBackupWorkflow.makeExportDocument(from: store)
        try recoveryStore.stage(checkpoint)
        try recoveryStore.promoteStaged()

        item.title = "current data"
        _ = store.createItem(title: "removed by committed restore", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())

        var saveCount = 0
        store.saveAction = { context in
            saveCount += 1
            if saveCount == 1 {
                try context.save()
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o500],
                    ofItemAtPath: recoveryStore.directoryURL.path()
                )
            } else {
                throw SimulatedSaveFailure.unavailable
            }
        }

        XCTAssertNoThrow(
            try TodoBackupWorkflow.restoreLatestImportCheckpoint(
                into: store,
                recoveryStore: recoveryStore
            )
        )
        XCTAssertEqual(saveCount, 2)
        XCTAssertEqual(
            TodoBackupWorkflow.makeExportDocument(from: store).items,
            checkpoint.items
        )
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(store.canRedo)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: recoveryStore.directoryURL.path()
        )
        store.saveAction = nil
        let restoredItem = try XCTUnwrap(store.todoItemsCache[item.id])
        restoredItem.title = "ordinary edit after completed restore"
        XCTAssertTrue(store.flushPendingChangesSync())

        XCTAssertFalse(recoveryStore.hasRecoveryPoint)
        XCTAssertThrowsError(
            try TodoBackupWorkflow.restoreLatestImportCheckpoint(
                into: store,
                recoveryStore: recoveryStore
            )
        )
        XCTAssertEqual(
            store.todoItemsCache[item.id]?.title,
            "ordinary edit after completed restore"
        )

        let modelContext = try XCTUnwrap(store.modelContext)
        try recoveryStore.reconcileInterruptedConsumption(
            modelContext: modelContext
        )
        XCTAssertFalse(recoveryStore.hasRecoveryPoint)
    }

    func testUnsavedPersistenceFailureBlocksRestoreWithoutConsumingRecoveryPoint() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let checkpoint = TodoBackupWorkflow.makeExportDocument(from: store)
        try recoveryStore.stage(checkpoint)
        try recoveryStore.promoteStaged()
        store.saveStatus = .unsaved

        XCTAssertThrowsError(
            try TodoBackupWorkflow.restoreLatestImportCheckpoint(
                into: store,
                recoveryStore: recoveryStore
            )
        )
        XCTAssertTrue(recoveryStore.hasRecoveryPoint)
        XCTAssertEqual(store.saveStatus, .unsaved)
    }

    func testCommittedRestoreDoesNotResurrectCheckpointAfterLaterEditAndRestart() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let persistentContainer = try makePersistentContainer()
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: persistentContainer.mainContext)

        let date = try makeDate(year: 2026, month: 8, day: 26)
        let item = store.createItem(title: "checkpoint", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())
        let checkpoint = TodoBackupWorkflow.makeExportDocument(from: store)
        try recoveryStore.stage(checkpoint)
        try recoveryStore.promoteStaged()

        item.title = "current data"
        _ = store.createItem(title: "remove during restore", dayDate: date)
        XCTAssertTrue(store.flushPendingChangesSync())

        var saveCount = 0
        store.saveAction = { context in
            saveCount += 1
            if saveCount == 1 {
                try context.save()
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o500],
                    ofItemAtPath: recoveryStore.directoryURL.path()
                )
            } else {
                throw SimulatedSaveFailure.unavailable
            }
        }

        XCTAssertNoThrow(
            try TodoBackupWorkflow.restoreLatestImportCheckpoint(
                into: store,
                recoveryStore: recoveryStore
            )
        )
        XCTAssertEqual(saveCount, 2)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: recoveryStore.directoryURL.path()
        )
        store.saveAction = nil
        let restoredItem = try XCTUnwrap(store.todoItemsCache[item.id])
        restoredItem.title = "ordinary edit after restore"
        XCTAssertTrue(store.flushPendingChangesSync())

        TodoStore.shared.reset()
        let reopenedContainer = try makePersistentContainer()
        TodoStore.shared.initialize(with: reopenedContainer.mainContext)
        try recoveryStore.reconcileInterruptedConsumption(
            modelContext: reopenedContainer.mainContext
        )

        XCTAssertFalse(recoveryStore.hasRecoveryPoint)
        XCTAssertEqual(
            TodoStore.shared.todoItemsCache[item.id]?.title,
            "ordinary edit after restore"
        )
        XCTAssertTrue(
            try reopenedContainer.mainContext
                .fetch(FetchDescriptor<TodoBackupConsumptionState>())
                .isEmpty
        )
    }

    func testUnsavedRestoreConsumptionTokenDoesNotCountAsCommittedAfterRestart() throws {
        let store = TodoStore.shared
        let recoveryStore = try makeRecoveryStore()
        let persistentContainer = try makePersistentContainer()
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: persistentContainer.mainContext)

        let checkpoint = TodoBackupWorkflow.makeExportDocument(from: store)
        try recoveryStore.stage(checkpoint)
        try recoveryStore.promoteStaged()
        let token = try recoveryStore.stageConsumption()
        persistentContainer.mainContext.autosaveEnabled = false
        persistentContainer.mainContext.insert(TodoBackupConsumptionState(token: token))

        TodoStore.shared.reset()
        let reopenedContainer = try makePersistentContainer()
        TodoStore.shared.initialize(with: reopenedContainer.mainContext)
        try recoveryStore.reconcileInterruptedConsumption(
            modelContext: reopenedContainer.mainContext
        )

        XCTAssertTrue(recoveryStore.hasRecoveryPoint)
        XCTAssertEqual(try recoveryStore.loadRecoveryPoint(), checkpoint)
    }

    private func makeRecoveryStore() throws -> TodoBackupRecoveryStore {
        let root = try XCTUnwrap(temporaryDirectory)
        return TodoBackupRecoveryStore(
            directoryURL: root.appending(path: "recovery", directoryHint: .isDirectory)
        )
    }

    private func makePersistentContainer() throws -> ModelContainer {
        let root = try XCTUnwrap(temporaryDirectory)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let schema = Schema([
            TodoItem.self,
            DaySection.self,
            TodoBackupConsumptionState.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            url: root.appending(path: "TodoStore.sqlite")
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDate(year: Int, month: Int, day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
