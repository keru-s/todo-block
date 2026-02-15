//
//  SelectionManager.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI

enum VerticalMoveDirection {
    case up
    case down
}

/// 集中管理多选、焦点移动、删除等逻辑
@MainActor
@Observable
final class SelectionManager {
    // MARK: - 状态属性

    var focusedItemId: UUID?
    var selectedItemIds: Set<UUID> = []

    // Shift多选时的锚点
    var lastSelectedId: UUID?
    private var dragAnchorId: UUID?
    private(set) var isDragSelecting: Bool = false

    // 光标位置
    var cursorPosition: Int = 0
    var preferredHorizontalOffset: CGFloat?
    var verticalMoveDirection: VerticalMoveDirection?

    // MARK: - 选择逻辑

    /// 处理点击选择
    /// - Parameters:
    ///   - item: 被点击的待办事项
    ///   - allItems: 当前视图上下文中展示的所有待办事项（有序）
    ///   - shiftPressed: 是否按下了 Shift 键
    ///   - isCommandPressed: 是否按下了 Command 键 (预留)
    func handleSelect(
        item: TodoItem, allItems: [TodoItem], shiftPressed: Bool, cursorPosition: Int? = nil
    ) {
        isDragSelecting = false
        dragAnchorId = nil
        preferredHorizontalOffset = nil
        verticalMoveDirection = nil

        if let pos = cursorPosition {
            self.cursorPosition = pos
        }

        if shiftPressed, let lastId = lastSelectedId {
            // Shift 范围选择
            if let startIndex = allItems.firstIndex(where: { $0.id == lastId }),
                let endIndex = allItems.firstIndex(where: { $0.id == item.id })
            {
                let range = min(startIndex, endIndex)...max(startIndex, endIndex)
                for i in range {
                    selectedItemIds.insert(allItems[i].id)
                }
            }
        } else {
            // 单选
            selectedItemIds = [item.id]
            lastSelectedId = item.id
        }

        // 无论如何，焦点跟随点击
        focusedItemId = item.id
    }

    /// 长按开始：以当前 item 为锚点开始连续多选
    func beginDragSelection(item: TodoItem, allItems: [TodoItem], cursorPosition: Int? = nil) {
        preferredHorizontalOffset = nil
        verticalMoveDirection = nil

        if let pos = cursorPosition {
            self.cursorPosition = pos
        }

        isDragSelecting = true
        dragAnchorId = item.id
        lastSelectedId = item.id
        focusedItemId = item.id
        selectedItemIds = [item.id]
    }

    /// 长按拖拽更新：按锚点与当前命中项形成连续范围
    func updateDragSelection(to item: TodoItem, allItems: [TodoItem]) {
        guard isDragSelecting, let anchorId = dragAnchorId else { return }
        guard
            let anchorIndex = allItems.firstIndex(where: { $0.id == anchorId }),
            let targetIndex = allItems.firstIndex(where: { $0.id == item.id })
        else { return }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedItemIds = Set(range.map { allItems[$0].id })
        focusedItemId = item.id
    }

    /// 长按拖拽结束
    func endDragSelection() {
        isDragSelecting = false
        dragAnchorId = nil
    }

    /// 清除所有选择
    func clearSelection() {
        if selectedItemIds.count > 1 {
            selectedItemIds.removeAll()
        }
    }

    // MARK: - 焦点移动

    /// 移动焦点到上一项
    /// - Parameters:
    ///   - item: 当前 item
    ///   - allItems: 所有 items
    ///   - cursorPosition: 光标位置（可选，不传则使用当前保存的位置）
    func moveFocusUp(
        from item: TodoItem,
        allItems: [TodoItem],
        cursorPosition: Int? = nil,
        preferredHorizontalOffset: CGFloat? = nil
    ) {
        guard let currentIndex = allItems.firstIndex(where: { $0.id == item.id }),
            currentIndex > 0
        else { return }

        let targetItem = allItems[currentIndex - 1]
        if let pos = cursorPosition {
            self.cursorPosition = pos
        }
        setFocusAndSelect(
            targetItem,
            verticalMoveDirection: .up,
            preferredHorizontalOffset: preferredHorizontalOffset
        )
    }

