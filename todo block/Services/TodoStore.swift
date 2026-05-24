//
//  TodoStore.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import Foundation
import OSLog
import SwiftData

/// 单例数据存储，内存缓存 + 异步持久化
/// 主窗口和菜单栏共享此实例，实现数据同步
@MainActor
@Observable
final class TodoStore {
    static let shared = TodoStore()

    @ObservationIgnored
    static let logger = Logger(subsystem: "com.insight.to-do-block", category: "persistence")

    // MARK: - 内存缓存
    // 注：以下属性丢掉了 `private(set)` 以便 TodoStore 的 extension 文件
    // (TodoStore+DaySectionMaintenance / TodoStore+Persistence) 跨文件读写。
    // 视图层不应直接修改这些缓存——通过公共 API（createItem / deleteItem / ...）。

    var todoItemsCache: [UUID: TodoItem] = [:]
    var daySectionsCache: [UUID: DaySection] = [:]

    /// 刷新触发器：每次数据变化时递增，强制依赖它的视图刷新
    var refreshTrigger: Int = 0

    /// 拖拽指示线重置触发器：拖拽结束后统一清理所有列表的插入提示线
    var dropIndicatorResetTrigger: Int = 0

    /// 焦点恢复请求：撤销后需要聚焦的 item ID
    var focusRequestId: UUID?

    /// 最近一次持久化失败的错误。出错时 modelContext 已被 rollback，
    /// UI 可订阅此属性做提示（本仓库暂未实现 banner）。
    var lastSaveError: Error?

    // MARK: - 撤销管理

    let undoManager = TodoUndoManager()

    // MARK: - 内部状态（@ObservationIgnored，extension 跨文件需要访问）

    @ObservationIgnored
    var modelContext: ModelContext?

    @ObservationIgnored
    var saveTask: Task<Void, Never>?

    @ObservationIgnored
    let saveDebounceInterval: TimeInterval = 0.3

    private init() {}

    // MARK: - 初始化

    /// 初始化并从数据库加载数据到缓存
    func initialize(with modelContext: ModelContext) {
        if let existingContext = self.modelContext, existingContext !== modelContext {
            clearCachesAndState(clearUndo: true)
        }
        saveTask?.cancel()
        self.modelContext = modelContext
        loadFromDatabase()
        cleanupAllOrphanSections()
    }

