//
//  TodoListView.swift
//  notion to do
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    
    let year: Int
    let month: Int
    
    @State private var focusedItemId: UUID?
    
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
                                focusedItemId: $focusedItemId,
                                onItemCreated: { itemId in
                                    scrollToItem(itemId, proxy: proxy)
                                }
                            )
                            .id(section.id)
                        }
                    }
                    .padding()
                }
                
                // 底部添加按钮
                HStack {
                    Button(action: { addTodaySection(proxy: proxy) }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("添加一个今日待办")
                        }
                        .foregroundColor(.pink)
                        .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    Spacer()
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
            // 焦点变化时自动滚动
            .onChange(of: focusedItemId) { _, newValue in
                if let itemId = newValue {
                    scrollToItem(itemId, proxy: proxy)
                }
            }
        }
    }
    
    private func addTodaySection(proxy: ScrollViewProxy) {
        let section = store.getOrCreateTodaySection()
        let newItem = store.createItem(dayDate: section.date)
        focusedItemId = newItem.id
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
