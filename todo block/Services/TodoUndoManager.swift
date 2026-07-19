//
//  TodoUndoManager.swift
//  todo block
//

import Foundation

enum TodoOperationValueTarget {
    case before
    case after
}

// MARK: - 旧入口的临时描述

/// 旧调用点在迁移期间仍使用这些描述。它们会在进入 `TodoUndoManager` 时一次性转换为
/// `TodoOperationUnit`，不会形成第二套历史。
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

    func operationUnit(
        sourceTarget: TodoOperationValueTarget,
        store: TodoStore
    ) -> TodoOperationUnit? {
        guard isEmpty == false else { return nil }

        var transitions = itemExistenceChanges.map {
            TodoItemTransition(
                before: $0.exists(for: .before) ? $0.snapshot : nil,
                after: $0.exists(for: .after) ? $0.snapshot : nil
            )
        }
        transitions.append(contentsOf: itemStateChanges.map {
            TodoItemTransition(before: $0.before, after: $0.after)
        })

        for change in completionChanges {
            guard let currentItem = store.todoItemsCache[change.itemId] else { return nil }
            let currentSnapshot = TodoItemSnapshot(from: currentItem)
            guard currentSnapshot.isCompleted == change.value(for: sourceTarget) else { return nil }
            transitions.append(
                TodoItemTransition(
                    before: currentSnapshot.replacing(isCompleted: change.before),
                    after: currentSnapshot.replacing(isCompleted: change.after)
                )
            )
        }

        return TodoOperationUnit(
            actionName: actionName,
            itemTransitions: transitions,
            selectionTransitions: selectionChanges.map(TodoSelectionTransition.init)
        )
    }
}

// MARK: - 操作单元

/// 一个待办在一个操作单元两端的完整用户状态。`nil` 表示该待办在该端不存在。
struct TodoItemTransition {
    let before: TodoItemSnapshot?
    let after: TodoItemSnapshot?

    init(before: TodoItemSnapshot?, after: TodoItemSnapshot?) {
        self.before = before
        self.after = after
    }

    var itemId: UUID? {
        before?.id ?? after?.id
    }

    var isValid: Bool {
        guard let itemId else { return false }
        return before.map { $0.id == itemId } ?? true
            && after.map { $0.id == itemId } ?? true
    }

    var changesUserState: Bool {
        switch (before, after) {
        case (nil, nil):
            false
        case let (before?, after?):
            before.matchesUserState(of: after) == false
        default:
            true
        }
    }

    func snapshot(for target: TodoOperationValueTarget) -> TodoItemSnapshot? {
        switch target {
        case .before:
            before
        case .after:
            after
        }
    }
}

/// 历史只记录可移植的选择值及其所属列表，不保留活的界面对象。
struct TodoSelectionTransition {
    let historyContext: TodoSelectionHistoryContext
    let before: TodoSelectionState
    let after: TodoSelectionState

    init(
        historyContext: TodoSelectionHistoryContext,
        before: TodoSelectionState,
        after: TodoSelectionState
    ) {
        self.historyContext = historyContext
        self.before = before
        self.after = after
    }

