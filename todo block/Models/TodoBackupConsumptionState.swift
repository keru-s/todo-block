//
//  TodoBackupConsumptionState.swift
//  todo block
//
//  Created by Codex on 2026/8/28.
//

import Foundation
import SwiftData

/// 精确恢复已完成首次持久化的内部标记；它不属于备份领域数据。
@Model
final class TodoBackupConsumptionState {
    @Attribute(.unique) var id: String = "exact-restore"
    var token: UUID = UUID()

    init(token: UUID) {
        self.token = token
    }
}
