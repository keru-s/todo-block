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
    @Query private var allSections: [DaySection]
    @Query private var allTodoItems: [TodoItem]
    
    let year: Int
    let month: Int
    
    @State private var focusedItemId: UUID?
    @State private var dataService: TodoDataService?
    
    private var daySections: [DaySection] {
        let calendar = Calendar.current
        return allSections.filter { section in
            let sectionYear = calendar.component(.year, from: section.date)
            let sectionMonth = calendar.component(.month, from: section.date)
            return sectionYear == year && sectionMonth == month
        }.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(daySections) { section in
                            if let dataService = dataService {
                                DaySectionView(
                                    section: section,
                                    dataService: dataService,
                                    focusedItemId: $focusedItemId
                                )
                                .id(section.id)
                            }
                        }
                    }
                    .padding()
                }
                
                // 底部添加按钮
                HStack {
                    Button(action: addTodaySection) {
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
        }
        .onAppear {
            dataService = TodoDataService(modelContext: modelContext)
        }
    }
    
    private func addTodaySection() {
        guard let dataService = dataService else { return }
        let section = dataService.getOrCreateTodaySection()
        let newItem = dataService.createTodoItem(dayDate: section.date)
        focusedItemId = newItem.id
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)
    
    return TodoListView(year: 2026, month: 1)
        .modelContainer(container)
}
