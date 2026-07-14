//
//  TodoListView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct TodoListView: View {
    let year: Int
    let month: Int
    var isActiveContext: Bool = true

    @State private var actionModule = TodoListActionModule(
        store: .shared,
        selectionManager: SelectionManager(historyContext: .mainWindow)
    )
    @State private var showModePopover = false
    @State private var handledHistoryRevealId: UUID?
    @State private var commandRegistration: TodoListCommandRegistration?
    @AppStorage("addTodayMode") private var addTodayModeRaw: String = TodoTodayAdditionMode.carryOver.rawValue

    private var addTodayMode: TodoTodayAdditionMode {
        get { TodoTodayAdditionMode(rawValue: addTodayModeRaw) ?? .carryOver }
    }

    private var store: TodoStore { TodoStore.shared }
    private var selectionManager: SelectionManager { actionModule.selectionManager }
    private var historyPresentation: TodoHistoryPresentationCoordinator { .shared }
    private var commandCoordinator: ActiveListCommandCoordinator { .shared }

    private var daySections: [DaySection] {
        store.sections(year: year, month: month)
    }

    private var appKitEditorSections: [TodoEditorSectionSnapshot] {
        daySections.map { section in
            TodoEditorSectionSnapshot(
                section: section,
                items: store.items(for: section.date),
                selectionManager: selectionManager
            )
        }
    }

    private var editorActions: TodoEditorActions {
        let registration = commandRegistration
        return actionModule.editorActions {
            guard let registration else { return }
            ActiveListCommandCoordinator.shared.claim(registration)
        }
    }

    private var clipboardScope: TodoClipboardScope {
        .scheduledMonth(year: year, month: month)
    }

    private var hasTodaySection: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return daySections.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TodoEditorRepresentable(
                sections: appKitEditorSections,
                emptyTitle: "暂无待办",
                actions: editorActions,
                revealRequest: visibleHistoryRevealRequest
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                TodoListFeedbackToast(feedback: actionModule.feedbackPresenter.feedback)
                    .padding(12)
            }

            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    Button(action: executeAddToday) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text(addTodayButtonLabel)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 8)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1, height: 18)

                    Button {
                        showModePopover.toggle()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showModePopover, arrowEdge: .bottom) {
                        addTodayModePanel
                    }
                }
                .foregroundStyle(.white)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if !hasTodaySection && addTodayMode == .carryOver {
                    Text("默认将导入前一日未完成的任务")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectionManager.selectedItemIds.count > 1 {
                    Text("已选 \(selectionManager.selectedItemIds.count) 项")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(TodoDesignTokens.windowBackground)
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
        .onChange(of: clipboardScope) { _, _ in
            actionModule.feedbackPresenter.clear()
            replaceCommandContextForCurrentScope()
        }
        .onChange(of: historyPresentation.revealRequest) { _, request in
            restoreHistoryRevealIfVisible(request)
        }
        .onDisappear {
            actionModule.feedbackPresenter.clear()
            unregisterCommandContext()
        }
    }

    private func restoreHistoryRevealIfVisible(_ request: TodoHistoryRevealRequest?) {
        guard isActiveContext,
              let request,
              handledHistoryRevealId != request.id,
              request.destination == .month(year: year, month: month)
        else { return }
        handledHistoryRevealId = request.id
        actionModule.restoreHistorySelection(request.selectionState, itemId: request.itemId)
    }

    private var visibleHistoryRevealRequest: TodoHistoryRevealRequest? {
        guard isActiveContext,
              let request = historyPresentation.revealRequest,
              request.destination == .month(year: year, month: month)
        else { return nil }
        return request
    }

    private var addTodayModePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                addTodayModeRaw = TodoTodayAdditionMode.carryOver.rawValue
                showModePopover = false
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(addTodayMode == .carryOver ? Color.accentColor : .clear)
                        .frame(width: 14)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("添加今日待办（含昨日未完成）")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(addTodayMode == .carryOver ? Color.accentColor : .primary)
                        Text("自动导入前一日未完成的任务，保留层级")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal, 12)

            Button {
                addTodayModeRaw = TodoTodayAdditionMode.blank.rawValue
                showModePopover = false
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(addTodayMode == .blank ? Color.accentColor : .clear)
                        .frame(width: 14)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("添加空白待办")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(addTodayMode == .blank ? Color.accentColor : .primary)
                        Text("创建一个空的今日待办分组")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .frame(width: 280)
    }

    private var addTodayButtonLabel: String {
        if hasTodaySection {
            return "添加一个今日待办"
        }
        return addTodayMode == .carryOver ? "添加今日待办" : "添加空白待办"
    }

    private func executeAddToday() {
        claimCurrentList()
        actionModule.addToday(mode: addTodayMode)
    }

    private func claimCurrentList() {
        guard let commandRegistration else { return }
        commandCoordinator.claim(commandRegistration)
    }

    private func registerCommandContextIfNeeded() {
        guard isActiveContext, commandRegistration == nil else { return }
        actionModule.updateCommandScope(clipboardScope)
        commandRegistration = commandCoordinator.register(actionModule)
    }

    private func replaceCommandContextForCurrentScope() {
        guard isActiveContext else { return }
        actionModule.updateCommandScope(clipboardScope)
        guard let commandRegistration else {
            registerCommandContextIfNeeded()
            claimCurrentList()
            return
        }
        self.commandRegistration = commandCoordinator.replaceAndClaim(
            commandRegistration,
            with: actionModule
        )
    }

    private func unregisterCommandContext() {
        guard let commandRegistration else { return }
        commandCoordinator.unregister(commandRegistration)
        self.commandRegistration = nil
    }

}

#Preview {
    let container = TodoPreviewSupport.bootstrap()

    return TodoListView(year: 2026, month: 1)
        .modelContainer(container)
}
