//
//  TodoEditorContinuousInteraction.swift
//  todo block
//

import CoreGraphics
import Foundation

/// 编辑器里一次需要连续接收输入的交互类型。
///
/// 跨项拖选和待办拖动目前仍由不同的业务入口处理，但它们共享同一个
/// 生命周期。这个枚举让编辑器可以拒绝第二个同时开始的连续交互，而不
/// 把两种交互的业务规则混在一起。
enum TodoEditorContinuousInteractionKind: Equatable {
    case crossItemSelection
    case itemDrag
}

/// 一次待办拖动过程中最后一个仍然可以提交的列表内落点。
///
/// 鼠标移动到列表之外时，界面可以暂时没有有效目标，但松开鼠标仍应使用
/// 最后一份可靠落点，而不是把一次本来有效的移动变成随机结果。
struct TodoEditorContinuousDropLocation: Equatable {
    let destination: TodoDropDestination
    let index: Int
    let indentLevel: Int
}

/// 一次连续交互的不可变身份。
///
/// 事件在 AppKit 中可能晚于鼠标松开、Escape 或窗口失焦才送达。调用方
/// 必须把开始时拿到的 token 带回更新和结束入口；过期 token 会被安静忽略。
struct TodoEditorContinuousInteractionToken: Hashable {
    fileprivate let id: UUID
    fileprivate let kind: TodoEditorContinuousInteractionKind

    fileprivate init(
        id: UUID = UUID(),
        kind: TodoEditorContinuousInteractionKind
    ) {
        self.id = id
        self.kind = kind
    }
}

/// 管理编辑器内所有连续交互的共同生命周期。
///
/// 这个对象不决定选择范围、自动滚动或移动目标；那些规则继续由
/// `SelectionManager`、编辑器几何和各自的动作负责人处理。它只负责：
///
/// - 同一个编辑器同时只允许一个连续交互；
/// - 为每次交互发放 token；
/// - 记录跨项拖选的起始项、分组、最后有效鼠标位置和目标；
/// - 结束、取消后让迟到事件失效。
@MainActor
final class TodoEditorContinuousInteraction {
    struct ActiveState: Equatable {
        let token: TodoEditorContinuousInteractionToken
        let itemId: UUID
        let sectionId: UUID?
        var lastLocation: CGPoint?
        var lastValidLocation: CGPoint?
        var targetItemId: UUID?
        var targetSidebarDestination: SidebarDestination?
        var lastValidDrop: TodoEditorContinuousDropLocation?

        var kind: TodoEditorContinuousInteractionKind {
            token.kind
        }
    }

    private(set) var activeState: ActiveState?

    var isActive: Bool {
        activeState != nil
    }

    var activeKind: TodoEditorContinuousInteractionKind? {
        activeState?.kind
    }

    var activeToken: TodoEditorContinuousInteractionToken? {
        activeState?.token
    }

    var lastValidLocation: CGPoint? {
        activeState?.lastValidLocation
    }

    /// 鼠标当前所在位置。它可能暂时没有命中有效目标，主要供自动滚动使用。
    var lastLocation: CGPoint? {
        activeState?.lastLocation
    }

    var targetItemId: UUID? {
        activeState?.targetItemId
    }

    var targetSidebarDestination: SidebarDestination? {
        activeState?.targetSidebarDestination
    }

    var lastValidDrop: TodoEditorContinuousDropLocation? {
        activeState?.lastValidDrop
    }

    @discardableResult
    func begin(
        kind: TodoEditorContinuousInteractionKind,
        itemId: UUID,
        sectionId: UUID? = nil,
        location: CGPoint? = nil
    ) -> TodoEditorContinuousInteractionToken? {
        guard activeState == nil else { return nil }

        let token = TodoEditorContinuousInteractionToken(kind: kind)
        activeState = ActiveState(
            token: token,
            itemId: itemId,
            sectionId: sectionId,
            lastLocation: location,
            lastValidLocation: location,
            targetItemId: itemId,
            targetSidebarDestination: nil,
            lastValidDrop: nil
        )
        return token
    }

