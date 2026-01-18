//
//  TodoItem.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import Foundation
import SwiftData

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var indentLevel: Int = 0          // 0-3，最多 4 层
    var sortOrder: Double = 0         // 用于拖拽排序

    var dayDate: Date = Date()        // 所属日期（只保留年月日）
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    init(
        id: UUID = UUID(),
        title: String = "",
        isCompleted: Bool = false,
        indentLevel: Int = 0,
        sortOrder: Double = 0,
        dayDate: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.indentLevel = min(max(indentLevel, 0), 3) // 限制 0-3
        self.sortOrder = sortOrder
        self.dayDate = Calendar.current.startOfDay(for: dayDate)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - 便捷方法
    
    /// 增加缩进层级
    func indent() {
        if indentLevel < 3 {
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
    
    /// 标记完成/未完成
    func toggleComplete() {
        isCompleted.toggle()
        updatedAt = Date()
    }
    
    /// 格式化日期显示（如 "01-17"）
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: dayDate)
    }
    
    /// 获取所属月份（用于按月分组）
    var yearMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: dayDate)
    }
}
