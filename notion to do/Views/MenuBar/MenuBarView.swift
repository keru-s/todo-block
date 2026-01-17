//
//  MenuBarView.swift
//  notion to do
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    
    private var store: TodoStore { TodoStore.shared }
    
    private var todayItems: [TodoItem] {
        store.todayItems()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题
            HStack {
                Text("今日待办")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(formattedToday)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Divider()
            
            if todayItems.isEmpty {
                VStack {
                    Text("今天没有待办事项")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    Button("添加待办") {
                        addTodayItem()
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(todayItems) { item in
                            MenuBarItemRow(item: item)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 300)
            }
            
            Divider()
            
            // 底部操作
            HStack {
                Button(action: addTodayItem) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.pink)
                
                Spacer()
                
                Button("打开应用") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title.contains("notion") || $0.isKeyWindow == false }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
        .onAppear {
            // 确保 TodoStore 已初始化
            if store.todoItemsCache.isEmpty {
                store.initialize(with: modelContext)
            }
        }
    }
    
    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: Date())
    }
    
    private func addTodayItem() {
        _ = store.getOrCreateTodaySection()
        _ = store.createItem(dayDate: Date())
    }
}

struct MenuBarItemRow: View {
    @Bindable var item: TodoItem
    
    private var store: TodoStore { TodoStore.shared }
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleComplete) {
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(item.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
            
            Text(item.title.isEmpty ? "待办事项" : item.title)
                .font(.system(size: 13))
                .strikethrough(item.isCompleted, color: .gray)
                .foregroundColor(item.isCompleted ? .gray : .primary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private func toggleComplete() {
        store.toggleComplete(item)
    }
}

#Preview {
    MenuBarView()
        .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
