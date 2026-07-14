import Foundation
import Observation

enum TodoTextEditKind: Equatable {
    case insertion
    case deletion
    case replacement
}

struct TodoTextSelection: Equatable {
    let location: Int
    let length: Int

    init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    var range: NSRange {
        NSRange(location: location, length: length)
    }
}

enum TodoTextInputSession: Equatable {
    case dictation(UUID)
}

struct TodoTextEditEvent: Equatable {
    let beforeText: String
    let afterText: String
    let beforeSelection: TodoTextSelection
    let afterSelection: TodoTextSelection
    let kind: TodoTextEditKind
    let inputSession: TodoTextInputSession?

    init(
        beforeText: String,
        afterText: String,
        beforeSelection: TodoTextSelection,
        afterSelection: TodoTextSelection,
        kind: TodoTextEditKind,
        inputSession: TodoTextInputSession? = nil
    ) {
        self.beforeText = beforeText
        self.afterText = afterText
        self.beforeSelection = beforeSelection
        self.afterSelection = afterSelection
        self.kind = kind
        self.inputSession = inputSession
    }
}

@MainActor
@Observable
final class TodoTextEditSession {
    private struct PendingSegment {
        let itemId: UUID
        let kind: TodoTextEditKind
        let inputSession: TodoTextInputSession?
        let before: TodoItemSnapshot
        var after: TodoItemSnapshot
        let selectionManager: SelectionManager
        let selectionBefore: TodoSelectionState
        var selectionAfter: TodoSelectionState
        var afterTextSelection: TodoTextSelection
        var lastEditAt: ContinuousClock.Instant
    }

    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private var pending: PendingSegment?
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    private(set) var hasPendingSegment = false

    func apply(
        _ event: TodoTextEditEvent,
        to item: TodoItem,
        selectionManager: SelectionManager,
        store: TodoStore
    ) {
        guard item.title == event.beforeText, event.beforeText != event.afterText else { return }
        let now = clock.now
        let continuesCurrentSegment = pending.map { segment in
            let continuesNamedInputSession = event.inputSession.map {
                segment.inputSession == $0
            } ?? false
            let continuesOrdinaryInput = event.inputSession == nil
                && segment.inputSession == nil
                && segment.kind == event.kind
                && now - segment.lastEditAt < .seconds(1)
            return segment.itemId == item.id
                && segment.after.title == event.beforeText
                && segment.afterTextSelection == event.beforeSelection
                && (continuesNamedInputSession || continuesOrdinaryInput)
        } ?? false

        if continuesCurrentSegment == false {
            flush(store: store)
        }

        item.title = event.afterText
        item.updatedAt = .now
        selectionManager.focusedItemId = item.id
        selectionManager.selectedItemIds = [item.id]
        selectionManager.lastSelectedId = item.id
        selectionManager.cursorPosition = event.afterSelection.location
        selectionManager.textSelectionLength = event.afterSelection.length
        store.scheduleSave()

        if var segment = pending, continuesCurrentSegment {
            segment.after = segment.after.replacing(title: event.afterText)
            segment.selectionAfter = selectionState(
                selectionManager: selectionManager,
                textSelection: event.afterSelection
            )
            segment.afterTextSelection = event.afterSelection
            segment.lastEditAt = now
            pending = segment
        } else {
            let beforeSnapshot = TodoItemSnapshot(from: item).replacing(title: event.beforeText)
            pending = PendingSegment(
                itemId: item.id,
                kind: event.kind,
                inputSession: event.inputSession,
                before: beforeSnapshot,
                after: TodoItemSnapshot(from: item),
                selectionManager: selectionManager,
                selectionBefore: selectionState(
                    selectionManager: selectionManager,
                    textSelection: event.beforeSelection
                ),
                selectionAfter: selectionState(
                    selectionManager: selectionManager,
                    textSelection: event.afterSelection
                ),
                afterTextSelection: event.afterSelection,
                lastEditAt: now
            )
        }
        hasPendingSegment = true
        if event.inputSession == nil {
            scheduleFlush(store: store)
        } else {
            flushTask?.cancel()
            flushTask = nil
        }
    }

    func selectionDidChange(
        itemId: UUID,
        selection: TodoTextSelection,
        selectionManager: SelectionManager,
        store: TodoStore
    ) {
        if let pending,
           pending.itemId != itemId || pending.afterTextSelection != selection {
            flush(store: store)
        }
        selectionManager.cursorPosition = selection.location
        selectionManager.textSelectionLength = selection.length
    }

    @discardableResult
    func flush(store: TodoStore) -> Bool {
        flushTask?.cancel()
        flushTask = nil
        guard let segment = pending else { return false }
        pending = nil
        hasPendingSegment = false
        return store.undoManager.recordApplied(
            TodoOperation(
                actionName: "编辑",
                itemStateChanges: [
                    TodoItemStateChange(before: segment.before, after: segment.after)
                ],
                selectionChanges: [
                    TodoSelectionChange(
                        selectionManager: segment.selectionManager,
                        before: segment.selectionBefore,
                        after: segment.selectionAfter
                    )
                ]
            ),
            store: store
        )
    }

    func reset() {
        flushTask?.cancel()
        flushTask = nil
        pending = nil
        hasPendingSegment = false
    }

    private func scheduleFlush(store: TodoStore) {
        flushTask?.cancel()
        flushTask = Task { @MainActor [weak self, weak store] in
            try? await Task.sleep(for: .seconds(1))
            guard Task.isCancelled == false, let self, let store else { return }
            self.flush(store: store)
        }
    }

    private func selectionState(
        selectionManager: SelectionManager,
        textSelection: TodoTextSelection
    ) -> TodoSelectionState {
        TodoSelectionState(
            focusedItemId: selectionManager.focusedItemId,
            selectedItemIds: selectionManager.selectedItemIds,
            lastSelectedId: selectionManager.lastSelectedId,
            cursorPosition: textSelection.location,
            textSelectionLength: textSelection.length
        )
    }
}
