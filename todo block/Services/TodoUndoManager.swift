//
//  TodoUndoManager.swift
//  todo block
//
//  Created by Claude on 2026/2/9.
//

import Foundation

enum TodoOperationValueTarget {
    case before
    case after
}

struct TodoCompletionChange {
    let itemId: UUID
    let before: Bool
    let after: Bool

    func value(for target: TodoOperationValueTarget) -> Bool {
        switch target {
        case .before:
            before
        case .after:
            after
        }
    }
}

struct TodoItemExistenceChange {
    let snapshot: TodoItemSnapshot
    let beforeExists: Bool
    let afterExists: Bool

    func exists(for target: TodoOperationValueTarget) -> Bool {
        switch target {
        case .before:
            beforeExists
        case .after:
            afterExists
        }
    }
}

struct TodoItemStateChange {
    let before: TodoItemSnapshot
    let after: TodoItemSnapshot

    func snapshot(for target: TodoOperationValueTarget) -> TodoItemSnapshot {
        switch target {
        case .before:
            before
        case .after:
            after
        }
    }
}

struct TodoSelectionState: Equatable {
    let focusedItemId: UUID?
    let selectedItemIds: Set<UUID>
    let lastSelectedId: UUID?
    let cursorPosition: Int
    let textSelectionLength: Int

    init(selectionManager: SelectionManager) {
        focusedItemId = selectionManager.focusedItemId
        selectedItemIds = selectionManager.selectedItemIds
        lastSelectedId = selectionManager.lastSelectedId
        cursorPosition = selectionManager.cursorPosition
        textSelectionLength = selectionManager.textSelectionLength
    }

    init(focusing itemId: UUID?, cursorPosition: Int = 0) {
        focusedItemId = itemId
        selectedItemIds = itemId.map { [$0] } ?? []
        lastSelectedId = itemId
        self.cursorPosition = cursorPosition
        textSelectionLength = 0
    }

    init(
        focusedItemId: UUID?,
        selectedItemIds: Set<UUID>,
        lastSelectedId: UUID?,
        cursorPosition: Int,
        textSelectionLength: Int = 0
    ) {
        self.focusedItemId = focusedItemId
        self.selectedItemIds = selectedItemIds
        self.lastSelectedId = lastSelectedId
        self.cursorPosition = cursorPosition
        self.textSelectionLength = textSelectionLength
    }

    func apply(to selectionManager: SelectionManager) {
        selectionManager.focusedItemId = focusedItemId
        selectionManager.selectedItemIds = selectedItemIds
        selectionManager.lastSelectedId = lastSelectedId
        selectionManager.cursorPosition = cursorPosition
        selectionManager.textSelectionLength = textSelectionLength
        selectionManager.preferredHorizontalOffset = nil
        selectionManager.verticalMoveDirection = nil
    }
}

struct TodoSelectionChange {
    let historyContext: TodoSelectionHistoryContext
    let before: TodoSelectionState
    let after: TodoSelectionState

    init(
        selectionManager: SelectionManager,
        before: TodoSelectionState,
        after: TodoSelectionState
    ) {
        selectionManager.activateHistoryContext()
        historyContext = selectionManager.historyContext
        self.before = before
        self.after = after
    }

    func state(for target: TodoOperationValueTarget) -> TodoSelectionState {
        switch target {
        case .before:
            before
        case .after:
            after
        }
    }

    func apply(for target: TodoOperationValueTarget) {
        guard let selectionManager = SelectionManager.activeManager(for: historyContext) else {
            return
        }
        state(for: target).apply(to: selectionManager)
    }
}

struct TodoOperation {
    let actionName: String
    var completionChanges: [TodoCompletionChange] = []
    var itemExistenceChanges: [TodoItemExistenceChange] = []
    var itemStateChanges: [TodoItemStateChange] = []
    var selectionChanges: [TodoSelectionChange] = []

    var isEmpty: Bool {
        completionChanges.isEmpty
            && itemExistenceChanges.isEmpty
            && itemStateChanges.isEmpty
    }
}

// MARK: - TodoItem 快照（用于恢复已删除或移动的项目）

