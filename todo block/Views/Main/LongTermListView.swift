//
//  LongTermListView.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftData
import SwiftUI

struct LongTermListView: View {
    var isActiveContext: Bool = true

    @State private var selectionManager = SelectionManager(historyContext: .longTerm)
    @State private var handledHistoryRevealId: UUID?

    private var store: TodoStore { TodoStore.shared }
    private var historyPresentation: TodoHistoryPresentationCoordinator { .shared }
    private let urgentSectionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1))
    private let importantSectionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2))

    private var editorSections: [TodoEditorSectionSnapshot] {
        [
            TodoEditorSectionSnapshot(
                id: urgentSectionId,
                title: "紧急",
                destination: .longTerm(isUrgent: true),
                items: store.longTermItems(isUrgent: true).map {
                    TodoEditorItemSnapshot(item: $0, selectionManager: selectionManager)
                }
            ),
            TodoEditorSectionSnapshot(
                id: importantSectionId,
                title: "重要",
                destination: .longTerm(isUrgent: false),
                items: store.longTermItems(isUrgent: false).map {
                    TodoEditorItemSnapshot(item: $0, selectionManager: selectionManager)
                }
            )
        ]
    }

    var body: some View {
        TodoEditorRepresentable(
            sections: editorSections,
            emptyTitle: "暂无长期待办",
            actions: TodoEditorActionFactory.make(
                store: store,
                selectionManager: selectionManager
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            bindContextsIfNeeded()
            restoreRequestedFocusIfVisible()
            restoreHistoryRevealIfVisible(historyPresentation.revealRequest)
        }
        .onChange(of: isActiveContext) { _, newValue in
            guard newValue else { return }
            bindContextsIfNeeded()
            restoreRequestedFocusIfVisible()
            restoreHistoryRevealIfVisible(historyPresentation.revealRequest)
        }
        .onChange(of: store.focusRequestId) { _, newValue in
            restoreRequestedFocusIfVisible(itemId: newValue)
        }
        .onChange(of: historyPresentation.revealRequest) { _, request in
            restoreHistoryRevealIfVisible(request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverDidClose)) { _ in
            bindContextsIfNeeded()
        }
    }

    private func bindContextsIfNeeded() {
        guard isActiveContext else { return }
        ActiveListCommandContext.bind(
            scope: .longTerm,
            store: store,
            selectionManager: selectionManager
        )
    }

    private func restoreRequestedFocusIfVisible(itemId: UUID? = nil) {
        guard isActiveContext else { return }
        guard let itemId = itemId ?? store.focusRequestId,
              let item = store.todoItemsCache[itemId],
              item.containerKind != .scheduled
        else { return }
        selectionManager.restoreFocus(to: itemId)
    }

    private func restoreHistoryRevealIfVisible(_ request: TodoHistoryRevealRequest?) {
        guard isActiveContext,
              let request,
              handledHistoryRevealId != request.id,
              request.destination == .longTerm,
              let itemId = request.itemId,
              store.todoItemsCache[itemId] != nil
        else { return }
        handledHistoryRevealId = request.id
        selectionManager.restoreFocus(to: itemId)
    }
}

#Preview {
    let container = TodoPreviewSupport.bootstrap()
    return LongTermListView()
        .modelContainer(container)
}
