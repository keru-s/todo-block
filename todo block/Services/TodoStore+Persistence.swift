//
//  TodoStore+Persistence.swift
//  todo block
//

import Foundation
import OSLog
import SwiftData

/// SwiftData 持久化协调：debounce 异步落盘 + 同步 flush + 失败 rollback。
/// 把 IO 与缓存/CRUD 拆开，便于：
/// - 单独测试 debounce / rollback 路径（详见 Phase 1.A 单测）
/// - 后续替换持久化策略时不影响 CRUD
extension TodoStore {
    /// 调度一次延迟写盘。重复调用会 cancel 上一次未触发的 task，最终只发生一次实际 save。
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(saveDebounceInterval * 1000)))
            guard Task.isCancelled == false else { return }
            await performSave()
        }
    }

    /// 同步落盘当前所有 pending changes。用于必须打破 debounce 的关键路径，
    /// 例如撤销恢复（避免与同 UUID 的 pending delete 撞 unique 约束）。
    @discardableResult
    func flushPendingChangesSync() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard let modelContext, modelContext.hasChanges else {
            lastSaveError = nil
            return true
        }
        do {
            try modelContext.save()
            lastSaveError = nil
            return true
        } catch {
            Self.logger.error(
                "flushPendingChangesSync failed: \(error.localizedDescription, privacy: .public)")
            modelContext.rollback()
            lastSaveError = error
            return false
        }
    }

    private func performSave() async {
        guard let modelContext else { return }
        guard modelContext.hasChanges else {
            lastSaveError = nil
            return
        }
        do {
            try modelContext.save()
            lastSaveError = nil
        } catch {
            Self.logger.error(
                "performSave failed: \(error.localizedDescription, privacy: .public)")
            modelContext.rollback()
            lastSaveError = error
        }
    }
}