struct TodoItemSnapshot {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let indentLevel: Int
    let sortOrder: Double
    let containerKindRaw: String
    let dayDate: Date
    let createdAt: Date
    let updatedAt: Date

    init(from item: TodoItem) {
        self.id = item.id
        self.title = item.title
        self.isCompleted = item.isCompleted
        self.indentLevel = item.indentLevel
        self.sortOrder = item.sortOrder
        self.containerKindRaw = item.containerKindRaw
        self.dayDate = item.dayDate
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        indentLevel: Int,
        sortOrder: Double,
        containerKindRaw: String,
        dayDate: Date,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.indentLevel = indentLevel
        self.sortOrder = sortOrder
        self.containerKindRaw = containerKindRaw
        self.dayDate = Calendar.current.startOfDay(for: dayDate)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func matchesUserState(of item: TodoItem) -> Bool {
        item.id == id
            && item.title == title
            && item.isCompleted == isCompleted
            && item.indentLevel == indentLevel
            && item.sortOrder == sortOrder
            && item.containerKindRaw == containerKindRaw
            && item.dayDate == dayDate
            && item.createdAt == createdAt
    }

    func matchesUserState(of snapshot: TodoItemSnapshot) -> Bool {
        snapshot.id == id
            && snapshot.title == title
            && snapshot.isCompleted == isCompleted
            && snapshot.indentLevel == indentLevel
            && snapshot.sortOrder == sortOrder
            && snapshot.containerKindRaw == containerKindRaw
            && snapshot.dayDate == dayDate
            && snapshot.createdAt == createdAt
    }

    func replacing(
        title: String? = nil,
        indentLevel: Int? = nil,
        sortOrder: Double? = nil,
        containerKindRaw: String? = nil,
        dayDate: Date? = nil
    ) -> TodoItemSnapshot {
        TodoItemSnapshot(
            id: id,
            title: title ?? self.title,
            isCompleted: isCompleted,
            indentLevel: indentLevel ?? self.indentLevel,
            sortOrder: sortOrder ?? self.sortOrder,
            containerKindRaw: containerKindRaw ?? self.containerKindRaw,
            dayDate: dayDate ?? self.dayDate,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

}

// MARK: - 统一撤销管理器（基于 NSUndoManager）

/// 使用 NSUndoManager 统一管理所有撤销操作
/// 这样可以与 TextField 的原生撤销共享同一个撤销栈
@MainActor
@Observable
final class TodoUndoManager {
    private struct TodayImpact {
        let scheduledDays: Set<Date>

        func affectsToday(on date: Date, calendar: Calendar) -> Bool {
            scheduledDays.contains { calendar.isDate($0, inSameDayAs: date) }
        }
    }

    /// 共享的 NSUndoManager 实例
    private let nsUndoManager = UndoManager()

    /// 最大撤销步数
    private let maxUndoSteps = 50

    private enum InvocationResult {
        case applied
        case invalid
    }

    private var invocationResult = InvocationResult.invalid
    private var historyRevision = 0
    private var undoTodayImpacts: [TodayImpact] = []
    private var redoTodayImpacts: [TodayImpact] = []

    /// 是否有可撤销的操作
    var canUndo: Bool {
        _ = historyRevision
        return nsUndoManager.canUndo
    }

    /// 是否有可重做的操作
    var canRedo: Bool {
        _ = historyRevision
        return nsUndoManager.canRedo
    }

    var undoActionName: String {
        nsUndoManager.undoActionName
    }

    func nextUndoAffectsToday(on date: Date) -> Bool? {
        undoTodayImpacts.last?.affectsToday(on: date, calendar: .current)
    }

    func nextRedoAffectsToday(on date: Date) -> Bool? {
        redoTodayImpacts.last?.affectsToday(on: date, calendar: .current)
    }

    init() {
        nsUndoManager.levelsOfUndo = maxUndoSteps
        nsUndoManager.groupsByEvent = false
    }

    @discardableResult
    func perform(_ operation: TodoOperation, store: TodoStore) -> Bool {
        store.flushPendingTextEdit()
        guard operation.isEmpty == false else { return false }
        guard canApply(operation, target: .after, store: store) else { return false }

        guard apply(operation, target: .after, store: store) else { return false }
        register(operation, target: .before, store: store)
        store.scheduleSave()
        return true
    }

    @discardableResult
    func recordApplied(_ operation: TodoOperation, store: TodoStore) -> Bool {
        guard operation.isEmpty == false else { return false }
        guard canApply(operation, target: .before, store: store) else { return false }
        register(operation, target: .before, store: store)
        store.scheduleSave()
        return true
    }

    private func register(
        _ operation: TodoOperation,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) {
        recordHistoryRegistration(operation, store: store)
        registerStandalone {
            nsUndoManager.registerUndo(withTarget: store) { [weak self] store in
                guard let self else { return }
                guard self.canApply(operation, target: target, store: store) else {
                    self.invocationResult = .invalid
                    return
                }

                guard self.apply(operation, target: target, store: store) else {
                    self.invocationResult = .invalid
                    return
                }
                self.invocationResult = .applied
                self.revealResult(of: operation, target: target, store: store)
                let oppositeTarget: TodoOperationValueTarget =
                    target == .before ? .after : .before
                self.register(operation, target: oppositeTarget, store: store)
                store.scheduleSave()
            }
            nsUndoManager.setActionName(operation.actionName)
        }
    }

    private func recordHistoryRegistration(_ operation: TodoOperation, store: TodoStore) {
        let todayImpact = todayImpact(of: operation, store: store)
        if nsUndoManager.isUndoing {
            redoTodayImpacts.append(todayImpact)
            trimHistory(&redoTodayImpacts)
        } else if nsUndoManager.isRedoing {
            undoTodayImpacts.append(todayImpact)
            trimHistory(&undoTodayImpacts)
        } else {
            undoTodayImpacts.append(todayImpact)
            trimHistory(&undoTodayImpacts)
            redoTodayImpacts.removeAll()
        }
    }

    private func trimHistory(_ history: inout [TodayImpact]) {
        if history.count > maxUndoSteps {
            history.removeFirst(history.count - maxUndoSteps)
        }
    }

    private func todayImpact(of operation: TodoOperation, store: TodoStore) -> TodayImpact {
        let snapshots = operation.itemExistenceChanges.map(\.snapshot)
            + operation.itemStateChanges.flatMap { [$0.before, $0.after] }
        let snapshotDays = snapshots.compactMap { snapshot -> Date? in
            guard (TodoContainerKind(rawValue: snapshot.containerKindRaw) ?? .scheduled)
                == .scheduled
            else { return nil }
            return snapshot.dayDate
        }
        let completionDays = operation.completionChanges.compactMap { change -> Date? in
            guard let item = store.todoItemsCache[change.itemId],
                  item.containerKind == .scheduled
            else { return nil }
            return item.dayDate
        }
        return TodayImpact(scheduledDays: Set(snapshotDays + completionDays))
    }

    private func registerStandalone(_ registration: () -> Void) {
        let opensGroup = nsUndoManager.isUndoing == false
            && nsUndoManager.isRedoing == false
            && nsUndoManager.groupingLevel == 0
        if opensGroup {
            nsUndoManager.beginUndoGrouping()
        }
        registration()
        if opensGroup {
            nsUndoManager.endUndoGrouping()
        }
        historyRevision += 1
    }

    private func revealResult(
        of operation: TodoOperation,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) {
        let selectionIds = operation.selectionChanges.reversed().flatMap { change in
            let state = change.state(for: target)
            return [state.focusedItemId].compactMap { $0 }
                + Array(state.selectedItemIds)
        }
        let changedIds = operation.itemStateChanges.map { $0.snapshot(for: target).id }
            + operation.itemExistenceChanges.map(\.snapshot.id)
            + operation.completionChanges.map(\.itemId)
        let resultItem = (selectionIds + changedIds).lazy.compactMap {
            store.todoItemsCache[$0]
        }.first
        let resultSelectionState = operation.selectionChanges.last?.state(for: target)

        let fallbackSnapshot = operation.itemStateChanges.first?.snapshot(for: target)
            ?? operation.itemExistenceChanges.first?.snapshot
        let resultDestination: TodoDropDestination?
        if let resultItem {
            resultDestination = store.destination(for: resultItem)
        } else if let fallbackSnapshot {
            resultDestination = destination(for: fallbackSnapshot)
        } else if let completion = operation.completionChanges.first,
                  let item = store.todoItemsCache[completion.itemId] {
            resultDestination = store.destination(for: item)
        } else {
            resultDestination = nil
        }

        guard let resultDestination else { return }
        TodoHistoryPresentationCoordinator.shared.reveal(
            destination: resultDestination,
            itemId: resultItem?.id,
            selectionState: resultSelectionState
        )
    }

    private func destination(for snapshot: TodoItemSnapshot) -> TodoDropDestination {
        switch TodoContainerKind(rawValue: snapshot.containerKindRaw) ?? .scheduled {
        case .scheduled:
            .scheduled(date: snapshot.dayDate)
        case .longTermUrgent:
            .longTerm(isUrgent: true)
        case .longTermImportant:
            .longTerm(isUrgent: false)
        }
    }

    private func canApply(
        _ operation: TodoOperation,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) -> Bool {
        let sourceTarget: TodoOperationValueTarget = target == .before ? .after : .before
        let completionChangesAreValid = operation.completionChanges.allSatisfy { change in
            guard let item = store.todoItemsCache[change.itemId] else { return false }
            return item.isCompleted == change.value(for: sourceTarget)
        }
        guard completionChangesAreValid else { return false }

        let itemStateChangesAreValid = operation.itemStateChanges.allSatisfy { change in
            let sourceSnapshot = change.snapshot(for: sourceTarget)
            guard let item = store.todoItemsCache[sourceSnapshot.id] else { return false }
            return sourceSnapshot.matchesUserState(of: item)
        }
        guard itemStateChangesAreValid else { return false }

        return operation.itemExistenceChanges.allSatisfy { change in
            let sourceExists = change.exists(for: sourceTarget)
            guard sourceExists else {
                return store.todoItemsCache[change.snapshot.id] == nil
            }
            guard let item = store.todoItemsCache[change.snapshot.id] else { return false }
            return change.snapshot.matchesUserState(of: item)
        }
    }

    private func apply(
        _ operation: TodoOperation,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) -> Bool {
        let snapshotsToRestore: [TodoItemSnapshot] =
            operation.itemExistenceChanges.compactMap { change -> TodoItemSnapshot? in
            guard
                change.exists(for: target),
                store.todoItemsCache[change.snapshot.id] == nil
            else { return nil }
            return change.snapshot
        }
        guard store.restoreItems(from: snapshotsToRestore) else {
            return false
        }

        for change in operation.completionChanges {
            guard let item = store.todoItemsCache[change.itemId] else { continue }
            item.isCompleted = change.value(for: target)
            item.updatedAt = .now
        }

        guard store.applyExistingItemSnapshots(
            operation.itemStateChanges.map { $0.snapshot(for: target) }
        ) else {
            return false
        }

        for change in operation.itemExistenceChanges
        where change.exists(for: target) == false {
            guard let item = store.todoItemsCache[change.snapshot.id] else { continue }
            store.deleteItemWithoutUndo(item)
        }

        operation.selectionChanges.forEach { $0.apply(for: target) }
        return true
    }

    /// 执行撤销
    @discardableResult
    func undo() -> Bool {
        while nsUndoManager.canUndo {
            if undoTodayImpacts.isEmpty == false {
                undoTodayImpacts.removeLast()
            }
            invocationResult = .invalid
            nsUndoManager.undo()
            historyRevision += 1
            switch invocationResult {
            case .invalid:
                continue
            case .applied:
                return true
            }
        }
        return false
    }

    /// 执行重做
    @discardableResult
    func redo() -> Bool {
        while nsUndoManager.canRedo {
            if redoTodayImpacts.isEmpty == false {
                redoTodayImpacts.removeLast()
            }
            invocationResult = .invalid
            nsUndoManager.redo()
            historyRevision += 1
            switch invocationResult {
            case .invalid:
                continue
            case .applied:
                return true
            }
        }
        return false
    }

    /// 清空撤销栈
    func clear() {
        nsUndoManager.removeAllActions()
        undoTodayImpacts.removeAll()
        redoTodayImpacts.removeAll()
        historyRevision += 1
    }
}
