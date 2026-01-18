//
//  DaySection.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import Foundation
import SwiftData

@Model
final class DaySection {
    @Attribute(.unique) var id: UUID = UUID()
    var date: Date = Date()           // 日期（只保留年月日）
    var title: String = ""            // 用户可编辑的标题，默认为 "MM-dd"
    var sortOrder: Double = 0         // 用于排序
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String? = nil,
        sortOrder: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        let startOfDay = Calendar.current.startOfDay(for: date)
        self.date = startOfDay
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        
        // 默认标题为 MM-dd 格式
        if let customTitle = title {
            self.title = customTitle
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd"
            self.title = formatter.string(from: startOfDay)
        }
    }
    
    /// 获取所属月份（用于按月分组）
    var yearMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    /// 获取所属年份
    var year: Int {
        Calendar.current.component(.year, from: date)
    }
    
    /// 获取所属月份数字
    var month: Int {
        Calendar.current.component(.month, from: date)
    }
}
