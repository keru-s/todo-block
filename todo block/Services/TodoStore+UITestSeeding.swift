//
//  TodoStore+UITestSeeding.swift
//  todo block
//
//  UI 测试专用的数据播种入口。
//  让 todoItemsCache / modelContext / refreshTrigger 的直写留在 friendship 边界内
//  （见 docs/agents/architecture.md），app 层的 ContentSeedUITestHook 只调用这里。
//

import Foundation
import SwiftData

extension TodoStore {
    /// 只在启用内存容器和明确指定测试数据时播种。
    /// 直写 cache + modelContext，刻意不经过 undoManager——
    /// 撤销可用状态应只来自测试里真实的一次 UI 编辑。
    /// 幂等：onAppear 可能多次触发（窗口重建等），只播种一次。
    func seedUITestContentIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestInMemoryStore"),
              validTodoItems.isEmpty, validDaySections.isEmpty,
              let modelContext
        else { return }

        let fixture: (sectionTitle: String?, titles: [String])
        if arguments.contains("-UITestSeedContent") {
            fixture = ("守卫分组", ["守卫待办"])
        } else if arguments.contains("-UITestSeedCopyMarkdown") {
            fixture = (nil, ["Alpha", "Beta", "Gamma"])
        } else {
            return
        }

        let today = Calendar.current.startOfDay(for: .now)
        let (section, _) = ensureSectionMaterialized(for: today)
        if let title = fixture.sectionTitle {
            section.title = title
        }

        for (index, title) in fixture.titles.enumerated() {
            let item = TodoItem(title: title, sortOrder: Double(index + 1), dayDate: today)
            todoItemsCache[item.id] = item
            modelContext.insert(item)
        }
        refreshTrigger += 1
        scheduleSave()
    }
}
