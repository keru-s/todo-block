//
//  TodoBackupRecoveryStore.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import Foundation
import SwiftData

enum TodoBackupRecoveryStoreError: LocalizedError {
    case noRecoveryPoint
    case invalidConsumptionToken
    case autosaveMustBeDisabled
    case consumptionInProgress

    var errorDescription: String? {
        switch self {
        case .noRecoveryPoint:
            "没有可用的导入恢复点。"
        case .invalidConsumptionToken:
            "导入恢复点的消费标记无效。"
        case .autosaveMustBeDisabled:
            "无法在自动保存开启时准备导入恢复点消费。"
        case .consumptionInProgress:
            "上一次恢复正在完成收尾，暂时无法创建新的导入恢复点。"
        }
    }
}

struct TodoBackupRecoveryStore: Sendable {
    let directoryURL: URL
    private let discardStagedOverride: (@Sendable () -> Bool)?

    init(
        directoryURL: URL,
        discardStagedOverride: (@Sendable () -> Bool)? = nil
    ) {
        self.directoryURL = directoryURL
        self.discardStagedOverride = discardStagedOverride
    }

    static func applicationSupportStore() throws -> TodoBackupRecoveryStore {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        // UI 测试（带 -UITestRecoveryState 启动）：重定向到测试专用目录，
        // 避免测试读写用户真实的导入恢复点。见 todo_blockApp.swift 的
        // BackupRecoveryUITestHook 与 todo blockUITests/BackupMenuUITests.swift。
        let directoryName = ProcessInfo.processInfo.arguments.contains("-UITestRecoveryState")
            ? "UITestBackupRecovery"
            : "BackupRecovery"
        return TodoBackupRecoveryStore(
            directoryURL: baseURL
                .appending(path: "TodoBlock", directoryHint: .isDirectory)
                .appending(path: directoryName, directoryHint: .isDirectory)
        )
    }

