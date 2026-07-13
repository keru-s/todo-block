//
//  TodoListView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

enum AddTodayMode: String {
    case carryOver
    case blank
}

struct TodoListView: View {
    let year: Int
    let month: Int
    var isActiveContext: Bool = true

    @State private var selectionManager = SelectionManager(historyContext: .mainWindow)
    @State private var showModePopover = false
    @State private var handledHistoryRevealId: UUID?
    @AppStorage("addTodayMode") private var addTodayModeRaw: String = AddTodayMode.carryOver.rawValue

    private var addTodayMode: AddTodayMode {
        get { AddTodayMode(rawValue: addTodayModeRaw) ?? .carryOver }
    }

    private var store: TodoStore { TodoStore.shared }
    private var historyPresentation: TodoHistoryPresentationCoordinator { .shared }

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
                actions: appKitEditorActions,
                revealRequest: visibleHistoryRevealRequest
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
            bindContextsIfNeeded()
            restoreHistoryRevealIfVisible(historyPresentation.revealRequest)
        }
        .onChange(of: isActiveContext) { _, newValue in
            guard newValue else { return }
            bindContextsIfNeeded()
            restoreHistoryRevealIfVisible(historyPresentation.revealRequest)
        }
        .onChange(of: clipboardScope) { _, _ in
            bindContextsIfNeeded()
        }
        .onChange(of: historyPresentation.revealRequest) { _, request in
            restoreHistoryRevealIfVisible(request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverDidClose)) { _ in
            bindContextsIfNeeded()
        }
    }

    private func restoreHistoryRevealIfVisible(_ request: TodoHistoryRevealRequest?) {
        guard isActiveContext,
              let request,
              handledHistoryRevealId != request.id,
              request.destination == .month(year: year, month: month)
        else { return }
        handledHistoryRevealId = request.id
        if let selectionState = request.selectionState {
            selectionState.apply(to: selectionManager)
        } else if let itemId = request.itemId,
                  store.todoItemsCache[itemId] != nil {
            selectionManager.restoreFocus(to: itemId)
        }
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
                addTodayModeRaw = AddTodayMode.carryOver.rawValue
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
                addTodayModeRaw = AddTodayMode.blank.rawValue
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
        if hasTodaySection {
            let section = store.getOrCreateTodaySection()
            let newItem = store.createItem(
                dayDate: section.date,
                selectionManager: selectionManager
            )
            selectionManager.handleSelect(
                item: newItem,
                allItems: store.items(for: section.date),
                shiftPressed: false,
                cursorPosition: 0
            )
        } else {
            switch addTodayMode {
            case .carryOver:
                store.carryOverIncompleteItems(trigger: .userInitiated)
            case .blank:
                store.getOrCreateTodaySection()
            }
        }
    }

    private func bindContextsIfNeeded() {
        guard isActiveContext else { return }
        ActiveListCommandContext.bind(
            scope: clipboardScope,
            store: store,
            selectionManager: selectionManager
        )
    }

    private var appKitEditorActions: TodoEditorActions {
        TodoEditorActionFactory.make(
            store: store,
            selectionManager: selectionManager,
            sectionById: { sectionId in
                daySections.first { $0.id == sectionId }
            }
        )
    }
}

#Preview {
    let container = TodoPreviewSupport.bootstrap()

    return TodoListView(year: 2026, month: 1)
        .modelContainer(container)
}
