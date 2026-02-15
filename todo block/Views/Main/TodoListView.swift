//
//  TodoListView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    
    let year: Int
    let month: Int
    
    @State private var selectionManager = SelectionManager()
    
    private var store: TodoStore { TodoStore.shared }
    
    private var daySections: [DaySection] {
        store.sections(year: year, month: month)
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
                                }
                            )
                            .id(section.id)
                        }
                    }
                    .padding()
                }
                .onTapGesture {
                    // 点击空白处取消选择
                    selectionManager.clearSelection()
                }
                
                // 底部添加按钮
                HStack {
                    Button(action: { addTodaySection(proxy: proxy) }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("添加一个今日待办")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    Spacer()
                    
                    // 显示选中数量
                    if selectionManager.selectedItemIds.count > 1 {
                        Text("已选 \(selectionManager.selectedItemIds.count) 项")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 12)
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
            .onChange(of: selectionManager.focusedItemId) { _, newValue in
                if let itemId = newValue {
                    scrollToItem(itemId, proxy: proxy)
                }
            }
            .onChange(of: store.focusRequestId) { _, newValue in
                guard let itemId = newValue, store.todoItemsCache[itemId] != nil else { return }
                selectionManager.restoreFocus(to: itemId)
                scrollToItem(itemId, proxy: proxy)
            }
        }
    }
    
    private func addTodaySection(proxy: ScrollViewProxy) {
        let section = store.getOrCreateTodaySection()
        let newItem = store.createItem(dayDate: section.date)
        selectionManager.handleSelect(item: newItem, allItems: store.items(for: section.date), shiftPressed: false)
        scrollToItem(newItem.id, proxy: proxy)
    }
    
    private func scrollToItem(_ itemId: UUID, proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(itemId, anchor: .center)
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)
    
    TodoStore.shared.initialize(with: container.mainContext)
    
    return TodoListView(year: 2026, month: 1)
        .modelContainer(container)
}
