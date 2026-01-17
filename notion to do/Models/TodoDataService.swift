//
//  TodoDataService.swift
//  notion to do
//
//  Created by Claude on 2026/1/17.
//

import Foundation
import SwiftData

/// 数据服务层，封装 CRUD 操作和异步保存逻辑
@MainActor
@Observable
final class TodoDataService {
    private let modelContext: ModelContext
    private var saveTask: Task<Void, Never>?
    private let saveDebounceInterval: TimeInterval = 0.3 // 300ms 防抖
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - DaySection 操作
    
    /// 获取或创建今日的 DaySection
    func getOrCreateTodaySection() -> DaySection {
        let today = Calendar.current.startOfDay(for: Date())
        
        let descriptor = FetchDescriptor<DaySection>(
            predicate: #Predicate { $0.date == today }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        
        // 创建新的今日分组
        let newSection = DaySection(date: today, sortOrder: Double(Date().timeIntervalSince1970))
        modelContext.insert(newSection)
        scheduleSave()
        return newSection
    }
    
    /// 获取某月所有 DaySection
    func fetchDaySections(year: Int, month: Int) -> [DaySection] {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: year, month: month, day: 1)
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) else {
            return []
        }
        
        let descriptor = FetchDescriptor<DaySection>(
            predicate: #Predicate { section in
                section.date >= startDate && section.date < endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// 获取所有有数据的月份
    func fetchAvailableMonths() -> [(year: Int, month: Int)] {
        let descriptor = FetchDescriptor<DaySection>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        guard let sections = try? modelContext.fetch(descriptor) else {
            return []
        }
        
        var uniqueMonths: [(year: Int, month: Int)] = []
        var seen = Set<String>()
        
        for section in sections {
            let key = section.yearMonth
            if !seen.contains(key) {
                seen.insert(key)
                uniqueMonths.append((section.year, section.month))
            }
        }
        
        return uniqueMonths
    }
    
    // MARK: - TodoItem 操作
    
    /// 获取某日的所有待办事项
    func fetchTodoItems(for date: Date) -> [TodoItem] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { item in
                item.dayDate == startOfDay
            },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// 创建新的待办事项
    func createTodoItem(
        title: String = "",
        dayDate: Date,
        afterItem: TodoItem? = nil,
        indentLevel: Int = 0
    ) -> TodoItem {
        let items = fetchTodoItems(for: dayDate)
        
        var newSortOrder: Double
        if let afterItem = afterItem,
           let afterIndex = items.firstIndex(where: { $0.id == afterItem.id }) {
            // 在指定项目之后插入
            if afterIndex + 1 < items.count {
                let nextItem = items[afterIndex + 1]
                newSortOrder = (afterItem.sortOrder + nextItem.sortOrder) / 2
            } else {
                newSortOrder = afterItem.sortOrder + 1000
            }
        } else if let lastItem = items.last {
            // 在末尾添加
            newSortOrder = lastItem.sortOrder + 1000
        } else {
            // 第一个项目
            newSortOrder = 1000
        }
        
        let newItem = TodoItem(
            title: title,
            indentLevel: indentLevel,
            sortOrder: newSortOrder,
            dayDate: dayDate
        )
        
        modelContext.insert(newItem)
        scheduleSave()
        return newItem
    }
    
    /// 删除待办事项
    func deleteTodoItem(_ item: TodoItem) {
        modelContext.delete(item)
        scheduleSave()
    }
    
    /// 更新待办事项
    func updateTodoItem(_ item: TodoItem) {
        item.updatedAt = Date()
        scheduleSave()
    }
    
    /// 标记完成（包括子任务）
    func toggleComplete(_ item: TodoItem, allItems: [TodoItem]) {
        let newState = !item.isCompleted
        item.isCompleted = newState
        item.updatedAt = Date()
        
        // 找到所有子任务并同步状态
        let itemIndex = allItems.firstIndex(where: { $0.id == item.id }) ?? 0
        let itemIndent = item.indentLevel
        
        for i in (itemIndex + 1)..<allItems.count {
            let child = allItems[i]
            if child.indentLevel > itemIndent {
                child.isCompleted = newState
                child.updatedAt = Date()
            } else {
                break // 遇到同级或更高级别的项目，停止
            }
        }
        
        scheduleSave()
    }
    
    /// 移动待办事项到新位置
    func moveTodoItem(_ item: TodoItem, toDate: Date, afterItem: TodoItem?) {
        _ = item.dayDate  // 保留以备将来使用
        let newDate = Calendar.current.startOfDay(for: toDate)
        
        item.dayDate = newDate
        
        // 重新计算 sortOrder
        let targetItems = fetchTodoItems(for: newDate).filter { $0.id != item.id }
        
        if let afterItem = afterItem,
           let afterIndex = targetItems.firstIndex(where: { $0.id == afterItem.id }) {
            if afterIndex + 1 < targetItems.count {
                let nextItem = targetItems[afterIndex + 1]
                item.sortOrder = (afterItem.sortOrder + nextItem.sortOrder) / 2
            } else {
                item.sortOrder = afterItem.sortOrder + 1000
            }
        } else if let firstItem = targetItems.first {
            item.sortOrder = firstItem.sortOrder - 1000
        } else {
            item.sortOrder = 1000
        }
        
        item.updatedAt = Date()
        scheduleSave()
    }
    
    // MARK: - 异步保存
    
    /// 防抖保存 - 避免频繁写入
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(saveDebounceInterval * 1000)))
            guard !Task.isCancelled else { return }
            await performSave()
        }
    }
    
    /// 立即保存
    func saveNow() {
        saveTask?.cancel()
        Task {
            await performSave()
        }
    }
    
    private func performSave() async {
        do {
            try modelContext.save()
        } catch {
            print("保存失败: \(error)")
        }
    }
}
