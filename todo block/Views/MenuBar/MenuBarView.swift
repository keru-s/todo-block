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

    @State private var participation: TodoListParticipationModule

    private var store: TodoStore { TodoStore.shared }
    private var selectionManager: SelectionManager { participation.selectionManager }
    private var historyPresentation: TodoHistoryPresentationCoordinator { .shared }
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

    init(onOpenMainWindow: @escaping () -> Void = {}) {
        self.onOpenMainWindow = onOpenMainWindow
        let actionModule = TodoListActionModule(
            store: .shared,
            selectionManager: SelectionManager(historyContext: .menuBar),
            commandScope: .today,
            allowsSidebarMoves: false
        )
        _participation = State(
            initialValue: TodoListParticipationModule(
                actionModule: actionModule,
                retainsHistoryRevealsWhileInactive: false,
                historyRevealMatches: { request in
                    guard case .scheduled(let date) = request.resultDestination.normalized else {
                        return false
                    }
                    return Calendar.current.isDateInToday(date)
                }
            )
        )
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
                actions: participation.editorActions,
                revealRequest: participation.visibleHistoryRevealRequest
            )
            .frame(minHeight: 80, maxHeight: 350)
            .overlay(alignment: .bottom) {
                TodoListFeedbackToast(feedback: participation.feedback)
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
            participation.register()
            if MenuBarStatusItemController.shared.isPopoverShown {
                participation.beginTemporaryParticipation()
            }
            participation.receiveHistoryReveal(historyPresentation.revealRequest)
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverWillShow)) { _ in
            participation.beginTemporaryParticipation()
            participation.receiveHistoryReveal(historyPresentation.revealRequest)
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverDidClose)) { _ in
            participation.endTemporaryParticipation()
        }
        .onDisappear {
            participation.endTemporaryParticipation()
        }
        .gesture(
            TapGesture().onEnded {
                handleBackgroundTap()
            },
            including: .gesture
        )
        .onChange(of: historyPresentation.revealRequest) { _, request in
            participation.receiveHistoryReveal(request)
        }
    }
}

// MARK: - Actions

private extension MenuBarView {
    func addTodayItem() {
        participation.performDirectAction {
            $0.editorActions.addItem(.scheduled(date: .now))
        }
    }

    func handleBackgroundTap() {
        participation.performDirectAction { $0.clearSelection() }
    }
}

#Preview {
    let container = TodoPreviewSupport.bootstrap()
    return MenuBarView()
        .modelContainer(container)
}
