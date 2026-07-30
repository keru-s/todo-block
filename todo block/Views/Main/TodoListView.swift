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

    @State private var participation: TodoListParticipationModule
    @State private var showModePopover = false
    @AppStorage("addTodayMode") private var addTodayModeRaw: String = TodoTodayAdditionMode.carryOver.rawValue

    private var addTodayMode: TodoTodayAdditionMode {
        get { TodoTodayAdditionMode(rawValue: addTodayModeRaw) ?? .carryOver }
    }

    private var store: TodoStore { TodoStore.shared }
    private var selectionManager: SelectionManager { participation.selectionManager }
    private var historyPresentation: TodoHistoryPresentationCoordinator { .shared }

    init(year: Int, month: Int, isActiveContext: Bool = true) {
        self.year = year
        self.month = month
        self.isActiveContext = isActiveContext
        let actionModule = TodoListActionModule(
            store: .shared,
            selectionManager: SelectionManager(historyContext: .mainWindow),
            commandScope: .scheduledMonth(year: year, month: month)
        )
        _participation = State(
            initialValue: TodoListParticipationModule(
                actionModule: actionModule,
                claimsCurrentListWhenFirstActivated: false,
                historyRevealMatches: { request in
                    request.destination == .month(year: year, month: month)
                }
            )
        )
    }

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
                actions: participation.editorActions,
                revealRequest: participation.visibleHistoryRevealRequest
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                TodoListFeedbackToast(feedback: participation.feedback)
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
            participation.updateCommandScope(clipboardScope)
            updateHistoryRevealMatcher()
            participation.appear(isActive: isActiveContext)
            participation.receiveHistoryReveal(historyPresentation.revealRequest)
        }
        .onChange(of: isActiveContext) { _, newValue in
            participation.update(isActive: newValue)
            participation.receiveHistoryReveal(historyPresentation.revealRequest)
        }
        .onChange(of: clipboardScope) { _, _ in
            participation.updateCommandScope(clipboardScope)
            updateHistoryRevealMatcher()
            participation.receiveHistoryReveal(historyPresentation.revealRequest)
        }
        .onChange(of: historyPresentation.revealRequest) { _, request in
            participation.receiveHistoryReveal(request)
        }
        .onDisappear {
            participation.update(isActive: false)
        }
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
        participation.performDirectAction { $0.addToday(mode: addTodayMode) }
    }

    private func updateHistoryRevealMatcher() {
        let destination = SidebarDestination.month(year: year, month: month)
        participation.updateHistoryRevealMatcher { request in
            request.destination == destination
        }
    }

}

#Preview {
    let container = TodoPreviewSupport.bootstrap()

    return TodoListView(year: 2026, month: 1)
        .modelContainer(container)
}