    @discardableResult
    func beginCrossItemSelection(
        itemId: UUID,
        sectionId: UUID,
        location: CGPoint? = nil
    ) -> TodoEditorContinuousInteractionToken? {
        begin(
            kind: .crossItemSelection,
            itemId: itemId,
            sectionId: sectionId,
            location: location
        )
    }

    @discardableResult
    func beginItemDrag(
        itemId: UUID,
        location: CGPoint? = nil
    ) -> TodoEditorContinuousInteractionToken? {
        begin(kind: .itemDrag, itemId: itemId, location: location)
    }

    /// 更新交互并可选地记录一个新的有效位置。
    ///
    /// `targetItemId == nil` 表示这次鼠标事件没有命中有效目标。交互本身
    /// 仍保持活动，但最后有效位置和目标不会被无效事件覆盖，这样自动滚动
    /// 和鼠标松开时仍能使用最后一份可靠信息。
    @discardableResult
    func update(
        token: TodoEditorContinuousInteractionToken,
        itemId: UUID? = nil,
        location: CGPoint? = nil,
        targetItemId: UUID? = nil,
        validDrop: TodoEditorContinuousDropLocation? = nil,
        sidebarDestination: SidebarDestination? = nil
    ) -> Bool {
        guard var state = activeState,
              state.token == token,
              itemId == nil || itemId == state.itemId
        else { return false }

        if let location {
            state.lastLocation = location
        }
        if let targetItemId {
            state.targetItemId = targetItemId
            state.targetSidebarDestination = nil
            if let location {
                state.lastValidLocation = location
            }
            if let validDrop {
                state.lastValidDrop = validDrop
            }
        }
        if let sidebarDestination {
            state.targetSidebarDestination = sidebarDestination
            state.targetItemId = nil
        }
        activeState = state
        return true
    }

    /// 记录鼠标当前位置，但不把它当成可提交落点。
    ///
    /// 拖到编辑区外时仍需要继续自动滚动；这和“最后有效位置”是两个不同
    /// 的概念，因此不能通过 `update(... targetItemId: nil)` 伪造一个目标。
    @discardableResult
    func updateLocation(
        token: TodoEditorContinuousInteractionToken,
        itemId: UUID? = nil,
        location: CGPoint
    ) -> Bool {
        guard var state = activeState,
              state.token == token,
              itemId == nil || itemId == state.itemId
        else { return false }
        state.lastLocation = location
        activeState = state
        return true
    }

    @discardableResult
    func clearSidebarTarget(
        token: TodoEditorContinuousInteractionToken,
        itemId: UUID? = nil
    ) -> Bool {
        guard var state = activeState,
              state.token == token,
              itemId == nil || itemId == state.itemId
        else { return false }
        state.targetSidebarDestination = nil
        activeState = state
        return true
    }

    /// 目标已经离开界面或被删除；保留过程身份供调用方完成统一取消。
    @discardableResult
    func invalidateTarget(
        token: TodoEditorContinuousInteractionToken,
        itemId: UUID? = nil
    ) -> Bool {
        guard var state = activeState,
              state.token == token,
              itemId == nil || itemId == state.itemId
        else { return false }
        state.targetItemId = nil
        state.targetSidebarDestination = nil
        state.lastValidDrop = nil
        activeState = state
        return true
    }

    func accepts(
        token: TodoEditorContinuousInteractionToken,
        itemId: UUID? = nil,
        kind: TodoEditorContinuousInteractionKind? = nil
    ) -> Bool {
        guard let state = activeState,
              state.token == token,
              itemId == nil || itemId == state.itemId,
              kind == nil || kind == state.kind
        else { return false }
        return true
    }

    /// 正常结束一次交互，并让 token 立即失效。
    @discardableResult
    func end(token: TodoEditorContinuousInteractionToken) -> Bool {
        guard accepts(token: token) else { return false }
        activeState = nil
        return true
    }

    /// 取消一次交互，并让 token 立即失效。
    @discardableResult
    func cancel(token: TodoEditorContinuousInteractionToken) -> Bool {
        end(token: token)
    }

    /// 用于编辑器内容消失或控制器销毁时的收尾。之后原先保存的 token
    /// 不会再匹配任何事件。
    func clear() {
        activeState = nil
    }
}
