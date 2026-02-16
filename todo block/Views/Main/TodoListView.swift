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

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(daySections) { section in
                            DaySectionView(
                                section: section,
                                selectionManager: selectionManager,
                                onItemCreated: { itemId in
                                    scrollToItem(itemId, proxy: proxy)
                                },
                                onInteraction: {
                                    bindClipboardContextIfNeeded()
                                }
                            )
                            .id(section.id)
                        }
                    }
                    .padding()
                }
                .gesture(
                    TapGesture().onEnded {
                        bindClipboardContextIfNeeded()
                        selectionManager.clearSelection()
                    }
                )

                HStack {
                    Button(action: { addTodaySection(proxy: proxy) }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("添加一个今日待办")
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
                bindClipboardContextIfNeeded()
            }
            .onChange(of: selectionManager.focusedItemId) { _, newValue in
                bindClipboardContextIfNeeded()
                if let itemId = newValue {
                    scrollToItem(itemId, proxy: proxy)
                }
            }
            .onChange(of: selectionManager.selectedItemIds) { _, _ in
                bindClipboardContextIfNeeded()
            }
            .onChange(of: isActiveContext) { _, newValue in
                guard newValue else { return }
                bindClipboardContextIfNeeded()
            }
            .onChange(of: store.focusRequestId) { _, newValue in
                guard let itemId = newValue, store.todoItemsCache[itemId] != nil else { return }
                bindClipboardContextIfNeeded()
                selectionManager.restoreFocus(to: itemId)
                scrollToItem(itemId, proxy: proxy)
            }
        }
    }

    private func addTodaySection(proxy: ScrollViewProxy) {
        bindClipboardContextIfNeeded()
        let section = store.getOrCreateTodaySection()
        let newItem = store.createItem(dayDate: section.date)
        selectionManager.handleSelect(item: newItem, allItems: store.items(for: section.date), shiftPressed: false)
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

    private func bindClipboardContextIfNeeded() {
        guard isActiveContext else { return }
        TodoClipboardManager.shared.activateListContext(
            scope: clipboardScope,
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
