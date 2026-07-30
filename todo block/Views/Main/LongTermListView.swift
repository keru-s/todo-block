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

    @State private var participation: TodoListParticipationModule

    private var store: TodoStore { TodoStore.shared }
    private var selectionManager: SelectionManager { participation.selectionManager }
    private var historyPresentation: TodoHistoryPresentationCoordinator { .shared }
    private let urgentSectionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1))
    private let importantSectionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2))

    init(isActiveContext: Bool = true) {
        self.isActiveContext = isActiveContext
        let actionModule = TodoListActionModule(
            store: .shared,
            selectionManager: SelectionManager(historyContext: .longTerm),
            commandScope: .longTerm
        )
        _participation = State(
            initialValue: TodoListParticipationModule(actionModule: actionModule)
        )
    }

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
            actions: participation.editorActions,
            revealRequest: participation.visibleHistoryRevealRequest
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            TodoListFeedbackToast(feedback: participation.feedback)
                .padding(12)
        }
        .onAppear {
            participation.appear(isActive: isActiveContext)
            participation.receiveHistoryReveal(historyPresentation.revealRequest)
        }
        .onChange(of: isActiveContext) { _, newValue in
            participation.update(isActive: newValue)
            participation.receiveHistoryReveal(historyPresentation.revealRequest)
        }
        .onChange(of: historyPresentation.revealRequest) { _, request in
            participation.receiveHistoryReveal(request)
        }
        .onDisappear {
            participation.update(isActive: false)
        }
    }
}

#Preview {
    let container = TodoPreviewSupport.bootstrap()
    return LongTermListView()
        .modelContainer(container)
}
