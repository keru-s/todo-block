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

    @State private var selectionManager = SelectionManager()

    private var store: TodoStore { TodoStore.shared }

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
                actions: appKitEditorActions
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button(action: addTodaySection) {
                    HStack {
                        Image(systemName: "plus")
                        Text(hasTodaySection ? "添加一个今日待办" : "添加今日分区")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                Spacer()

                if selectionManager.selectedItemIds.count > 1 {
                    Text("已选 \(selectionManager.selectedItemIds.count) 项")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                }
            }
            .background(TodoDesignTokens.windowBackground)
        }
        .onAppear {
            bindContextsIfNeeded()
        }
        .onChange(of: isActiveContext) { _, newValue in
            guard newValue else { return }
            bindContextsIfNeeded()
        }
        .onChange(of: clipboardScope) { _, _ in
            bindContextsIfNeeded()
        }
        .onChange(of: store.focusRequestId) { _, newValue in
            guard let itemId = newValue, store.todoItemsCache[itemId] != nil else { return }
            selectionManager.restoreFocus(to: itemId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverDidClose)) { _ in
            bindContextsIfNeeded()
        }
    }

    private func addTodaySection() {
        let section = store.getOrCreateTodaySection()
        if hasTodaySection {
            let newItem = store.createItem(dayDate: section.date)
            selectionManager.handleSelect(
                item: newItem,
                allItems: store.items(for: section.date),
                shiftPressed: false,
                cursorPosition: 0
            )
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
