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

    private var clipboardScope: TodoClipboardScope {
        .scheduledMonth(year: year, month: month)
    }

    private var hasTodaySection: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return daySections.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    // 用 VStack 而非 LazyVStack: LazyVStack 的 prefetch 与
                    // NSViewRepresentable (CustomTextEditor) 的 intrinsicContentSize
                    // 测量在滚动期间会形成不收敛的 layout 循环,导致 100% CPU 卡死。
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(daySections) { section in
                            DaySectionView(
                                section: section,
                                selectionManager: selectionManager,
                                onItemCreated: { itemId in
                                    scrollToItem(itemId, proxy: proxy)
                                },
                                onInteraction: {
                                    bindContextsIfNeeded()
                                }
                            )
                            .id(section.id)
                        }
                    }
                    .padding()
                }
                .gesture(
                    TapGesture().onEnded {
                        bindContextsIfNeeded()
                        selectionManager.clearSelection()
                    }
                )

                HStack {
                    Button(action: { addTodaySection(proxy: proxy) }) {
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
                .background(Color(NSColor.windowBackgroundColor))
            }
            .onAppear {
                bindContextsIfNeeded()
            }
            .onChange(of: selectionManager.focusedItemId) { _, newValue in
                bindContextsIfNeeded()
                if let itemId = newValue {
                    scrollToItem(itemId, proxy: proxy)
                }
            }
            .onChange(of: selectionManager.selectedItemIds) { _, _ in
                bindContextsIfNeeded()
            }
            .onChange(of: isActiveContext) { _, newValue in
                guard newValue else { return }
                bindContextsIfNeeded()
            }
            .onChange(of: store.focusRequestId) { _, newValue in
                guard let itemId = newValue, store.todoItemsCache[itemId] != nil else { return }
                bindContextsIfNeeded()
                selectionManager.restoreFocus(to: itemId)
                scrollToItem(itemId, proxy: proxy)
            }
        }
    }

    private func addTodaySection(proxy: ScrollViewProxy) {
        bindContextsIfNeeded()
        let hadTodaySection = hasTodaySection
        let section = store.getOrCreateTodaySection()
        if hadTodaySection == false {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(section.id, anchor: .center)
                }
            }
            return
        }

        let newItem = store.createItem(dayDate: section.date)
        selectionManager.handleSelect(
            item: newItem,
            allItems: store.items(for: section.date),
            shiftPressed: false
        )
        scrollToItem(newItem.id, proxy: proxy)
    }

    private func scrollToItem(_ itemId: UUID, proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(itemId, anchor: .center)
            }
        }
    }

    private func bindContextsIfNeeded() {
        guard isActiveContext else { return }
        TodoClipboardManager.shared.activateListContext(
            scope: clipboardScope,
            store: store,
            selectionManager: selectionManager
        )
        TodoReorderCommandManager.shared.activateListContext(
            store: store,
            selectionManager: selectionManager
        )
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)
    
    TodoStore.shared.initialize(with: container.mainContext)
    
    return TodoListView(year: 2026, month: 1)
        .modelContainer(container)
}