    /// 用于测试：重置状态
    func reset() {
        saveTask?.cancel()
        saveTask = nil
        modelContext = nil
        clearCachesAndState(clearUndo: true)
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

    /// 触发一次焦点恢复请求（用于撤销/重做后的光标恢复）
    func requestFocus(_ itemId: UUID?) {
        focusRequestId = nil
        focusRequestId = itemId
    }

    /// 触发全局拖拽提示线重置（用于修复跨列表残留插入线）
    func requestDropIndicatorReset() {
        dropIndicatorResetTrigger += 1
    }

    /// 通知所有依赖派生集合（items(for:)/longTermItems 等）的视图刷新。
    /// 仅在改变了"哪些 item 属于哪个 bucket / 顺序如何"的写操作末尾调用；
    /// 字段级编辑（title/isCompleted/indentLevel）由 @Bindable item 自动驱动，无需调用。
    func bumpRefreshTrigger() {
        refreshTrigger += 1
    }

    private func loadFromDatabase() {
        guard let modelContext = modelContext else { return }

        var loadedSections: [UUID: DaySection] = [:]
        var loadedItems: [UUID: TodoItem] = [:]

        // 加载所有 DaySection
        let sectionDescriptor = FetchDescriptor<DaySection>()
        if let sections = try? modelContext.fetch(sectionDescriptor) {
            for section in sections {
                loadedSections[section.id] = section
            }
        }

        // 加载所有 TodoItem
        let itemDescriptor = FetchDescriptor<TodoItem>()
        if let items = try? modelContext.fetch(itemDescriptor) {
            for item in items {
                loadedItems[item.id] = item
            }
        }

        // 全量替换缓存，避免残留已失效的 SwiftData 实例
        daySectionsCache = loadedSections
        todoItemsCache = loadedItems
        refreshTrigger += 1
    }

    private func clearCachesAndState(clearUndo: Bool) {
        todoItemsCache.removeAll()
        daySectionsCache.removeAll()
        focusRequestId = nil
        if clearUndo {
            undoManager.clear()
        }
        refreshTrigger += 1
    }

    func isValid(model item: TodoItem) -> Bool {
        guard item.isDeleted == false else { return false }
        guard let modelContext else { return true }
        return item.modelContext === modelContext
    }

    func isValid(model section: DaySection) -> Bool {
        guard section.isDeleted == false else { return false }
        guard let modelContext else { return true }
        return section.modelContext === modelContext
    }

    var validTodoItems: [TodoItem] {
        todoItemsCache.values.filter { isValid(model: $0) }
    }

    var validDaySections: [DaySection] {
        daySectionsCache.values.filter { isValid(model: $0) }
    }

    // MARK: - 查询方法（从缓存）

    /// 获取某日的所有待办事项（按 sortOrder 排序）
    func items(for date: Date) -> [TodoItem] {
        _ = refreshTrigger

        let startOfDay = Calendar.current.startOfDay(for: date)
        return validTodoItems
            .filter {
                $0.containerKind == .scheduled
                    && Calendar.current.isDate($0.dayDate, inSameDayAs: startOfDay)
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 获取今日待办
    func todayItems() -> [TodoItem] {
        _ = refreshTrigger
        return items(for: Date())
    }

    /// 获取长期列表
    func longTermItems(isUrgent: Bool) -> [TodoItem] {
        _ = refreshTrigger

        let targetKind: TodoContainerKind = isUrgent ? .longTermUrgent : .longTermImportant
        return validTodoItems
            .filter { $0.containerKind == targetKind }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func destination(for item: TodoItem) -> TodoDropDestination {
        switch item.containerKind {
        case .scheduled:
            .scheduled(date: Calendar.current.startOfDay(for: item.dayDate))
        case .longTermUrgent:
            .longTerm(isUrgent: true)
        case .longTermImportant:
            .longTerm(isUrgent: false)
        }
    }

    func items(in destination: TodoDropDestination) -> [TodoItem] {
        switch destination.normalized {
        case .scheduled(let date):
            items(for: date)
        case .longTerm(let isUrgent):
            longTermItems(isUrgent: isUrgent)
        }
    }

    /// 获取某月最新日期（仅 scheduled 容器）
    func latestScheduledDate(year: Int, month: Int) -> Date? {
        let calendar = Calendar.current
        return validTodoItems
            .filter {
                $0.containerKind == .scheduled
                    && calendar.component(.year, from: $0.dayDate) == year
                    && calendar.component(.month, from: $0.dayDate) == month
            }
            .map { calendar.startOfDay(for: $0.dayDate) }
            .max()
    }

    /// 目标月份为空时，用今天日号夹紧到目标月份天数
    func fallbackDateForEmptyMonth(year: Int, month: Int, today: Date = .now) -> Date {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: today)

        var monthComponents = DateComponents()
        monthComponents.year = year
        monthComponents.month = month
        monthComponents.day = 1

        guard let monthStart = calendar.date(from: monthComponents) else {
            return calendar.startOfDay(for: today)
        }

        let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        monthComponents.day = min(day, maxDay)
        let targetDate = calendar.date(from: monthComponents) ?? monthStart
        return calendar.startOfDay(for: targetDate)
    }

    /// 获取某月的最后一项（优先该月最新 DaySection 日期 -> 该日期最后一项）
    func tailItemForScheduledMonth(year: Int, month: Int) -> (date: Date, tailItem: TodoItem?) {
        if let latestSectionDate = sections(year: year, month: month).first?.date {
            let normalizedDate = Calendar.current.startOfDay(for: latestSectionDate)
            return (normalizedDate, items(for: normalizedDate).last)
        }

        if let latestDate = latestScheduledDate(year: year, month: month) {
            return (latestDate, items(for: latestDate).last)
        }

        let fallbackDate = fallbackDateForEmptyMonth(year: year, month: month)
        return (fallbackDate, nil)
    }

    /// 获取某月的所有 DaySection
    func sections(year: Int, month: Int) -> [DaySection] {
        let calendar = Calendar.current
        return validDaySections
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

        let sortedSections = validDaySections.sorted { $0.date > $1.date }
        for section in sortedSections {
            let key = section.yearMonth
            if seen.contains(key) == false {
                seen.insert(key)
                uniqueMonths.append((section.year, section.month))
            }
        }

        return uniqueMonths
    }

    // MARK: - DaySection 操作（实现移至 TodoStore+DaySectionMaintenance.swift）

    // MARK: - TodoItem 操作（实现移至 TodoStore+ItemMutations.swift）

    // MARK: - 异步保存（实现移至 TodoStore+Persistence.swift）
}
