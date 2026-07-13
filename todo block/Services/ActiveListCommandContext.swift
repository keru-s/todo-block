//
//  ActiveListCommandContext.swift
//  todo block
//
//  Thin facade：把 TodoClipboardManager / TodoReorderCommandManager 的
//  activateListContext 合成一次调用。
//
//  视图层（TodoListView / LongTermListView / MenuBarView）原本要分别
//  调两次 activateListContext，三处重复。统一后扩展只需在 bind / clear
//  各加一行，调用方零改动。
//
//  注意：popover willShow/didClose 通知仍由各 view 自己监听 — 因为
//  "本 view 当前是否应 active" 是 view 的状态判断，不属于 facade 职责。
//

import Foundation

@MainActor
enum ActiveListCommandContext {
    /// 一次绑定剪贴板与重排两套命令上下文。
    static func bind(
        scope: TodoClipboardScope,
        store: TodoStore,
        selectionManager: SelectionManager
    ) {
        selectionManager.activateHistoryContext()
        TodoHistoryPresentationCoordinator.shared.activate(scope: scope)
        TodoClipboardManager.shared.activateListContext(
            scope: scope,
            store: store,
            selectionManager: selectionManager
        )
        TodoReorderCommandManager.shared.activateListContext(
            store: store,
            selectionManager: selectionManager
        )
    }
}
