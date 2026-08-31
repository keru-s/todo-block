//
//  TodoBackupRecoveryStoreTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/8/26.
//

import SwiftData
import XCTest
@testable import todo_block

@MainActor
final class TodoBackupRecoveryStoreTests: XCTestCase {
    func testStagedRecoveryPointSurvivesRestartWhenPromotionDidNotFinish() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appending(path: "recovery", directoryHint: .isDirectory)
        let document = makeDocument(exportedAt: 1_787_000_100)
        try TodoBackupRecoveryStore(directoryURL: directory).stage(document)

        let reopenedStore = TodoBackupRecoveryStore(directoryURL: directory)
        XCTAssertTrue(reopenedStore.hasRecoveryPoint)
        XCTAssertEqual(try reopenedStore.loadRecoveryPoint(), document)
    }

    func testDiscardingNewStagePreservesPreviouslyUnpromotedRecoveryPoint() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoBackupRecoveryStore(
            directoryURL: root.appending(path: "recovery", directoryHint: .isDirectory)
        )
        let previous = makeDocument(exportedAt: 1_787_000_100)
        let next = makeDocument(exportedAt: 1_787_000_200)
        try store.stage(previous)

        try store.stage(next)
        XCTAssertEqual(try store.loadRecoveryPoint(), next)
        store.discardStaged()

        XCTAssertTrue(store.hasRecoveryPoint)
        XCTAssertEqual(try store.loadRecoveryPoint(), previous)
    }

    func testSuccessfulNextImportReplacesPreviousRecoveryPoint() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoBackupRecoveryStore(
            directoryURL: root.appending(path: "recovery", directoryHint: .isDirectory)
        )
        let previous = makeDocument(exportedAt: 1_787_000_100)
        let next = makeDocument(exportedAt: 1_787_000_200)
        try store.stage(previous)
        try store.promoteStaged()

        try store.stage(next)
        try store.promoteStaged()

        XCTAssertEqual(try store.loadRecoveryPoint(), next)
    }

    func testRestartDiscardsStageWhenImportNeverReachedPersistence() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appending(path: "recovery", directoryHint: .isDirectory)
        let store = TodoBackupRecoveryStore(directoryURL: directory)
        let previous = makeDocument(exportedAt: 1_787_000_100, title: "older checkpoint")
        let interrupted = makeDocument(exportedAt: 1_787_000_200, title: "current data")
        try store.stage(previous)
        try store.promoteStaged()
        try store.stage(interrupted)

        let reopenedStore = TodoBackupRecoveryStore(directoryURL: directory)
        try reopenedStore.reconcileInterruptedImport(currentDocument: interrupted)

        XCTAssertTrue(reopenedStore.hasRecoveryPoint)
        XCTAssertEqual(try reopenedStore.loadRecoveryPoint(), previous)
    }

    func testRestartPromotesStageWhenImportedDataReachedPersistence() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appending(path: "recovery", directoryHint: .isDirectory)
        let store = TodoBackupRecoveryStore(directoryURL: directory)
        let previous = makeDocument(exportedAt: 1_787_000_100, title: "older checkpoint")
        let staged = makeDocument(exportedAt: 1_787_000_200, title: "before import")
        let persisted = makeDocument(exportedAt: 1_787_000_300, title: "after import")
        try store.stage(previous)
        try store.promoteStaged()
        try store.stage(staged)

        let reopenedStore = TodoBackupRecoveryStore(directoryURL: directory)
        try reopenedStore.reconcileInterruptedImport(currentDocument: persisted)

        XCTAssertTrue(reopenedStore.hasRecoveryPoint)
        XCTAssertEqual(try reopenedStore.loadRecoveryPoint(), staged)
    }

    func testFailedPromotionLeavesPendingRecoveryPointReadable() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appending(path: "recovery", directoryHint: .isDirectory)
        let store = TodoBackupRecoveryStore(directoryURL: directory)
        let document = makeDocument(exportedAt: 1_787_000_100)
        try store.stage(document)
        let blockingActiveDirectory = directory.appending(
            path: "ImportRecoveryPoint.json",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: blockingActiveDirectory,
            withIntermediateDirectories: true
        )
        try Data("keep directory nonempty".utf8).write(
            to: blockingActiveDirectory.appending(path: "blocker")
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path()
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path()
            )
        }

        XCTAssertThrowsError(try store.promoteStaged())
        XCTAssertTrue(store.hasRecoveryPoint)
        XCTAssertEqual(try store.loadRecoveryPoint(), document)
    }

    func testFailedRestartReconciliationLeavesPendingRecoveryPointReadable() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appending(path: "recovery", directoryHint: .isDirectory)
        let store = TodoBackupRecoveryStore(directoryURL: directory)
        let staged = makeDocument(exportedAt: 1_787_000_100, title: "before import")
        let persisted = makeDocument(exportedAt: 1_787_000_200, title: "after import")
        try store.stage(staged)
        let blockingActiveDirectory = directory.appending(
            path: "ImportRecoveryPoint.json",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: blockingActiveDirectory,
            withIntermediateDirectories: true
        )
        try Data("keep directory nonempty".utf8).write(
            to: blockingActiveDirectory.appending(path: "blocker")
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path()
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path()
            )
        }

        XCTAssertThrowsError(
            try store.reconcileInterruptedImport(currentDocument: persisted)
        )
        XCTAssertTrue(store.hasRecoveryPoint)
        XCTAssertEqual(try store.loadRecoveryPoint(), staged)
    }

    func testPromotedRecoveryPointSurvivesNewStoreInstance() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appending(path: "recovery", directoryHint: .isDirectory)
        let firstStore = TodoBackupRecoveryStore(directoryURL: directory)
        let document = makeDocument()

        try firstStore.stage(document)
        try firstStore.promoteStaged()

        let reopenedStore = TodoBackupRecoveryStore(directoryURL: directory)
        XCTAssertTrue(reopenedStore.hasRecoveryPoint)
        XCTAssertEqual(try reopenedStore.loadRecoveryPoint(), document)
    }

    func testConsumedRecoveryPointStaysUnavailableInNewStoreInstance() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appending(path: "recovery", directoryHint: .isDirectory)
        let firstStore = TodoBackupRecoveryStore(directoryURL: directory)
        try firstStore.stage(makeDocument())
        try firstStore.promoteStaged()
        try firstStore.consumeRecoveryPoint()

        let reopenedStore = TodoBackupRecoveryStore(directoryURL: directory)
        XCTAssertFalse(reopenedStore.hasRecoveryPoint)
        XCTAssertThrowsError(try reopenedStore.loadRecoveryPoint())
    }

    func testInterruptedConsumptionKeepsRecoveryPointAvailableAfterRestart() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appending(path: "recovery", directoryHint: .isDirectory)
        let document = makeDocument()
        let firstStore = TodoBackupRecoveryStore(directoryURL: directory)
        try firstStore.stage(document)
        try firstStore.promoteStaged()
        try firstStore.stageConsumption()

        let reopenedStore = TodoBackupRecoveryStore(directoryURL: directory)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoBackupConsumptionState.self,
            configurations: configuration
        )
        try reopenedStore.reconcileInterruptedConsumption(
            modelContext: container.mainContext
        )
        XCTAssertTrue(reopenedStore.hasRecoveryPoint)
        XCTAssertEqual(try reopenedStore.loadRecoveryPoint(), document)
    }

    func testConsumptionStateCannotBeStagedWhileAutosaveIsEnabled() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoBackupConsumptionState.self,
            configurations: configuration
        )
        XCTAssertTrue(container.mainContext.autosaveEnabled)

        XCTAssertThrowsError(
            try TodoBackupRecoveryStore(directoryURL: root)
                .stageConsumptionState(token: UUID(), in: container.mainContext)
        ) { error in
            guard case .autosaveMustBeDisabled = error as? TodoBackupRecoveryStoreError else {
                return XCTFail("Expected autosaveMustBeDisabled, got \(error)")
            }
        }
    }

    private func makeDocument(exportedAt: TimeInterval = 1_787_000_000) -> TodoBackupDocument {
        TodoBackupDocument(
            exportedAt: Date(timeIntervalSince1970: exportedAt),
            items: [],
            daySections: []
        )
    }

    private func makeDocument(
        exportedAt: TimeInterval,
        title: String
    ) -> TodoBackupDocument {
        let timestamp = Date(timeIntervalSince1970: exportedAt)
        return TodoBackupDocument(
            exportedAt: timestamp,
            items: [
                TodoBackupItem(
                    id: UUID(),
                    title: title,
                    isCompleted: false,
                    indentLevel: 0,
                    sortOrder: 1,
                    containerKind: .longTermImportant,
                    dayDate: TodoBackupCalendarDate(year: 2026, month: 8, day: 27),
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            ],
            daySections: []
        )
    }
}
