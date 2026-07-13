//
//  TodoStore+DaySectionMaintenance.swift
//  todo block
//

import Foundation
import SwiftData

/// DaySection 生命周期：创建 / 落实 / 清理。
/// 与 TodoStore CRUD 解耦，让"item 写路径触发 section 维护"的逻辑集中在一处。
extension TodoStore {
    /// 获取或创建今日的 DaySection
    func getOrCreateTodaySection() -> DaySection {
        getOrCreateSection(for: Date())
    }

    /// 获取或创建指定日期的 DaySection。
    /// 若新建则 bump refreshTrigger + scheduleSave；命中现存 section 时为 no-op。
    /// 内部写路径（createItem / restoreItems / moveItemWithChildren）已在末尾统一 bump+save，
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
    func ensureSectionMaterialized(for date: Date) -> (section: DaySection, didCreate: Bool) {
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

    /// 若指定 scheduled 日期下已无任何 item，则同步删除对应 DaySection。
    /// 调用方负责后续的 refreshTrigger / scheduleSave，避免重复触发。
    func cleanupSectionIfEmpty(scheduledDate: Date) {
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
    func cleanupAllOrphanSections() {
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
}
