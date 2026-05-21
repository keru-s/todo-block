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
    private static let logger = Logger(subsystem: "com.insight.to-do-block", category: "persistence")

    // MARK: - 内存缓存

    private(set) var todoItemsCache: [UUID: TodoItem] = [:]
    private(set) var daySectionsCache: [UUID: DaySection] = [:]

    /// 刷新触发器：每次数据变化时递增，强制依赖它的视图刷新
    private(set) var refreshTrigger: Int = 0

    /// 拖拽指示线重置触发器：拖拽结束后统一清理所有列表的插入提示线
    private(set) var dropIndicatorResetTrigger: Int = 0

    /// 焦点恢复请求：撤销后需要聚焦的 item ID
    var focusRequestId: UUID?

    /// 最近一次持久化失败的错误。出错时 modelContext 已被 rollback，
    /// UI 可订阅此属性做提示（本仓库暂未实现 banner）。
    private(set) var lastSaveError: Error?

    // MARK: - 撤销管理

    let undoManager = TodoUndoManager()

    // MARK: - 私有属性

    private var modelContext: ModelContext?
    private var saveTask: Task<Void, Never>?
    private let saveDebounceInterval: TimeInterval = 0.3
    private let schemaVersionDefaultsKey = "todo.block.schema.version"

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
        migrateCachedItemsIfNeeded()
        cleanupAllOrphanSections()
    }

    /// 用于测试：重置状态
    func reset() {
        saveTask?.cancel()
        saveTask = nil
        modelContext = nil
        clearCachesAndState(clearUndo: true)
    }

    /// 重新从数据库加载缓存（用于外部数据变更后的显式同步）
    func reloadFromPersistentStore() {
        loadFromDatabase()
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
    func registerIndentChange(itemId: UUID, oldIndent: Int, newIndent: Int) {
        undoManager.registerIndentChange(
            itemId: itemId, oldIndent: oldIndent, newIndent: newIndent, store: self)
    }

    /// 注册标题变化（供视图层调用）
    func registerTitleChange(itemId: UUID, oldTitle: String, newTitle: String) {
        undoManager.registerTitleChange(
            itemId: itemId, oldTitle: oldTitle, newTitle: newTitle, store: self)
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

    private func isValid(model item: TodoItem) -> Bool {
        guard item.isDeleted == false else { return false }
        guard let modelContext else { return true }
        return item.modelContext === modelContext
    }

    private func isValid(model section: DaySection) -> Bool {
        guard section.isDeleted == false else { return false }
        guard let modelContext else { return true }
        return section.modelContext === modelContext
    }

    private var validTodoItems: [TodoItem] {
        todoItemsCache.values.filter { isValid(model: $0) }
    }

    private var validDaySections: [DaySection] {
        daySectionsCache.values.filter { isValid(model: $0) }
    }

    private func migrateCachedItemsIfNeeded() {
        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionDefaultsKey)
        guard storedVersion < TodoModelContainerFactory.currentModelVersion else { return }

        var hasChanges = false
        for item in todoItemsCache.values where item.containerKindRaw.isEmpty {
            item.containerKindRaw = TodoContainerKind.scheduled.rawValue
            item.updatedAt = Date()
            hasChanges = true
        }

        UserDefaults.standard.set(
            TodoModelContainerFactory.currentModelVersion,
            forKey: schemaVersionDefaultsKey
        )

        if hasChanges {
            refreshTrigger += 1
            scheduleSave()
        }
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

    // MARK: - DaySection 操作

    /// 获取或创建今日的 DaySection
    func getOrCreateTodaySection() -> DaySection {
        getOrCreateSection(for: Date())
    }

    /// 获取或创建指定日期的 DaySection。
    /// 若新建则 bump refreshTrigger + scheduleSave；命中现存 section 时为 no-op。
    /// 内部写路径（createItem / restoreItem / moveItemWithChildren）已在末尾统一 bump+save，
    /// 应改用 `ensureSectionMaterialized(for:)` 跳过这层冗余触发。
    @discardableResult
    func getOrCreateSection(for date: Date) -> DaySection {
        let (section, didCreate) = ensureSectionMaterialized(for: date)
        if didCreate {
            refreshTrigger += 1
            scheduleSave()
        }
        return section
    }

    /// 仅落实 DaySection 在 cache + modelContext 中的存在，不 bump 也不 schedule save。
    /// 用于"调用方自己稍后会统一 bump+save"的内部写路径。
    @discardableResult
    private func ensureSectionMaterialized(for date: Date) -> (section: DaySection, didCreate: Bool) {
        let targetDate = Calendar.current.startOfDay(for: date)

        if let existing = validDaySections.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }) {
            return (existing, false)
        }

        let newSection = DaySection(date: targetDate, sortOrder: Double(Date().timeIntervalSince1970))
        daySectionsCache[newSection.id] = newSection
        modelContext?.insert(newSection)
        return (newSection, true)
    }

    /// 删除 DaySection
    func deleteSection(_ section: DaySection) {
        daySectionsCache.removeValue(forKey: section.id)
        modelContext?.delete(section)

        refreshTrigger += 1
        scheduleSave()
    }

    /// 若指定 scheduled 日期下已无任何 item，则同步删除对应 DaySection。
    /// 调用方负责后续的 refreshTrigger / scheduleSave，避免重复触发。
    private func cleanupSectionIfEmpty(scheduledDate: Date) {
        let targetDate = Calendar.current.startOfDay(for: scheduledDate)
        guard let section = validDaySections.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }) else { return }

        let hasItems = validTodoItems.contains { item in
            item.containerKind == .scheduled
                && Calendar.current.isDate(item.dayDate, inSameDayAs: targetDate)
        }
        guard hasItems == false else { return }

        daySectionsCache.removeValue(forKey: section.id)
        modelContext?.delete(section)
    }

    /// 启动时回收没有任何 scheduled item 引用的 DaySection（清理旧版本累积的孤儿）。
    private func cleanupAllOrphanSections() {
        let calendar = Calendar.current
        let scheduledDates: Set<Date> = Set(
            validTodoItems
                .filter { $0.containerKind == .scheduled }
                .map { calendar.startOfDay(for: $0.dayDate) }
        )

        var didDelete = false
        for section in validDaySections {
            let sectionDate = calendar.startOfDay(for: section.date)
            if scheduledDates.contains(sectionDate) == false {
                daySectionsCache.removeValue(forKey: section.id)
                modelContext?.delete(section)
                didDelete = true
            }
        }

        if didDelete {
            refreshTrigger += 1
            scheduleSave()
        }
    }

    // MARK: - TodoItem 操作

    /// 创建新的待办事项
    func createItem(
        title: String = "",
        dayDate: Date,
        afterItem: TodoItem? = nil,
        indentLevel: Int = 0,
        containerKind: TodoContainerKind = .scheduled,
        insertAtBeginning: Bool = false
    ) -> TodoItem {
        let normalizedDate = Calendar.current.startOfDay(for: dayDate)
        let destination: TodoDropDestination = {
            switch containerKind {
            case .scheduled:
                return .scheduled(date: normalizedDate)
            case .longTermUrgent:
                return .longTerm(isUrgent: true)
            case .longTermImportant:
                return .longTerm(isUrgent: false)
            }
        }()

        let currentItems = items(in: destination)
        var newSortOrder: Double

        if let afterItem,
            let afterIndex = currentItems.firstIndex(where: { $0.id == afterItem.id })
        {
            if afterIndex + 1 < currentItems.count {
                let nextItem = currentItems[afterIndex + 1]
                newSortOrder = (afterItem.sortOrder + nextItem.sortOrder) / 2
            } else {
                newSortOrder = afterItem.sortOrder + 1000
            }
        } else if insertAtBeginning, let firstItem = currentItems.first {
            newSortOrder = firstItem.sortOrder - 1000
        } else if let lastItem = currentItems.last {
            newSortOrder = lastItem.sortOrder + 1000
        } else {
            newSortOrder = 1000
        }

        if containerKind == .scheduled {
            _ = ensureSectionMaterialized(for: normalizedDate)
        }

        let newItem = TodoItem(
            title: title,
            indentLevel: indentLevel,
            sortOrder: newSortOrder,
            containerKindRaw: containerKind.rawValue,
            dayDate: normalizedDate
        )

        todoItemsCache[newItem.id] = newItem

        modelContext?.insert(newItem)
        refreshTrigger += 1
        scheduleSave()

        undoManager.registerCreateItem(
            itemId: newItem.id, previousItemId: afterItem?.id, store: self)

        return newItem
    }

    /// 删除待办事项
    func deleteItem(_ item: TodoItem) {
        let snapshot = TodoItemSnapshot(from: item)
        undoManager.registerDeleteItem(snapshot: snapshot, store: self)

        let scheduledDate: Date? = item.containerKind == .scheduled ? item.dayDate : nil
        todoItemsCache.removeValue(forKey: item.id)
        modelContext?.delete(item)
        if let scheduledDate {
            cleanupSectionIfEmpty(scheduledDate: scheduledDate)
        }
        refreshTrigger += 1
        scheduleSave()
    }

    /// 删除待办事项（不注册撤销，用于撤销操作内部调用）
    func deleteItemWithoutUndo(_ item: TodoItem) {
        let scheduledDate: Date? = item.containerKind == .scheduled ? item.dayDate : nil
        todoItemsCache.removeValue(forKey: item.id)
        modelContext?.delete(item)
        if let scheduledDate {
            cleanupSectionIfEmpty(scheduledDate: scheduledDate)
        }
        refreshTrigger += 1
        scheduleSave()
    }

    /// 恢复已删除的待办事项
    func restoreItem(from snapshot: TodoItemSnapshot) {
        // 让 pending 的 delete 先落盘，避免与下方 insert 撞 @Attribute(.unique) UUID
        flushPendingChangesSync()
        let restoredItem = TodoItem(
            id: snapshot.id,
            title: snapshot.title,
            isCompleted: snapshot.isCompleted,
            indentLevel: snapshot.indentLevel,
            sortOrder: snapshot.sortOrder,
            containerKindRaw: snapshot.containerKindRaw,
            dayDate: snapshot.dayDate,
            createdAt: snapshot.createdAt,
            updatedAt: Date()
        )

        if restoredItem.containerKind == .scheduled {
            _ = ensureSectionMaterialized(for: restoredItem.dayDate)
        }

        todoItemsCache[restoredItem.id] = restoredItem
        modelContext?.insert(restoredItem)
        refreshTrigger += 1
        scheduleSave()
    }

    /// 更新待办事项
    func updateItem(_ item: TodoItem) {
        item.updatedAt = Date()
        scheduleSave()
    }

    /// 标记完成（包括子任务）
    func toggleComplete(_ item: TodoItem) {
        let allItems = items(in: destination(for: item))
        let oldState = item.isCompleted
        let newState = oldState == false

        var childStates: [(UUID, Bool)] = []

        item.isCompleted = newState
        item.updatedAt = Date()

        if let itemIndex = allItems.firstIndex(where: { $0.id == item.id }) {
            let itemIndent = item.indentLevel

            for index in (itemIndex + 1)..<allItems.count {
                let child = allItems[index]
                if child.indentLevel > itemIndent {
                    childStates.append((child.id, child.isCompleted))
                    child.isCompleted = newState
                    child.updatedAt = Date()
                } else {
                    break
                }
            }
        }

        let childNewStates = childStates.map { ($0.0, newState) }
        undoManager.registerToggleComplete(
            itemId: item.id,
            oldState: oldState,
            newState: newState,
            childOldStates: childStates,
            childNewStates: childNewStates,
            store: self
        )

        scheduleSave()
    }

    /// 兼容旧接口：移动待办事项到指定日期
    func moveItem(_ item: TodoItem, toDate: Date, afterItem: TodoItem?) {
        moveItemWithChildren(
            item,
            to: .scheduled(date: toDate),
            afterItem: afterItem,
            newIndentLevel: item.indentLevel
        )
    }

    /// 移动待办事项及其子项到新位置
    func moveItemWithChildren(
        _ item: TodoItem,
        to destination: TodoDropDestination,
        afterItem: TodoItem?,
        newIndentLevel: Int
    ) {
        let normalizedDestination = destination.normalized
        let sourceDestination = self.destination(for: item)
        let sourceItems = items(in: sourceDestination)

        guard let itemIndex = sourceItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        var itemsToMove = [item]
        var movingIds: Set<UUID> = [item.id]
        let baseIndent = item.indentLevel

        for index in (itemIndex + 1)..<sourceItems.count {
            let child = sourceItems[index]
            if child.indentLevel > baseIndent {
                itemsToMove.append(child)
                movingIds.insert(child.id)
            } else {
                break
            }
        }

        let snapshots = itemsToMove.map { TodoItemSnapshot(from: $0) }
        let indentDelta = newIndentLevel - baseIndent

        let targetItems = items(in: normalizedDestination).filter { movingIds.contains($0.id) == false }

        let baseSortOrder: Double
        if let afterItem,
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

        if case .scheduled(let date) = normalizedDestination {
            _ = ensureSectionMaterialized(for: date)
        }

        for (offset, movingItem) in itemsToMove.enumerated() {
            movingItem.containerKind = normalizedDestination.containerKind
            if case .scheduled(let date) = normalizedDestination {
                movingItem.dayDate = date
            }
            movingItem.sortOrder = baseSortOrder + Double(offset) * 0.001
            movingItem.indentLevel = max(
                0,
                min(TodoItem.maxIndentLevel, movingItem.indentLevel + indentDelta)
            )
            movingItem.updatedAt = Date()
        }

        let movedSnapshots = itemsToMove.map { TodoItemSnapshot(from: $0) }
        undoManager.registerMoveItems(from: snapshots, to: movedSnapshots, store: self)

        // 若源是 scheduled 且目标 ≠ 源，源日期可能变成空 section，清理掉。
        if case .scheduled(let sourceDate) = sourceDestination.normalized,
           sourceDestination.normalized != normalizedDestination {
            cleanupSectionIfEmpty(scheduledDate: sourceDate)
        }

        refreshTrigger += 1
        scheduleSave()
    }

    // MARK: - 异步保存

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(saveDebounceInterval * 1000)))
            guard Task.isCancelled == false else { return }
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
}
