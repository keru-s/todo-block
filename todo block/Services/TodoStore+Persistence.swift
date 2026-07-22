//
//  TodoStore+Persistence.swift
//  todo block
//

import Foundation
import OSLog
import SwiftData

/// SwiftData 持久化协调：debounce 异步落盘 + 同步 flush + 失败后保留内存状态并重试。
/// 把 IO 与缓存/CRUD 拆开，便于：
/// - 单独测试 debounce / 失败重试路径
/// - 后续替换持久化策略时不影响 CRUD
extension TodoStore {
    /// 调度一次延迟写盘。重复调用会 cancel 上一次未触发的 task，最终只发生一次实际 save。
    func scheduleSave() {
        if saveStatus != .unsaved {
            saveStatus = .queued
        }
        scheduleSaveAttempt(after: .milliseconds(Int(saveDebounceInterval * 1000)))
    }

    /// 同步落盘当前所有 pending changes。用于必须打破 debounce 的关键路径，
    /// 例如撤销恢复（避免与同 UUID 的 pending delete 撞 unique 约束）。
    @discardableResult
    func flushPendingChangesSync() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        return saveCurrentChanges()
    }

    /// 在应用终止前尝试立即写盘。失败时由调用方取消退出，绝不静默丢失用户状态。
    @discardableResult
    func prepareForTermination() -> Bool {
        flushPendingTextEdit()
        return flushPendingChangesSync()
    }

    private func performSave() {
        saveTask = nil
        _ = saveCurrentChanges()
    }

    private func scheduleSaveAttempt(after delay: Duration) {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard Task.isCancelled == false else { return }
            self?.performSave()
        }
    }

    @discardableResult
    private func saveCurrentChanges() -> Bool {
        guard let modelContext else {
            return saveStatus != .unsaved
        }
        guard modelContext.hasChanges else {
            guard saveStatus != .unsaved else { return false }
            markSaveSucceeded()
            return true
        }
        do {
            if let saveAction {
                try saveAction(modelContext)
            } else {
                try modelContext.save()
            }
            markSaveSucceeded()
            return true
        } catch {
            Self.logger.error(
                "save failed: \(error.localizedDescription, privacy: .public)")
            lastSaveError = error
            saveStatus = .unsaved
            scheduleSaveAttempt(after: saveRetryInterval)
            return false
        }
    }

    private func markSaveSucceeded() {
        lastSaveError = nil
        saveStatus = .saved
    }
}
