//
//  TodoStore+UITestSeeding.swift
//  todo block
//
//  UI 测试专用的数据播种入口。把「播种守卫待办 + 守卫分组」收进 store 扩展文件，
//  让 todoItemsCache / modelContext / refreshTrigger 的直写留在 friendship 边界内
//  （见 docs/agents/architecture.md），app 层的 ContentSeedUITestHook 只调用这里。
//

import Foundation
import SwiftData

extension TodoStore {
    /// 仅当同时带 -UITestInMemoryStore 与 -UITestSeedContent 启动时生效：
    /// 往内存容器放入一条可识别的待办及其日期分组（「守卫分组」/「守卫待办」），
    /// 供 BackupMenuUITests 验证备份相关的取消操作不改动数据。
    /// 双 flag 门控保证只写内存容器，永不触碰真实用户数据。
    /// 直写 cache + modelContext，刻意不经过 undoManager——
    /// 撤销可用状态应只来自测试里真实的一次 UI 编辑。
    /// 幂等：onAppear 可能多次触发（窗口重建等），只播种一次。
    func seedUITestContentIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestInMemoryStore"),
              arguments.contains("-UITestSeedContent"),
              validTodoItems.isEmpty, validDaySections.isEmpty,
              let modelContext
        else { return }

        let today = Calendar.current.startOfDay(for: .now)
        let (section, _) = ensureSectionMaterialized(for: today)
        section.title = "守卫分组"

        let item = TodoItem(title: "守卫待办", sortOrder: 1, dayDate: today)
        todoItemsCache[item.id] = item
        modelContext.insert(item)
        refreshTrigger += 1
        scheduleSave()
    }
}
