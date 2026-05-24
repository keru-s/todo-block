//
//  TodoItem.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import Foundation
import SwiftData

enum TodoContainerKind: String, Codable, CaseIterable {
    case scheduled
    case longTermUrgent
    case longTermImportant = "longTermNonUrgent"
}

@Model
final class TodoItem {
    static let maxIndentLevel = 4

    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var indentLevel: Int = 0          // 0-4，最多 5 层（顶层为 0）
    var sortOrder: Double = 0         // 用于拖拽排序

    var containerKindRaw: String = TodoContainerKind.scheduled.rawValue
    var dayDate: Date = Date()        // 所属日期（只保留年月日）
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var containerKind: TodoContainerKind {
        get { TodoContainerKind(rawValue: containerKindRaw) ?? .scheduled }
        set { containerKindRaw = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        title: String = "",
        isCompleted: Bool = false,
        indentLevel: Int = 0,
        sortOrder: Double = 0,
        containerKindRaw: String = TodoContainerKind.scheduled.rawValue,
        dayDate: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.indentLevel = min(max(indentLevel, 0), Self.maxIndentLevel)
        self.sortOrder = sortOrder
        self.containerKindRaw = containerKindRaw
        self.dayDate = Calendar.current.startOfDay(for: dayDate)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - 便捷方法
    
    /// 增加缩进层级
    func indent() {
        if indentLevel < Self.maxIndentLevel {
            indentLevel += 1
            updatedAt = Date()
        }
    }
    
    /// 减少缩进层级
    func outdent() {
        if indentLevel > 0 {
            indentLevel -= 1
            updatedAt = Date()
        }
    }
    
    /// 获取所属月份（用于按月分组）
    var yearMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: dayDate)
    }
}
