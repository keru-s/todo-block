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

    // 状态管理
    @State private var selectionManager = SelectionManager()

    private var store: TodoStore { TodoStore.shared }
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

            Divider()

            TodoEditorRepresentable(
                sections: editorSections,
                emptyTitle: "今天没有待办事项",
                actions: TodoEditorActionFactory.make(
                    store: store,
                    selectionManager: selectionManager
                )
            )
            .frame(minHeight: 80, maxHeight: 350)

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
            bindContexts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverWillShow)) { _ in
            bindContexts()
        }
        .gesture(
            TapGesture().onEnded {
                handleBackgroundTap()
            },
            including: .gesture
        )
        .onChange(of: store.focusRequestId) { _, newValue in
            guard let itemId = newValue, store.todoItemsCache[itemId] != nil else { return }
            selectionManager.restoreFocus(to: itemId)
        }
    }
}

// MARK: - Actions

private extension MenuBarView {
    func addTodayItem() {
        _ = store.getOrCreateTodaySection()
        let newItem = store.createItem(dayDate: Date())
        selectionManager.handleSelect(item: newItem, allItems: todayItems, shiftPressed: false)
    }

    func bindContexts() {
        ActiveListCommandContext.bind(
            scope: .today,
            store: store,
            selectionManager: selectionManager
        )
    }

    func handleBackgroundTap() {
        selectionManager.clearSelection()
    }
}

#Preview {
    let container = TodoPreviewSupport.bootstrap()
    return MenuBarView()
        .modelContainer(container)
}