    /// 移动焦点到下一项
    /// - Parameters:
    ///   - item: 当前 item
    ///   - allItems: 所有 items
    ///   - cursorPosition: 光标位置（可选，不传则使用当前保存的位置）
    func moveFocusDown(
        from item: TodoItem,
        allItems: [TodoItem],
        cursorPosition: Int? = nil,
        preferredHorizontalOffset: CGFloat? = nil
    ) {
        guard let currentIndex = allItems.firstIndex(where: { $0.id == item.id }),
            currentIndex + 1 < allItems.count
        else { return }

        let targetItem = allItems[currentIndex + 1]
        if let pos = cursorPosition {
            self.cursorPosition = pos
        }
        setFocusAndSelect(
            targetItem,
            verticalMoveDirection: .down,
            preferredHorizontalOffset: preferredHorizontalOffset
        )
    }

    /// 直接设置焦点并选中
    private func setFocusAndSelect(
        _ item: TodoItem,
        verticalMoveDirection: VerticalMoveDirection? = nil,
        preferredHorizontalOffset: CGFloat? = nil
    ) {
        focusedItemId = item.id
        selectedItemIds = [item.id]
        lastSelectedId = item.id
        self.verticalMoveDirection = verticalMoveDirection
        self.preferredHorizontalOffset = preferredHorizontalOffset
    }

    /// 从外部（如撤销/重做）恢复焦点
    func restoreFocus(to itemId: UUID?) {
        focusedItemId = itemId
        preferredHorizontalOffset = nil
        verticalMoveDirection = nil
        if let itemId {
            selectedItemIds = [itemId]
            lastSelectedId = itemId
        } else {
            selectedItemIds.removeAll()
            lastSelectedId = nil
        }
    }

    // MARK: - 删除逻辑

    /// 删除当前选中的项目，并自动计算下一个焦点
    /// - Parameters:
    ///   - store: TodoStore 实例
    ///   - allItemsLookup: 一个闭包，用于获取某一天的所有 items（用于计算上下文）
    func deleteSelectedItems(store: TodoStore, allItemsLookup: (Date) -> [TodoItem]) {
        guard !selectedItemIds.isEmpty else { return }

        let itemsToDelete = selectedItemIds.compactMap { id in store.todoItemsCache[id] }
        // 优先以当前焦点作为删除锚点；否则使用选中项中排序最靠前的项
        let firstSelectedId: UUID? =
            if let focusedItemId, selectedItemIds.contains(focusedItemId) {
                focusedItemId
            } else {
                itemsToDelete
                    .sorted {
                        if Calendar.current.isDate($0.dayDate, inSameDayAs: $1.dayDate) {
                            return $0.sortOrder < $1.sortOrder
                        }
                        return $0.dayDate < $1.dayDate
                    }
                    .first?.id
            }

        // 计算下一个焦点
        // 我们只需要根据第一个被删除的项目来决定焦点去向即可
        var nextFocusId: UUID? = nil

        if let firstSelectedId,
            let firstItemToDelete = store.todoItemsCache[firstSelectedId]
        {
            let allItems = allItemsLookup(firstItemToDelete.dayDate)

            if let firstIndex = allItems.firstIndex(where: { $0.id == firstItemToDelete.id }) {
                // 1. 尝试向上找最近未被删除的
                for i in stride(from: firstIndex - 1, through: 0, by: -1) {
                    if !selectedItemIds.contains(allItems[i].id) {
                        nextFocusId = allItems[i].id
                        break
                    }
                }

                // 2. 如果上面没了，尝试向下找
                if nextFocusId == nil {
                    for i in (firstIndex + 1)..<allItems.count {
                        if !selectedItemIds.contains(allItems[i].id) {
                            nextFocusId = allItems[i].id
                            break
                        }
                    }
                }
            }
        }

        // 执行删除
        for item in itemsToDelete {
            store.deleteItem(item)
        }

        // 重置状态
        selectedItemIds.removeAll()

        // 恢复焦点
        focusedItemId = nextFocusId
        if let nextId = nextFocusId {
            selectedItemIds = [nextId]
            lastSelectedId = nextId
        }
    }
}
