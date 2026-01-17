//
//  TodoStore.swift
//  notion to do
//
//  Created by Claude on 2026/1/17.
//

import Foundation
import SwiftData

/// 单例数据存储，内存缓存 + 异步持久化
/// 主窗口和菜单栏共享此实例，实现数据同步
@MainActor
@Observable
final class TodoStore {
    static let shared = TodoStore()
    
    // MARK: - 内存缓存
    
    private(set) var todoItemsCache: [UUID: TodoItem] = [:]
    private(set) var daySectionsCache: [UUID: DaySection] = [:]
    
    /// 刷新触发器：每次数据变化时递增，强制依赖它的视图刷新
    private(set) var refreshTrigger: Int = 0
    
    // MARK: - 私有属性
    
    private var modelContext: ModelContext?
    private var saveTask: Task<Void, Never>?
    private let saveDebounceInterval: TimeInterval = 0.3
    
    private init() {}
    
    // MARK: - 初始化
    
    /// 初始化并从数据库加载数据到缓存
    func initialize(with modelContext: ModelContext) {
        self.modelContext = modelContext
        loadFromDatabase()
    }
    
    /// 用于测试：重置状态
    func reset() {
        todoItemsCache.removeAll()
        daySectionsCache.removeAll()
        refreshTrigger += 1
    }
    
    private func loadFromDatabase() {
        guard let modelContext = modelContext else { return }
        
        // 加载所有 DaySection
        let sectionDescriptor = FetchDescriptor<DaySection>()
        if let sections = try? modelContext.fetch(sectionDescriptor) {
            for section in sections {
                daySectionsCache[section.id] = section
            }
        }
        
        // 加载所有 TodoItem
        let itemDescriptor = FetchDescriptor<TodoItem>()
        if let items = try? modelContext.fetch(itemDescriptor) {
            for item in items {
                todoItemsCache[item.id] = item
            }
        }
    }
    
    // MARK: - 查询方法（从缓存）
    
    /// 获取某日的所有待办事项（按 sortOrder 排序）
    func items(for date: Date) -> [TodoItem] {
        // 引用 refreshTrigger 以建立 Observable 依赖
        _ = refreshTrigger
        
        let startOfDay = Calendar.current.startOfDay(for: date)
        return todoItemsCache.values
            .filter { Calendar.current.isDate($0.dayDate, inSameDayAs: startOfDay) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    /// 获取今日待办
    func todayItems() -> [TodoItem] {
        // 引用 refreshTrigger 以建立 Observable 依赖
        _ = refreshTrigger
        
        return items(for: Date())
    }
    
    /// 获取某月的所有 DaySection
    func sections(year: Int, month: Int) -> [DaySection] {
        let calendar = Calendar.current
        return daySectionsCache.values
            .filter { section in
                let y = calendar.component(.year, from: section.date)
                let m = calendar.component(.month, from: section.date)
                return y == year && m == month
            }
            .sorted { $0.date > $1.date }
    }
    
    /// 获取所有有数据的月份
    func availableMonths() -> [(year: Int, month: Int)] {
        var uniqueMonths: [(year: Int, month: Int)] = []
        var seen = Set<String>()
        
        let sortedSections = daySectionsCache.values.sorted { $0.date > $1.date }
        for section in sortedSections {
            let key = section.yearMonth
            if !seen.contains(key) {
                seen.insert(key)
                uniqueMonths.append((section.year, section.month))
            }
        }
        
        return uniqueMonths
    }
    
    // MARK: - DaySection 操作
    
    /// 获取或创建今日的 DaySection
    func getOrCreateTodaySection() -> DaySection {
        let today = Calendar.current.startOfDay(for: Date())
        
        // 先从缓存查找
        if let existing = daySectionsCache.values.first(where: { 
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }) {
            return existing
        }
        
        // 创建新的
        let newSection = DaySection(date: today, sortOrder: Double(Date().timeIntervalSince1970))
        
        // 加入缓存
        daySectionsCache[newSection.id] = newSection
        
        // 异步持久化
        modelContext?.insert(newSection)
        scheduleSave()
        
        return newSection
    }
    
    // MARK: - TodoItem 操作
    
    /// 创建新的待办事项
    func createItem(
        title: String = "",
        dayDate: Date,
        afterItem: TodoItem? = nil,
        indentLevel: Int = 0
    ) -> TodoItem {
        let currentItems = items(for: dayDate)
        
        var newSortOrder: Double
        if let afterItem = afterItem,
           let afterIndex = currentItems.firstIndex(where: { $0.id == afterItem.id }) {
            if afterIndex + 1 < currentItems.count {
                let nextItem = currentItems[afterIndex + 1]
                newSortOrder = (afterItem.sortOrder + nextItem.sortOrder) / 2
            } else {
                newSortOrder = afterItem.sortOrder + 1000
            }
        } else if let lastItem = currentItems.last {
            newSortOrder = lastItem.sortOrder + 1000
        } else {
            newSortOrder = 1000
        }
        
        let newItem = TodoItem(
            title: title,
            indentLevel: indentLevel,
            sortOrder: newSortOrder,
            dayDate: dayDate
        )
        
        // 加入缓存（即时响应）
        todoItemsCache[newItem.id] = newItem
        
        // 异步持久化
        modelContext?.insert(newItem)
        scheduleSave()
        
        return newItem
    }
    
    /// 删除待办事项
    func deleteItem(_ item: TodoItem) {
        // 从缓存移除（即时响应）
        todoItemsCache.removeValue(forKey: item.id)
        
        // 异步持久化
        modelContext?.delete(item)
        scheduleSave()
    }
    
    /// 更新待办事项
    func updateItem(_ item: TodoItem) {
        item.updatedAt = Date()
        scheduleSave()
    }
    
    /// 标记完成（包括子任务）
    func toggleComplete(_ item: TodoItem) {
        let allItems = items(for: item.dayDate)
        let newState = !item.isCompleted
        item.isCompleted = newState
        item.updatedAt = Date()
        
        // 找到所有子任务并同步状态
        if let itemIndex = allItems.firstIndex(where: { $0.id == item.id }) {
            let itemIndent = item.indentLevel
            
            for i in (itemIndex + 1)..<allItems.count {
                let child = allItems[i]
                if child.indentLevel > itemIndent {
                    child.isCompleted = newState
                    child.updatedAt = Date()
                } else {
                    break
                }
            }
        }
        
        scheduleSave()
    }
    
    /// 移动待办事项到新位置
    func moveItem(_ item: TodoItem, toDate: Date, afterItem: TodoItem?) {
        let newDate = Calendar.current.startOfDay(for: toDate)
        item.dayDate = newDate
        
        let targetItems = items(for: newDate).filter { $0.id != item.id }
        
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
    
    func scheduleSave() {
        // 立即触发视图刷新
        refreshTrigger += 1
        
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(saveDebounceInterval * 1000)))
            guard !Task.isCancelled else { return }
            await performSave()
        }
    }
    
    func saveNow() {
        saveTask?.cancel()
        Task {
            await performSave()
        }
    }
    
    private func performSave() async {
        do {
            try modelContext?.save()
        } catch {
            print("保存失败: \(error)")
        }
    }
}
