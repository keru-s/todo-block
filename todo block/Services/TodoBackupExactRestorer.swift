//
//  TodoBackupExactRestorer.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import Foundation
import SwiftData

enum TodoBackupExactRestoreError: LocalizedError {
    case unsavedChanges
    case unableToFlushLocalChanges
    case missingModelContext
    case invalidCalendarDate(TodoBackupCalendarDate)
    case persistenceFailed

    var errorDescription: String? {
        let profile = TodoBackupMutationSafety.Operation.exactRestore.profile
        return switch self {
        case .unsavedChanges:
            profile.unsavedChangesMessage
        case .unableToFlushLocalChanges:
            profile.unableToFlushMessage
        case .missingModelContext:
            profile.missingModelContextMessage
        case .invalidCalendarDate(let date):
            profile.invalidCalendarDateMessage(date)
        case .persistenceFailed:
            profile.persistenceFailedMessage
        }
    }
}

@MainActor
enum TodoBackupExactRestorer {
    static func restore(
        into store: TodoStore,
        recoveryStore: TodoBackupRecoveryStore,
        calendar: Calendar = .current
    ) throws {
        try TodoBackupMutationSafety.prepare(store: store, for: .exactRestore)

        let currentDocument = TodoBackupWorkflow.makeExportDocument(
            from: store,
            exportedAt: .now,
            calendar: calendar
        )

        let checkpoint = try recoveryStore.loadRecoveryPoint()
        try TodoBackupImportPlanner.validate(checkpoint)

        let modelContext = try TodoBackupMutationSafety.requireModelContext(
            from: store,
            for: .exactRestore
        )

        try TodoBackupMutationSafety.withAutosaveDisabled(in: modelContext) {
            do {
                let consumptionToken = try recoveryStore.stageConsumption()
                try recoveryStore.stageConsumptionState(
                    token: consumptionToken,
                    in: modelContext
                )
            } catch {
                recoveryStore.discardConsumptionStage()
                throw error
            }

            do {
                try restore(
                    checkpoint,
                    store: store,
                    modelContext: modelContext,
                    calendar: calendar
                )
                store.bumpRefreshTrigger()

                try TodoBackupMutationSafety.persist(store: store, for: .exactRestore)
            } catch {
                TodoBackupMutationSafety.rollback(
                    modelContext: modelContext,
                    store: store,
                    cleanup: { recoveryStore.discardConsumptionStage() }
                )
                throw error
            }

            do {
                try recoveryStore.consumeRecoveryPoint()
            } catch {
                do {
                    try restore(
                        currentDocument,
                        store: store,
                        modelContext: modelContext,
                        calendar: calendar
                    )
                    try recoveryStore.clearConsumptionState(in: modelContext)
                    store.bumpRefreshTrigger()
                    try TodoBackupMutationSafety.persist(store: store, for: .exactRestore)
                    recoveryStore.discardConsumptionStage()
                    store.initialize(with: modelContext)
                } catch {
                    TodoBackupMutationSafety.rollback(
                        modelContext: modelContext,
                        store: store,
                        cleanup: {}
                    )
                    store.undoManager.clear()
                    return
                }
                throw error
            }

            try? recoveryStore.clearConsumptionState(in: modelContext)
            try? modelContext.save()
            store.undoManager.clear()
        }
    }

    private static func restore(
        _ document: TodoBackupDocument,
        store: TodoStore,
        modelContext: ModelContext,
        calendar: Calendar
    ) throws {
        try restoreTodoItems(
            from: document,
            store: store,
            modelContext: modelContext,
            calendar: calendar
        )
        try restoreDaySections(
            from: document,
            store: store,
            modelContext: modelContext,
            calendar: calendar
        )
    }

    private static func restoreTodoItems(
        from checkpoint: TodoBackupDocument,
        store: TodoStore,
        modelContext: ModelContext,
        calendar: Calendar
    ) throws {
        let targetByID = Dictionary(uniqueKeysWithValues: checkpoint.items.map { ($0.id, $0) })

        for item in store.validTodoItems where targetByID[item.id] == nil {
            store.todoItemsCache.removeValue(forKey: item.id)
            modelContext.delete(item)
        }

        for target in checkpoint.items {
            if let item = store.todoItemsCache[target.id], store.isValid(model: item) {
                try TodoBackupMutationSafety.apply(
                    target,
                    to: item,
                    calendar: calendar,
                    for: .exactRestore
                )
            } else {
                try TodoBackupMutationSafety.insert(
                    target,
                    into: modelContext,
                    store: store,
                    calendar: calendar,
                    for: .exactRestore
                )
            }
        }
    }

    private static func restoreDaySections(
        from checkpoint: TodoBackupDocument,
        store: TodoStore,
        modelContext: ModelContext,
        calendar: Calendar
    ) throws {
        let targetByID = Dictionary(uniqueKeysWithValues: checkpoint.daySections.map { ($0.id, $0) })

        for section in store.validDaySections where targetByID[section.id] == nil {
            store.daySectionsCache.removeValue(forKey: section.id)
            modelContext.delete(section)
        }

        for target in checkpoint.daySections {
            if let section = store.daySectionsCache[target.id], store.isValid(model: section) {
                try TodoBackupMutationSafety.apply(
                    target,
                    to: section,
                    calendar: calendar,
                    for: .exactRestore
                )
            } else {
                try TodoBackupMutationSafety.insert(
                    target,
                    into: modelContext,
                    store: store,
                    calendar: calendar,
                    for: .exactRestore
                )
            }
        }
    }

}