    var hasRecoveryPoint: Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: consumedMarkerURL.path(percentEncoded: false)) == false else {
            return false
        }
        guard fileManager.fileExists(atPath: consumptionPendingURL.path(percentEncoded: false)) == false else {
            return false
        }
        guard hasFailedStagedImport(fileManager: fileManager) == false else {
            return fileManager.fileExists(atPath: activeURL.path(percentEncoded: false))
        }
        return fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false))
            || fileManager.fileExists(atPath: activeURL.path(percentEncoded: false))
    }

    func stage(_ document: TodoBackupDocument) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        guard fileManager.fileExists(atPath: consumptionPendingURL.path(percentEncoded: false)) == false else {
            throw TodoBackupRecoveryStoreError.consumptionInProgress
        }

        if hasFailedStagedImport(fileManager: fileManager) {
            try removeIfPresent(pendingURL, fileManager: fileManager)
            let data = try TodoBackupCodec.encode(document)
            do {
                try data.write(to: pendingURL, options: .atomic)
                try removeIfPresent(failedURL, fileManager: fileManager)
            } catch {
                try? fileManager.removeItem(at: pendingURL)
                throw error
            }
            return
        }

        if fileManager.fileExists(atPath: consumedMarkerURL.path(percentEncoded: false)) {
            // 上一个恢复点已经被消费。先在 marker 保护下清理遗留文件，
            // 只有新的 pending 写成功后才重新开放恢复能力。
            try removeIfPresent(activeURL, fileManager: fileManager)
            try removeIfPresent(pendingURL, fileManager: fileManager)
            let data = try TodoBackupCodec.encode(document)
            do {
                try data.write(to: pendingURL, options: .atomic)
                try fileManager.removeItem(at: consumedMarkerURL)
            } catch {
                try? fileManager.removeItem(at: pendingURL)
                throw error
            }
            return
        }

        // 如果上一次成功导入的 pending 文件未能晋升，先保护它，避免新导入覆盖。
        if fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)) {
            try promoteStaged()
        }

        let data = try TodoBackupCodec.encode(document)
        try data.write(to: pendingURL, options: .atomic)
    }

    func promoteStaged() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)) else { return }

        try removeIfPresent(activeURL, fileManager: fileManager)
        try fileManager.moveItem(at: pendingURL, to: activeURL)
    }

    @discardableResult
    func discardStaged() -> Bool {
        if let discardStagedOverride {
            guard discardStagedOverride() else {
                markStagedImportFailed()
                return false
            }
            return true
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)) else { return true }
        do {
            try fileManager.removeItem(at: pendingURL)
            return true
        } catch {
            markStagedImportFailed()
            return false
        }
    }

    func loadRecoveryPoint() throws -> TodoBackupDocument {
        guard hasRecoveryPoint else {
            throw TodoBackupRecoveryStoreError.noRecoveryPoint
        }
        let fileManager = FileManager.default
        let url: URL
        if hasFailedStagedImport(fileManager: fileManager) {
            url = activeURL
        } else if fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)) {
            url = pendingURL
        } else {
            url = activeURL
        }
        let data = try Data(contentsOf: url)
        return try TodoBackupCodec.decode(data)
    }

    func reconcileInterruptedImport(currentDocument: TodoBackupDocument) throws {
        let fileManager = FileManager.default
        if hasFailedStagedImport(fileManager: fileManager) {
            try removeIfPresent(pendingURL, fileManager: fileManager)
            try removeIfPresent(failedURL, fileManager: fileManager)
            return
        }
        guard fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)) else { return }

        let data = try Data(contentsOf: pendingURL)
        let stagedDocument = try TodoBackupCodec.decode(data)
        if hasSameDomainData(stagedDocument, currentDocument) {
            try removeIfPresent(pendingURL, fileManager: fileManager)
        } else {
            try promoteStaged()
        }
    }

    @MainActor
    func reconcileInterruptedConsumption(modelContext: ModelContext) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: consumptionPendingURL.path(percentEncoded: false)) else {
            return
        }

        let consumingToken = try loadConsumptionToken()
        let states = try modelContext.fetch(FetchDescriptor<TodoBackupConsumptionState>())
        guard states.contains(where: { $0.token == consumingToken }) else {
            try removeIfPresent(consumptionPendingURL, fileManager: fileManager)
            return
        }

        try consumeRecoveryPoint()
        try clearConsumptionState(in: modelContext)
        try? modelContext.save()
    }

    @discardableResult
    func stageConsumption() throws -> UUID {
        guard hasRecoveryPoint else {
            throw TodoBackupRecoveryStoreError.noRecoveryPoint
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let token = UUID()
        try Data(token.uuidString.utf8).write(to: consumptionPendingURL, options: .atomic)
        return token
    }

    @MainActor
    func stageConsumptionState(
        token: UUID,
        in modelContext: ModelContext
    ) throws {
        guard modelContext.autosaveEnabled == false else {
            throw TodoBackupRecoveryStoreError.autosaveMustBeDisabled
        }
        let states = try modelContext.fetch(FetchDescriptor<TodoBackupConsumptionState>())
        if let state = states.first {
            state.token = token
            for duplicate in states.dropFirst() {
                modelContext.delete(duplicate)
            }
        } else {
            modelContext.insert(TodoBackupConsumptionState(token: token))
        }
    }

    @MainActor
    func clearConsumptionState(in modelContext: ModelContext) throws {
        let states = try modelContext.fetch(FetchDescriptor<TodoBackupConsumptionState>())
        for state in states {
            modelContext.delete(state)
        }
    }

    func discardConsumptionStage() {
        try? FileManager.default.removeItem(at: consumptionPendingURL)
    }

    func consumeRecoveryPoint() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: consumptionPendingURL.path(percentEncoded: false)) == false {
            try stageConsumption()
        }

        // consumption pending 在恢复修改数据前已经持久化。成功保存后只需同目录改名，
        // 不再依赖一次新的文件写入；即使后续 checkpoint 清理失败，消费状态也已持久化。
        try fileManager.moveItem(at: consumptionPendingURL, to: consumedMarkerURL)
        try? fileManager.removeItem(at: pendingURL)
        try? fileManager.removeItem(at: activeURL)
        try? fileManager.removeItem(at: failedURL)
    }

    private func loadConsumptionToken() throws -> UUID {
        let data = try Data(contentsOf: consumptionPendingURL)
        guard
            let value = String(data: data, encoding: .utf8),
            let token = UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw TodoBackupRecoveryStoreError.invalidConsumptionToken
        }
        return token
    }

    private func removeIfPresent(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: url)
    }

    private func markStagedImportFailed() {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try Data().write(to: failedURL, options: .atomic)
        } catch {
            // 如果旁路标记也因目录权限失败，回写现有 pending 文件不需要目录写权限，
            // 仍可把它标记为失败，避免重启时被误认为已成功导入。
            try? failureMarkerData.write(to: pendingURL)
        }
    }

    private func hasFailedStagedImport(fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: failedURL.path(percentEncoded: false)) {
            return true
        }
        guard
            fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)),
            let data = try? Data(contentsOf: pendingURL)
        else {
            return false
        }
        return data == failureMarkerData
    }

    private var failureMarkerData: Data {
        Data("todo-block-import-failed-v1".utf8)
    }

    private func hasSameDomainData(
        _ lhs: TodoBackupDocument,
        _ rhs: TodoBackupDocument
    ) -> Bool {
        lhs.items == rhs.items && lhs.daySections == rhs.daySections
    }

    private var activeURL: URL {
        directoryURL.appending(path: "ImportRecoveryPoint.json")
    }

    private var pendingURL: URL {
        directoryURL.appending(path: "ImportRecoveryPoint.pending.json")
    }

    private var failedURL: URL {
        directoryURL.appending(path: "ImportRecoveryPoint.failed")
    }

    private var consumedMarkerURL: URL {
        directoryURL.appending(path: "ImportRecoveryPoint.consumed")
    }

    private var consumptionPendingURL: URL {
        directoryURL.appending(path: "ImportRecoveryPoint.consuming")
    }
}
