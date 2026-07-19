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

    @State private var actionModule = TodoListActionModule(
        store: .shared,
        selectionManager: SelectionManager(historyContext: .longTerm),
        commandScope: .longTerm
    )
    @State private var handledHistoryRevealId: UUID?
    @State private var commandRegistration: TodoListCommandRegistration?

    private var store: TodoStore { TodoStore.shared }
    private var selectionManager: SelectionManager { actionModule.selectionManager }
    private var historyPresentation: TodoHistoryPresentationCoordinator { .shared }
    private var commandCoordinator: ActiveListCommandCoordinator { .shared }
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

    private var editorActions: TodoEditorActions {
        let registration = commandRegistration
        return actionModule.editorActions {
            guard let registration else { return }
            ActiveListCommandCoordinator.shared.claim(registration)
        }
    }

    var body: some View {
        TodoEditorRepresentable(
            sections: editorSections,
            emptyTitle: "暂无长期待办",
            actions: editorActions,
            revealRequest: visibleHistoryRevealRequest
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            TodoListFeedbackToast(feedback: actionModule.feedbackPresenter.feedback)
                .padding(12)
        }
        .onAppear {
            registerCommandContextIfNeeded()
            restoreHistoryRevealIfVisible(historyPresentation.revealRequest)
        }
        .onChange(of: isActiveContext) { _, newValue in
            guard newValue else {
                actionModule.feedbackPresenter.clear()
                unregisterCommandContext()
                return
            }
            registerCommandContextIfNeeded()
            claimCurrentList()
            restoreHistoryRevealIfVisible(historyPresentation.revealRequest)
        }
        .onChange(of: historyPresentation.revealRequest) { _, request in
            restoreHistoryRevealIfVisible(request)
        }
        .onDisappear {
            actionModule.feedbackPresenter.clear()
            unregisterCommandContext()
        }
    }

    private func registerCommandContextIfNeeded() {
        guard isActiveContext, commandRegistration == nil else { return }
        commandRegistration = commandCoordinator.register(actionModule)
    }

    private func claimCurrentList() {
        guard let commandRegistration else { return }
        commandCoordinator.claim(commandRegistration)
    }

    private func unregisterCommandContext() {
        guard let commandRegistration else { return }
        commandCoordinator.unregister(commandRegistration)
        self.commandRegistration = nil
    }

    private func restoreHistoryRevealIfVisible(_ request: TodoHistoryRevealRequest?) {
        guard isActiveContext,
              let request,
              handledHistoryRevealId != request.id,
              request.destination == .longTerm
        else { return }
        handledHistoryRevealId = request.id
        actionModule.restoreHistorySelection(
            request.selectionState,
            itemId: request.itemId,
            sourceHistoryContext: request.sourceHistoryContext
        )
    }

    private var visibleHistoryRevealRequest: TodoHistoryRevealRequest? {
        guard isActiveContext,
              let request = historyPresentation.revealRequest,
              request.destination == .longTerm
        else { return nil }
        return request
    }
}

#Preview {
    let container = TodoPreviewSupport.bootstrap()
    return LongTermListView()
        .modelContainer(container)
}
