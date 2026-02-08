//
//  TodoStore.swift
//  todo block
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

    /// 焦点恢复请求：撤销后需要聚焦的 item ID
    var focusRequestId: UUID?

    // MARK: - 撤销管理

    let undoManager = TodoUndoManager()

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
        undoManager.clear()
        refreshTrigger += 1
    }

    // MARK: - 撤销操作

    /// 执行撤销操作
    @discardableResult
    func undo() -> Bool {
        guard undoManager.canUndo else { return false }
        undoManager.undo()
        return true
    }

    /// 执行重做操作
    @discardableResult
    func redo() -> Bool {
        guard undoManager.canRedo else { return false }
        undoManager.redo()
        return true
    }

    /// 是否有可撤销的操作
    var canUndo: Bool {
        undoManager.canUndo
    }

    /// 是否有可重做的操作
    var canRedo: Bool {
        undoManager.canRedo
    }

    /// 获取共享的 NSUndoManager（供 TextField 使用）
    var nsUndoManager: UndoManager {
        undoManager.nsUndoManager
    }

    /// 注册缩进变化（供视图层调用）
    func registerIndentChange(itemId: UUID, oldIndent: Int) {
        undoManager.registerIndentChange(itemId: itemId, oldIndent: oldIndent, store: self)
    }

    /// 注册标题变化（供视图层调用）
    func registerTitleChange(itemId: UUID, oldTitle: String) {
        undoManager.registerTitleChange(itemId: itemId, oldTitle: oldTitle, store: self)
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

    /// 删除 DaySection
    func deleteSection(_ section: DaySection) {
        // 从缓存移除
        daySectionsCache.removeValue(forKey: section.id)

        // 从数据库删除
        modelContext?.delete(section)

        refreshTrigger += 1
        scheduleSave()
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
            let afterIndex = currentItems.firstIndex(where: { $0.id == afterItem.id })
        {
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

        // 注册撤销（传入 afterItem 的 ID，撤销时恢复焦点）
        undoManager.registerCreateItem(
            itemId: newItem.id, previousItemId: afterItem?.id, store: self)

        return newItem
    }

    /// 删除待办事项
    func deleteItem(_ item: TodoItem) {
        // 注册撤销（在删除前保存快照）
        let snapshot = TodoItemSnapshot(from: item)
        undoManager.registerDeleteItem(snapshot: snapshot, store: self)

        // 从缓存移除（即时响应）
        todoItemsCache.removeValue(forKey: item.id)

        // 异步持久化
        modelContext?.delete(item)
        scheduleSave()
    }

    /// 删除待办事项（不注册撤销，用于撤销操作内部调用）
    func deleteItemWithoutUndo(_ item: TodoItem) {
        todoItemsCache.removeValue(forKey: item.id)
        modelContext?.delete(item)
        scheduleSave()
    }

    /// 恢复已删除的待办事项
    func restoreItem(from snapshot: TodoItemSnapshot) {
        let restoredItem = TodoItem(
            id: snapshot.id,
            title: snapshot.title,
            isCompleted: snapshot.isCompleted,
            indentLevel: snapshot.indentLevel,
            sortOrder: snapshot.sortOrder,
            dayDate: snapshot.dayDate,
            createdAt: snapshot.createdAt,
            updatedAt: Date()
        )

        todoItemsCache[restoredItem.id] = restoredItem
        modelContext?.insert(restoredItem)
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
        let oldState = item.isCompleted
        let newState = !item.isCompleted

        // 收集子任务的旧状态（用于撤销）
        var childStates: [(UUID, Bool)] = []

        item.isCompleted = newState
        item.updatedAt = Date()

        // 找到所有子任务并同步状态
        if let itemIndex = allItems.firstIndex(where: { $0.id == item.id }) {
            let itemIndent = item.indentLevel

            for i in (itemIndex + 1)..<allItems.count {
                let child = allItems[i]
                if child.indentLevel > itemIndent {
                    childStates.append((child.id, child.isCompleted))
                    child.isCompleted = newState
                    child.updatedAt = Date()
                } else {
                    break
                }
            }
        }

        // 注册撤销
        undoManager.registerToggleComplete(
            itemId: item.id, oldState: oldState, childStates: childStates, store: self)

        scheduleSave()
    }

    /// 移动待办事项到新位置
    func moveItem(_ item: TodoItem, toDate: Date, afterItem: TodoItem?) {
        let newDate = Calendar.current.startOfDay(for: toDate)
        item.dayDate = newDate

        let targetItems = items(for: newDate).filter { $0.id != item.id }

        if let afterItem = afterItem,
            let afterIndex = targetItems.firstIndex(where: { $0.id == afterItem.id })
        {
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

    /// 移动待办事项及其子项到新位置
    func moveItemWithChildren(
        _ item: TodoItem, toDate: Date, afterItem: TodoItem?, newIndentLevel: Int
    ) {
        let sourceDate = item.dayDate
        let sourceItems = items(for: sourceDate)

        // 找到被拖拽项及其所有子项
        guard let itemIndex = sourceItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        var itemsToMove = [item]
        let baseIndent = item.indentLevel

        // 收集所有子项（indentLevel > baseIndent 的连续项）
        for i in (itemIndex + 1)..<sourceItems.count {
            let child = sourceItems[i]
            if child.indentLevel > baseIndent {
                itemsToMove.append(child)
            } else {
                break  // 遇到同级或更高级别项，停止
            }
        }

        // 保存快照（用于撤销）
        let snapshots = itemsToMove.map { TodoItemSnapshot(from: $0) }

        // 计算缩进差异
        let indentDelta = newIndentLevel - baseIndent

        // 计算新的 sortOrder
        let newDate = Calendar.current.startOfDay(for: toDate)
        let targetItems = items(for: newDate).filter { movingItem in
            !itemsToMove.contains { $0.id == movingItem.id }
        }

        var baseSortOrder: Double
        if let afterItem = afterItem,
            let afterIndex = targetItems.firstIndex(where: { $0.id == afterItem.id })
        {
            if afterIndex + 1 < targetItems.count {
                let nextItem = targetItems[afterIndex + 1]
                baseSortOrder = (afterItem.sortOrder + nextItem.sortOrder) / 2
            } else {
                baseSortOrder = afterItem.sortOrder + 1000
            }
        } else if let firstItem = targetItems.first {
            baseSortOrder = firstItem.sortOrder - 1000
        } else {
            baseSortOrder = 1000
        }

        // 移动所有项
        for (offset, movingItem) in itemsToMove.enumerated() {
            movingItem.dayDate = newDate
            movingItem.sortOrder = baseSortOrder + Double(offset) * 0.001  // 保持相对顺序
            movingItem.indentLevel = max(0, min(3, movingItem.indentLevel + indentDelta))
            movingItem.updatedAt = Date()
        }

        // 注册撤销
        undoManager.registerMoveItems(snapshots: snapshots, store: self)

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
