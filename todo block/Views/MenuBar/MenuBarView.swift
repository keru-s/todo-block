//
//  MenuBarView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI

struct MenuBarView: View {
    let onOpenMainWindow: () -> Void

    init(onOpenMainWindow: @escaping () -> Void = {}) {
        self.onOpenMainWindow = onOpenMainWindow
    }

    @State private var actionModule = TodoListActionModule(
        store: .shared,
        selectionManager: SelectionManager(historyContext: .menuBar),
        commandScope: .today,
        allowsSidebarMoves: false
    )
    @State private var handledHistoryRevealId: UUID?
    @State private var commandRegistration: TodoListCommandRegistration?
    @State private var temporaryCommandClaim: TodoListTemporaryCommandClaim?

    private var store: TodoStore { TodoStore.shared }
    private var selectionManager: SelectionManager { actionModule.selectionManager }
    private var historyPresentation: TodoHistoryPresentationCoordinator { .shared }
    private var commandCoordinator: ActiveListCommandCoordinator { .shared }
    private let todaySectionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1))

    private var todayItems: [TodoItem] {
        store.todayItems()
    }

    private var editorSections: [TodoEditorSectionSnapshot] {
        [
            TodoEditorSectionSnapshot(
                id: todaySectionId,
                title: "待办",
                destination: .scheduled(date: Date()),
                items: todayItems.map {
                    TodoEditorItemSnapshot(item: $0, selectionManager: selectionManager)
                }
            )
        ]
    }

    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: Date())
    }

    private var editorActions: TodoEditorActions {
        let registration = commandRegistration
        return actionModule.editorActions {
            guard let registration else { return }
            ActiveListCommandCoordinator.shared.claim(registration)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("今日待办")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(formattedToday)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if store.hasUnsavedChanges {
                Label("待办尚未保存，正在自动重试", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            TodoEditorRepresentable(
                sections: editorSections,
                emptyTitle: "今天没有待办事项",
                actions: editorActions,
                revealRequest: visibleHistoryRevealRequest
            )
            .frame(minHeight: 80, maxHeight: 350)
            .overlay(alignment: .bottom) {
                TodoListFeedbackToast(feedback: actionModule.feedbackPresenter.feedback)
                    .padding(10)
            }

            Divider()

            // 底部操作栏
            HStack {
                Button(action: addTodayItem) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer()

                if selectionManager.selectedItemIds.count > 1 {
                    Text("已选 \(selectionManager.selectedItemIds.count) 项")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }

                Button("打开应用") {
                    onOpenMainWindow()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .background(TodoDesignTokens.windowBackground)
        .onAppear {
            registerCommandContextIfNeeded()
            if MenuBarStatusItemController.shared.isPopoverShown {
                beginTemporaryCommandClaim()
            }
            restoreHistoryRevealIfVisible(historyPresentation.revealRequest)
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverWillShow)) { _ in
            registerCommandContextIfNeeded()
            beginTemporaryCommandClaim()
            restoreHistoryRevealIfVisible(historyPresentation.revealRequest)
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverDidClose)) { _ in
            actionModule.feedbackPresenter.clear()
            endTemporaryCommandClaim()
        }
        .onDisappear {
            actionModule.feedbackPresenter.clear()
            endTemporaryCommandClaim()
        }
        .gesture(
            TapGesture().onEnded {
                handleBackgroundTap()
            },
            including: .gesture
        )
        .onChange(of: historyPresentation.revealRequest) { _, request in
            restoreHistoryRevealIfVisible(request)
        }
    }
}

// MARK: - Actions

private extension MenuBarView {
    func restoreHistoryRevealIfVisible(_ request: TodoHistoryRevealRequest?) {
        guard let request,
              handledHistoryRevealId != request.id,
              visibleHistoryRevealRequest?.id == request.id
        else { return }
        handledHistoryRevealId = request.id
        actionModule.restoreHistorySelection(
            request.selectionState,
            itemId: request.itemId,
            sourceHistoryContext: request.sourceHistoryContext
        )
    }

    var visibleHistoryRevealRequest: TodoHistoryRevealRequest? {
        guard let request = historyPresentation.revealRequest,
              case .scheduled(let date) = request.resultDestination.normalized,
              Calendar.current.isDateInToday(date)
        else { return nil }
        return request
    }

    func addTodayItem() {
        claimCurrentList()
        actionModule.editorActions.addItem(.scheduled(date: .now))
    }

    func registerCommandContextIfNeeded() {
        guard commandRegistration == nil else { return }
        commandRegistration = commandCoordinator.register(actionModule)
    }

    func claimCurrentList() {
        guard let commandRegistration else { return }
        commandCoordinator.claim(commandRegistration)
    }

    func beginTemporaryCommandClaim() {
        guard temporaryCommandClaim == nil,
              let commandRegistration
        else { return }
        actionModule.feedbackPresenter.clear()
        temporaryCommandClaim = commandCoordinator.beginTemporaryClaim(commandRegistration)
    }

    func endTemporaryCommandClaim() {
        guard let temporaryCommandClaim else { return }
        commandCoordinator.endTemporaryClaim(temporaryCommandClaim)
        self.temporaryCommandClaim = nil
    }

    func handleBackgroundTap() {
        claimCurrentList()
        actionModule.clearSelection()
    }
}

#Preview {
    let container = TodoPreviewSupport.bootstrap()
    return MenuBarView()
        .modelContainer(container)
}