    init(_ legacyChange: TodoSelectionChange) {
        self.init(
            historyContext: legacyChange.historyContext,
            before: legacyChange.before,
            after: legacyChange.after
        )
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

/// 唯一进入正式历史的记录。规则模块只应计算这个单元，应用和登记由 `TodoUndoManager` 负责。
struct TodoOperationUnit {
    let actionName: String
    let itemTransitions: [TodoItemTransition]
    let selectionTransitions: [TodoSelectionTransition]

    init(
        actionName: String,
        itemTransitions: [TodoItemTransition] = [],
        selectionTransitions: [TodoSelectionTransition] = []
    ) {
        self.actionName = actionName
        self.itemTransitions = itemTransitions.filter(\.changesUserState)
        self.selectionTransitions = selectionTransitions
    }

    var isEmpty: Bool {
        itemTransitions.isEmpty
    }

    var isValid: Bool {
        let ids = itemTransitions.compactMap(\.itemId)
        return itemTransitions.allSatisfy(\.isValid) && Set(ids).count == ids.count
    }

    func snapshots(for target: TodoOperationValueTarget) -> [TodoItemSnapshot] {
        itemTransitions.compactMap { $0.snapshot(for: target) }
    }
}

// MARK: - TodoItem 快照

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
        id = item.id
        title = item.title
        isCompleted = item.isCompleted
        indentLevel = item.indentLevel
        sortOrder = item.sortOrder
        containerKindRaw = item.containerKindRaw
        dayDate = item.dayDate
        createdAt = item.createdAt
        updatedAt = item.updatedAt
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
        isCompleted: Bool? = nil,
        indentLevel: Int? = nil,
        sortOrder: Double? = nil,
        containerKindRaw: String? = nil,
        dayDate: Date? = nil
    ) -> TodoItemSnapshot {
        TodoItemSnapshot(
            id: id,
            title: title ?? self.title,
            isCompleted: isCompleted ?? self.isCompleted,
            indentLevel: indentLevel ?? self.indentLevel,
            sortOrder: sortOrder ?? self.sortOrder,
            containerKindRaw: containerKindRaw ?? self.containerKindRaw,
            dayDate: dayDate ?? self.dayDate,
            createdAt: createdAt,
            updatedAt: .now
        )
    }
}

// MARK: - 统一操作历史

@MainActor
@Observable
final class TodoUndoManager {
    private let maxUndoSteps = 50
    private var undoHistory: [TodoOperationUnit] = []
    private var redoHistory: [TodoOperationUnit] = []
    private var historyRevision = 0

    var canUndo: Bool {
        _ = historyRevision
        return undoHistory.isEmpty == false
    }

    var canRedo: Bool {
        _ = historyRevision
        return redoHistory.isEmpty == false
    }

    var undoActionName: String {
        _ = historyRevision
        return undoHistory.last?.actionName ?? ""
    }

    func nextUndoAffectsToday(on date: Date) -> Bool? {
        _ = historyRevision
        return undoHistory.last.map { affectsToday($0, on: date) }
    }

    func nextRedoAffectsToday(on date: Date) -> Bool? {
        _ = historyRevision
        return redoHistory.last.map { affectsToday($0, on: date) }
    }

    @discardableResult
    func perform(_ operation: TodoOperation, store: TodoStore) -> Bool {
        store.flushPendingTextEdit()
        guard let unit = operation.operationUnit(sourceTarget: .before, store: store) else {
            return false
        }
        return perform(unit, store: store)
    }

    @discardableResult
    func perform(_ unit: TodoOperationUnit, store: TodoStore) -> Bool {
        store.flushPendingTextEdit()
        guard unit.isEmpty == false, unit.isValid else { return false }
        guard canApply(unit, target: .after, store: store) else { return false }
        guard apply(unit, target: .after, store: store) else { return false }
        appendNewHistory(unit)
        store.scheduleSave()
        return true
    }

    /// 仅用于连续文字输入这类已即时呈现的变化：当前状态必须已经等于 `after`。
    @discardableResult
    func recordApplied(_ operation: TodoOperation, store: TodoStore) -> Bool {
        guard let unit = operation.operationUnit(sourceTarget: .after, store: store) else {
            return false
        }
        return recordApplied(unit, store: store)
    }

    @discardableResult
    func recordApplied(_ unit: TodoOperationUnit, store: TodoStore) -> Bool {
        guard unit.isEmpty == false, unit.isValid else { return false }
        guard canApply(unit, target: .before, store: store) else { return false }
        appendNewHistory(unit)
        store.scheduleSave()
        return true
    }

    @discardableResult
    func undo() -> Bool {
        while let unit = undoHistory.popLast() {
            historyRevision += 1
            let store = TodoStore.shared
            guard canApply(unit, target: .before, store: store) else { continue }
            guard apply(unit, target: .before, store: store) else { continue }
            redoHistory.append(unit)
            historyRevision += 1
            store.scheduleSave()
            revealResult(of: unit, target: .before, store: store)
            return true
        }
        return false
    }

    @discardableResult
    func redo() -> Bool {
        while let unit = redoHistory.popLast() {
            historyRevision += 1
            let store = TodoStore.shared
            guard canApply(unit, target: .after, store: store) else { continue }
            guard apply(unit, target: .after, store: store) else { continue }
            undoHistory.append(unit)
            historyRevision += 1
            store.scheduleSave()
            revealResult(of: unit, target: .after, store: store)
            return true
        }
        return false
    }

    func clear() {
        undoHistory.removeAll()
        redoHistory.removeAll()
        historyRevision += 1
    }

    private func appendNewHistory(_ unit: TodoOperationUnit) {
        undoHistory.append(unit)
        if undoHistory.count > maxUndoSteps {
            undoHistory.removeFirst(undoHistory.count - maxUndoSteps)
        }
        redoHistory.removeAll()
        historyRevision += 1
    }

    private func canApply(
        _ unit: TodoOperationUnit,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) -> Bool {
        let sourceTarget: TodoOperationValueTarget = target == .before ? .after : .before
        return unit.itemTransitions.allSatisfy { transition in
            switch transition.snapshot(for: sourceTarget) {
            case let snapshot?:
                guard let item = store.todoItemsCache[snapshot.id] else { return false }
                return snapshot.matchesUserState(of: item)
            case nil:
                guard let itemId = transition.itemId else { return false }
                return store.todoItemsCache[itemId] == nil
            }
        }
    }

    private func apply(
        _ unit: TodoOperationUnit,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) -> Bool {
        let sourceTarget: TodoOperationValueTarget = target == .before ? .after : .before
        let createSnapshots = unit.itemTransitions.compactMap { transition -> TodoItemSnapshot? in
            guard transition.snapshot(for: sourceTarget) == nil else { return nil }
            return transition.snapshot(for: target)
        }
        let updateSnapshots = unit.itemTransitions.compactMap { transition -> TodoItemSnapshot? in
            guard transition.snapshot(for: sourceTarget) != nil else { return nil }
            return transition.snapshot(for: target)
        }
        let deleteIds = unit.itemTransitions.compactMap { transition -> UUID? in
            guard transition.snapshot(for: sourceTarget) != nil,
                  transition.snapshot(for: target) == nil
            else { return nil }
            return transition.itemId
        }

        // `canApply` 已完整验证全部前态；以下三个存储调用在此前提下不会留下半个操作。
        guard store.restoreItems(from: createSnapshots) else { return false }
        guard store.applyExistingItemSnapshots(updateSnapshots) else { return false }
        for itemId in deleteIds {
            guard let item = store.todoItemsCache[itemId] else { return false }
            store.deleteItemWithoutUndo(item)
        }
        unit.selectionTransitions.forEach { $0.apply(for: target) }
        return true
    }

    private func affectsToday(_ unit: TodoOperationUnit, on date: Date) -> Bool {
        unit.itemTransitions.contains { transition in
            [transition.before, transition.after].contains(where: { snapshot in
                guard let snapshot,
                      TodoContainerKind(rawValue: snapshot.containerKindRaw) == .scheduled
                else { return false }
                return Calendar.current.isDate(snapshot.dayDate, inSameDayAs: date)
            })
        }
    }

    private func revealResult(
        of unit: TodoOperationUnit,
        target: TodoOperationValueTarget,
        store: TodoStore
    ) {
        let selectionIds = unit.selectionTransitions.reversed().flatMap { transition in
            let state = transition.state(for: target)
            return [state.focusedItemId].compactMap { $0 } + Array(state.selectedItemIds)
        }
        let changedIds = unit.snapshots(for: target).map(\.id)
        let resultItem = (selectionIds + changedIds).lazy.compactMap { store.todoItemsCache[$0] }.first
        let resultSelectionState = unit.selectionTransitions.last?.state(for: target)
        let fallbackSnapshot = unit.snapshots(for: target).first

        let resultDestination: TodoDropDestination?
        if let resultItem {
            resultDestination = store.destination(for: resultItem)
        } else if let fallbackSnapshot {
            resultDestination = destination(for: fallbackSnapshot)
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
}
